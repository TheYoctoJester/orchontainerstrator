# Point the closed-source recipe at the locally downloaded tarball and ship
# this project's Topology. The tarball must stay the first SRC_URI entry.
ORCHONTAINER_ORCHESTRATOR_TARBALL ??= ""

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI = "file://${ORCHONTAINER_ORCHESTRATOR_TARBALL} file://topology.yaml"
