#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KERNEL_REPO="${KERNEL_REPO:-https://github.com/LineageOS/android_kernel_xiaomi_sm8450.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-lineage-24.0}"
KERNEL_REF="${KERNEL_REF:-eff4b40407a1b6f1b1ab84554cbb540bcb495175}"
KSU_VARIANT="${KSU_VARIANT:-BakaSU}"
KERNEL_LOCALVERSION="${KERNEL_LOCALVERSION:--gki-geff4b40407a1}"
# Do not let the kernel Makefile see a LOCALVERSION environment variable:
# it would be appended in addition to CONFIG_LOCALVERSION.
unset LOCALVERSION

CLANG_DIR="${CLANG_DIR:-$ROOT/.clang-r596125}"
CLANG_URL="${CLANG_URL:-https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android17-release/clang-r596125.tar.gz}"

log() { printf '\n[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# LineageOS 24 for mondrian is built with Android clang r596125 (22.0.2).
# Using a different clang can break LTO/CFI and the prebuilt vendor modules.
if [ ! -x "$CLANG_DIR/bin/clang" ]; then
  log "Downloading clang-r596125"
  rm -rf "$CLANG_DIR"
  mkdir -p "$CLANG_DIR"
  curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 30 \
    "$CLANG_URL" -o "$ROOT/clang-r596125.tar.gz"
  tar -xzf "$ROOT/clang-r596125.tar.gz" -C "$CLANG_DIR"
  rm -f "$ROOT/clang-r596125.tar.gz"
fi
if [ ! -x "$CLANG_DIR/bin/clang" ]; then
  echo "clang archive did not contain bin/clang" >&2
  find "$CLANG_DIR" -maxdepth 2 -type d >&2 || true
  exit 1
fi
export PATH="$CLANG_DIR/bin:$PATH"
log "clang: $(clang --version | head -n1)"

if [ ! -d "$ROOT/kernel/.git" ]; then
  log "Cloning $KERNEL_REPO ($KERNEL_BRANCH)"
  git clone --depth 1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$ROOT/kernel"
fi
cd "$ROOT/kernel"

if [ -n "$KERNEL_REF" ]; then
  log "Checking out kernel $KERNEL_REF"
  git fetch --depth 1 origin "$KERNEL_REF"
  git checkout --detach FETCH_HEAD
fi
git log -1 --oneline

log "Adding $KSU_VARIANT"
case "$KSU_VARIANT" in
  BakaSU)
    curl -LSs https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh | bash -s main
    ;;
  Official)
    curl -LSs https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh | bash -s main
    ;;
  SukiSU)
    curl -LSs https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh | bash -s main
    ;;
  *)
    echo "Unknown KSU_VARIANT: $KSU_VARIANT" >&2
    exit 1
    ;;
esac

# BakaSU/KernelSU modify tracked files in the kernel tree.  setlocalversion
# appends "-dirty" whenever `git diff-index` is not clean, even with
# CONFIG_LOCALVERSION_AUTO=n, which breaks the exact release string that the
# prebuilt vendor modules expect.  Commit those tracked changes so the tree is
# clean before the release check.
if ! git diff-index --quiet HEAD --; then
  log "Committing kernel patches so localversion stays clean"
  git add -u
  git -c user.name="LineageOS Kernel Builder" \
      -c user.email="kernel-builder@localhost" \
      commit -m "Add $KSU_VARIANT"
fi
if ! git diff-index --quiet HEAD --; then
  echo "kernel tree is still dirty after committing patches" >&2
  git status --short --untracked-files=no >&2
  exit 1
fi

# Force a deterministic release string.  An empty .scmversion makes
# scripts/setlocalversion skip git/hg/svn entirely, so neither "-dirty" nor a
# "-g<commit>" suffix can leak into kernelrelease.  CONFIG_LOCALVERSION
# supplies the exact suffix that /vendor/lib/modules expects.
: > .scmversion

# Use the exact config from the installed LineageOS build.  This is what makes
# the kernel ABI/vermagic match the vendor modules that stay on the device.
mkdir -p "$ROOT/out"
cp "$ROOT/configs/mondrian_running.config" "$ROOT/out/.config"

MAKE_ARGS=(
  O="$ROOT/out"
  ARCH=arm64
  LLVM=1
  LLVM_IAS=1
  CLANG_TRIPLE=aarch64-linux-gnu-
)
make "${MAKE_ARGS[@]}" olddefconfig

# KernelSU is a new symbol, so it is not in the captured config.
./scripts/config --file "$ROOT/out/.config" -e KSU
# Resolve KSU and any new symbols first.  Set the release string afterwards so
# a later olddefconfig cannot put CONFIG_LOCALVERSION_AUTO back.
make "${MAKE_ARGS[@]}" olddefconfig

# Keep the exact release string expected by /vendor/lib/modules.
./scripts/config --file "$ROOT/out/.config" --set-str LOCALVERSION "$KERNEL_LOCALVERSION"
./scripts/config --file "$ROOT/out/.config" -d LOCALVERSION_AUTO

if ! grep -q '^CONFIG_KSU=y' "$ROOT/out/.config"; then
  echo "CONFIG_KSU was not enabled" >&2
  grep -n 'KSU' "$ROOT/out/.config" >&2 || true
  exit 1
fi
if ! grep -qx "CONFIG_LOCALVERSION=\"$KERNEL_LOCALVERSION\"" "$ROOT/out/.config"; then
  echo "CONFIG_LOCALVERSION was not set as expected" >&2
  grep -n 'CONFIG_LOCALVERSION' "$ROOT/out/.config" >&2 || true
  exit 1
fi
if grep -q '^CONFIG_LOCALVERSION_AUTO=y' "$ROOT/out/.config"; then
  echo "CONFIG_LOCALVERSION_AUTO is still enabled" >&2
  exit 1
fi

# kernelrelease reads include/config/auto.conf, not .config.  Regenerate it so
# the LOCALVERSION value above actually reaches the release string.
log "Syncing include/config/auto.conf"
make "${MAKE_ARGS[@]}" syncconfig

if ! grep -qx "CONFIG_LOCALVERSION=\"$KERNEL_LOCALVERSION\"" "$ROOT/out/include/config/auto.conf"; then
  echo "auto.conf has the wrong CONFIG_LOCALVERSION" >&2
  grep -n 'CONFIG_LOCALVERSION' "$ROOT/out/include/config/auto.conf" >&2 || true
  exit 1
fi
if grep -q '^CONFIG_LOCALVERSION_AUTO=y' "$ROOT/out/include/config/auto.conf"; then
  echo "auto.conf still has CONFIG_LOCALVERSION_AUTO=y" >&2
  exit 1
fi

BASE_VERSION="$(awk '/^VERSION[[:space:]]*=/{v=$3} /^PATCHLEVEL[[:space:]]*=/{p=$3} /^SUBLEVEL[[:space:]]*=/{s=$3} END{print v"."p"."s}' Makefile)"
EXPECTED_RELEASE="${BASE_VERSION}${KERNEL_LOCALVERSION}"
ACTUAL_RELEASE="$(make -s "${MAKE_ARGS[@]}" kernelrelease | tail -n1)"
log "kernel release: $ACTUAL_RELEASE (expected: $EXPECTED_RELEASE)"
if [ "$ACTUAL_RELEASE" != "$EXPECTED_RELEASE" ]; then
  echo "kernel release mismatch; vendor modules would fail to load" >&2
  exit 1
fi

log "Building Image"
make -j"$(nproc)" "${MAKE_ARGS[@]}" KCFLAGS="-D__ANDROID_COMMON_KERNEL__" Image 2>&1 | tee "$ROOT/build.log"

cp -f "$ROOT/out/arch/arm64/boot/Image" "$ROOT/Image"
cp -f "$ROOT/out/.config" "$ROOT/kernel.config"
sha256sum "$ROOT/Image" | tee "$ROOT/Image.sha256"

log "Packaging AnyKernel3"
rm -rf "$ROOT/ak3"
git clone --depth 1 https://github.com/osm0sis/AnyKernel3.git "$ROOT/ak3"
cp -f "$ROOT/out/arch/arm64/boot/Image" "$ROOT/ak3/Image"
cp -f "$ROOT/anykernel/anykernel.sh" "$ROOT/ak3/anykernel.sh"
(
  cd "$ROOT/ak3"
  rm -rf .git README.md
  zip -r9 "$ROOT/AnyKernel3-mondrian-lineage.zip" .
)

log "Done"
ls -lh "$ROOT/Image" "$ROOT/AnyKernel3-mondrian-lineage.zip" "$ROOT/build.log"
