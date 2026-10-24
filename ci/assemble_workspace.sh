#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Builds the merged "kernel_platform" workspace the OPLUS/MTK Kleaf build
# expects. The two git clones and the prebuilts store are never modified.
#
# Why bind mounts (not plain symlinks): kernel/build ships hundreds of
# location-sensitive relative symlinks (e.g.
# build/kernel/build-tools/path/linux-x86/awk -> ../../../../../prebuilts/...)
# that only resolve when the tree physically sits at its manifest path.
# Bind mounts give every package its real workspace path. Where sudo is
# unavailable, a symlink fallback is provided (best-effort, for browsing).
#
# Result:
#   $ROOT/kernel_platform/kernel/      <- Bazel workspace root (has WORKSPACE)
#   $ROOT/kernel_platform/vendor/{mediatek,oplus}
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

mkdir -p "${K}/prebuilts/clang/host" "${K}/prebuilts/bazel" \
         "${K}/prebuilts/jdk" "${K}/prebuilts/gcc/linux-x86/host" \
         "${K}/external/python" "${K}/vendor" "${WP}/vendor"

HAVE_SUDO=0
if sudo -n true 2>/dev/null; then HAVE_SUDO=1; fi
echo "bind mounts: $([ "${HAVE_SUDO}" = 1 ] && echo enabled || echo 'unavailable, using symlink fallback')"

# bind <src> <dst>: idempotent bind mount (dirs) or symlink fallback.
bind() {
    local src="$1" dst="$2"
    [ -e "${src}" ] || { echo "ERROR: missing source ${src}" >&2; exit 1; }
    mkdir -p "${dst}"
    if mountpoint -q "${dst}" 2>/dev/null; then return; fi
    if [ "${HAVE_SUDO}" = 1 ]; then
        sudo mount --bind "${src}" "${dst}"
    else
        ln -sfn "${src}" "${dst}"
    fi
}

# link <src> <dst>: plain symlink for leaves with no path-sensitive symlinks.
link() { ln -sfn "$1" "$2"; }

# --- source trees: bind mounted so in-tree relative symlinks resolve -------
bind "${VENDOR_SRC}/kernel/build"                    "${K}/build"
bind "${VENDOR_SRC}/kernel/oplus"                    "${K}/oplus"
bind "${VENDOR_SRC}/kernel/kernel_device_modules-6.1" "${K}/kernel_device_modules-6.1"
bind "${VENDOR_SRC}/kernel/tools"                    "${K}/tools"
bind "${KERNEL_SRC}"                                 "${K}/kernel-6.1"

# WORKSPACE is a single file - plain symlink is enough.
link "${VENDOR_SRC}/kernel/WORKSPACE"                "${K}/WORKSPACE"

# bazel_common_rules joins the (mounted) build/ tree as a sibling package.
mkdir -p "${K}/build/bazel_common_rules"
if ! mountpoint -q "${K}/build/bazel_common_rules" 2>/dev/null; then
    if [ "${HAVE_SUDO}" = 1 ]; then
        sudo mount --bind "${STORE_DIR}/bazel_common_rules" "${K}/build/bazel_common_rules"
    else
        ln -sfn "${STORE_DIR}/bazel_common_rules" "${K}/build/bazel_common_rules"
    fi
fi

# --- prebuilts (final targets; repo-internal symlinks are self-contained) --
link "${STORE_DIR}/clang"                            "${K}/prebuilts/clang/host/linux-x86"
link "${STORE_DIR}/build-tools"                      "${K}/prebuilts/build-tools"
link "${STORE_DIR}/kernel-build-tools"               "${K}/prebuilts/kernel-build-tools"
link "${STORE_DIR}/bazel"                            "${K}/prebuilts/bazel/linux-x86_64"
link "${STORE_DIR}/jdk11"                            "${K}/prebuilts/jdk/jdk11"
link "${STORE_DIR}/ndk-r23"                          "${K}/prebuilts/ndk-r23"
link "${STORE_DIR}/gcc-host"                        "${K}/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8"
link "${STORE_DIR}/clang-tools"                      "${K}/prebuilts/clang-tools"

# --- external Bazel repositories (local checkouts) -------------------------
link "${STORE_DIR}/external/bazel-skylib"            "${K}/external/bazel-skylib"
link "${STORE_DIR}/external/stardoc"                 "${K}/external/stardoc"
link "${STORE_DIR}/external/absl-py"                 "${K}/external/python/absl-py"

# --- out-of-tree modules ----------------------------------------------------
# //vendor/... main-repo labels (inside workspace) ...
bind "${VENDOR_SRC}/vendor/mediatek"                 "${K}/vendor/mediatek"
bind "${VENDOR_SRC}/vendor/oplus"                    "${K}/vendor/oplus"
# ...and ../vendor for the @mgk_ko/@mgk_internal local repositories.
bind "${VENDOR_SRC}/vendor/mediatek"                 "${WP}/vendor/mediatek"
bind "${VENDOR_SRC}/vendor/oplus"                    "${WP}/vendor/oplus"

echo "Workspace assembled. Verifying critical paths:"
ls -l "${K}/WORKSPACE" "${K}/kernel-6.1/Makefile" \
      "${K}/prebuilts/clang/host/linux-x86/kleaf/versions.bzl" \
      "${K}/vendor/mediatek/kernel_modules" >/dev/null
# The hermetic toolchain's most failure-prone path:
[ -d "${K}/build/kernel/build-tools/sysroot/usr" ] || {
    echo "ERROR: build-tools/sysroot not reachable at workspace path" >&2; exit 1; }
# Only assert entries known to exist in this prebuilt revision.
for t in python3 cpio; do
    [ -e "${K}/build/kernel/build-tools/path/linux-x86/${t}" ] || {
        echo "ERROR: hermetic host tool '${t}' not resolving" >&2; exit 1; }
done
echo "OK: all key paths resolve"
