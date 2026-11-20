#!/bin/sh
# Generate Manifest Artifacts for one test stage into artifacts/manifests/.
#
#   scripts/manifests.sh manifests/<stage>.txt
#
# Each non-comment line of the stage file is one Manifest:
#   <name> <component_type>=<artifact_name>:<order> ...
# "@rootfs" stands for the Artifact name of the build. Manifest names
# get the build as prefix (rootfs-c3 -> c3-<name>) because names must be
# unique on the server.
#
# Requires the project venv for mender-orchestrator-manifest-gen.
set -e

TOP=$(cd "$(dirname "$0")/.." && pwd)
DEPLOY="$TOP/my-qemuarm64/build/tmp/deploy/images/qemuarm64"
OUT="$TOP/artifacts/manifests"
SYSTEM_TYPE="orchontainer"
PATH="$TOP/.venv/bin:$PATH"

STAGE="$1"
test -f "$STAGE" || { echo "usage: $0 manifests/<stage>.txt" >&2; exit 1; }

# BUILT=<file> uses a specific build instead of the latest one
BUILT="${BUILT:-$DEPLOY/orchontainerstrator-image-qemuarm64.mender}"
ROOTFS=$(mender-artifact read "$BUILT" 2>/dev/null \
    | sed -n 's/^  Name: //p' | head -n1)
test -n "$ROOTFS" || { echo "cannot read the built rootfs Artifact name" >&2; exit 1; }
PREFIX="${ROOTFS#rootfs-}-"

mkdir -p "$OUT"
grep -v -E '^[[:space:]]*(#|$)' "$STAGE" | while read -r name entries; do
    name="$PREFIX$name"
    {
        echo 'api_version: "mender/v1"'
        echo 'kind: "manifest"'
        echo "name: \"$name\""
        echo "system_types_compatible: [\"$SYSTEM_TYPE\"]"
        echo
        echo "component_types:"
        for e in $entries; do
            type="${e%%=*}" rest="${e#*=}"
            artifact="${rest%:*}" order="${rest##*:}"
            [ "$artifact" = "@rootfs" ] && artifact="$ROOTFS"
            echo "  $type:"
            echo "    artifact_name: $artifact"
            echo "    update_strategy:"
            echo "      order: $order"
        done
    } > "$OUT/$name.yaml"
    mender-orchestrator-manifest-gen \
        --system-type "$SYSTEM_TYPE" \
        --output-path "$OUT/$name.mender" \
        "$OUT/$name.yaml" > /dev/null 2>&1
    echo "$name"
done
