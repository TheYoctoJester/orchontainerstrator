#!/bin/sh
# Boot the qemuarm64 build (EDK2 + grub-efi + Mender A/B) under TCG.
# The disk is a working copy, so Mender updates persist across runs.
#   scripts/run-qemu.sh          boot the existing working copy
#   scripts/run-qemu.sh --reset  start over from the freshly built image
# SSH: ssh -p 2222 root@localhost
set -e

TOP=$(cd "$(dirname "$0")/.." && pwd)
DEPLOY="$TOP/my-qemuarm64/build/tmp/deploy/images/qemuarm64"
RUN="$TOP/my-qemuarm64/run"
mkdir -p "$RUN"

IMG=$(ls "$DEPLOY"/orchontainerstrator-image-qemuarm64*.uefiimg 2>/dev/null | head -n1)
BIOS="$DEPLOY/QEMU_EFI.fd"
test -n "$IMG" || { echo "no .uefiimg in $DEPLOY" >&2; exit 1; }
test -f "$BIOS" || { echo "no QEMU_EFI.fd in $DEPLOY" >&2; exit 1; }

if [ "$1" = "--reset" ] || [ ! -f "$RUN/disk.img" ]; then
    echo "creating working copy of $(basename "$IMG")"
    cp --sparse=always "$IMG" "$RUN/disk.img"
fi

exec qemu-system-aarch64 \
    -machine virt -cpu cortex-a57 -smp 4 -m 3072 \
    -accel tcg,thread=multi \
    -bios "$BIOS" \
    -drive file="$RUN/disk.img",if=none,format=raw,id=hd0 \
    -device virtio-blk-pci,drive=hd0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -device virtio-rng-pci,rng=rng0 \
    -nographic
