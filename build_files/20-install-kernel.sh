#!/bin/bash
set -euxo pipefail

KVER="7.0.11"
TARBALL="/packages/kernel/armada-kernel-${KVER}.tar.zst"

# bootc expects exactly one kernel under /usr/lib/modules.
dnf5 -y remove kernel kernel-core kernel-modules kernel-modules-core 2>/dev/null || true
rm -rf /usr/lib/modules/*

# Verify the shipped checksum.
[ -f "${TARBALL}" ] || { echo "ERROR: kernel tarball missing at ${TARBALL}"; exit 1; }
( cd /packages/kernel && sha256sum -c "armada-kernel-${KVER}.tar.zst.sha256" )

tar --extract --zstd -f "${TARBALL}" -C /usr/
depmod -a "${KVER}" -b /

RP5_DTB="/usr/lib/modules/${KVER}/dtb/qcom/sm8250-retroidpocket-rp5.dtb"
[ -f "${RP5_DTB}" ] || { echo "ERROR: pinned kernel is missing RP5 DTB: ${RP5_DTB}"; exit 1; }

# dracut MODULE_FIRMWARE introspection needs firmware at the build-time path.
mkdir -p /usr/lib/firmware
cp -a /ctx/system_files/usr/lib/firmware/. /usr/lib/firmware/

# Fedora keeps the SM8250 SLPI files in the linux-firmware vendor subdirectory;
# ROCKNIX flattens them because the RP5 DT expects qcom/sm8250/slpi*.mbn.
if ! compgen -G '/usr/lib/firmware/qcom/sm8250/slpi*' >/dev/null; then
    shopt -s nullglob
    slpi_files=(/usr/lib/firmware/qcom/sm8250/Thundercomm/RB5/slpi*)
    [ "${#slpi_files[@]}" -gt 0 ] || { echo "ERROR: SM8250 SLPI firmware is missing"; exit 1; }
    cp -L "${slpi_files[@]}" /usr/lib/firmware/qcom/sm8250/
    shopt -u nullglob
fi

while IFS= read -r pattern || [[ -n "${pattern}" ]]; do
    case "${pattern}" in ''|'#'*) continue ;; esac
    compgen -G "/usr/lib/firmware/${pattern}" >/dev/null \
        || { echo "ERROR: RP5 firmware missing: ${pattern}"; exit 1; }
done < /ctx/system_files/usr/lib/armada/firmware-sm8250.list

# Plymouth theme must exist before dracut bakes the splash into initramfs.
mkdir -p /usr/share/plymouth/themes
cp -a /ctx/system_files/usr/share/plymouth/themes/armada /usr/share/plymouth/themes/

plymouth-set-default-theme armada

dracut \
    --force \
    --no-hostonly \
    --reproducible \
    --kver "${KVER}" \
    --add ostree \
    --add plymouth \
    "/usr/lib/modules/${KVER}/initramfs.img" "${KVER}"

echo "armada kernel ${KVER} installed at /usr/lib/modules/${KVER}/"
ls -la "/usr/lib/modules/${KVER}/" | head -10
