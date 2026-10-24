#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Reproducible stock-equivalent build of the RMX5110 kernel + vendor modules.
# Mirrors the official oplus_build_function.sh flow, but:
#   * platform is k6878v1_64 (MT6878) instead of the hardcoded k6989 default
#   * bazel.py is invoked directly (the shipped tools/bazel wrapper needs a
# gettop.sh that is not present in the published source and an OPLUS internal
# namespace-mount cache; neither is usable outside OPLUS)
#   * all remote caches are disabled - fully local, hermetic build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_SRC="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT="${ROOT:-$(cd "${KERNEL_SRC}/.." && pwd)/buildroot}"
K="${ROOT}/kernel_platform/kernel"
DIST="${ROOT}/dist"
LOGDIR="${ROOT}/logs"
VARIANT="${VARIANT:-user}"          # user | userdebug

[ -f "${K}/WORKSPACE" ] || { echo "ERROR: run assemble_workspace.sh first" >&2; exit 1; }
mkdir -p "${DIST}" "${LOGDIR}"

# --- environment consumed by //build/bazel_mgk_rules key_value_repo ---------
export CHIPSET_COMPANY=MTK
export OPLUS_VND_BUILD_PLATFORM=MT6878
export BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1
export KERNEL_VERSION=kernel-6.1
export OPLUS_PLATFORM_INFO=k6878v1_64
export OPLUS_FEATURES=""
export DEFCONFIG_OVERLAYS=""
export KERNEL_BUILD_VARIANT="${VARIANT}"
export OPLUS_USE_JFROG_CACHE=false
export OPLUS_USE_BUILDBUDDY_REMOTE_BUILD=false

PY3="${K}/prebuilts/build-tools/path/linux-x86/python3"
BAZEL_PY="build/kernel/kleaf/bazel.py"
KLEAF_OUT="${ROOT}/out_krn"

cd "${K}"

echo "==> [1/2] kernel + customer vendor modules (${VARIANT})"
"${PY3}" "${BAZEL_PY}" "$(pwd)" \
    --output_root="${KLEAF_OUT}" \
    build \
    --//build/bazel_mgk_rules:kernel_version=6.1 \
    --experimental_writable_outputs \
    "//kernel_device_modules-6.1:mgk_64_k61_customer_modules_install.${VARIANT}" \
    2>&1 | tee "${LOGDIR}/01_build.log"

echo "==> [2/2] customer dist (staging into ${DIST})"
"${PY3}" "${BAZEL_PY}" "$(pwd)" \
    --output_root="${KLEAF_OUT}" \
    run \
    --//build/bazel_mgk_rules:kernel_version=6.1 \
    --experimental_writable_outputs \
    --nokmi_symbol_list_violations_check \
    "//kernel_device_modules-6.1:mgk_64_k61_customer_dist.${VARIANT}" \
    -- --dist_dir="${DIST}" \
    2>&1 | tee "${LOGDIR}/02_dist.log"

echo "==> artifacts"
find "${DIST}" -maxdepth 2 -type f | sed "s#${DIST}/##" | sort | tee "${LOGDIR}/artifact_manifest.txt"
echo "kernel modules:"; find "${DIST}" -name '*.ko' | wc -l
echo "vermagic sample:"; find "${KLEAF_OUT}" -name '*.ko' -print -quit 2>/dev/null | head -1 \
    | xargs -r "${K}/prebuilts/clang/host/linux-x86/clang-r487747c/bin/llvm-readelf" -p .modinfo 2>/dev/null \
    | grep -E 'vermagic|srcversion' | head -4 || true
echo "Build finished. Dist: ${DIST}"
