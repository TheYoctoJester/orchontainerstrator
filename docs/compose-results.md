# Compose Interface results (2026-11-20)

Setup: rootfs-c2 (partition layout, Topology in the rootfs), Topology
`qemuarm64` (rootfs-image, order 10), `app` (docker-compose Interface,
order 20), `probe` (order 30). Managed mode through hosted Mender.
Artifacts and Manifests from `scripts/compose-artifacts.sh`; compositions in
`compose/` (busybox httpd with a healthcheck, forwarded to localhost:18080).

The Interface (`docker-compose`) wraps the docker-compose Update Module
from mender-container-modules 1.1.0 and adds Identity, Provides and
Inventory. Provides are kept as current/previous in
`/data/orchontainerstrator/app/`.

| Test | Manifest | Expected | Result |
|---|---|---|---|
| A1 | c2-a1: app-v1 | rootfs skipped, app installed, probe-v1 | pass; page "app v1", container healthy |
| A2 | c2-a2: app-v2 | new image, old image removed | pass; busybox 1.36.1 removed in Cleanup |
| A3 | c2-a3: app-v3-broken | healthcheck never passes, back to v2 | pass; "running:unhealthy" at the timeout, v2 healthy again, deployment "failure" |
| A4 | c2-a4: app-v1 + probe-v2, probe ArtifactCommit fails | app rolled back after its commit | pass; "Rolling back after a Commit", v2 healthy, v1 image removed |

Findings:

- **The Interface name must equal the Artifact payload type.** The first
  attempt with an Interface called `compose` failed in ArtifactInstall:
  "Update Interface does not match Artifact payload_type: 'compose' !=
  'docker-compose'". The Interface is now called `docker-compose`, like the
  Update Module (different directory). The probe matched because its
  payload type and Interface name were both `probe`.
- **Manifest and Topology must match exactly.** A Topology Component missing
  from the Manifest: "Component type extra not found in manifest". A
  Manifest entry missing from the Topology: "Cannot find interface for
  component type". Both are checked when an install starts, not on resume:
  a standalone install whose reboot brought a Topology with an extra
  Component resumed and finished with Success. A new Component can
  therefore arrive with a rootfs update, followed by a deployment that
  names it.
- **The Topology lives in the rootfs.** Orchestrator only reads
  `/data/mender-orchestrator/topology.yaml` and has no option for another
  path; it follows a symlink. The data partition image now contains a
  symlink to `/usr/share/mender-orchestrator/topology.yaml`, so Topology and
  Interfaces are versioned and rolled back together. Migrating an already
  flashed device over the air would leave a dangling symlink if that one
  deployment rolled back to the old rootfs, so the device was reflashed.
- **Health timeout under TCG.** The module's `WAIT_TIMEOUT=120` counts loop
  iterations with `sleep 1`, each also running `docker compose ps` and
  `docker inspect`. Under TCG A3 took about 4.5 minutes to give up.
  `/etc/mender/mender-docker-compose.conf` can lower it.
- **Rollback after a failed install, examined, not staged.** The module
  treats a rollback without `uncommitted` marker and without `previous` as
  "rollback after commit" and stops the current composition. That happens
  only if ArtifactInstall fails after `parse_metadata` and before it moves
  `current` aside, i.e. a Docker API failure in `discover_requirements`
  that recovers before the rollback. A broken Artifact fails
  `parse_metadata` in install and rollback alike and leaves the running app
  untouched.
- Rootfs Artifact names are bumped per uploaded build (`rootfs-c1`, `-c2`),
  Manifest names carry the build (`c2-a1-app-v1`), so nothing on the
  server has to be deleted for a rebuild.
