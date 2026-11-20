#!/bin/bash
# Generate the compose stage Artifacts and Manifest Artifacts into
# artifacts/compose/.
#
#   app-v1, app-v2, app-v3-broken  docker-compose Artifacts from compose/<name>/
#                                  (gen_docker-compose, mender-container-modules)
#   <build>-a1..a4 Manifests (artifact_name only, for the Mender server):
#     a1-app-v1         first install of the app
#     a2-app-v2         app update, new image
#     a3-app-broken     healthcheck never passes -> install fails, back to v2
#     a4-commit-fails   app-v1 + probe-v2; inject probe ArtifactCommit.FAIL
#                       first -> app rolled back after its commit, to v2
#
# The rootfs and probe entries name the Artifacts already on the server; the
# rootfs name is read from the latest build.
#
# Requires: mender-artifact, m4, skopeo-native from the build
#   (kas shell ... -c "bitbake skopeo-native -c addto_recipe_sysroot")
# and the project venv for mender-orchestrator-manifest-gen.
set -e

TOP=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$TOP/my-qemuarm64/build"
DEPLOY="$BUILD/tmp/deploy/images/qemuarm64"
OUT="$TOP/artifacts/compose"
GEN_SRC="$TOP/downloads/mender-container-modules"
GEN_TAG="1.1.0"
SYSTEM_TYPE="orchontainer"
DEVICE_TYPE="qemuarm64"
PROJECT="orchontainer"
ARCH="arm64"

SKOPEO=$(ls "$BUILD"/tmp/work/x86_64-linux/skopeo-native/*/recipe-sysroot-native/usr/sbin/skopeo 2>/dev/null | head -n1)
test -x "$SKOPEO" || { echo "no skopeo-native sysroot, see the header of $0" >&2; exit 1; }
PATH="$(dirname "$SKOPEO"):$TOP/.venv/bin:$PATH"

# The generator from the same release as the Update Module on the device.
if [ ! -x "$GEN_SRC/src/gen_docker-compose" ]; then
    rm -rf "$GEN_SRC"
    git clone -q --depth 1 --branch "$GEN_TAG" \
        https://github.com/mendersoftware/mender-container-modules "$GEN_SRC"
    make -C "$GEN_SRC" src/gen_docker-compose
fi

mkdir -p "$OUT"
cd "$OUT"

# --- app Artifacts --------------------------------------------------------
for dir in "$TOP"/compose/*/; do
    name=$(basename "$dir")
    images="$OUT/images-$name"
    rm -rf "$images" && mkdir "$images"
    # Fetch arm64 images ourselves so the archive tag matches the manifest's
    # image: reference (docker load tags from it).
    for image in $(sed -n 's/^[[:space:]]*image:[[:space:]]*//p' "$dir"/*.yaml); do
        skopeo copy --override-os linux --override-arch "$ARCH" \
            "docker://docker.io/library/$image" \
            "docker-archive:$images/$(echo "$image" | tr '/:@' '_').tar:$image"
    done
    "$GEN_SRC/src/gen_docker-compose" \
        --artifact-name "$name" \
        --device-type app \
        --project-name "$PROJECT" \
        --manifests-dir "$dir" \
        --images-dir "$images" \
        --output-path "$OUT/$name.mender" \
        -- --software-filesystem apps-partition > /dev/null
    rm -rf "$images"
done

# --- manifests ------------------------------------------------------------
ROOTFS=$(mender-artifact read "$DEPLOY/orchontainerstrator-image-qemuarm64.mender" 2>/dev/null \
    | sed -n 's/^  Name: //p' | head -n1)
test -n "$ROOTFS" || { echo "cannot read the built rootfs Artifact name" >&2; exit 1; }

# Manifest names must be unique on the server; prefix them with the rootfs
# build (rootfs-c2 -> c2-a1-app-v1).
PREFIX="${ROOTFS#rootfs-}-"

entry() {
    echo "  $1:"
    echo "    artifact_name: $2"
    echo "    update_strategy:"
    echo "      order: $3"
}

manifest() {
    name="$PREFIX$1" app="$2" probe="$3"
    {
        echo 'api_version: "mender/v1"'
        echo 'kind: "manifest"'
        echo "name: \"$name\""
        echo "system_types_compatible: [\"$SYSTEM_TYPE\"]"
        echo
        echo "component_types:"
        entry "$DEVICE_TYPE" "$ROOTFS" 10
        entry app "$app" 20
        entry probe "$probe" 30
    } > "$name.yaml"
    mender-orchestrator-manifest-gen \
        --system-type "$SYSTEM_TYPE" \
        --output-path "$name.mender" \
        "$name.yaml"
}

manifest a1-app-v1       app-v1        probe-v1
manifest a2-app-v2       app-v2        probe-v1
manifest a3-app-broken   app-v3-broken probe-v1
manifest a4-commit-fails app-v1        probe-v2

ls -la "$OUT"
