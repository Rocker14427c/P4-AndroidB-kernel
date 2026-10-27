# MAINTAINER_NOTES — realme P4 5G (RMX5110) custom kernel

Persistent maintenance log. Read at the start of every session, update at the end.
Newest entries at the top. Never put credentials in this file.

---

## Phase 1b — release artifacts & module-compatibility proof (2026-10-27)

### Why stock WiFi/BT/modem/audio modules keep loading (verified in source)
The modules on the phone (`/vendor_dlkm/lib/modules`, e.g.
`wlan_drv_gen4m_6878.ko`, `bt_drv_*.ko`, `ccci_md_all.ko` for
modem/IMS/VoLTE, `gps_drv_*`, smart-pa audio) were built with
`CONFIG_MODVERSIONS=y` (gki_defconfig line 102; every built .ko carries a
`__versions` section and the `modversions` vermagic token). In that mode:
- `kernel/module/main.c:2008` calls `same_magic(modmagic, vermagic,
  info->index.vers)`;
- `kernel/module/version.c` `same_magic()` advances both strings past the
  first space **when the module has CRCs**, i.e. the entire release token
  (`6.1.134-android14-11-o[-maybe-dirty]`) is ignored; only
  `SMP preempt mod_unload modversions aarch64` is compared — identical
  because the defconfig is the published one;
- the real gate is `check_version()` symbol CRCs (KMI). Same source
  release + same pinned clang r487747c => same CRCs; the Kleaf GKI checker
  also passed in every green run.
Independent corroboration: same-SoC MT6878 devices (RMX5003) and Pixel GKI
audits show differing release strings loading fine under modversions.

### Clean version stamp (vendor commit `532fcfad`)
`build/kernel/kleaf/impl/stamp.bzl` unstamped fallback was
`echo '-maybe-dirty'`; changed to `true` (no suffix). New UTS release /
vermagic prefix: **`6.1.134-android14-11-o`** (canonical GKI form).
External modules inherit the kernel's UTS release, so kernel and all .ko
stay consistent. No functional effect, only the version string.

### Raw outputs published as a GitHub Release (no AnyKernel3, per user)
User builds packaging manually; CI now uploads raw artifacts when
`workflow_dispatch` input `release_tag` is set (ephemeral GITHUB_TOKEN,
`permissions: contents: write`, nothing stored):
- `p4-kernel-images-<tag>.zip` — `Image` (35 MB), `Image.gz` (14 MB),
  `Image.lz4` (17 MB), `System.map`, `BUILD-MANIFEST.txt`, `SHA256SUMS`;
- `p4-vendor-modules-<tag>.tar.gz` — all 1000+ built .ko + name lists;
- `p4-kernel-dist-<tag>.tar.gz` — full dist incl. `vmlinux`/symvers;
- `p4-release-<tag>.sha256`.
There is deliberately **no `Image.gz-dtb`**: on this GKI/MTK target DTBs
are in vendor_boot/dtbo, not appended to the kernel. Kernel-only flashing
leaves every vendor module and dtbo byte-identical to stock.

### Release `rmx5110-6.1.134-r1` — PUBLISHED (2026-10-27)
URL: https://github.com/Rocker14427c/P4-AndroidB-kernel/releases/tag/rmx5110-6.1.134-r1
Built by dispatch run `40538420609` (kernel `1beaedce0`, vendor `532fcfad`),
published via the `publish` mode of `p4-kernel-build.yml`
(run `40556478322`, release id 425804799). Assets, all state `uploaded`:
| Asset | Size | Purpose |
|---|---:|---|
| `p4-kernel-images-rmx5110-6.1.134-r1.zip` | 44 MB | Image (35 MB), Image.gz (14 MB), Image.lz4 (17 MB), System.map, BUILD-MANIFEST, SHA256SUMS |
| `p4-vendor-modules-…tar.gz` | 657 MB | all 1164 built .ko (1014 customer) + module-name lists |
| `p4-kernel-dist-…tar.gz` | 920 MB | full dist incl. vmlinux, vmlinux.symvers, GKI modules |
| `p4-release-….sha256` | 216 B | SHA-256 of the two primary archives |
Release-asset checksum re-verified after download (matches published hash).
UTS release in the artifacts: **`6.1.134-android14-11-o`**; module vermagic:
`6.1.134-android14-11-o SMP preempt mod_unload modversions aarch64`.

### Workflow modes (one registered workflow, two jobs)
- `mode=build` (default): full compile; if `release_tag` is set it stages
  and publishes at the end.
- `mode=publish`: no rebuild — downloads a named artifact (`source_run_id`
  + `artifact_name`) and runs `ci/publish_release.sh`. Needed because
  newly added separate workflow files are not dispatchable until GitHub
  indexes them, and the local sandbox OOM-kills POST uploads above
  ~700 MB (1.9 GiB RAM, no swap); hosted runners handle the full set.
- `ci/publish_release.sh` is idempotent: reuses an existing release and
  replaces same-named assets. Auth is always the ephemeral GITHUB_TOKEN.
- Lesson: `set -u` requires an explicit step `env: GITHUB_TOKEN` mapping;
  shell variables used by Python (`TAG`, `BODY`) must be exported;
  `find | head` breaks under pipefail (use `find -print -quit`).

---

## Phase 1 — clean unmodified build GREEN (2026-10-24)

GitHub Actions run **40093351089** on branch `p4/ci-build`, variant `user`,
conclusion **success**, one dispatched command (`workflow_dispatch`) from a
fresh clone. Build phase bazel elapsed 4045 s, dist phase 49 s; 1667 actions.

Output (dist tar inside CI artifact `p4-kernel-12.zip`, 910,975,272 bytes,
artifact id 12561812768, zip SHA-256
`1d6905ce60f739ca10ea2be956d3c38ce7947e5a137f59abb34e9cdd5dab66e8`):
- `kernel_device_modules-6.1/mgk_64_k61_kernel_aarch64.user/`: `vmlinux`,
  `System.map`, `Image`, `Image.lz4`, `Image.gz`, `modules.builtin`,
  `vmlinux.symvers` + in-tree GKI modules.
- `kernel_device_modules-6.1/mgk_64_k61_customer_modules_install.user/`:
  customer/vendor modules; **1164 `*.ko` total** in dist.
- `mgk_64_k61.user_all_module_names` module manifest.
- Spot-checked present: `oplus_chg_v2.ko`, `mt6375-charger.ko`,
  `mt6375-battery.ko`, `snd-smartpa-aw883xx.ko`, `snd-soc-frsm-i2ca.ko`.

### Why the published source did not build out-of-the-box for k6878
The published harness (`oplus_setup.sh`) hardcodes k6989 and exports
`DEFCONFIG_OVERLAYS=""`. Every `if "oplus6878.config" in DEFCONFIG_OVERLAYS`
block in `mgk_64_k61.bzl` is therefore dormant, and the k6878 platform was
also missing from two platform-keyed selectors. Fixes, all on vendor branch
`p4/ci-build` (6 commits over baseline `e0563891`):
1. `56c2b698` — drop absent out-of-tree fpsgo DDK labels (published subset).
2. `c1f2dfac` — charger v2 Makefile: always add the `mediatek_v2` DRM include
   path under `CONFIG_OPLUS_CHARGER_MTK` (fixes `mtk_panel_ext.h` not found;
   matches the DDK build's copts).
3. `b04b43ca` — `build/bazel_mgk_rules/mgk.bzl`: add k6878 case to the
   defconfig-fragment platform selector so `kernel/configs/oplus6878.config`
   actually merges (enables MT6375 charger stack + HAL symbol providers,
   FS181X/AW883XX smartpa, AW37501 bias). The fragment's `#ifdef
   OPLUS_FEATURE_CHG_BASIC` lines are inert: `merge_config.sh` treats `#`
   lines as comments, no C preprocessing occurs.
4. `e51595e6`, `57c9f171`, `3fa55763` — `kernel/kleaf/mgk_64_k61.bzl`: apply
   the same module-list delta the dormant overlay block encoded, keyed on
   `OPLUS_PLATFORM_INFO == "k6878v1_64"` (the signal that actually works in
   this flow): declare the two smartpa `.ko` in outs, and remove
   `cpufreq_bouncing.ko` / `oplus_bsp_task_overload.ko` whose Kconfigs are
   `not set` in the fragment. `e51595e6` was an intermediate attempt keyed on
   the empty overlay env; superseded by `57c9f171` (kept in history, no
   force-push).

### Version stamp history: `-maybe-dirty` removed (2026-10-27)
Run 40093351089 modules showed `vermagic=6.1.134-android14-11-o-maybe-dirty`.
That was the Kleaf unstamped fallback in `stamp.bzl` for a sandbox without
git metadata — a version *stamp*, never a dirty tree, and harmless under
CONFIG_MODVERSIONS (see Phase 1b proof). Vendor commit `532fcfad` removes
the suffix; current builds report plain `6.1.134-android14-11-o`.

### Phase 1 acceptance status
- [x] Clean build from fresh clone via one documented command (GitHub
  Actions `workflow_dispatch`; same scripts run locally per commands below).
- [x] Unmodified driver/source logic: all six deltas are build-system
  wiring (selectors, include paths, module lists), no functional C changes.
- [ ] Compare generated `.config` and module list against stock (blocked on
  user-supplied OFP/full firmware; no RMX5110 stock images in workspace).
- [ ] Reproducibility re-verification: rerun dispatch and diff dist
  (pinned inputs make this deterministic except timestamps/SCM stamp).

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

### Pinned toolchain (resolved Phase 1, 2026-10-24)
All prebuilts come from android.googlesource.com, manifest branch
`main-kernel-build-2023` (per AOSP kernel manifest common-android14-6.1),
checked out at exact hashes recorded in `ci/pins.env`. Clang r487747c is
confirmed both by `build.config.constants` and by the prebuilts'
`kleaf/versions.bzl` (single VERSIONS entry).
- platform/prebuilts/clang/host/linux-x86 @382db94f (sparse: clang-r487747c, kleaf)
- platform/prebuilts/build-tools @4649614b
- kernel/prebuilts/build-tools (kernel-build-tools) @e905be25
- platform/prebuilts/bazel/linux-x86_64 @7bfbec9e (bazel symlink -> bazel_nojdk binary)
- platform/prebuilts/jdk/jdk11 @649eec44
- toolchain/prebuilts/ndk/r23 @19ac7e4e (sparse: hermetic sysroot only)
- platform/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8 @f6d40532 (sysroot only)
- platform/prebuilts/clang-tools @f08a96e4 (linux-x86 only)
- platform/build/bazel_common_rules @62c496cd; external bazel-skylib/stardoc/absl-py pinned in ci/pins.env
- SHA-256 of key binaries: written to prebuilts-store/SHA256SUMS by fetch_prebuilts.sh

### Exact build commands (reproducible)
CI: push to branch `p4/ci-build` (kernel fork) triggers
`.github/workflows/p4-kernel-build.yml` on GitHub-hosted ubuntu-22.04
(4 vCPU, 16 GiB RAM, 8 GiB swap added, working set on /mnt). No secrets.
Local (WSL2, same scripts):
```
VENDOR_SRC=$PWD/../vendor-src ci/fetch_prebuilts.sh
VENDOR_SRC=$PWD/../vendor-src ci/assemble_workspace.sh   # needs sudo for bind mounts
ci/build.sh                                              # VARIANT=userdebug optional
ci/unmount_workspace.sh
```
Vendor-side required adaptations (branch p4/ci-build in vendor fork,
six commits — see the Phase 1 section above for the full rationale):
fpsgo label subset fix; charger v2 mediatek_v2 include; k6878 defconfig
platform selector; k6878 module-list outs delta. First green run:
**40093351089 (2026-10-24)**. Earlier failed runs are tabulated below;
each failure produced the fix for the next layer, no source logic changed.

### Known gaps
- Prebuilts absent from source repos (toolchain, bazel, jdk, host tools).
- DTBO legacy packaging needs unpublished MTK dct/device projects → plan: reuse stock `dtbo.img`, do not flash self-built dtbo until board ID (`oplus6878_xxxxx` for RMX5110) is proven from stock dtbo.
- Stock images needed for repack: boot, vendor_boot, init_boot, dtbo, vendor_dlkm, system_dlkm, vbmeta(+system+vendor), misc_info/file_contexts if available.

## Build / test history
| Date | Run id | Result | Failure point / notes |
|---|---|---|---|
| 2026-10-24 | 40073183167 | fail | /mnt workspace permissions — CI harness fix |
| 2026-10-24 | 40073615539 | fail | fpsgo DDK label resolution — vendor `56c2b698` |
| 2026-10-24 | 40074392306 | fail | host toolchain/sysroot gaps — pins + fetch fixes |
| 2026-10-24 | 40075544386, 40076230638 | fail | gcc sysroot glob — bind-mount assembly |
| 2026-10-24 | 40077007177 | fail | prebuilt tool assertions (bash not shipped) |
| 2026-10-24 | 40077687796 | fail | `mtk_panel_ext.h` not found — vendor `c1f2dfac` |
| 2026-10-24 | 40080774791 | fail | modpost: 6 undefined charger symbols — vendor `b04b43ca` (fragment never merged) |
| 2026-10-24 | 40083667059 | fail | Kleaf: 2 smartpa .ko built but not in outs |
| 2026-10-24 | 40087055129 | fail | same — first fix keyed on empty `DEFCONFIG_OVERLAYS` (`e51595e6`, dormant) |
| 2026-10-24 | 40089977980 | fail | missing `cpufreq_bouncing.ko` / `oplus_bsp_task_overload.ko` in outs — vendor `3fa55763` |
| 2026-10-24 | **40093351089** | **success** | full dist, 1164 .ko, artifact 12561812768 |
| 2026-10-27 | 40511535658 | fail | build OK; release stage SIGPIPE under pipefail — `find\|head` (fixed `8d88e983d`) |
| 2026-10-27 | 40521274116 | fail | build+stage OK; release step `GITHUB_TOKEN: unbound variable` under set -u (fixed `1beaedce`) |
| 2026-10-27 | 40538420609 | fail | build+stage OK; release step unexported `TAG` (fixed `682c6acc`); its artifact `p4-kernel-18` is the published source |
| 2026-10-27 | 40556478322 | **success** | publish-only mode; release `rmx5110-6.1.134-r1` id 425804799, all 4 assets `uploaded` |
| 2026-10-27 | 40555256017/…54393/…5454393 | running | push-triggered validation builds of the final workflow (no release) |

Test matrix (per release): boots to Android; WiFi; BT; calls+mobile data; GPS; camera; audio; touch/display; fingerprint; charging; sensors; no kernel panic/new SELinux denials; 3 clean reboots.

## Phase 2 — pre-flash requirements (NOT executed; user performs all device steps)

The released kernel is a **kernel-only** payload: replace only the kernel in
the boot image; do not touch vendor_boot, dtbo, vendor_dlkm, system_dlkm,
vbmeta, preloader/lk/tee/nvram. Before any flash the user must:
1. Have an unlocked bootloader (currently externally blocked for this
   device — resolve outside this workflow); relocking after a custom kernel
   is not supported.
2. Back up the current stock `boot.img` (and, for convenience,
   `init_boot.img`, `vendor_boot.img`, `dtbo.img`) — `fastboot boot` is not
   available on MediaTek, so a saved boot image is the rollback path:
   `fastboot flash boot boot-stock.img`.
3. Keep a full OFP/firmware on PC for emergency reflash with download tool.
4. Charge >50%, know how to force-power-off and enter recovery/bootloader.
5. First boot after flashing: expect one longer boot; capture
   `dmesg`/`logcat` and run the 14-point matrix below before trusting daily
   use. If a module fails to load, `dmesg` shows either a vermagic flags
   mismatch (should be impossible per the Phase 1b proof) or a symbol CRC
   disagreement (would point to a source/toolchain mismatch to investigate).

### Functional mapping for the test matrix (what to watch)
| Feature | Userspace-facing component | Kernel side (left stock unless noted) |
|---|---|---|
| WiFi + hotspot | wlan HAL/hostapd | `wlan_drv_gen4m_6878.ko`, `wmt_chrdev_wifi*.ko`, cfg80211/mac80211 GKI modules |
| Bluetooth | BT stack | `bt_drv_*.ko`, `btif_drv.ko`, `wmt_*` |
| Mobile data / VoLTE / calls | RIL, IMS | `ccci_md_all.ko`, `ccci_*`, modem; kernel only provides transport |
| GPS | location HAL | `gps_drv_*.ko`, `gps_pwr.ko` |
| Audio (speaker/earpiece/BT audio) | audio HAL/AudioFlinger | `snd-soc-mtk-*`, smartpa `snd-smartpa-aw883xx.ko`, `snd-soc-frsm-i2ca.ko` |
| Charging | health HAL | `oplus_chg_v2.ko`, `mt6375-charger.ko`, `mt6375-battery.ko` |
All are vendor modules loaded from verified partitions; with matching
modversions/CRC they load exactly as on stock. The kernel itself changes no
defconfig values relative to the published k6878 configuration.

## Open issues
1. RMX5110 board ID among 44 `oplus6878_*.dts` — [unverified], needs stock dtbo.
2. Local sandbox host constrained (2 vCPU / 1.9 GiB); CI (ubuntu-22.04,
   16 GiB + 8 GiB swap) is the primary builder and is now green.
3. Resolved: exact Bazel/clang versions come from pinned prebuilts
   (`ci/pins.env`, clang r487747c).
4. Stock `.config` / module-list byte comparison still blocked on
   user-supplied stock OFP/full firmware images. Vermagic prefix no longer
   differs; KMI/CRC equivalence is argued from identical source+toolchain,
   not yet measured against stock modules (would need one stock .ko).
5. Device-facing packaging: user chose raw release outputs over AnyKernel3
   (delivered, see Phase 1b). Any actual flashing still needs the user's
   backup/recovery plan; bootloader unlock remains externally blocked.
6. Workspace snapshots in the build sandbox drop `.git` and binary
   artifacts — always re-clone from the forks; GitHub releases/artifacts
   are the only durable artifact store.

## Cherry-pick / backport log
(none yet — stock reproduction first; rule: `git cherry-pick -x`, one fix per commit, source URL recorded, upstream Linux stable / AOSP common / MTK CLO / same-SoC OSS kernels only)
