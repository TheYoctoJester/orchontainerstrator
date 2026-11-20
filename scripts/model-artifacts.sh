#!/bin/sh
# Generate llm-model Artifacts for the model Component into artifacts/model/
# from the GGUF files in downloads/models/ (not in git).
#
#   model-smollm2-135m   SmolLM2-135M-Instruct Q8_0   architecture llama
#   model-smollm2-360m   SmolLM2-360M-Instruct Q8_0   architecture llama
#   model-qwen3-0.6b     Qwen3-0.6B Q4_0              architecture qwen3
#                        (llama.cpp server >= b5092; b5074 cannot load it)
set -e

TOP=$(cd "$(dirname "$0")/.." && pwd)
MODELS="$TOP/downloads/models"
OUT="$TOP/artifacts/model"
mkdir -p "$OUT"

model() {
    name="$1" file="$2" arch="$3"
    test -f "$MODELS/$file" || { echo "missing $MODELS/$file" >&2; exit 1; }
    # GGUF is not compressible; compression only costs time on the device.
    mender-artifact write module-image \
        --type llm-model \
        --compatible-types model \
        --artifact-name "$name" \
        --provides "llm-model.name:$name" \
        --provides "llm-model.architecture:$arch" \
        --clears-provides 'llm-model.*' \
        --no-default-clears-provides \
        --no-default-software-version \
        --compression none \
        --file "$MODELS/$file" \
        --output-path "$OUT/$name.mender"
}

model model-smollm2-135m SmolLM2-135M-Instruct-Q8_0.gguf llama
model model-smollm2-360m SmolLM2-360M-Instruct-Q8_0.gguf llama
model model-qwen3-0.6b   Qwen3-0.6B-Q4_0.gguf            qwen3

ls -la "$OUT"
