SUMMARY = "Logging probe Interface for Mender Orchestrator (phase 0 evaluation)"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://probe"
S = "${UNPACKDIR}"

RDEPENDS:${PN} = "jq mender-orchestrator"

do_install() {
    install -d ${D}${datadir}/mender-orchestrator/interfaces/v1
    install -m 0755 ${S}/probe ${D}${datadir}/mender-orchestrator/interfaces/v1/probe
}

FILES:${PN} = "${datadir}/mender-orchestrator/interfaces/v1/probe"
