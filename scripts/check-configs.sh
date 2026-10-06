#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 ]]; then
  echo 'Usage: check-configs.sh BASELINE_CONFIG DIAGNOSTIC_CONFIG' >&2
  exit 2
fi

# LOCALVERSION is a make flag, so the generated .config files must be identical.
cmp "$1" "$2"

for option in MODULES DEBUG_FS FTRACE TRACING DYNAMIC_DEBUG INTEL_IOMMU; do
  if ! grep -qx "CONFIG_${option}=y" "$1"; then
    echo "Required diagnostic option is missing: CONFIG_${option}=y" >&2
    exit 1
  fi
done
for option in USB_XHCI_HCD USB_XHCI_PCI USB_VIDEO_CLASS; do
  if ! grep -Eq "^CONFIG_${option}=(y|m)$" "$1"; then
    echo "Required driver is missing: CONFIG_${option}" >&2
    exit 1
  fi
done
echo 'Both kernel configs match; xHCI, UVC, IOMMU, tracing and dynamic debug are enabled.'
