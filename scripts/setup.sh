#!/bin/sh
# Fetch everything the build and the Artifact scripts need that is not in
# git, into downloads/ and .venv/:
#   - mender-orchestrator 1.0.0 tarball (hosted Mender credentials,
#     MENDER_HOSTED_USER / MENDER_HOSTED_PASS from the environment)
#   - mender-orchestrator-manifest-gen from mender-orchestrator-support 1.0.0,
#     plus python yq, in .venv
#   - the GGUF models for the model Component
set -e

TOP=$(cd "$(dirname "$0")/.." && pwd)
DL="$TOP/downloads"
ORCH_VERSION="1.0.0"
mkdir -p "$DL/models"

if [ ! -f "$DL/mender-orchestrator-$ORCH_VERSION.tar.xz" ]; then
    : "${MENDER_HOSTED_USER:?}" "${MENDER_HOSTED_PASS:?}"
    curl -sS --fail -u "$MENDER_HOSTED_USER:$MENDER_HOSTED_PASS" \
        -o "$DL/mender-orchestrator-$ORCH_VERSION.tar.xz" \
        "https://downloads.customer.mender.io/content/hosted/mender-orchestrator/yocto/$ORCH_VERSION/mender-orchestrator-$ORCH_VERSION.tar.xz"
fi

if [ ! -x "$TOP/.venv/bin/mender-orchestrator-manifest-gen" ]; then
    python3 -m venv "$TOP/.venv"
    "$TOP/.venv/bin/pip" install -q yq
    rm -rf "$DL/mender-orchestrator-support"
    git clone -q --depth 1 --branch "$ORCH_VERSION" \
        https://github.com/mendersoftware/mender-orchestrator-support "$DL/mender-orchestrator-support"
    install -m 0755 \
        "$DL/mender-orchestrator-support/modules/mender-orchestrator-manifest/module-artifact-gen/mender-orchestrator-manifest-gen" \
        "$TOP/.venv/bin/"
fi

model() {
    test -f "$DL/models/$1" || curl -sSL --fail -o "$DL/models/$1" "$2"
}
model SmolLM2-135M-Instruct-Q8_0.gguf https://huggingface.co/unsloth/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q8_0.gguf
model SmolLM2-360M-Instruct-Q8_0.gguf https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf
model Qwen3-0.6B-Q4_0.gguf            https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_0.gguf

sha256sum "$DL/mender-orchestrator-$ORCH_VERSION.tar.xz" "$DL"/models/*.gguf
