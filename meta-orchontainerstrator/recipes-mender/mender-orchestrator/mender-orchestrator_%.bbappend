# Point the closed-source recipe at the locally downloaded tarball and ship
# this project's Topology. The tarball must stay the first SRC_URI entry.
# scripts/setup.sh downloads it into downloads/ at the top of this repository.
ORCHONTAINER_TOP := "${@os.path.abspath(os.path.join(d.getVar('THISDIR'), '../../..'))}"
ORCHONTAINER_ORCHESTRATOR_TARBALL ??= "${ORCHONTAINER_TOP}/downloads/mender-orchestrator-1.0.0.tar.xz"

# One Topology per test stage (phase0, compose, llm), chosen by
# ORCHONTAINER_STAGE; each stage adds a Component.
ORCHONTAINER_STAGE ??= "llm"
FILESEXTRAPATHS:prepend := "${THISDIR}/files/${ORCHONTAINER_STAGE}:"
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
