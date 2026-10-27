#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Stage release assets from a successful ci/build.sh dist tree.
# Produces, under uploads/release/:
#   p4-kernel-images-<TAG>.zip   Image / Image.gz / Image.lz4 / System.map
#                                + BUILD-MANIFEST.txt + SHA256SUMS
#   p4-vendor-modules-<TAG>.tar.gz  all built .ko (GKI in-tree + customer)
#                                   and module-name manifests
# The full dist tarball (p4-kernel-dist.tar.gz, incl. vmlinux/symvers) is
# created by the workflow and uploaded separately.
# No network access, no credentials: this script only stages files locally.
set -euo pipefail

ROOT="${ROOT:-/mnt/buildroot}"
TAG="${RELEASE_TAG:?RELEASE_TAG must be set}"
VARIANT="${VARIANT:-user}"
DM="dist/kernel_device_modules-6.1"
KDIR="${ROOT}/${DM}/mgk_64_k61_kernel_aarch64.${VARIANT}"
CDIR="${ROOT}/${DM}/mgk_64_k61_customer_modules_install.${VARIANT}"
OUT="uploads/release"
STAGE="p4-kernel-images-${TAG}"

[ -f "${KDIR}/Image.gz" ] || { echo "ERROR: ${KDIR}/Image.gz missing" >&2; exit 1; }
[ -d "${CDIR}" ]        || { echo "ERROR: ${CDIR} missing" >&2; exit 1; }

# In CI the hermetic clang prebuilt lives in the assembled workspace (see
# ci/assemble_workspace.sh); fall back to a host readelf for local testing.
READELF="${ROOT}/kernel_platform/kernel/prebuilts/clang/host/linux-x86/clang-r487747c/bin/llvm-readelf"
[ -x "${READELF}" ] || READELF="$(command -v readelf || true)"
[ -n "${READELF}" ] || { echo "ERROR: no readelf available" >&2; exit 1; }

mkdir -p "${OUT}/${STAGE}"
cd "${OUT}/${STAGE}"
cp "${KDIR}/Image" "${KDIR}/Image.gz" "${KDIR}/Image.lz4" "${KDIR}/System.map" .

# --- build manifest -----------------------------------------------------------
KO_SAMPLE="$(find "${CDIR}" -name '*.ko' | head -1)"
VERMAGIC="$("${READELF}" -p .modinfo "${KO_SAMPLE}" 2>/dev/null \
            | tr -d '\0' | sed -n 's/.*vermagic=\([^[:space:]]* .*\)/\1/p' | head -1 || true)"
UTS_RELEASE="$(strings Image | grep -E '^6\.1\.[0-9]+-android14-[0-9]+-o' | head -1 || true)"
KO_COUNT="$(find "${ROOT}/${DM}" -name '*.ko' | wc -l)"
CUST_KO_COUNT="$(find "${CDIR}" -name '*.ko' | wc -l)"

{
  echo "realme P4 5G (RMX5110, MT6878 / k6878v1_64) kernel build"
  echo "========================================================"
  echo "release tag      : ${TAG}"
  echo "build variant    : ${VARIANT}"
  echo "created (UTC)    : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "GitHub run       : ${GITHUB_SERVER_URL:-local}/${GITHUB_REPOSITORY:-?}/actions/runs/${GITHUB_RUN_ID:-local}"
  echo "kernel ref       : ${KERNEL_REF:-?} @ ${KERNEL_SHA:-?}"
  echo "vendor ref       : ${VENDOR_REF:-?} @ ${VENDOR_SHA:-?}"
  echo "UTS release      : ${UTS_RELEASE:-unknown}"
  echo "module vermagic  : ${VERMAGIC:-unknown}"
  echo ".ko total        : ${KO_COUNT} (customer dir: ${CUST_KO_COUNT})"
  echo
  echo "Contents:"
  echo "  Image       raw arm64 kernel (bootable Image, 4K pages)"
  echo "  Image.gz    gzip-compressed kernel (typical GKI boot.img payload)"
  echo "  Image.lz4   lz4-compressed kernel"
  echo "  System.map  kernel symbol table"
  echo
  echo "Note: this GKI/MTK target does NOT use an appended DTB, so there is"
  echo "no Image.gz-dtb: DTB/DTBO live in vendor_boot/dtbo and must be kept"
  echo "stock. Flash the kernel payload into boot only; vendor modules are"
  echo "compatible as-is (CONFIG_MODVERSIONS=y, same KMI/source/toolchain)."
} > BUILD-MANIFEST.txt

sha256sum Image Image.gz Image.lz4 System.map > SHA256SUMS
cd ..
zip -q -r -9 "${STAGE}.zip" "${STAGE}"
rm -rf "${STAGE}"

# --- module tarball -----------------------------------------------------------
tar -C "${ROOT}" -czf "p4-vendor-modules-${TAG}.tar.gz" \
    "${DM}/mgk_64_k61_customer_modules_install.${VARIANT}" \
    "${DM}/mgk_64_k61_kernel_aarch64.${VARIANT}/drivers" \
    "${DM}/mgk_64_k61.user_all_module_names" \
    "${DM}/mgk_64_k61_kernel_aarch64.user_all_module_names" \
    2>/dev/null

sha256sum "p4-kernel-images-${TAG}.zip" "p4-vendor-modules-${TAG}.tar.gz" \
    > "p4-release-${TAG}.sha256"
ls -lh
echo "Release assets staged in ${OUT}"
