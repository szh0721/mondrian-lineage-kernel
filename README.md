# Redmi K60 (mondrian) — LineageOS 24 kernel build

Builds a **LineageOS 24 (Android 17)** kernel for the Redmi K60 / POCO F5 Pro
(`mondrian`, SM8450) with **BakaSU** (KernelSU fork) integrated, and packages it
as an AnyKernel3 zip.

This is intentionally **not** the stock HyperOS GKI build. The kernel source,
config, and release string are taken from the LineageOS build that is already
running on the device, so the prebuilt `/vendor/lib/modules` keep the same
vermagic and ABI.

## What it does

1. Clones `LineageOS/android_kernel_xiaomi_sm8450` at the LineageOS 24 commit
   (`eff4b40407a1…` by default).
2. Adds BakaSU with its upstream `kernel/setup.sh`.
3. Uses `configs/mondrian_running.config` — the exact `.config` captured from
   the installed LineageOS kernel.
4. Forces `CONFIG_LOCALVERSION` to `-gki-geff4b40407a1` and disables
   `CONFIG_LOCALVERSION_AUTO`, so the release is exactly
   `5.10.269-gki-geff4b40407a1` and matches the vendor modules.
5. Builds `Image` with the Android 17 clang prebuilt (`clang-r596125`, 22.0.2),
   matching the ROM's LTO/CFI toolchain.
6. Packages `Image` into `AnyKernel3-mondrian-lineage.zip` (boot partition,
   slot-aware, modules untouched).

## Run

GitHub → **Actions** → **Build LineageOS 24 kernel (mondrian)** → **Run workflow**.

Inputs:

| Input | Default | Notes |
|---|---|---|
| `kernel_ref` | `eff4b40407a1…` | LineageOS `lineage-24.0` commit |
| `ksu_variant` | `BakaSU` | `BakaSU`, `Official`, `SukiSU` |
| `localversion` | `-gki-geff4b40407a1` | Must match `/proc/version` of the ROM |

Artifacts: `Image`, `Image.sha256`, `kernel.config`,
`AnyKernel3-mondrian-lineage.zip`, `build.log`.

## Flash

Boot into LineageOS recovery, then:

```bash
adb sideload AnyKernel3-mondrian-lineage.zip
```

If recovery reports a signature error, allow installing the unsigned zip.
The zip only replaces the kernel in the active `boot` slot; vendor modules and
`vendor_boot` are not touched.

After reboot:

```bash
adb shell uname -r
# 5.10.269-gki-geff4b40407a1
```

The BakaSU manager should then show the kernel as working.

## Rollback

Keep a copy of the current boot image before flashing. If it bootloops:

```bash
fastboot flash boot kernelsu_patched_20261112_151854.img
# or the unpatched LineageOS boot.img
```

## Notes / limits

- **K60 `mondrian` only.** The AnyKernel3 device check rejects other devices.
- The kernel is built from the LineageOS source at the pinned commit. If the
  ROM is updated, update `kernel_ref`, re-capture `.config`, and update
  `localversion`; otherwise vendor modules may fail to load.
- BakaSU only; SUSFS and Droidspaces are not included in this workflow.
- The first build is a real kernel build, not a boot-image patch. Expect roughly
  30–90 minutes on a GitHub-hosted runner.
- No warranty. Unlocked bootloader required.

## Why the running config instead of `gki_defconfig` + fragments?

LineageOS's `kernel.mk` merges `gki_defconfig` with
`vendor/waipio_GKI.config`, `vendor/xiaomi_GKI.config`,
`vendor/mondrian_GKI.config`, and `vendor/debugfs.config`. Using the captured
running `.config` avoids merge-order and `olddefconfig` differences and keeps
the exact module ABI. The trade-off is that it must be refreshed when the ROM
kernel changes.
