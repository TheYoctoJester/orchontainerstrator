SUMMARY = "Mender Orchestrator Interface for a docker compose project"
DESCRIPTION = "Wraps the docker-compose Update Module from mender-container-modules \
and adds Identity, Provides and Inventory."
LICENSE = "Apache-2.0"
# Orchestrator requires the Interface name to equal the Artifact payload type,
# so it shares the name with the Update Module (in a different directory).
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://docker-compose"
S = "${UNPACKDIR}"

RDEPENDS:${PN} = "jq mender-docker-compose mender-orchestrator"

do_install() {
    install -d ${D}${datadir}/mender-orchestrator/interfaces/v1
    install -m 0755 ${S}/docker-compose ${D}${datadir}/mender-orchestrator/interfaces/v1/docker-compose
}

FILES:${PN} = "${datadir}/mender-orchestrator/interfaces/v1/docker-compose"
