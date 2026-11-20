SUMMARY = "Authorized SSH key for root, for the test scripts (demo only)"
DESCRIPTION = "Installs the public key that scripts/setup.sh generates in \
keys/ as root's only way in. Root has no password (locked by the image \
class), so this is key-only access. Pulled in by kas/demo-access.yml."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

ORCHONTAINER_TOP := "${@os.path.abspath(os.path.join(d.getVar('THISDIR'), '../../..'))}"
ORCHONTAINER_SSH_PUBKEY ??= "${ORCHONTAINER_TOP}/keys/replay_ed25519.pub"

# Read from outside the layer, so track it explicitly for rebuilds.
do_install[file-checksums] += "${ORCHONTAINER_SSH_PUBKEY}:True"

inherit allarch

do_install() {
    test -f "${ORCHONTAINER_SSH_PUBKEY}" || bbfatal "no SSH key ${ORCHONTAINER_SSH_PUBKEY}, run scripts/setup.sh"
    install -d -m 0700 ${D}${ROOT_HOME}/.ssh
    install -m 0600 "${ORCHONTAINER_SSH_PUBKEY}" ${D}${ROOT_HOME}/.ssh/authorized_keys
}

FILES:${PN} = "${ROOT_HOME}/.ssh"
