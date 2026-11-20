SUMMARY = "Keep docker and containerd state on the /apps partition, container logs in the journal"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://daemon.json file://config.toml file://apps-mount.conf"
S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/docker ${D}${sysconfdir}/containerd
    install -m 0644 ${S}/daemon.json ${D}${sysconfdir}/docker/daemon.json
    install -m 0644 ${S}/config.toml ${D}${sysconfdir}/containerd/config.toml
    for unit in docker.service containerd.service; do
        install -d ${D}${systemd_system_unitdir}/$unit.d
        install -m 0644 ${S}/apps-mount.conf ${D}${systemd_system_unitdir}/$unit.d/apps-mount.conf
    done
}

FILES:${PN} = " \
    ${sysconfdir}/docker/daemon.json \
    ${sysconfdir}/containerd/config.toml \
    ${systemd_system_unitdir}/docker.service.d \
    ${systemd_system_unitdir}/containerd.service.d \
"
