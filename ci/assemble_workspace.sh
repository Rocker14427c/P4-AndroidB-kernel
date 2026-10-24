#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Builds the merged "kernel_platform" workspace the OPLUS/MTK Kleaf build
# expects, using symlinks only - the two git clones and the prebuilts store
# are never modified.
#
# Result:
#   $ROOT/kernel_platform/kernel/      <- Bazel workspace root (has WORKSPACE)
#     WORKSPACE, build/, oplus/, kernel_device_modules-6.1/, tools/,
#     kernel-6.1/ (the ACK GKI source), prebuilts/, external/
#   $ROOT/kernel_platform/vendor/
#     mediatek/, oplus/                <- out-of-tree module sources
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_SRC="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_SRC="${VENDOR_SRC:-$(cd "${KERNEL_SRC}/../vendor" && pwd)}"
ROOT="${ROOT:-$(cd "${KERNEL_SRC}/.." && pwd)/buildroot}"
STORE_DIR="${STORE_DIR:-$(cd "${KERNEL_SRC}/.." && pwd)/prebuilts-store}"

WP="${ROOT}/kernel_platform"
K="${WP}/kernel"

echo "KERNEL_SRC=${KERNEL_SRC}"
echo "VENDOR_SRC=${VENDOR_SRC}"
echo "STORE_DIR =${STORE_DIR}"
echo "workspace =${K}"

[ -f "${VENDOR_SRC}/kernel/WORKSPACE" ] || { echo "ERROR: vendor clone not found at ${VENDOR_SRC}" >&2; exit 1; }
[ -d "${STORE_DIR}/clang/clang-r487747c" ] || { echo "ERROR: run fetch_prebuilts.sh first" >&2; exit 1; }

mkdir -p "${K}/build" "${K}/prebuilts/clang/host" "${K}/prebuilts/bazel" \
         "${K}/prebuilts/jdk" "${K}/external/python" "${K}/tools" \
         "${WP}/vendor"

link() { ln -sfn "$1" "$2"; }

# --- workspace root pieces coming from the vendor repo ---------------------
link "${VENDOR_SRC}/kernel/WORKSPACE"                "${K}/WORKSPACE"
link "${VENDOR_SRC}/kernel/oplus"                    "${K}/oplus"
link "${VENDOR_SRC}/kernel/kernel_device_modules-6.1" "${K}/kernel_device_modules-6.1"

# build/ is a real folder: every vendor build/ entry plus bazel_common_rules
for entry in "${VENDOR_SRC}"/kernel/build/*; do
    link "${entry}" "${K}/build/$(basename "${entry}")"
done
link "${STORE_DIR}/bazel_common_rules"               "${K}/build/bazel_common_rules"

# tools/: official manifest uses linkfile tools/bazel plus tools/mkbootimg
link "${VENDOR_SRC}/kernel/tools/bazel"              "${K}/tools/bazel"
link "${STORE_DIR}/mkbootimg"                        "${K}/tools/mkbootimg"

# ACK common kernel source, presented as the kernel-6.1 workspace package
link "${KERNEL_SRC}"                                 "${K}/kernel-6.1"

# --- prebuilts (exact manifest paths Kleaf looks for) ----------------------
link "${STORE_DIR}/clang"                            "${K}/prebuilts/clang/host/linux-x86"
link "${STORE_DIR}/build-tools"                      "${K}/prebuilts/build-tools"
link "${STORE_DIR}/kernel-build-tools"               "${K}/prebuilts/kernel-build-tools"
link "${STORE_DIR}/bazel"                            "${K}/prebuilts/bazel/linux-x86_64"
link "${STORE_DIR}/jdk11"                            "${K}/prebuilts/jdk/jdk11"
link "${STORE_DIR}/ndk-r23"                          "${K}/prebuilts/ndk-r23"

# --- external Bazel repositories (local checkouts) -------------------------
link "${STORE_DIR}/external/bazel-skylib"            "${K}/external/bazel-skylib"
link "${STORE_DIR}/external/stardoc"                 "${K}/external/stardoc"
link "${STORE_DIR}/external/absl-py"                 "${K}/external/python/absl-py"

# --- out-of-tree modules, referenced as ../vendor relative to workspace ----
link "${VENDOR_SRC}/vendor/mediatek"                 "${WP}/vendor/mediatek"
link "${VENDOR_SRC}/vendor/oplus"                    "${WP}/vendor/oplus"

echo "Workspace assembled. Sanity check:"
ls -l "${K}/WORKSPACE" "${K}/kernel-6.1/Makefile" "${K}/prebuilts/clang/host/linux-x86/kleaf/versions.bzl" \
      "${WP}/vendor/mediatek/kernel_modules" >/dev/null && echo "OK: all key paths resolve"
