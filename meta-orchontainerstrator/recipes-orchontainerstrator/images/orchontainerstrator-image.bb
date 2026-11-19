SUMMARY = "Single device managed as a Mender Orchestrator System"
LICENSE = "MIT"

inherit core-image

# Everything mutable lives on /data; finding what still writes is part of
# the evaluation.
IMAGE_FEATURES += "read-only-rootfs"

IMAGE_INSTALL = " \
    packagegroup-core-boot \
    ${CORE_IMAGE_EXTRA_INSTALL} \
    mender-docker-compose \
    container-storage \
    probe-interface \
    ca-certificates \
    curl \
    jq \
"
