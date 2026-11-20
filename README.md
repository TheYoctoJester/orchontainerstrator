# orchontainerstrator

A proof of concept for [Mender Orchestrator](https://docs.mender.io/) on a
single device: the base OS, a docker compose application and an LLM model
file are separate Components. Each is updated on its own, in the order a
Manifest gives, and a failure in any of them rolls back the whole System,
including a rootfs that was already committed.

The device is a qemuarm64 Yocto build (wrynose, EDK2 + grub-efi, Mender A/B,
read-only rootfs) managed through hosted Mender. A replay script builds
everything, uploads it, and runs all test scenarios against the VM.

## What is in here

| Path | Content |
|---|---|
| `kas/` | Build configuration, one override per test stage, the hosted Mender connection and the demo SSH access |
| `meta-orchontainerstrator/` | Image, partition layout, persistent state, and the three Orchestrator Interfaces |
| `compose/` | docker compose projects for the app Component (busybox test stacks, llama.cpp servers) |
| `manifests/` | Manifests per test stage, one line each |
| `scripts/` | Setup, Artifact and Manifest generation, QEMU, server API, the replay |
| `docs/` | Results and findings per stage |

The Interfaces, in `meta-orchontainerstrator/recipes-orchontainerstrator/`:

- `docker-compose` wraps the docker-compose Update Module from
  mender-container-modules 1.1.0 and adds Identity, Provides and Inventory.
- `llm-model` keeps the model in A/B slots on `/apps`, streams the payload
  into the inactive slot, switches, restarts the inference server and
  self-tests it with a short completion. A model the running server cannot
  load is rolled back.
- `probe` logs every call and fails a state on request (touch
  `/data/orchontainerstrator/probe/<State>.FAIL`). It is part of every
  Topology because the rollback tests use it.

The rootfs Component uses the `rootfs-image` Interface that ships with
Orchestrator.

## Test stages

Each stage has its own Topology, built into the rootfs; the device moves
from one to the next with an ordinary deployment.

| Stage | Topology | Tests | Results |
|---|---|---|---|
| phase0 | rootfs, probe | T1 to T3 standalone (`mender-orchestrator install`), M1b to M3 from the server | [docs/phase0-results.md](docs/phase0-results.md) |
| compose | adds the app | A1 to A4: install, update, broken healthcheck, rollback after commit | [docs/compose-results.md](docs/compose-results.md) |
| llm | adds the model | L0 to L4: first install, model update, a model the server cannot load, server update before the model | [docs/llm-results.md](docs/llm-results.md) |

The results documents are the evaluation log, in the order things were
found; earlier sections can be superseded by later ones.

## Requirements

- A Linux host that can build Yocto wrynose, with
  [kas](https://kas.readthedocs.io/) (tested with 5.4), 50 GB of disk or
  more (without `rm_work`) and some hours for the first build.
- `mender-artifact` (tested with 4.4.2), `qemu-system-aarch64` (8.2),
  `jq`, `curl`, `git`, `make`, `m4`, `python3` with venv, OpenSSH client.
- A hosted Mender tenant (US instance) with the Enterprise plan, which
  Orchestrator needs, and in the environment:

| Variable | Used for |
|---|---|
| `MENDER_HOSTED_USER`, `MENDER_HOSTED_PASS` | downloading the Orchestrator tarball from downloads.customer.mender.io |
| `MENDER_TENANT_TOKEN` | built into the image |
| `MENDER_HOSTED_PAT` | a Personal Access Token for the management API |

Mender Orchestrator is closed source; `scripts/setup.sh` downloads it into
`downloads/`, which stays out of git.

## Running it

Lets build everything, upload it and run all stages:

```sh
scripts/replay.sh build
scripts/replay.sh upload
IMG=artifacts/builds/phase0.uefiimg scripts/run-qemu.sh --reset   # in a second terminal
scripts/replay.sh flash
scripts/replay.sh tests
```

`build` runs `scripts/setup.sh` (tarball, manifest generator, GGUF models,
SSH key), builds the three stages and generates all Artifacts and
Manifests into `artifacts/`. To reuse download and sstate caches, put them
in a kas file in `my-qemuarm64/` (kas only takes override files from inside
the repository; that directory is ignored by git) and pass its name with
`KAS_EXTRA=caches.yml`.

`flash` waits for the freshly booted VM and accepts it on the server.
`tests` writes one line per test to `artifacts/replay/results.txt` and
exits non-zero if one failed. M1b reports XFAIL: it reproduces a known
issue of the Update Module (an up-to-date Manifest fails the deployment).

The VM is reachable with `ssh -i keys/replay_ed25519 -p 2222 root@localhost`;
port 8080 of the device (the app) is forwarded to `localhost:18080`.

## Server side

Everything is uploaded with the description `orchontainerstrator`;
`scripts/mender-api.sh delete-project` deletes exactly those Artifacts and
Manifests and decommissions the VM. The VM gets a MAC address derived from
its own UUID (`my-qemuarm64/run/`), so it does not collide with other QEMU
devices on the same tenant.

## Demo only

`kas/demo-access.yml` puts an SSH server and a root key into the image so
that the scripts can drive the device. Root has no password and there is no
console login, but leave that file out for anything that is not a demo.
