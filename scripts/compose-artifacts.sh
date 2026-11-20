#!/bin/bash
# Generate docker-compose Artifacts for the app Component into
# artifacts/compose/: one per directory in compose/, named after it
# (gen_docker-compose from mender-container-modules).
#
# Requires: mender-artifact, m4, skopeo-native from the build
#   (kas shell ... -c "bitbake skopeo-native -c addto_recipe_sysroot")
set -e

TOP=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$TOP/my-qemuarm64/build"
OUT="$TOP/artifacts/compose"
GEN_SRC="$TOP/downloads/mender-container-modules"
GEN_TAG="1.1.0"
PROJECT="orchontainer"
ARCH="arm64"

SKOPEO=$(ls "$BUILD"/tmp/work/x86_64-linux/skopeo-native/*/recipe-sysroot-native/usr/sbin/skopeo 2>/dev/null | head -n1)
test -x "$SKOPEO" || { echo "no skopeo-native sysroot, see the header of $0" >&2; exit 1; }
PATH="$(dirname "$SKOPEO"):$PATH"

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

ls -la "$OUT"
