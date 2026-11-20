#!/bin/bash
# Small client for the hosted Mender management API, for the test scripts.
# Authenticates with MENDER_HOSTED_PAT (a Personal Access Token of the
# organization) from the environment.
#
#   mender-api.sh upload-artifact <file>
#   mender-api.sh upload-manifest <file>
#   mender-api.sh deploy <deployment-name> <artifact-or-manifest-name> [timeout-s]
#                   waits, prints the device status (success, failure,
#                   already-installed, ...) as the last line
#   mender-api.sh device-id               the device with this VM's MAC
#   mender-api.sh accept <pubkey-base64>  accept the matching auth set
#   mender-api.sh list-project            this project's Artifacts and Manifests
#   mender-api.sh delete-project          delete them and decommission the device
#
# The device is the one with the MAC from my-qemuarm64/run/mac (written by
# scripts/run-qemu.sh), or DEVICE_MAC.
set -e

: "${MENDER_HOSTED_PAT:?}"
TOP=$(cd "$(dirname "$0")/.." && pwd)
SERVER="https://hosted.mender.io/api/management"
# Everything this project uploads; other releases are never touched.
ARTIFACT_RE='^(rootfs-|probe-|app-|llm-|model-)'
MANIFEST_RE='^(m[1-3]-|a[1-4]-|c[0-9]+-|v1-)'

api() {
    curl -sS -H "Authorization: Bearer $MENDER_HOSTED_PAT" "$@"
}

upload() {
    local out code
    out=$(mktemp)
    code=$(api -o "$out" -w '%{http_code}' --form-string "description=orchontainerstrator" \
        -F "artifact=@$2" "$SERVER/v1/deployments/$1")
    echo "$(basename "$2"): $code $(head -c 200 "$out")"
    rm -f "$out"
    [ "$code" = 201 ]
}

device_id() {
    local mac="${DEVICE_MAC:-$(cat "$TOP/my-qemuarm64/run/mac" 2>/dev/null)}"
    [ -n "$mac" ] || { echo "no MAC: start scripts/run-qemu.sh or set DEVICE_MAC" >&2; return 1; }
    api "$SERVER/v2/devauth/devices?per_page=500" \
        | jq -r --arg mac "$mac" '.[] | select(.identity_data.mac == $mac) | .id'
}

deploy() {
    local name="$1" artifact="$2" timeout="${3:-1800}" dev id end st ds last=""
    dev=$(device_id)
    [ -n "$dev" ] || { echo "device not found on the server" >&2; return 1; }
    id=$(api -D - -o /dev/null -H 'Content-Type: application/json' \
        -d "{\"name\":\"$name\",\"artifact_name\":\"$artifact\",\"devices\":[\"$dev\"]}" \
        "$SERVER/v1/deployments/deployments" | tr -d '\r' | sed -n 's|^location: .*/||p')
    [ -n "$id" ] || { echo "creating deployment $name failed" >&2; return 1; }
    echo "deployment $name ($artifact): $id" >&2
    end=$(( $(date +%s) + timeout ))
    while [ "$(date +%s)" -lt "$end" ]; do
        st=$(api "$SERVER/v1/deployments/deployments/$id" | jq -r .status)
        ds=$(api "$SERVER/v1/deployments/deployments/$id/devices" | jq -r '.[0].status')
        if [ "$ds" != "$last" ]; then echo "  $(date +%T) $ds" >&2; last="$ds"; fi
        [ "$st" = finished ] && break
        sleep 10
    done
    if [ "$st" != finished ]; then echo timeout; return 0; fi
    echo "$ds"
}

accept() {
    local dev aid
    dev=$(device_id)
    aid=$(api "$SERVER/v2/devauth/devices/$dev" | jq -r --arg k "$1" \
        '.auth_sets[] | select((.pubkey | gsub("\n";"") | gsub("-----[A-Z ]+-----";"")) == $k) | .id')
    [ -n "$aid" ] || { echo "no auth set with that key on device $dev" >&2; return 1; }
    api -o /dev/null -w "accept $aid: %{http_code}\n" -X PUT -H 'Content-Type: application/json' \
        -d '{"status":"accepted"}' "$SERVER/v2/devauth/devices/$dev/auth/$aid/status"
}

project_artifacts() {
    api "$SERVER/v1/deployments/artifacts" | jq -r --arg re "$ARTIFACT_RE" '.[] | select(.name | test($re)) | "\(.id) \(.name)"'
}

project_manifests() {
    api "$SERVER/v1/deployments/manifests?per_page=500" | jq -r --arg re "$MANIFEST_RE" '.[] | select(.name | test($re)) | .name'
}

case "$1" in
    upload-artifact) upload artifacts "$2" ;;
    upload-manifest) upload manifests "$2" ;;
    deploy) deploy "$2" "$3" "$4" ;;
    device-id) device_id ;;
    accept) accept "$2" ;;
    list-project)
        echo "Artifacts:"; project_artifacts | sed 's/^/  /'
        echo "Manifests:"; project_manifests | sed 's/^/  /'
        echo "Device: $(device_id)"
        ;;
    delete-project)
        project_artifacts | while read -r id name; do
            api -o /dev/null -w "artifact $name: %{http_code}\n" -X DELETE "$SERVER/v1/deployments/artifacts/$id"
        done
        project_manifests | while read -r name; do
            api -o /dev/null -w "manifest $name: %{http_code}\n" -X DELETE "$SERVER/v1/deployments/manifests?name=$name"
        done
        for dev in $(device_id); do
            api -o /dev/null -w "device $dev: %{http_code}\n" -X DELETE "$SERVER/v2/devauth/devices/$dev"
        done
        ;;
    *) sed -n '2,15p' "$0"; exit 1 ;;
esac
