SUMMARY = "Keep timesyncd's clock file and the random seed on /data (read-only rootfs)"
DESCRIPTION = "Both live in the tmpfs overlay on /var/lib otherwise and are \
lost on every reboot. Bind mounts from /data, pulled in by the services \
that use them."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://persistent-state-dirs.service \
    file://timesync.mount \
    file://random-seed.mount \
    file://timesyncd-persistent.conf \
"
S = "${UNPACKDIR}"

do_install() {
    u=${D}${systemd_system_unitdir}
    install -d $u $u/systemd-timesyncd.service.d
    install -m 0644 ${S}/persistent-state-dirs.service $u/
    # Unit names must be the escaped mount paths (systemd-escape -p).
    install -m 0644 ${S}/timesync.mount $u/var-lib-systemd-timesync.mount
    install -m 0644 ${S}/random-seed.mount "$u"/'var-lib-systemd-random\x2dseed.mount'
    install -m 0644 ${S}/timesyncd-persistent.conf $u/systemd-timesyncd.service.d/
}

FILES:${PN} = "${systemd_system_unitdir}"
