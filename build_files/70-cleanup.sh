#!/bin/bash
set -euxo pipefail

# Firmware for unrelated hardware.
dnf5 -y remove --no-autoremove \
    amd-gpu-firmware \
    amd-ucode-firmware \
    brcmfmac-firmware \
    cirrus-audio-firmware \
    intel-audio-firmware \
    intel-gpu-firmware \
    mt7xxx-firmware \
    nvidia-gpu-firmware \
    nxpwireless-firmware \
    qcom-wwan-firmware \
    realtek-firmware \
    tiwilink-firmware

rm -f /usr/lib/binfmt.d/qemu-*.conf

# AWS SDK chain from the bootc base.
dnf5 -y remove --no-autoremove \
    python3-boto3 \
    python3-botocore \
    python3-s3transfer

dnf5 -y remove --no-autoremove binutils

required_packages='qcom-firmware atheros-firmware bootc podman skopeo gamescope gamescope-session mangohud'
if [[ "${ARMADA_CPU_PROFILE:-default}" != sm8250 ]]; then
    required_packages+=' fex-emu-utils'
fi
for required in ${required_packages}; do
    rpm -q "$required" >/dev/null || { echo "ERROR: $required got removed"; exit 1; }
done

if [[ "${ARMADA_CPU_PROFILE:-default}" != sm8250 ]]; then
    # The patched Turnip (Mesa #14656 fix) must be the installed one, not stock Fedora.
    case "$(rpm -q --qf '%{release}' mesa-vulkan-drivers)" in
        *armada*) ;;
        *) echo "ERROR: stock mesa-vulkan-drivers installed; patched .armada Turnip lost"; exit 1 ;;
    esac

    # The patched mangohud (Adreno SM8550 sysfs repoints) must be the installed one.
    case "$(rpm -q --qf '%{release}' mangohud)" in
        *armada*) ;;
        *) echo "ERROR: stock mangohud installed; patched .armada mangohud lost"; exit 1 ;;
    esac
fi

rm -rf \
    /usr/lib/firmware/amdgpu \
    /usr/lib/firmware/amd-ucode \
    /usr/lib/firmware/brcm \
    /usr/lib/firmware/cirrus \
    /usr/lib/firmware/cypress \
    /usr/lib/firmware/intel \
    /usr/lib/firmware/i915 \
    /usr/lib/firmware/iwlwifi-* \
    /usr/lib/firmware/mediatek \
    /usr/lib/firmware/mrvl \
    /usr/lib/firmware/nvidia \
    /usr/lib/firmware/nxp \
    /usr/lib/firmware/rtw89 \
    /usr/lib/firmware/rtl_nic \
    /usr/lib/firmware/ti-connectivity \
    /usr/lib/firmware/xe
