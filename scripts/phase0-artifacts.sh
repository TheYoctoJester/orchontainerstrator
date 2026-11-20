#!/bin/sh
# Generate phase 0 Artifacts and Manifest Artifacts into artifacts/phase0/.
#
#   rootfs-v1/v2       the built rootfs payload, written under both names
#   probe-v1/v2.mender module-image Artifacts for the "probe" Interface
#   m1..m3 Manifests, in two variants:
#     ./                 with artifact_path, for standalone runs (phase0-push.sh)
#     managed/           artifact_name only, for upload to the Mender server
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
# Where scripts/phase0-push.sh puts the Artifacts on the device. A missing
# artifact_path falls back to artifact_name with a warning; the managed
# variant leaves the paths out so server deployments log no such warnings.
DEVICE_DIR="/data/phase0"
PATH="$TOP/.venv/bin:$PATH"

mkdir -p "$OUT"
cd "$OUT"

# --- rootfs ---------------------------------------------------------------
# BUILT=<file> uses a specific build instead of the latest one
BUILT="${BUILT:-$DEPLOY/orchontainerstrator-image-qemuarm64.mender}"
test -f "$BUILT" || { echo "no built .mender in $DEPLOY" >&2; exit 1; }
rm -rf dump && mkdir dump
mender-artifact dump --files dump "$BUILT"
ROOTFS=$(ls dump/* | head -n1)
# The built Artifact also provides rootfs-image.update-module.<module>.*
# keys (versioned with the build name); a device flashed with the build
# starts with them. Carry them over, or the Provides of rootfs-v1 differ
# from the flashed image and the Orchestrator installs instead of skipping.
BUILT_NAME=$(mender-artifact read "$BUILT" 2>/dev/null | sed -n 's/^ *Name: //p' | head -n1)
MODULE_PROVIDES=$(mender-artifact read "$BUILT" 2>/dev/null \
    | sed -n 's/^ *\(rootfs-image\.update-module\.[^:]*\): \(.*\)$/\1:\2/p')
for v in v1 v2; do
    set --
    for p in $MODULE_PROVIDES; do
        test "${p#*:}" = "$BUILT_NAME" && p="${p%%:*}:rootfs-$v"
        set -- "$@" --provides "$p"
    done
    mender-artifact write rootfs-image \
        --file "$ROOTFS" \
        --compatible-types "$DEVICE_TYPE" \
        --artifact-name rootfs-$v \
        "$@" \
        --output-path rootfs-$v.mender
done
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
# manifest <dir> <name> <rootfs> <probe>
# Entries get an artifact_path when $LOCAL is set.
entry() {
    echo "  $1:"
    echo "    artifact_name: $2"
    test -n "$LOCAL" && echo "    artifact_path: $DEVICE_DIR/$2.mender"
    echo "    update_strategy:"
    echo "      order: $3"
}

manifest() {
    dir="$1" name="$2" rootfs="$3" probe="$4"
    {
        echo 'api_version: "mender/v1"'
        echo 'kind: "manifest"'
        echo "name: \"$name\""
        echo "system_types_compatible: [\"$SYSTEM_TYPE\"]"
        echo
        echo "component_types:"
        entry "$DEVICE_TYPE" "$rootfs" 10
        entry probe "$probe" 20
    } > "$dir/$name.yaml"
    mender-orchestrator-manifest-gen \
        --system-type "$SYSTEM_TYPE" \
        --output-path "$dir/$name.mender" \
        "$dir/$name.yaml"
}

mkdir -p managed
for dir in . managed; do
    LOCAL=; test "$dir" = . && LOCAL=1
    manifest "$dir" m1-probe-v1  rootfs-v1 probe-v1
    manifest "$dir" m2-rootfs-v2 rootfs-v2 probe-v2
    manifest "$dir" m3-rollback  rootfs-v1 probe-v1
done

ls -la "$OUT" "$OUT/managed"
