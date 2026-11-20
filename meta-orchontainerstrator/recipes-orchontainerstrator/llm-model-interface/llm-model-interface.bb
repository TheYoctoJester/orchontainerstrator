SUMMARY = "Mender Orchestrator Interface for an LLM model in A/B slots"
DESCRIPTION = "Streams the model into the inactive slot on /apps, switches \
the active slot, restarts the inference containers and self-tests them."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://llm-model"
S = "${UNPACKDIR}"

# docker comes with mender-docker-compose
RDEPENDS:${PN} = "jq mender-orchestrator"

do_install() {
    install -d ${D}${datadir}/mender-orchestrator/interfaces/v1
    install -m 0755 ${S}/llm-model ${D}${datadir}/mender-orchestrator/interfaces/v1/llm-model
}

FILES:${PN} = "${datadir}/mender-orchestrator/interfaces/v1/llm-model"
