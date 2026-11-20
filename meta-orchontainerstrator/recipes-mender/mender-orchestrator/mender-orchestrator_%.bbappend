# Point the closed-source recipe at the locally downloaded tarball and ship
# this project's Topology. The tarball must stay the first SRC_URI entry.
ORCHONTAINER_ORCHESTRATOR_TARBALL ??= ""

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI = "file://${ORCHONTAINER_ORCHESTRATOR_TARBALL} file://topology.yaml"

# The Topology belongs to the rootfs, next to the Interfaces it references:
# it is versioned and rolled back with the A/B rootfs. Orchestrator only
# reads it from its datastore on /data, so that becomes a symlink.
TOPOLOGY_ROOTFS_PATH = "${datadir}/mender-orchestrator/topology.yaml"

do_install:append() {
    install -d ${D}${datadir}/mender-orchestrator
    install -m 0644 ${UNPACKDIR}/topology.yaml ${D}${TOPOLOGY_ROOTFS_PATH}
    ln -sf ${TOPOLOGY_ROOTFS_PATH} ${D}/data/mender-orchestrator/topology.yaml
}

FILES:${PN} += "${TOPOLOGY_ROOTFS_PATH}"
