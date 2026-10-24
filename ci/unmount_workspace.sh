#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Tear down the bind-mounted workspace (local runs). CI runners are ephemeral
# and do not need this. Safe to run repeatedly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_SRC="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT="${ROOT:-$(cd "${KERNEL_SRC}/.." && pwd)/buildroot}"
WP="${ROOT}/kernel_platform"
K="${WP}/kernel"

[ -d "${K}" ] || { echo "nothing to tear down"; exit 0; }

# Unmount in reverse depth order; ignore already-unmounted.
for m in \
    "${K}/build/bazel_common_rules" \
    "${WP}/vendor/oplus" \
    "${WP}/vendor/mediatek" \
    "${K}/vendor/oplus" \
    "${K}/vendor/mediatek" \
    "${K}/kernel-6.1" \
    "${K}/tools" \
    "${K}/kernel_device_modules-6.1" \
    "${K}/oplus" \
    "${K}/build" ; do
    if mountpoint -q "${m}" 2>/dev/null; then
        sudo umount "${m}" && echo "umounted ${m}"
    fi
done

# Empty mountpoint created inside the (bound) vendor build tree.
rmdir "${K}/build/bazel_common_rules" 2>/dev/null || true
echo "teardown complete (symlinked prebuilts/external left in place)"
