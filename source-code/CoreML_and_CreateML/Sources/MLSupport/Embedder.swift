import CoreML
import Foundation

/// Sentence embeddings from the int8 quantized MiniLM Core ML model.
///
/// MLModel is not marked Sendable, but Apple documents its async
/// prediction API as safe to call concurrently. The class holds only
/// immutable state, so @unchecked Sendable is sound here and lets a
/// task group run many predictions at once.
public final class Embedder: @unchecked Sendable {
    public static let dimension = 384
    private let model: MLModel
    private let tokenizer: WordPieceTokenizer

    public init(computeUnits: MLComputeUnits = .all) async throws {
        model = try await ModelStore.load("MiniLMEmbedding.mlpackage", computeUnits: computeUnits)
        tokenizer = try WordPieceTokenizer(vocabURL: Paths.model("minilm_vocab.txt"))
    }

    /// Returns a unit length embedding with shape [1, 384].
    public func embed(_ text: String) async throws -> MLTensor {
        let (ids, mask) = tokenizer.encode(text)
        let shape = [1, tokenizer.maxLength]
        let inputs: [String: MLTensor] = [
            "input_ids": MLTensor(shape: shape, scalars: ids, scalarType: Int32.self),
            "attention_mask": MLTensor(shape: shape, scalars: mask, scalarType: Int32.self),
        ]
        let outputs = try await model.prediction(from: inputs)
        return outputs["embedding"]!
    }

    /// Embeds texts concurrently and stacks them, in input order, into a
    /// [count, 384] matrix.
    public func embed(batch texts: [String]) async throws -> MLTensor {
        precondition(!texts.isEmpty, "Batch must contain at least one text")
        let rows = try await withThrowingTaskGroup(of: (Int, MLTensor).self) { group in
            for (i, text) in texts.enumerated() {
                group.addTask { (i, try await self.embed(text)) }
            }
            var rows = [MLTensor?](repeating: nil, count: texts.count)
            for try await (i, row) in group { rows[i] = row }
            return rows.map { $0! }
        }
        return MLTensor(concatenating: rows, alongAxis: 0)
    }
}
