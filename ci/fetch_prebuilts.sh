#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Fetches the pinned AOSP prebuilts (toolchain, bazel, host tools) needed to
# build the RMX5110 kernel. Everything comes from android.googlesource.com
# (the canonical source named in the AOSP kernel manifest) - no third-party
# blobs. Each project is checked out at the exact hash in ci/pins.env.
#
# Output layout (STORE_DIR, plain files - safe to cache):
#   $STORE_DIR/clang            (sparse: clang-r487747c + kleaf only)
#   $STORE_DIR/build-tools
#   $STORE_DIR/kernel-build-tools
#   $STORE_DIR/bazel
#   $STORE_DIR/jdk11
#   $STORE_DIR/ndk-r23          (sparse: hermetic sysroot only)
#   $STORE_DIR/bazel_common_rules
#   $STORE_DIR/external/{bazel-skylib,stardoc,absl-py}
#   $STORE_DIR/mkbootimg
#   $STORE_DIR/SHA256SUMS       (checksums of key binaries)
#   $STORE_DIR/REVISIONS        (resolved commit hashes)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pins.env
source "${SCRIPT_DIR}/pins.env"

STORE_DIR="${STORE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)/../prebuilts-store}"
mkdir -p "${STORE_DIR}"
STORE_DIR="$(cd "${STORE_DIR}" && pwd)"

# fetch <dest-dirname> "<project hash>" [sparse path ...]
fetch() {
    local name="$1"; local spec="$2"; shift 2
    local project hash dest
    project="$(echo "${spec}" | awk '{print $1}')"
    hash="$(echo "${spec}" | awk '{print $2}')"
    dest="${STORE_DIR}/${name}"

    if [ -d "${dest}/.git" ] && git -C "${dest}" rev-parse HEAD 2>/dev/null | grep -q "${hash}"; then
        echo "[skip] ${name} already at ${hash:0:12}"
        return
    fi

    echo "==> ${name} <- ${project} @ ${hash:0:12}"
    rm -rf "${dest}"
    git init -q "${dest}"
    git -C "${dest}" remote add origin "${AOSP_GIT}/${project}"
    if [ "$#" -gt 0 ]; then
        git -C "${dest}" config core.sparseCheckout true
        git -C "${dest}" sparse-checkout set "$@"
    fi
    # Pinned hash is the branch head today; fetch by branch first (cheap),
    # then verify we landed on the exact pinned commit.
    git -C "${dest}" fetch --depth 1 -q origin "${PIN_BRANCH}"
    git -C "${dest}" checkout -q FETCH_HEAD
    local got
    got="$(git -C "${dest}" rev-parse HEAD)"
    if [ "${got}" != "${hash}" ]; then
        echo "ERROR: ${name} pin mismatch: want ${hash}, got ${got}" >&2
        echo "       Re-resolve pins.env from the manifest before continuing." >&2
        exit 1
    fi
    echo "${project} ${got}" >> "${STORE_DIR}/REVISIONS"
}

: > "${STORE_DIR}/REVISIONS"

# Biggest repo first, sparsely: ~dozen clang versions exist upstream, we take
# only the pinned toolchain and the Kleaf registration files.
fetch clang "${PIN_CLANG}" clang-r487747c kleaf
fetch build-tools "${PIN_BUILD_TOOLS}"
fetch kernel-build-tools "${PIN_KERNEL_BUILD_TOOLS}"
fetch bazel "${PIN_BAZEL}"
fetch jdk11 "${PIN_JDK11}"
# Hermetic host toolchain only needs the NDK sysroot (see kleaf/ndk.BUILD).
fetch ndk-r23 "${PIN_NDK_R23}" toolchains/llvm/prebuilt/linux-x86_64/sysroot
fetch bazel_common_rules "${PIN_BAZEL_COMMON_RULES}"
mkdir -p "${STORE_DIR}/external"
fetch external/bazel-skylib "${PIN_SKYLIB}"
fetch external/stardoc "${PIN_STARDOC}"
fetch external/absl-py "${PIN_ABSL_PY}"
fetch mkbootimg "${PIN_MKBOOTIMG}"

echo "==> checksums of key executables"
(
    cd "${STORE_DIR}"
    sha256sum \
        clang/clang-r487747c/bin/clang \
        bazel/bazel \
        build-tools/path/linux-x86/python3 \
        kernel-build-tools/linux-x86/bin/mkdtimg 2>/dev/null \
        | tee SHA256SUMS
)

echo "Prebuilts ready at: ${STORE_DIR}"
du -sh "${STORE_DIR}" | tee -a "${STORE_DIR}/REVISIONS"
