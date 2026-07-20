#!/bin/bash
set -euo pipefail

firmware_root=${1:-/usr/lib/firmware}
manifest=${2:-/ctx/system_files/usr/lib/armada/firmware-sm8250.list}

expand_pattern() {
    local pattern=$1 compressed target
    while IFS= read -r compressed; do
        [[ -n "${compressed}" ]] || continue
        target=${compressed%.xz}
        [[ -e "${target}" ]] && continue
        echo "Expanding firmware: ${compressed#${firmware_root}/}"
        xz --decompress --stdout -- "${compressed}" > "${target}"
        chmod --reference="${compressed}" "${target}"
        rm -f -- "${compressed}"
    done < <(compgen -G "${firmware_root}/${pattern}.xz" || true)
}

while IFS= read -r pattern || [[ -n "${pattern}" ]]; do
    case "${pattern}" in ''|'#'*) continue ;; esac
    expand_pattern "${pattern}"
done < "${manifest}"

# ROCKNIX expects the RB5 SLPI payloads directly under qcom/sm8250.
expand_pattern 'qcom/sm8250/Thundercomm/RB5/slpi*'
shopt -s nullglob
slpi_files=("${firmware_root}"/qcom/sm8250/Thundercomm/RB5/slpi*)
for source in "${slpi_files[@]}"; do
    [[ "${source}" == *.xz ]] && continue
    cp -L "${source}" "${firmware_root}/qcom/sm8250/"
done
shopt -u nullglob

while IFS= read -r pattern || [[ -n "${pattern}" ]]; do
    case "${pattern}" in ''|'#'*) continue ;; esac
    compgen -G "${firmware_root}/${pattern}" >/dev/null \
        || { echo "ERROR: RP5 firmware missing: ${pattern}" >&2; exit 1; }
done < "${manifest}"