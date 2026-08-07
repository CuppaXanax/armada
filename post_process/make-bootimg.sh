#!/bin/bash
# Assemble an ABL-bootable Android boot.img and stage it as /KERNEL.
set -euxo pipefail

RAW="${1:-output/image/disk.raw}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MKBOOTIMG="${MKBOOTIMG:-}"
ARMADA_BOOT_DTB="${ARMADA_BOOT_DTB:-}"
ARMADA_BOOT_DEBUG="${ARMADA_BOOT_DEBUG:-0}"

# Single sources shared with the on-device regen (armada-bootimg-update).
ARMADA_LIB="${SCRIPT_DIR}/../system_files/usr/lib/armada"
DTB_LIST="${ARMADA_LIB}/supported-dtbs"
[[ -r "${DTB_LIST}" ]] || { echo "missing DTB list: ${DTB_LIST}"; exit 1; }
SUPPORTED_DTBS=$(cat "${DTB_LIST}")
[[ -r "${ARMADA_LIB}/bootimg-args" ]] || { echo "missing ${ARMADA_LIB}/bootimg-args"; exit 1; }
source "${ARMADA_LIB}/bootimg-args"

[[ -f "${RAW}" ]] || { echo "raw image not found: ${RAW} (run a build first)"; exit 1; }

WORK=$(mktemp -d)
LOOP=$(sudo losetup -fP --show "${RAW}")
trap 'sudo umount "${WORK}/p1" 2>/dev/null||true; sudo umount "${WORK}/p2" 2>/dev/null||true; sudo losetup -d "${LOOP}" 2>/dev/null||true; rm -rf "${WORK}"' EXIT

mkdir -p "${WORK}/p1" "${WORK}/p2"

if [[ -z "${MKBOOTIMG}" ]]; then
    MKBOOTIMG="${SCRIPT_DIR}/../build_files/vendor/mkbootimg/mkbootimg.py"
fi
[[ -x "${MKBOOTIMG}" ]] || { echo "mkbootimg not executable: ${MKBOOTIMG}"; exit 1; }

sudo mount "${LOOP}p2" "${WORK}/p2"          # /boot

# Read the raw entry lines (matching armada-bootimg-update) so the stamp we write
# matches what it computes — a fresh install then skips first-boot regeneration.
BLS=$(armada_default_bls_entry "${WORK}/p2")
[[ -n "${BLS}" ]] || { echo "ERROR: no BLS entry found"; exit 1; }
LINUX_LINE=$(sudo sed -n 's/^linux //p' "${BLS}" | head -1)
INITRD_LINE=$(sudo sed -n 's/^initrd //p' "${BLS}" | head -1)
OPTIONS_LINE=$(sudo sed -n 's/^options //p' "${BLS}" | head -1)
FDTDIR=$(sudo sed -n 's/^fdtdir //p' "${BLS}" | head -1)
[[ "${LINUX_LINE}" == /boot/* ]] || { echo "ERROR: unsupported BLS linux path: ${LINUX_LINE}"; exit 1; }
BOOTDIR=$(dirname "${WORK}/p2${LINUX_LINE#/boot}")
KVER=${LINUX_LINE##*/vmlinuz-}
OPTIONS_LINE=$(armada_normalize_rootflags "${OPTIONS_LINE}")

if [[ -n "${ARMADA_BOOT_DTB}" ]]; then
    grep -Fxq "${ARMADA_BOOT_DTB}" "${DTB_LIST}" \
        || { echo "ERROR: unsupported ARMADA_BOOT_DTB: ${ARMADA_BOOT_DTB}"; exit 1; }
    [[ "${FDTDIR}" == /boot/* ]] || { echo "ERROR: unsupported BLS fdtdir: ${FDTDIR}"; exit 1; }
    SELECTED_DTB="${FDTDIR}/qcom/${ARMADA_BOOT_DTB}.dtb"
    sudo test -s "${WORK}/p2${SELECTED_DTB#/boot}" \
        || { echo "ERROR: selected BLS DTB is missing: ${SELECTED_DTB}"; exit 1; }
    sudo sed -i \
        "s|^fdtdir .*|devicetree ${SELECTED_DTB}|" "${BLS}"
fi
DTB_SPEC=$(sudo sed -n -e 's/^devicetree //p' -e 's/^fdtdir //p' "${BLS}" | head -1)
if [[ "${ARMADA_BOOT_DEBUG}" == 1 ]]; then
    DEBUG_OPTIONS=""
    for _token in ${OPTIONS_LINE}; do
        case "${_token}" in rhgb|quiet|loglevel=*) continue ;; esac
        DEBUG_OPTIONS="${DEBUG_OPTIONS} ${_token}"
    done
    OPTIONS_LINE="${DEBUG_OPTIONS# } loglevel=7 systemd.show_status=1"
fi
sudo sed -i "s|^options .*|options ${OPTIONS_LINE}|" "${BLS}"
STAMP_ID=$(armada_bootimg_id "${LINUX_LINE}" "${INITRD_LINE}" "${OPTIONS_LINE}" "${DTB_LIST}" "${ARMADA_LIB}/bootimg-args" "${DTB_SPEC}")
CMDLINE="${OPTIONS_LINE}"

# Fit the 512-byte cmdline: drop serial console, ostree= first, keep splash kargs.
_drop=" console=ttyS0 "
_ostree=""; _rest=""
for _t in ${CMDLINE}; do
    case "${_drop}" in *" ${_t} "*) continue ;; esac
    case "${_t}" in ostree=*) _ostree="${_t}" ;; *) _rest="${_rest} ${_t}" ;; esac
done
CMDLINE="${_ostree}${_rest}"

if [[ "${#CMDLINE}" -gt "${ARMADA_CMDLINE_MAX}" ]]; then
    echo "ERROR: cmdline is ${#CMDLINE}B, over the ${ARMADA_CMDLINE_MAX}B boot-header limit"; exit 1
fi

# ROCKNIX ABL expects gzip(Image) with DTBs appended.
sudo cat "${BOOTDIR}/vmlinuz-${KVER}" > "${WORK}/vmlinuz"
sudo cat "${BOOTDIR}/initramfs-${KVER}.img" > "${WORK}/initramfs"
gzip -c "${WORK}/vmlinuz" > "${WORK}/kernel.gz"
DTBS_TO_STAGE="${ARMADA_BOOT_DTB:-${SUPPORTED_DTBS}}"
for _name in ${DTBS_TO_STAGE}; do
    _dtb="${BOOTDIR}/dtb/qcom/${_name}.dtb"
    sudo test -f "${_dtb}" || { echo "ERROR: supported DTB missing: ${_dtb}"; exit 1; }
    sudo cat "${_dtb}" >> "${WORK}/kernel.gz"
done

python3 "${MKBOOTIMG}" \
    --kernel "${WORK}/kernel.gz" --ramdisk "${WORK}/initramfs" \
    ${ARMADA_BOOTIMG_ARGS} --os_patch_level "$(date '+%Y-%m')" \
    --cmdline "${CMDLINE}" \
    -o "${WORK}/KERNEL"

sudo mount "${LOOP}p1" "${WORK}/p1"
sudo cp "${WORK}/KERNEL" "${WORK}/p1/KERNEL"
printf '%s' "${STAMP_ID}" | sudo tee "${WORK}/p1/.armada-bootimg.id" >/dev/null
sudo sync

echo "Staged /KERNEL ($(du -h "${WORK}/KERNEL" | cut -f1)) on the FAT partition of ${RAW}"
echo "bls=${BLS} kver=${KVER}"
echo "cmdline=${CMDLINE}"
