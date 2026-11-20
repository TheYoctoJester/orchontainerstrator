# Phase 0 results (2026-11-19)

Setup: qemuarm64 (TCG, EDK2 + grub-efi), wrynose, mender 5.2.0 (Mender Client 6.1.0),
mender-orchestrator 1.0.0, read-only rootfs. Topology: `qemuarm64`
(rootfs-image Interface) + `probe` (logging Interface). Tests ran in
standalone mode (`mender-orchestrator install` with `artifact_path`),
Artifacts and Manifests from `scripts/phase0-artifacts.sh`.

## Orchestrator behaviour

| Test | Manifest | Expected | Result |
|---|---|---|---|
| T1 | rootfs-v1 (installed) + probe-v1 | rootfs skipped, probe installed, no reboot | pass |
| T1b | same again | nothing installed | pass: "All components are already up to date"; only Identity + Provides called |
| T2 | rootfs-v2 + probe-v2 | rootfs via nested mender-update, reboot, then probe | pass; probe (order 20) only ran after `resume` |
| T3 | rootfs-v1 + probe-v1, probe ArtifactCommit fails | System rollback incl. rootfs | pass; end state rootfs-v2 + probe-v2 |

Observations:

- The rootfs-image Interface wrapping `mender-update` works while the
  `mender-updated` daemon is running.
- Commit order in T3: the rootfs was committed ("Committed.") before the
  probe's ArtifactCommit failed, and was still rolled back. This is the
  deferred `--stop-before ArtifactCommit_Leave` in the rootfs-image Interface.
- Standalone mode needs a manual `resume` after every reboot: after the
  install reboot and again after the rollback reboot (final status
  "Failure (Rollback finished with status: Success)").
- File API per Component under
  `/var/lib/mender-orchestrator/interfaces/v1/deployments/<type>/<n>/payloads/0000/tree`.
  `stream-next` exists in Download; if the Interface does not consume the
  streams, the payload appears in `files/` from ArtifactInstall on.
- Provides skipping compares the Interface's `Provides` output; the probe
  reports `artifact_name` (header-info) plus type-info provides, which was
  sufficient.
- Not verified: whether `install` refuses while a deployment is unfinished
  (the check ran, but its output was lost).

## Platform findings

- No RTC under EDK2/ACPI (`/dev/rtc*` missing although `RTC_DRV_PL031=y`):
  the clock starts at 2018 until NTP syncs (~40 s). TLS fails before that,
  and logs from early after boot carry 2018 timestamps.
- Mender device key is generated with the 2018 timestamp at first boot.

## Read-only rootfs: runtime writes captured by the tmpfs overlays

OE's read-only setup overlays `/var/lib`, `/var/cache`, `/var/spool`,
`/srv` with tmpfs upper layers. Everything written there is lost on reboot.
Writes observed after boot, update and rollback:

| Path | Proposed class |
|---|---|
| `/var/lib/systemd/timesync/clock` | persistent (/data): its mtime is timesyncd's lower bound for the clock, which also mitigates the missing RTC |
| `/var/lib/systemd/random-seed` | persistent (/data) |
| `/var/lib/dbus/machine-id` | persistent or derived; changes every boot today |
| `/var/log/{messages,wtmp,btmp,lastlog}` | ephemeral is fine |

Already on /data: mender, mender-orchestrator, mender-docker-compose,
docker data-root, containerd root, probe state.

Docker on the read-only rootfs: `docker run hello-world` pulls and runs;
image and container state lands in /data/docker and /data/containerd, no
new writes appear in the overlays. `docker compose` (plugin, reports
version "dev") is present, which is what the docker-compose module
looks for first; `docker-compose` (standalone) is not installed.

## Still open for phase 0

- The same T1 to T3 flow through hosted Mender (managed mode, Manifest
  Artifacts uploaded, update module drives reboots).
- The docker-compose module with an actual composition (moves into the
  compose Interface work).
