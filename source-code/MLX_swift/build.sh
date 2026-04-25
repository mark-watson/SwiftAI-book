#!/usr/bin/env bash
# build.sh — Build and run the MLX_swift example.
#
# MLX requires a compiled Metal shader library (default.metallib)
# to be present next to the binary at runtime.  Swift Package
# Manager does not compile or copy this file automatically for
# command-line tool targets, so we do it here.
#
# First-time setup (if you see "cannot execute tool 'metal'"):
#   xcodebuild -downloadComponent MetalToolchain
#
# Usage:
#   ./build.sh                        # build only
#   ./build.sh "your prompt here"     # build + run single-shot
#   ./build.sh --repl                 # build + launch interactive REPL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build/arm64-apple-macosx/release"
BINARY="${BUILD_DIR}/MLX_swift"
CHECKOUTS="${SCRIPT_DIR}/.build/checkouts/mlx-swift"

# MLX source root — metal files include from here as "mlx/..."
MLX_ROOT="${CHECKOUTS}/Source/Cmlx/mlx"
METAL_SRC="${MLX_ROOT}/mlx/backend/metal/kernels"

# ── Step 1: SPM build ──────────────────────────────────────────
echo "Building MLX_swift (release)..."
swift build -c release --product MLX_swift

# ── Step 2: Compile default.metallib if needed ─────────────────
METALLIB="${BUILD_DIR}/mlx.metallib"

if [ ! -f "${METALLIB}" ]; then
    echo "Compiling Metal shaders..."

    # Verify the Metal toolchain is installed.
    if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
        echo ""
        echo "ERROR: Metal compiler not found."
        echo "Install it with:"
        echo "  xcodebuild -downloadComponent MetalToolchain"
        exit 1
    fi

    # Collect all top-level .metal files (skip subdirectories that
    # have their own includes and are pulled in transitively).
    METAL_FILES=()
    while IFS= read -r -d '' f; do
        METAL_FILES+=("$f")
    done < <(find "${METAL_SRC}" -maxdepth 1 -name "*.metal" -print0 2>/dev/null)

    # Also grab metal files from steel/ subdirectory
    while IFS= read -r -d '' f; do
        METAL_FILES+=("$f")
    done < <(find "${METAL_SRC}/steel" -name "*.metal" -print0 2>/dev/null)

    if [ ${#METAL_FILES[@]} -eq 0 ]; then
        echo "ERROR: No .metal files found in ${METAL_SRC}" >&2
        exit 1
    fi

    # Compile each .metal to .air, using MLX_ROOT as the include path
    AIR_FILES=()
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "${TMP_DIR}"' EXIT

    for metal_file in "${METAL_FILES[@]}"; do
        base=$(basename "${metal_file}" .metal)
        # Use directory-relative name to avoid clashes
        rel="${metal_file#${METAL_SRC}/}"
        air_name="${rel//\//_}"
        air_file="${TMP_DIR}/${air_name%.metal}.air"

        xcrun -sdk macosx metal \
            -c "${metal_file}" \
            -o "${air_file}" \
            -I "${MLX_ROOT}" \
            2>/dev/null || true

        if [ -f "${air_file}" ]; then
            AIR_FILES+=("${air_file}")
        fi
    done

    if [ ${#AIR_FILES[@]} -eq 0 ]; then
        echo "ERROR: No .air files produced. Check Metal compiler output." >&2
        exit 1
    fi

    echo "  Compiled ${#AIR_FILES[@]} shader(s), linking..."

    # Link .air files into mlx.metallib (the name MLX looks for first)
    xcrun -sdk macosx metallib \
        "${AIR_FILES[@]}" \
        -o "${METALLIB}"

    echo "  Metal shaders compiled -> mlx.metallib"
fi

# ── Step 3: Run ────────────────────────────────────────────────
if [ $# -eq 0 ]; then
    echo "Build complete. Binary: ${BINARY}"
    echo "Run with: ${BINARY} \"your prompt\""
elif [ "$1" = "--repl" ]; then
    exec "${BINARY}"
else
    exec "${BINARY}" "$@"
fi
