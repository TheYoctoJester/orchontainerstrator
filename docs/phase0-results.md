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

## Managed mode (hosted Mender, 2026-11-20)

Component Artifacts uploaded as regular Artifacts
(`POST /api/management/v1/deployments/artifacts`); Manifest Artifacts are
rejected there ("invalid update type: mender-orchestrator-manifest") and go
to `POST /api/management/v1/deployments/manifests` (Enterprise). A normal
deployment (`POST .../v1/deployments/deployments`) with
`artifact_name: <manifest name>` targets the System device. Manifests from
`artifacts/phase0/managed/` (no `artifact_path`), `/data/phase0` removed.
Start state rootfs-v2 + probe-v2, so the order differs from standalone.

| Test | Manifest | Expected | Result |
|---|---|---|---|
| M1b | m2 (all installed) | nothing to do, success | **fail**: see below |
| M1 | m2 after clearing probe Provides | rootfs skipped, probe fetched from server | pass, 20 s |
| M2 | m1: rootfs-v1 + probe-v1 | rootfs, reboot, probe, no manual `resume` | pass; probe ran after the reboot |
| M3 | m2, probe ArtifactCommit fails | rollback incl. committed rootfs | pass; device back on /dev/vda2, rootfs-v1 + probe-v1, deployment "failure" |

Findings:

- **Up-to-date Manifest fails the deployment.** The
  `mender-orchestrator-manifest` Update Module (mender-orchestrator-support
  1.0.0) runs `install` in ArtifactInstall. If all Components are up to
  date, Orchestrator finishes there with exit 0 and leaves no deployment, so
  `resume` in ArtifactCommit, ArtifactRollback and Cleanup returns exit 2
  "Nothing to resume". mender-update reports Failure and sets
  `artifact_name=<manifest>_INCONSISTENT`. Triggered here by a Manifest whose
  name differs from the installed `artifact_name`; the module needs a
  "nothing installed" marker like its `no-needs-reboot` one.
- **Shared mender-update database.** The rootfs-image Interface wraps the
  same mender-update that installs the Manifest Artifact, so the rootfs
  Component's Provides include the Manifest's `artifact_name` (including the
  `_INCONSISTENT` one) and `data-partition.mender-orchestrator-manifest.version`.
  Harmless so far: skip decisions use the payload Provides
  (`rootfs-image.version`), M1 skipped the rootfs while its `artifact_name`
  was `m2-rootfs-v2_INCONSISTENT`. The nested `mender-update install` while
  mender-updated runs the Manifest deployment did not conflict.
- A missing `artifact_path` makes Orchestrator fall back to `artifact_name`
  with a warning per Component (tested in standalone mode); it is not an
  error.
- After the rollback reboot the clock was at 2018 again, the status upload
  failed with "Unauthorized" and was retried after 60 s, successfully once
  NTP had synced. The RTC gap costs about a minute per reboot in reporting.
- The journal is volatile, so logs of the boot before a reboot are lost;
  M3 was captured with `journalctl -f` into /data.

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

## Still open after phase 0

- The docker-compose module with an actual composition (moves into the
  compose Interface work).
- Report the up-to-date Manifest failure of the Update Module upstream.
- Whether `install` refuses while a deployment is unfinished (standalone).
