#!/bin/bash
# Replay all test stages from scratch: phase 0 (standalone and managed),
# compose (A1-A4) and LLM (L0-L4), each with its own Topology, rolled
# forward over the air between the stages.
#
#   scripts/replay.sh build      setup, three stage builds, all Artifacts
#   scripts/replay.sh upload     upload Artifacts and Manifests
#   scripts/replay.sh flash      accept the freshly booted device (start it
#                                first: IMG=artifacts/builds/phase0.uefiimg
#                                scripts/run-qemu.sh --reset)
#   scripts/replay.sh phase0     T1-T3 standalone, M1b-M3 managed
#   scripts/replay.sh compose    rollout to the compose Topology, A1-A4
#   scripts/replay.sh llm        rollout to the LLM Topology, L0-L4
#   scripts/replay.sh tests      phase0, compose and llm in order
#
# Every test prints one PASS/FAIL line into artifacts/replay/results.txt.
# Expected results are the ones established in docs/*-results.md, including
# the known failure of M1b (Update Module, up-to-date Manifest).
#
# Needs MENDER_HOSTED_PAT, MENDER_HOSTED_USER, MENDER_HOSTED_PASS.
set -e

TOP=$(cd "$(dirname "$0")/.." && pwd)
S="$TOP/scripts"
OUT="$TOP/artifacts"
BUILDS="$OUT/builds"
RESULTS="$OUT/replay/results.txt"
KAS_TYJ="tyj-local.yml:tyj-debug.yml:tyj-mender.yml"
DEPLOY="$TOP/my-qemuarm64/build/tmp/deploy/images/qemuarm64"
API="$S/mender-api.sh"
PROBE="/data/orchontainerstrator/probe"
mkdir -p "$BUILDS" "$(dirname "$RESULTS")"

log() { echo "$(date +%T) $*" >&2; }

dev() {
    ssh -p 2222 -i "$TOP/keys/replay_ed25519" -o IdentitiesOnly=yes \
        -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
        -o LogLevel=ERROR -o ConnectTimeout=5 root@localhost "$@"
}

wait_ssh() {
    local end=$(( $(date +%s) + ${1:-600} ))
    until dev true 2>/dev/null; do
        [ "$(date +%s)" -lt "$end" ] || { log "device unreachable"; return 1; }
        sleep 5
    done
}

boot_id() { dev cat /proc/sys/kernel/random/boot_id; }

# Wait until the device has rebooted (boot id changed) and is reachable.
wait_reboot() {
    local old="$1" end=$(( $(date +%s) + 600 ))
    while :; do
        [ "$(date +%s)" -lt "$end" ] || { log "no reboot seen"; return 1; }
        sleep 5
        dev true 2>/dev/null || continue
        [ "$(boot_id)" != "$old" ] && break
    done
    sleep 20   # let mender-updated and the containers come up
}

provides() { dev 'mender-orchestrator show-provides 2>/dev/null'; }

# has <provides-regex>...: all must match the current Provides
has() {
    local p r
    p=$(provides)
    for r in "$@"; do echo "$p" | grep -q -E "$r" || { log "missing: $r"; return 1; }; done
}

result() {   # result <test> <PASS|FAIL> <detail>
    printf '%-8s %-5s %s\n' "$1" "$2" "$3" | tee -a "$RESULTS"
}

check() {    # check <test> <detail> <command...>
    local t="$1" d="$2"; shift 2
    if "$@"; then result "$t" PASS "$d"; else result "$t" FAIL "$d"; fi
}

deploy() {   # deploy <test> <manifest> <expected device status>
    local st
    st=$("$API" deploy "replay-$1-$(date +%H%M%S)" "$2" 1800 | tail -n1)
    log "$1: $st (expected $3)"
    [ "$st" = "$3" ]
}

completion() {
    curl -sS -m 120 http://localhost:18080/completion \
        -d '{"prompt":"The capital of France is","n_predict":8}' | jq -r '.content // empty'
}

# --- build ------------------------------------------------------------------
build_stage() {   # build_stage <stage>
    log "building stage $1"
    (cd "$TOP/my-qemuarm64" && env -u TMPDIR kas build \
        "../kas/orchontainerstrator-qemuarm64.yml:../kas/stage-$1.yml:$KAS_TYJ" \
        > "$TOP/my-qemuarm64/build-replay-$1.log" 2>&1)
    cp -L "$DEPLOY/orchontainerstrator-image-qemuarm64.mender" "$BUILDS/$1.mender"
    cp -L --sparse=always "$DEPLOY/orchontainerstrator-image-qemuarm64.uefiimg" "$BUILDS/$1.uefiimg"
}

do_build() {
    "$S/setup.sh"
    mkdir -p "$TOP/my-qemuarm64"
    (cd "$TOP/my-qemuarm64" && for f in tyj-local tyj-debug tyj-mender; do
        ln -sf "$HOME/kas/$f.yml" "$f.yml"; done)
    build_stage phase0
    BUILT="$BUILDS/phase0.mender" "$S/phase0-artifacts.sh" > /dev/null
    build_stage compose
    build_stage llm
    log "skopeo-native for the compose Artifacts"
    (cd "$TOP/my-qemuarm64" && env -u TMPDIR kas shell \
        "../kas/orchontainerstrator-qemuarm64.yml:../kas/stage-llm.yml:$KAS_TYJ" \
        -c "bitbake skopeo-native -c addto_recipe_sysroot" > build-replay-skopeo.log 2>&1)
    "$S/compose-artifacts.sh" > /dev/null
    "$S/model-artifacts.sh" > /dev/null
    BUILT="$BUILDS/compose.mender" "$S/manifests.sh" "$TOP/manifests/compose.txt"
    BUILT="$BUILDS/llm.mender" "$S/manifests.sh" "$TOP/manifests/llm.txt"
}

do_upload() {
    local f
    for f in "$OUT"/phase0/rootfs-v1.mender "$OUT"/phase0/rootfs-v2.mender \
             "$OUT"/phase0/probe-v1.mender "$OUT"/phase0/probe-v2.mender \
             "$BUILDS/compose.mender" "$BUILDS/llm.mender" \
             "$OUT"/compose/*.mender "$OUT"/model/*.mender; do
        "$API" upload-artifact "$f"
    done
    for f in "$OUT"/phase0/managed/m*.mender "$OUT"/manifests/c2-*.mender "$OUT"/manifests/c3-*.mender; do
        "$API" upload-manifest "$f"
    done
}

# The VM runs outside this script (it has to outlive it):
#   IMG=artifacts/builds/phase0.uefiimg scripts/run-qemu.sh --reset
do_flash() {
    local key end
    wait_ssh
    sleep 20
    key=$(dev 'openssl pkey -in /data/mender/mender-agent.pem -pubout | grep -v PUBLIC')
    end=$(( $(date +%s) + 300 ))
    until "$API" accept "$key"; do
        [ "$(date +%s)" -lt "$end" ] || return 1
        sleep 10
    done
    dev 'systemctl restart mender-authd mender-updated'
    sleep 15
}

# --- phase 0 ----------------------------------------------------------------
do_phase0() {
    local b
    log "phase 0 standalone"
    "$S/phase0-push.sh" > /dev/null

    dev "mender-orchestrator install /data/phase0/m1-probe-v1.yaml" > /dev/null 2>&1 || true
    check T1 "rootfs-v1 skipped, probe-v1 installed" \
        has 'qemuarm64.*rootfs-image.version=rootfs-v1' 'probe.*probe.version=v1'

    out=$(dev "mender-orchestrator install /data/phase0/m1-probe-v1.yaml" 2>&1 || true)
    check T1b "nothing to install" grep -q "already up to date" <<< "$out"

    b=$(boot_id)
    dev "mender-orchestrator install /data/phase0/m2-rootfs-v2.yaml" > /dev/null 2>&1 || true
    wait_reboot "$b"
    dev "mender-orchestrator resume" > /dev/null 2>&1 || true
    check T2 "rootfs-v2 after reboot, then probe-v2" \
        has 'qemuarm64.*rootfs-image.version=rootfs-v2' 'probe.*probe.version=v2'

    dev "touch $PROBE/ArtifactCommit.FAIL"
    b=$(boot_id)
    dev "mender-orchestrator install /data/phase0/m3-rollback.yaml" > /dev/null 2>&1 || true
    wait_reboot "$b"
    b=$(boot_id)
    dev "mender-orchestrator resume" > /dev/null 2>&1 || true
    wait_reboot "$b"
    out=$(dev "mender-orchestrator resume" 2>&1 || true)
    dev "rm -f $PROBE/ArtifactCommit.FAIL; rm -rf /data/phase0"
    check T3 "probe commit fails, System rollback incl. committed rootfs" \
        eval 'grep -q "Rollback finished with status: Success" <<< "$out" &&
              has "qemuarm64.*rootfs-image.version=rootfs-v2" "probe.*probe.version=v2"'

    log "phase 0 managed"
    check M1b "installed Manifest fails (known Update Module issue)" \
        deploy M1b m2-rootfs-v2 failure
    dev "rm -f $PROBE/provides.*"
    check M1 "rootfs skipped, probe from the server" \
        eval 'deploy M1 m2-rootfs-v2 success && has "probe.*probe.version=v2"'
    check M2 "rootfs-v1 with reboot, then probe-v1" \
        eval 'deploy M2 m1-probe-v1 success && has "qemuarm64.*rootfs-image.version=rootfs-v1" "probe.*probe.version=v1"'
    dev "touch $PROBE/ArtifactCommit.FAIL"
    check M3 "probe commit fails, rollback incl. rootfs" \
        eval 'deploy M3 m2-rootfs-v2 failure && sleep 20 && has "qemuarm64.*rootfs-image.version=rootfs-v1" "probe.*probe.version=v1"'
    dev "rm -f $PROBE/ArtifactCommit.FAIL"
}

# --- compose ----------------------------------------------------------------
do_compose() {
    log "compose stage"
    check C-R0 "rollout to the compose Topology" \
        eval 'deploy C-R0 c2-r0-rollout success && sleep 20 && dev "grep -q component_type:\ app /usr/share/mender-orchestrator/topology.yaml"'
    check A1 "app-v1 installed and serving" \
        eval 'deploy A1 c2-a1-app-v1 success && curl -s -m 10 localhost:18080 | grep -q "app v1"'
    check A2 "app-v2, old image removed" \
        eval 'deploy A2 c2-a2-app-v2 success && curl -s -m 10 localhost:18080 | grep -q "app v2" &&
              ! dev "docker images --format {{.Tag}}" | grep -q 1.36.1'
    check A3 "broken healthcheck rolled back to v2" \
        eval 'deploy A3 c2-a3-app-broken failure && curl -s -m 10 localhost:18080 | grep -q "app v2"'
    dev "touch $PROBE/ArtifactCommit.FAIL"
    check A4 "app rolled back after its commit" \
        eval 'deploy A4 c2-a4-commit-fails failure && curl -s -m 10 localhost:18080 | grep -q "app v2" &&
              has "app.*artifact_name=app-v2" "probe.*probe.version=v1"'
    dev "rm -f $PROBE/ArtifactCommit.FAIL"
}

# --- llm --------------------------------------------------------------------
do_llm() {
    log "llm stage"
    check L0 "rollout to the LLM Topology" \
        eval 'deploy L0 c3-l0-rollout success && sleep 20 && dev "grep -q component_type:\ model /usr/share/mender-orchestrator/topology.yaml"'
    check L1 "first LLM install, server answers" \
        eval 'deploy L1 c3-l1-first-llm success && [ -n "$(completion)" ]'
    check L2 "model update with self-test" \
        eval 'deploy L2 c3-l2-model-360m success && has "model.*artifact_name=model-smollm2-360m"'
    check L3 "Qwen3 on b5074 rolled back, server answers" \
        eval 'deploy L3 c3-l3-qwen3-old failure && has "model.*artifact_name=model-smollm2-360m" &&
              [ -n "$(completion)" ] && ! dev "journalctl -t llm-model-interface -b --since -10min" | grep -q "failed its self-test after the rollback"'
    check L4 "server b5106, then Qwen3" \
        eval 'deploy L4 c3-l4-qwen3-new success && has "model.*artifact_name=model-qwen3-0.6b" "app.*artifact_name=llm-b5106" &&
              [ -n "$(completion)" ]'
}

case "$1" in
    build) do_build ;;
    upload) do_upload ;;
    flash) do_flash ;;
    phase0) do_phase0 ;;
    compose) do_compose ;;
    llm) do_llm ;;
    tests) do_phase0; do_compose; do_llm ;;
    *) sed -n '2,20p' "$0"; exit 1 ;;
esac
