#!/bin/sh
# Copy phase 0 Artifacts and Manifests to /data/phase0 on the QEMU device.
# Uses ssh + cat because the image has no sftp-server.
set -e

TOP=$(cd "$(dirname "$0")/.." && pwd)
SSH="ssh -p 2222 -i $TOP/keys/replay_ed25519 -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR root@localhost"

$SSH 'mkdir -p /data/phase0'
for f in "$TOP"/artifacts/phase0/*.mender "$TOP"/artifacts/phase0/*.yaml; do
    name=$(basename "$f")
    $SSH "cat > /data/phase0/$name" < "$f"
    echo "pushed $name"
done
$SSH 'ls -la /data/phase0; df -h /data'
