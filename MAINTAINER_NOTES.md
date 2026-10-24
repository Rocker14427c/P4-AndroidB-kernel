# MAINTAINER_NOTES — realme P4 5G (RMX5110) custom kernel

Persistent maintenance log. Read at the start of every session, update at the end.
Newest entries at the top. Never put credentials in this file.

---

## Device / source baseline (2026-10-24, Phase 0)

- Device: realme P4 5G, model RMX5110; SoC MediaTek **MT6878** (Dimensity 7400, Mali-G615); kernel platform **k6878v1_64**.
- Shared source tree with RMX5106 (realme 15 5G). Release: RMX5106_16.0.0.261(EX01), MTK tag `t-alps-release-u0.mp1.rc-V10.29` (sync date 2026-02-02).
- Linux **6.1.134**, AOSP common branch `android14-6.1`, GKI + MTK MGK mixed (vendor modules) build, KMI enforced vs `android/abi_gki_aarch64_mtk`.

### Repositories (push only to forks, feature branches `p4/<topic>` only, never master)
- Kernel fork: https://github.com/Rocker14427c/P4-AndroidB-kernel — known-good baseline commit: **`8cb3f8d71257`** (== upstream HEAD, pristine)
- Vendor fork: https://github.com/Rocker14427c/P4-AndroidB-vendor-source — baseline commit: **`e0563891`** (== upstream HEAD, pristine)
- Upstream (read-only): realme-kernel-opensource/realme_15_5G-P4_5G-AndroidB-{kernel,vendor}-source
- Both repos: single `master` branch, no tags.

### Build system
- Bazel/Kleaf hermetic build via vendor repo `kernel/tools/bazel` -> `build/kernel/kleaf/bazel.sh`.
- Workspace root needs package `kernel-6.1/` (ACK source) beside `build/`, `oplus/`, `kernel_device_modules-6.1/`, `tools/`, `prebuilts/`, and `../vendor/{mediatek,oplus}`.
- Targets: `//kernel_device_modules-6.1:mgk_64_k61_customer_modules_install.user` and `..._customer_dist.user`; flag `--//build/bazel_mgk_rules:kernel_version=6.1`.
- Config: ACK `gki_defconfig` + `kernel_device_modules-6.1/arch/arm64/configs/mgk_64_k61_defconfig` (1085 lines), no defconfig overlays.
- Env: `KERNEL_VERSION=kernel-6.1`, `OPLUS_PLATFORM_INFO=k6878v1_64` (harness defaults to k6989 — override), `CHIPSET_COMPANY=MTK`, `KERNEL_BUILD_VARIANT=user`, `BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1`, remote caches disabled.
- Do NOT use `oplus_setup.sh`/`oplus_build.sh` unmodified (hardcoded k6989, missing MTK dct/device trees, internal image server). Drive Bazel directly.

### Pinned toolchain (to be installed Phase 1)
- Clang/LLVM: **r487747c** — source pin: `build.config.constants` (`CLANG_VERSION=r487747c`, `BRANCH=android14-6.1`).
- Also required (not in published repos, fetch from android.googlesource.com, record checksum):
  `prebuilts/clang/host/linux-x86` (kleaf versions.bzl must agree with r487747c — verify),
  `prebuilts/bazel/linux-x86_64`, `prebuilts/jdk/jdk11`, `prebuilts/build-tools`, `prebuilts/kernel-build-tools`.
- Download URL: _to fill in Phase 1_ · SHA-256: _to fill in Phase 1_

### Exact build commands
- _Phase 1 pending — first successful build will be recorded here verbatim._

### Known gaps
- Prebuilts absent from source repos (toolchain, bazel, jdk, host tools).
- DTBO legacy packaging needs unpublished MTK dct/device projects → plan: reuse stock `dtbo.img`, do not flash self-built dtbo until board ID (`oplus6878_xxxxx` for RMX5110) is proven from stock dtbo.
- Stock images needed for repack: boot, vendor_boot, init_boot, dtbo, vendor_dlkm, system_dlkm, vbmeta(+system+vendor), misc_info/file_contexts if available.

## Build / test history
| Date | Commit(s) | Type | Result | Notes |
|---|---|---|---|---|
| 2026-10-24 | baseline | recon only | n/a | Phase 0 report written; no builds yet |

Test matrix (per release): boots to Android; WiFi; BT; calls+mobile data; GPS; camera; audio; touch/display; fingerprint; charging; sensors; no kernel panic/new SELinux denials; 3 clean reboots.

## Open issues
1. RMX5110 board ID among 44 `oplus6878_*.dts` — [unverified], needs stock dtbo.
2. Sandbox host constrained (2 vCPU / 1.9 GiB / no swap) — swap + LTO none for Phase 1.
3. Exact Bazel version pending prebuilts checkout.

## Cherry-pick / backport log
(none yet — stock reproduction first; rule: `git cherry-pick -x`, one fix per commit, source URL recorded, upstream Linux stable / AOSP common / MTK CLO / same-SoC OSS kernels only)
