# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#   "coremltools==9.0",
#   "torch==2.7.0",
#   "transformers==4.53.3",
#   "numpy<2.3",
# ]
# ///
"""
Build the Core ML models used by the Swift examples in this directory.

Run from the package root:

    uv run python/make_models.py

Writes to ./models:

  MiniLMEmbedding.mlpackage          all-MiniLM-L6-v2, fixed 128 tokens, int8 weights
  MiniLMEmbeddingFlexible.mlpackage  same network, flexible length, float32 (fallback demo)
  minilm_vocab.txt                   WordPiece vocabulary for the Swift tokenizer
  CharLM.mlpackage                   tiny character LM, two functions:
                                       "generate" (stateful KV-cache)
                                       "score"    (stateless log-probs)
  charlm_vocab.json                  character vocabulary for CharLM
"""

import json
import os
import pathlib
import shutil

import coremltools as ct
import coremltools.optimize.coreml as cto
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from transformers import AutoModel, AutoTokenizer

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODELS = ROOT / "models"
DATA = ROOT.parent / "data"
MODELS.mkdir(exist_ok=True)

SEQ_LEN = 128
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
torch.manual_seed(42)


# ---------------------------------------------------------------- embeddings

class MeanPooledEncoder(nn.Module):
    """Wraps a BERT encoder: mean pooling over real tokens, then L2 norm."""

    def __init__(self, encoder):
        super().__init__()
        self.encoder = encoder

    def forward(self, input_ids, attention_mask):
        hidden = self.encoder(input_ids=input_ids,
                              attention_mask=attention_mask)[0]
        mask = attention_mask.unsqueeze(-1).to(hidden.dtype)
        summed = (hidden * mask).sum(dim=1)
        counts = mask.sum(dim=1).clamp(min=1.0)
        return F.normalize(summed / counts, p=2.0, dim=1)


def build_embedding_models():
    name = "sentence-transformers/all-MiniLM-L6-v2"
    tokenizer = AutoTokenizer.from_pretrained(name)
    encoder = AutoModel.from_pretrained(name, torchscript=True,
                                        attn_implementation="eager").eval()
    model = MeanPooledEncoder(encoder).eval()

    # Save the vocabulary in id order; the Swift WordPiece tokenizer reads it.
    vocab = sorted(tokenizer.get_vocab().items(), key=lambda kv: kv[1])
    (MODELS / "minilm_vocab.txt").write_text(
        "\n".join(tok for tok, _ in vocab) + "\n")

    sample = tokenizer("Core ML runs on the Neural Engine.",
                       padding="max_length", max_length=SEQ_LEN,
                       truncation=True, return_tensors="pt")
    ids = sample["input_ids"].to(torch.int32)
    mask = sample["attention_mask"].to(torch.int32)
    with torch.no_grad():
        traced = torch.jit.trace(model, (ids, mask))
        reference = model(ids, mask).numpy()

    # 1. Fixed shape, float16 compute, int8 weights: the ANE friendly build.
    fixed = ct.convert(
        traced,
        inputs=[ct.TensorType("input_ids", shape=(1, SEQ_LEN), dtype=np.int32),
                ct.TensorType("attention_mask", shape=(1, SEQ_LEN), dtype=np.int32)],
        outputs=[ct.TensorType("embedding", dtype=np.float32)],
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT16,
    )
    op_config = cto.OpLinearQuantizerConfig(mode="linear_symmetric",
                                            dtype="int8",
                                            granularity="per_channel")
    fixed = cto.linear_quantize_weights(
        fixed, config=cto.OptimizationConfig(global_config=op_config))
    fixed.short_description = "all-MiniLM-L6-v2 sentence embeddings (384-d, int8 weights)"
    fixed.save(str(MODELS / "MiniLMEmbedding.mlpackage"))

    out = fixed.predict({"input_ids": ids.numpy(), "attention_mask": mask.numpy()})
    cos = float(np.dot(out["embedding"][0], reference[0]))
    print(f"MiniLMEmbedding: cosine(Core ML, PyTorch) = {cos:.4f}")

    # 2. Flexible sequence length in float32. Same weights, different runtime
    #    story: used by ComputePlanInspector to show device fallback.
    flex_len = ct.RangeDim(lower_bound=1, upper_bound=512, default=SEQ_LEN)
    flexible = ct.convert(
        traced,
        inputs=[ct.TensorType("input_ids", shape=(1, flex_len), dtype=np.int32),
                ct.TensorType("attention_mask", shape=(1, flex_len), dtype=np.int32)],
        outputs=[ct.TensorType("embedding", dtype=np.float32)],
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT32,
        skip_model_load=True,
    )
    flexible.short_description = "all-MiniLM-L6-v2, flexible length, float32"
    flexible.save(str(MODELS / "MiniLMEmbeddingFlexible.mlpackage"))


# ------------------------------------------------------- tiny character LM

CTX = 128      # maximum context, also the KV-cache length
D_MODEL = 128
N_HEADS = 4
N_LAYERS = 2
HEAD_DIM = D_MODEL // N_HEADS


class Block(nn.Module):
    def __init__(self):
        super().__init__()
        self.ln1 = nn.LayerNorm(D_MODEL)
        self.qkv = nn.Linear(D_MODEL, 3 * D_MODEL)
        self.proj = nn.Linear(D_MODEL, D_MODEL)
        self.ln2 = nn.LayerNorm(D_MODEL)
        self.mlp = nn.Sequential(nn.Linear(D_MODEL, 4 * D_MODEL), nn.GELU(),
                                 nn.Linear(4 * D_MODEL, D_MODEL))

    def split(self, x):
        b, t, _ = x.shape
        q, k, v = self.qkv(self.ln1(x)).split(D_MODEL, dim=2)
        shape = (b, t, N_HEADS, HEAD_DIM)
        return (q.view(shape).transpose(1, 2), k.view(shape).transpose(1, 2),
                v.view(shape).transpose(1, 2))

    def finish(self, x, attn):
        b, _, t, _ = attn.shape
        x = x + self.proj(attn.transpose(1, 2).reshape(b, t, D_MODEL))
        return x + self.mlp(self.ln2(x))


class CharLM(nn.Module):
    def __init__(self, vocab_size):
        super().__init__()
        self.tok = nn.Embedding(vocab_size, D_MODEL)
        self.pos = nn.Embedding(CTX, D_MODEL)
        self.blocks = nn.ModuleList(Block() for _ in range(N_LAYERS))
        self.ln = nn.LayerNorm(D_MODEL)
        self.head = nn.Linear(D_MODEL, vocab_size)

    def forward(self, idx):
        t = idx.shape[1]
        x = self.tok(idx) + self.pos(torch.arange(t))
        for blk in self.blocks:
            q, k, v = blk.split(x)
            attn = F.scaled_dot_product_attention(q, k, v, is_causal=True)
            x = blk.finish(x, attn)
        return self.head(self.ln(x))


class StatefulCharLM(nn.Module):
    """
    One token per call, with the KV-cache held in Core ML state.

    Every shape is fixed: the new key and value go into cache slot
    `position` through a one-hot blend, and attention covers all CTX slots
    with a mask that hides slots after `position`. Fixed shapes keep the
    graph simple for the converter and for the Neural Engine. A prompt is
    "prefilled" by calling the model once per prompt character.
    """

    def __init__(self, base):
        super().__init__()
        self.base = base
        shape = (N_LAYERS, 1, N_HEADS, CTX, HEAD_DIM)
        # Float32 here; the Core ML StateType declares them float16.
        self.register_buffer("keyCache", torch.zeros(shape))
        self.register_buffer("valueCache", torch.zeros(shape))

    def forward(self, input_ids, position):
        slots = torch.arange(CTX, dtype=torch.int32)
        onehot = (slots == position).float().view(1, 1, CTX, 1)   # write mask
        visible = (slots <= position).float().view(1, 1, 1, CTX)  # attention mask
        attn_mask = (1.0 - visible) * -1e4

        x = self.base.tok(input_ids) + self.base.pos(position).unsqueeze(0)
        for i, blk in enumerate(self.base.blocks):
            q, k, v = blk.split(x)                                # each [1, H, 1, D]
            keys = self.keyCache[i] * (1.0 - onehot) + k * onehot
            values = self.valueCache[i] * (1.0 - onehot) + v * onehot
            self.keyCache[i] = keys
            self.valueCache[i] = values
            attn = F.scaled_dot_product_attention(q, keys, values, attn_mask=attn_mask)
            x = blk.finish(x, attn)
        return self.base.head(self.base.ln(x))[:, -1, :]


class ScoringCharLM(nn.Module):
    """Stateless: log-probabilities for every position of a full window."""

    def __init__(self, base):
        super().__init__()
        self.base = base

    def forward(self, input_ids):
        return F.log_softmax(self.base(input_ids), dim=-1)


def load_corpus():
    files = sorted(DATA.glob("*.txt"))
    if not files:
        raise FileNotFoundError(f"No .txt corpus files found in {DATA}. Ensure ../data contains training files.")
    text = "\n".join(p.read_text() for p in files)
    cleaned = " ".join(text.split())
    if not cleaned:
        raise ValueError(f"Corpus files in {DATA} are empty.")
    return cleaned


def train_char_lm(text, steps=1500):
    chars = sorted(set(text))
    stoi = {c: i for i, c in enumerate(chars)}
    data = torch.tensor([stoi[c] for c in text], dtype=torch.long)
    model = CharLM(len(chars))
    opt = torch.optim.AdamW(model.parameters(), lr=3e-3)
    for step in range(steps):
        starts = torch.randint(0, len(data) - CTX - 1, (32,))
        x = torch.stack([data[s:s + CTX] for s in starts])
        y = torch.stack([data[s + 1:s + CTX + 1] for s in starts])
        loss = F.cross_entropy(model(x).reshape(-1, len(chars)), y.reshape(-1))
        opt.zero_grad()
        loss.backward()
        opt.step()
        if step % 250 == 0 or step == steps - 1:
            print(f"  char LM step {step:4d}  loss {loss.item():.3f}")
    return model.eval(), chars


def build_char_lm():
    text = load_corpus()
    base, chars = train_char_lm(text)
    (MODELS / "charlm_vocab.json").write_text(json.dumps(chars))
    vocab_size = len(chars)

    # Function 1: stateful generation.
    stateful = StatefulCharLM(base).eval()

    # Check the cache logic in PyTorch: feeding tokens one at a time must
    # give the same next-token logits as a full forward pass.
    probe = torch.tensor([[chars.index(c) for c in "Sport is "]], dtype=torch.int32)
    with torch.no_grad():
        for pos in range(probe.shape[1]):
            step = stateful(probe[:, pos:pos + 1], torch.tensor([pos], dtype=torch.int32))
        full = base(probe.long())[:, -1, :]
    print(f"  KV-cache check: max |stateful - full| = {(step - full).abs().max():.2e}")
    stateful.keyCache.zero_()
    stateful.valueCache.zero_()
    ids = torch.zeros((1, 1), dtype=torch.int32)
    position = torch.zeros((1,), dtype=torch.int32)
    with torch.no_grad():
        traced = torch.jit.trace(stateful, (ids, position))
    shape = (N_LAYERS, 1, N_HEADS, CTX, HEAD_DIM)
    generate = ct.convert(
        traced,
        inputs=[ct.TensorType("input_ids", shape=(1, 1), dtype=np.int32),
                ct.TensorType("position", shape=(1,), dtype=np.int32)],
        outputs=[ct.TensorType("logits", dtype=np.float32)],
        states=[ct.StateType(wrapped_type=ct.TensorType(shape=shape, dtype=np.float16),
                             name="keyCache"),
                ct.StateType(wrapped_type=ct.TensorType(shape=shape, dtype=np.float16),
                             name="valueCache")],
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT16,
        skip_model_load=True,
    )
    generate.save(str(MODELS / "_charlm_generate.mlpackage"))

    # Function 2: stateless scoring over a full window.
    scorer = ScoringCharLM(base).eval()
    window = torch.zeros((1, CTX), dtype=torch.int32)
    with torch.no_grad():
        traced = torch.jit.trace(scorer, (window,))
    score = ct.convert(
        traced,
        inputs=[ct.TensorType("input_ids", shape=(1, CTX), dtype=np.int32)],
        outputs=[ct.TensorType("log_probs", dtype=np.float32)],
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT16,
        skip_model_load=True,
    )
    score.save(str(MODELS / "_charlm_score.mlpackage"))

    # Merge: shared weights are stored once in the multifunction package.
    desc = ct.utils.MultiFunctionDescriptor()
    desc.add_function(str(MODELS / "_charlm_generate.mlpackage"),
                      src_function_name="main", target_function_name="generate")
    desc.add_function(str(MODELS / "_charlm_score.mlpackage"),
                      src_function_name="main", target_function_name="score")
    desc.default_function_name = "generate"
    ct.utils.save_multifunction(desc, str(MODELS / "CharLM.mlpackage"))
    for part in ("_charlm_generate.mlpackage", "_charlm_score.mlpackage"):
        shutil.rmtree(MODELS / part, ignore_errors=True)

    print(f"CharLM: vocab {vocab_size}, context {CTX}, saved with 2 functions")


if __name__ == "__main__":
    build_embedding_models()
    build_char_lm()
    print(f"Models written to {MODELS}")
