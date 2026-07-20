#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
firmware="${work}/firmware"
manifest="${root}/system_files/usr/lib/armada/firmware-sm8250.list"

while IFS= read -r pattern || [[ -n "${pattern}" ]]; do
    case "${pattern}" in ''|'#'*) continue ;; esac
    [[ "${pattern}" == 'qcom/sm8250/slpi*' ]] && continue
    path=${pattern/\*/test}
    mkdir -p "$(dirname "${firmware}/${path}")"
    printf 'firmware:%s\n' "${pattern}" | xz -c > "${firmware}/${path}.xz"
done < "${manifest}"

mkdir -p "${firmware}/qcom/sm8250/Thundercomm/RB5"
printf 'slpi firmware\n' | xz -c > "${firmware}/qcom/sm8250/Thundercomm/RB5/slpi.mbn.xz"
printf '{}\n' > "${firmware}/qcom/sm8250/Thundercomm/RB5/slpir.jsn"

bash "${root}/build_files/normalize-sm8250-firmware.sh" "${firmware}" "${manifest}"

while IFS= read -r pattern || [[ -n "${pattern}" ]]; do
    case "${pattern}" in ''|'#'*) continue ;; esac
    compgen -G "${firmware}/${pattern}" >/dev/null
done < "${manifest}"
grep -Fqx 'slpi firmware' "${firmware}/qcom/sm8250/slpi.mbn"
if find "${firmware}" -type f -name '*.xz' -print -quit | grep -q .; then
    echo 'Compressed RP5 firmware remained after normalization' >&2
    exit 1
fi

echo 'SM8250 compressed firmware normalization passed'