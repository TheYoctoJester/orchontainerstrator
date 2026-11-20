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
- Provides skipping compares the Interface's `Provides` output with the
  Artifact's Provides; the probe reports `artifact_name` (header-info) plus
  type-info provides, which was sufficient. See the second managed run for
  which keys count.
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
  M1 skipped the rootfs while its `artifact_name` was
  `m2-rootfs-v2_INCONSISTENT`, so `artifact_name` is not compared. The nested
  `mender-update install` while mender-updated runs the Manifest deployment
  did not conflict. The other direction does matter, see the second run.
- A missing `artifact_path` makes Orchestrator fall back to `artifact_name`
  with a warning per Component (tested in standalone mode); it is not an
  error.
- After the rollback reboot the clock was at 2018 again, the status upload
  failed with "Unauthorized" and was retried after 60 s, successfully once
  NTP had synced. The RTC gap costs about a minute per reboot in reporting.
- The journal is volatile, so logs of the boot before a reboot are lost;
  M3 was captured with `journalctl -f` into /data.

## Managed mode, second run on the partition layout (2026-11-20)

Fresh disk with the new layout (see below), Artifacts rebuilt and
re-uploaded under the same names, Manifests unchanged on the server. Start
state rootfs-v1 (previous build) without probe, so the standalone order
applies again.

| Test | Manifest | Expected | Result |
|---|---|---|---|
| M1 | m1: rootfs-v1 + probe-v1 | rootfs skipped, probe installed | rootfs **installed** (reboot), then probe; deployment success |
| M1b | m1 again | nothing to do | pass: deployment "already-installed", nothing ran on the device |
| M2 | m2: rootfs-v2 + probe-v2 | rootfs, reboot, probe | pass; new rootfs (hvc0 getty removed) delivered OTA, `systemctl is-system-running` = running 30 s after boot |
| M3 | m3, probe ArtifactCommit fails | rollback incl. committed rootfs | pass; back on /dev/vda2 with rootfs-v2 + probe-v2, deployment "failure", status reported at once (no 2018 clock) |

Findings:

- **Skipping compares all Provides, not names.** The rebuilt `rootfs-v1`
  provides a different `rootfs-image.checksum` than the installed build of
  the same name, so Orchestrator installed it although `rootfs-image.version`
  matched. Same name, different content gets installed; that is the right
  behaviour, and it corrects the earlier reading that only the version is
  compared. Orchestrator does not log the reason for installing a Component.
- **The built Artifact provides more than its payload.** A device flashed
  with the build starts with ten `rootfs-image.update-module.<module>.*`
  Provides from the built Artifact. A `rootfs-v1` written again from the
  dumped payload lacks them, so even with the right checksum it is
  installed instead of skipped (seen in the fresh end-to-end replay).
  `scripts/phase0-artifacts.sh` now carries them over.
- **The rootfs commit overwrites the System's `artifact_name`.** In the
  commit phase mender-update first records the Manifest
  (`artifact_name=<manifest>`), then Orchestrator's deferred rootfs commit
  runs mender-update on the same database and sets `artifact_name` to the
  rootfs Artifact name. After every deployment that touches the rootfs, the
  server inventory shows `rootfs-vN` instead of the Manifest name.
  `data-partition.mender-orchestrator-manifest.version` keeps the Manifest
  name, and redeploying the same Manifest was still detected as
  "already-installed" (mechanism not verified, presumably via those
  Provides). Same in the first run's M2, overlooked there.
- The 60 s "Unauthorized" status retry after reboots is gone with the RTC.

## Partition layout and write classification (2026-11-20)

8 GB disk: EFI 16 MB, rootfs A/B 1.4 GB each (397 MB used), `/data` 1 GB,
log 256 MB at `/var/log`, `/apps` 4 GB, all ext4. Verified after a fresh
flash and a reboot:

| What | Where | How |
|---|---|---|
| Mender, Orchestrator, Interface state, docker-compose module store | /data | unchanged |
| timesyncd clock file, random seed | /data/system | bind mounts pulled in by the services; seed loaded and rewritten each boot |
| machine-id | derived | systemd reads the SMBIOS UUID under QEMU (`run-qemu.sh -uuid`); hardware would use `systemd.machine_id=firmware` |
| journal | log partition | persistent, `SystemMaxUse=160M`; `journalctl --list-boots` spans reboots |
| syslog, wtmp/btmp/lastlog | eliminated | busybox syslog dropped, systemd without utmp |
| docker, containerd data | /apps | `RequiresMountsFor=/apps`; container output to the journal |
| tmpfs overlays | ephemeral | only empty directories and the random-seed mount point |

Sizing notes: `mender-growfs-data` is off once extra partitions exist, so
the sizes are final for a device. The docker-compose module stages
`images.tar.gz` plus its extracted copy under the Orchestrator datastore on
/data; the model Interface must stream its payload in Download, otherwise
Orchestrator stages it on /data too.

## Platform findings

- No RTC under EDK2/ACPI (`/dev/rtc*` missing although `RTC_DRV_PL031=y`):
  the clock started at 2018 until NTP synced (~40 s). Fixed with
  `CONFIG_RTC_DRV_EFI=y`; the kernel sets the time from rtc-efi at 0.9 s.
- `serial-getty@hvc0` waited for a console `run-qemu.sh` does not provide and
  held up multi-user.target for 90 s. Fixed with `SERIAL_CONSOLES` =
  ttyAMA0 only.

## Read-only rootfs: runtime writes captured by the tmpfs overlays (before the rework)

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

- The System `artifact_name` overwritten by the rootfs commit: report
  upstream together with the module issue, and decide whether the demo
  needs a workaround.
- The docker-compose module with an actual composition (moves into the
  compose Interface work).
- Report the up-to-date Manifest failure of the Update Module upstream.
- Whether `install` refuses while a deployment is unfinished (standalone).
