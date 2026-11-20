SUMMARY = "Single device managed as a Mender Orchestrator System"
LICENSE = "MIT"

inherit core-image

# Every write is classified: Mender and system state on /data, the journal
# on the log partition, containers and models on /apps, the rest ephemeral
# in tmpfs. Finding what still writes is part of the evaluation.
IMAGE_FEATURES += "read-only-rootfs"

IMAGE_INSTALL = " \
    packagegroup-core-boot \
    ${CORE_IMAGE_EXTRA_INSTALL} \
    mender-docker-compose \
    compose-interface \
    container-storage \
    llm-model-interface \
    persistent-journal \
    persistent-state \
    probe-interface \
    ca-certificates \
    curl \
    jq \
"
