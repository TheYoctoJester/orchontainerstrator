#!/bin/sh
# Generate phase 0 Artifacts and Manifest Artifacts into artifacts/phase0/.
#
#   rootfs-v1.mender   the built rootfs Artifact (renamed copy)
#   rootfs-v2.mender   same rootfs payload, re-written as rootfs-v2
#   probe-v1/v2.mender module-image Artifacts for the "probe" Interface
#   m1..m3 Manifests:
#     m1-probe-v1        rootfs-v1 (already installed -> expect skip) + probe-v1
#     m2-rootfs-v2       rootfs-v2 + probe-v2 (reboot, both installed in order)
#     m3-rollback        rootfs-v1 + probe-v1; inject probe ArtifactCommit.FAIL
#                        on the device first -> expect System rollback to m2
#
# Requires mender-artifact on the host and the project venv
# (.venv: python yq + mender-orchestrator-manifest-gen from
# mender-orchestrator-support 1.0.0).
set -e

TOP=$(cd "$(dirname "$0")/.." && pwd)
DEPLOY="$TOP/my-qemuarm64/build/tmp/deploy/images/qemuarm64"
OUT="$TOP/artifacts/phase0"
SYSTEM_TYPE="orchontainer"
DEVICE_TYPE="qemuarm64"
PATH="$TOP/.venv/bin:$PATH"

mkdir -p "$OUT"
cd "$OUT"

# --- rootfs ---------------------------------------------------------------
BUILT=$(ls "$DEPLOY"/orchontainerstrator-image-qemuarm64*.mender | head -n1)
test -f "$BUILT" || { echo "no built .mender in $DEPLOY" >&2; exit 1; }
cp "$BUILT" rootfs-v1.mender

rm -rf dump && mkdir dump
mender-artifact dump --files dump rootfs-v1.mender
ROOTFS=$(ls dump/* | head -n1)
mender-artifact write rootfs-image \
    --file "$ROOTFS" \
    --compatible-types "$DEVICE_TYPE" \
    --artifact-name rootfs-v2 \
    --output-path rootfs-v2.mender
rm -rf dump

# --- probe ----------------------------------------------------------------
for v in v1 v2; do
    echo "probe payload $v" > probe-payload
    mender-artifact write module-image \
        --type probe \
        --compatible-types probe \
        --artifact-name probe-$v \
        --provides probe.version:$v \
        --clears-provides 'probe.*' \
        --no-default-clears-provides \
        --no-default-software-version \
        --file probe-payload \
        --output-path probe-$v.mender
done
rm -f probe-payload

# --- manifests ------------------------------------------------------------
manifest() {
    name="$1" rootfs="$2" probe="$3"
    cat > "$name.yaml" <<EOF
api_version: "mender/v1"
kind: "manifest"
name: "$name"
system_types_compatible: ["$SYSTEM_TYPE"]

component_types:
  $DEVICE_TYPE:
    artifact_name: $rootfs
    update_strategy:
      order: 10
  probe:
    artifact_name: $probe
    update_strategy:
      order: 20
EOF
    mender-orchestrator-manifest-gen \
        --system-type "$SYSTEM_TYPE" \
        --output-path "$name.mender" \
        "$name.yaml"
}

manifest m1-probe-v1  rootfs-v1 probe-v1
manifest m2-rootfs-v2 rootfs-v2 probe-v2
manifest m3-rollback  rootfs-v1 probe-v1

ls -la "$OUT"
