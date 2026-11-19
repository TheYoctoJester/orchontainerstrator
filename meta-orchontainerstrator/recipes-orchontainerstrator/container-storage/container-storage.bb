SUMMARY = "Move docker and containerd persistent state to /data (read-only rootfs)"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://daemon.json file://config.toml"
S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/docker ${D}${sysconfdir}/containerd
    install -m 0644 ${S}/daemon.json ${D}${sysconfdir}/docker/daemon.json
    install -m 0644 ${S}/config.toml ${D}${sysconfdir}/containerd/config.toml
}

FILES:${PN} = "${sysconfdir}/docker/daemon.json ${sysconfdir}/containerd/config.toml"
