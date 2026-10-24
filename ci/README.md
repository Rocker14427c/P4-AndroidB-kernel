# CI build for realme P4 5G (RMX5110)

Reproducible, hermetic Bazel/Kleaf build of the unmodified 6.1 GKI kernel and
the MTK/OPLUS vendor modules for MT6878 (platform `k6878v1_64`).

## Pipeline (GitHub Actions)

`.github/workflows/p4-kernel-build.yml` runs on every push to `p4/ci-build`:

1. shallow-checkout of this kernel fork and the vendor fork;
2. `fetch_prebuilts.sh` — pinned AOSP prebuilts (clang **r487747c**, Bazel,
   JDK11, host tools), exact hashes in `pins.env`;
3. `assemble_workspace.sh` — symlink-only `kernel_platform` workspace, no
   source files are modified;
4. `build.sh` — builds `//kernel_device_modules-6.1:mgk_64_k61_customer_dist.user`;
5. uploads `p4-kernel-<run>` artifact: `dist` tarball + full logs.

No credentials or remote caches are used.

## Local use (WSL2 Ubuntu, Linux filesystem — never /mnt/c)

```sh
git clone https://github.com/Rocker14427c/P4-AndroidB-kernel kernel-src
git clone https://github.com/Rocker14427c/P4-AndroidB-vendor-source vendor-src
cd kernel-src && git checkout p4/ci-build
VENDOR_SRC=$PWD/../vendor-src ci/fetch_prebuilts.sh
VENDOR_SRC=$PWD/../vendor-src ci/assemble_workspace.sh
ci/build.sh                       # VARIANT=userdebug ci/build.sh for debug
```

Outputs land in `../buildroot/dist` (Image.lz4, vmlinux, all vendor `.ko`).

## Why bazel.py is called directly

The shipped `tools/bazel` wrapper expects `build/kernel/gettop.sh` (not present
in the published source) and an OPLUS-internal namespace-mount cache. Calling
`prebuilts/build-tools/path/linux-x86/python3 build/kernel/kleaf/bazel.py`
with the workspace root as argument is exactly the wrapper's non-cache code
path, without either missing dependency.
