# Model Interface results (2026-11-20)

Setup: rootfs-c3, Topology `qemuarm64` (rootfs-image), `app`
(docker-compose), `model` (llm-model), `probe`. Managed mode through hosted
Mender. Artifacts from `scripts/compose-artifacts.sh` (llama.cpp server
stacks in `compose/llm-*`) and `scripts/model-artifacts.sh`, Manifests from
`scripts/manifests.sh manifests/llm.txt`.

The `llm-model` Interface keeps the model in A/B slots on /apps
(`/apps/models/{a,b}/model.gguf`, `active` symlink). Download streams the
payload into the inactive slot; ArtifactInstall switches the symlink,
restarts the containers labelled `orchontainer.llm-model-consumer=true`
(they bind-mount `/apps/models/active`) and self-tests them: health, then
an 8-token completion. Rollback switches back and restarts again.

## llama.cpp version pair, confirmed on the device

| Server | SmolLM2-135M (llama) | Qwen3-0.6B (qwen3) |
|---|---|---|
| server-b5074 | loads, completion in 2 s | exits: "unknown model architecture: 'qwen3'" |
| server-b5106 | loads, completion in 1 s | loads, completion in 4 s |

## Deployments

| Test | Manifest | Expected | Result |
|---|---|---|---|
| L0 | rootfs-c3, app-v2, probe-v1 (no model) | Topology change over the air | pass; Manifest validated against the old Topology, rootfs-c3 brought the `model` Component, busybox app kept running across the reboot |
| L1 | model-135m (order 15), llm-b5074 (20) | model before its server | pass; streamed into slot a, no consumer yet so self-test skipped, server healthy, answers from the host |
| L2 | llm-b5074 (20), model-360m (25) | slot switch with self-test | pass; slot b, self-test "Paris. - Paris is the capital" |
| L3 | llm-b5074, model-qwen3 | server cannot load the model | pass; server crashed on load, Interface failed the install, rolled back to slot b / 360m, server answers again, deployment "failure" |
| L4 | llm-b5106 (20), model-qwen3 (25) | server first, then the model | pass; slot a, self-test "Paris. If you go to Paris,", b5074 image removed |

Findings:

- **Streaming keeps /data out of it.** With the Interface reading the
  streams in Download, /data stayed below 1 MB while 145 to 386 MB models
  were installed; the docker-compose module, which does not stream, stages
  its images on /data.
- **The Manifest decides the order per deployment.** The first install
  needs the model before the server (order 15 vs 20), the Qwen3 update
  needs the server before the model (20 vs 25). Both are plain Manifest
  data, the Topology does not change.
- **A slot switch needs a container restart.** Docker resolves the
  symlinked bind-mount source on container start; a running container keeps
  the old slot (verified with a test container).
- **`docker restart` resets RestartCount.** The self-test compared the
  restart count from before `docker restart`, so after the crash loop in
  L3 the rollback's own self-test reported a false failure ("previous model
  failed its self-test after the rollback") although the server answered.
  Fixed in the Interface (baseline read after the restart); the fix is not
  yet on the device (rootfs-c3).
- Download for a Component runs when its turn in the order comes, not up
  front: in L4 the model streamed after the app had been installed.
- llama.cpp loads the models in seconds even under TCG; the self-test
  completion took 2 to 10 s.
