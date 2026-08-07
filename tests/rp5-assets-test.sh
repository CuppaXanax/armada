#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
profile="${root}/system_files/usr/lib/armada/devices/retroid-pocket-5.conf"
device_env="${root}/system_files/usr/libexec/armada/device-env"
firmware="${root}/system_files/usr/lib/armada/firmware-sm8250.list"
finalize="${root}/post_process/finalize-armada-image.sh"
flash="${root}/abl/flash_abl.sh.template"

grep -qx 'sm8250-retroidpocket-rp5' "${root}/system_files/usr/lib/armada/supported-dtbs"
grep -Fqx '    "Retroid Pocket 5") profile=retroid-pocket-5 ;;' "${device_env}"
for expected in \
    'ARMADA_DEVICE_ID=retroid-pocket-5' \
    'ARMADA_SOC_CLASS=SM8250' \
    'ARMADA_PANEL_ORIENTATION=left' \
    'ARMADA_PANEL_NATIVE_WIDTH=1080' \
    'ARMADA_PANEL_NATIVE_HEIGHT=1920'; do
    grep -Fqx "${expected}" "${profile}"
done

for pattern in \
    qcom/a650_gmu.bin \
    qcom/a650_sqe.fw \
    qcom/sm8250/a650_zap.mbn \
    qcom/sm8250/adsp.mbn \
    qcom/sm8250/cdsp.mbn \
    'qcom/sm8250/slpi*' \
    qcom/vpu-1.0/venus.mbn \
    'ath11k/QCA6390/hw2.0/*.bin' \
    qca/htbtfw20.tlv \
    qca/htnv20.bin; do
    grep -Fqx "${pattern}" "${firmware}"
done

grep -Fq 'COPY system_files /system_files/' "${root}/Containerfile"
grep -Fq 'cp -a /ctx/system_files/. /' "${root}/build_files/40-vendor-system-files.sh"
grep -Fq 'sm8250-retroidpocket-rp5.dtb' "${root}/build_files/20-install-kernel.sh"
grep -Fq 'normalize-sm8250-firmware.sh' "${root}/build_files/20-install-kernel.sh"
grep -Fq 'EFI/BOOT/BOOTAA64.EFI' "${root}/post_process/finalize-armada-image.sh"
if grep -Fq 'EFI.disabled' "${root}/post_process/finalize-armada-image.sh"; then
    echo 'RP5 image must retain the standard EFI removable-media path' >&2
    exit 1
fi
grep -Fq 'ARMADA_BOOT_DTB: sm8250-retroidpocket-rp5' "${root}/.github/workflows/build-rp5.yml"
grep -Fq 'BLS=$(armada_default_bls_entry "${WORK}/p2")' "${root}/post_process/make-bootimg.sh"
grep -Fq 'devicetree ${SELECTED_DTB}' "${root}/post_process/make-bootimg.sh"
grep -Fq 'DTBS_TO_STAGE="${ARMADA_BOOT_DTB:-${SUPPORTED_DTBS}}"' "${root}/post_process/make-bootimg.sh"
grep -Fq 'devicetree=$(sed' "${root}/system_files/usr/libexec/armada/armada-bootimg-update"
grep -Fq 'ARMADA_BOOT_DEBUG: ${{' "${root}/.github/workflows/build-rp5.yml"
grep -Fq 'OPTIONS_LINE=$(armada_normalize_rootflags' "${root}/post_process/make-bootimg.sh"
grep -Fq 'options=$(armada_normalize_rootflags' "${root}/system_files/usr/libexec/armada/armada-bootimg-update"
source "${root}/system_files/usr/lib/armada/bootimg-args"
normalized=$(armada_normalize_rootflags 'rootflags=subvol=/root rw rootflags=noatime,compress=zstd:1')
test "${normalized}" = 'rw rootflags=subvol=/root,noatime,compress=zstd:1'
grep -Fq 'ARMADA_CPU_PROFILE=${ARMADA_CPU_PROFILE:-default}' "${root}/Justfile"
grep -Fq 'ARMADA_PACKAGE_CPU_PROFILE=default' "${root}/Containerfile"
grep -Fq 'carrier CPU profile mismatch' "${root}/build_files/30-install-steam-session.sh"
grep -Fq 'ARMADA_CPU_PROFILE:-default}" == sm8250' "${root}/build_files/30-install-steam-session.sh"
grep -Fq 'ARMADA_CPU_PROFILE:-default}" != sm8250' "${root}/build_files/70-cleanup.sh"
grep -Fq 'ARMADA_CPU_PROFILE:-default}" == sm8250' \
    "${root}/system_files/etc/gamescope-session-plus/sessions.d/steam"

test -f "${root}/system_files/usr/lib/udev/rules.d/99-retroid-pocket.rules"
grep -Fq 'capability_map_id: retroid_mcu' \
    "${root}/system_files/usr/share/inputplumber/devices/01-retroid-controller.yaml"
grep -Fq 'id: retroid_mcu' \
    "${root}/system_files/usr/share/inputplumber/capability_maps/retroid_mcu.yaml"
for alias in \
    RetroidPocket.conf \
    retroidpocket-RetroidPocket5.conf \
    retroid-RetroidPocket5-conf; do
    test -f "${root}/system_files/usr/share/alsa/ucm2/conf.d/sm8250/${alias}"
done

grep -Fq 'ROCKNIX_ABL_VERSION="${ROCKNIX_ABL_VERSION:-v1.1.4}"' "${finalize}"
grep -Fq 'for soc in SM8250 SM8550 SM8650 SM8750' "${finalize}"
verify_line=$(grep -nF 'sha256sum -c "abl_signed-${soc}.elf.sha256"' "${finalize}" | cut -d: -f1)
mount_line=$(grep -nF 'losetup -fP --show' "${finalize}" | cut -d: -f1)
test "${verify_line}" -lt "${mount_line}"

backup_line=$(grep -nF '[ -s "${backup}" ]' "${flash}" | head -1 | cut -d: -f1)
target_check_line=$(grep -nF '[ -w "${target}" ]' "${flash}" | cut -d: -f1)
write_line=$(grep -nF 'dd if="${image}"' "${flash}" | cut -d: -f1)
test "${backup_line}" -lt "${write_line}"
test "${target_check_line}" -lt "${write_line}"

echo 'RP5 asset and ABL safety checks passed'
