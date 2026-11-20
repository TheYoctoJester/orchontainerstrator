SUMMARY = "Persistent, size-capped journal on the log partition"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://persistent.conf"
S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${systemd_unitdir}/journald.conf.d
    install -m 0644 ${S}/persistent.conf ${D}${systemd_unitdir}/journald.conf.d/50-persistent.conf
}

FILES:${PN} = "${systemd_unitdir}/journald.conf.d"
