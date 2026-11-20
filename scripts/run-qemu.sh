#!/bin/sh
# Boot the qemuarm64 build (EDK2 + grub-efi + Mender A/B) under TCG.
# The disk is a working copy, so Mender updates persist across runs.
#   scripts/run-qemu.sh          boot the existing working copy
#   scripts/run-qemu.sh --reset  start over from the freshly built image
# SSH: ssh -p 2222 root@localhost; the app is forwarded to localhost:18080
set -e

TOP=$(cd "$(dirname "$0")/.." && pwd)
DEPLOY="$TOP/my-qemuarm64/build/tmp/deploy/images/qemuarm64"
RUN="$TOP/my-qemuarm64/run"
mkdir -p "$RUN"

# IMG=<file> boots a specific build instead of the latest one
IMG="${IMG:-$DEPLOY/orchontainerstrator-image-qemuarm64.uefiimg}"
BIOS="$DEPLOY/QEMU_EFI.fd"
test -f "$IMG" || { echo "no .uefiimg in $DEPLOY" >&2; exit 1; }
test -f "$BIOS" || { echo "no QEMU_EFI.fd in $DEPLOY" >&2; exit 1; }

# SMBIOS system UUID of this "board". systemd derives the machine-id from it
# under QEMU (on hardware: systemd.machine_id=firmware), so the machine-id
# stays stable without storing it. Kept across --reset like a serial number.
test -f "$RUN/uuid" || cat /proc/sys/kernel/random/uuid > "$RUN/uuid"
# MAC address from the same UUID. The Mender identity is the MAC, and every
# QEMU guest on the default MAC 52:54:00:12:34:56 would look like the same
# device to the server; scripts/mender-api.sh finds this one by run/mac.
MAC="52:54:00:$(cut -c1-6 "$RUN/uuid" | sed 's/\(..\)/\1:/g; s/:$//')"
echo "$MAC" > "$RUN/mac"

if [ "$1" = "--reset" ] || [ ! -f "$RUN/disk.img" ]; then
    echo "creating working copy of $(basename "$IMG")"
    cp --sparse=always "$IMG" "$RUN/disk.img"
fi

exec qemu-system-aarch64 \
    -machine virt -cpu cortex-a57 -smp 4 -m 3072 \
    -accel tcg,thread=multi \
    -bios "$BIOS" \
    -uuid "$(cat "$RUN/uuid")" \
    -drive file="$RUN/disk.img",if=none,format=raw,id=hd0 \
    -device virtio-blk-pci,drive=hd0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::18080-:8080 \
    -device virtio-net-pci,netdev=net0,mac="$MAC" \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -device virtio-rng-pci,rng=rng0 \
    -nographic
