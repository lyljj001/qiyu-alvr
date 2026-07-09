#!/usr/bin/env bash
#
# build.sh — One-shot build for the ALVR Qiyu Dream client.
#
# What it does:
#   1. Clones ALVR v20.14.1 (pinned, so the C ABI always matches this client).
#   2. Builds alvr_client_core for aarch64 (the Rust streaming/decoding core).
#   3. Generates alvr_client_core.h with cbindgen (exact ABI the C++ bridges to).
#   4. Copies the .so + header into build/alvr_client_core/ where CMake/gradle expect them.
#
# The final APK is built by Gradle (run `gradle assembleRelease`, or just push to
# GitHub and let the Actions workflow build it). This script only produces the
# native core + header that the Gradle/CMake build links against.
#
# Prerequisites (install once, for LOCAL builds):
#   - Android SDK with NDK r25 (ANDROID_NDK / ANDROID_NDK_HOME set)
#   - Rust + cargo (rustup), plus: rustup target add aarch64-linux-android
#   - cargo install cargo-ndk cbindgen
#   - JDK 17
#
set -euo pipefail

ALVR_TAG="v20.14.1"
ALVR_REPO="https://github.com/alvr-org/ALVR.git"
NDK_TARGET="arm64-v8a"
MIN_SDK=26
NDK_VERSION="25.1.8937393"
CBINDGEN_VER="0.26.0"
CARGO_NDK_VER="4.1.2"
SO_ABI="arm64-v8a"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$ROOT/build/alvr_client_core"

# cargo-ndk needs the NDK location; prefer ANDROID_NDK, fall back to ANDROID_HOME.
export ANDROID_NDK_HOME="${ANDROID_NDK:-${ANDROID_HOME:-}}/ndk/${NDK_VERSION}"
# Fixed target dir so CI can cache the (slow) Rust build across runs.
export CARGO_TARGET_DIR="/tmp/alvr_target"

echo "=================================================="
echo " ALVR Qiyu Dream client builder"
echo " ALVR version : $ALVR_TAG"
echo " NDK home     : $ANDROID_NDK_HOME"
echo " Output dir   : $OUT_DIR"
echo "=================================================="

# ---- 1. Fetch ALVR source (shallow clone of the exact tag) ----
SRC="$(mktemp -d)"
cleanup() { rm -rf "$SRC"; }
trap cleanup EXIT
echo "==> Cloning ALVR $ALVR_TAG"
git clone --depth 1 --branch "$ALVR_TAG" "$ALVR_REPO" "$SRC/alvr"

# ---- 2. Toolchain ----
echo "==> Rust target + tools"
rustup target add aarch64-linux-android >/dev/null 2>&1 || true
cargo install cargo-ndk --version "$CARGO_NDK_VER" 2>/dev/null || true
cargo install cbindgen --version "$CBINDGEN_VER" 2>/dev/null || true

# ---- 3. Build alvr_client_core (aarch64, release) ----
echo "==> Building alvr_client_core (slow step, ~10-40 min; cached across CI runs)"
cd "$SRC/alvr"
cargo ndk -t "$NDK_TARGET" -p "$MIN_SDK" build -p alvr_client_core --release

SO_SRC="$CARGO_TARGET_DIR/aarch64-linux-android/release/libalvr_client_core.so"
[ -f "$SO_SRC" ] || { echo "ERROR: $SO_SRC not found" >&2; exit 1; }

# ---- 4. Generate the C header ----
mkdir -p "$OUT_DIR/include"
echo "==> Generating alvr_client_core.h (cbindgen)"
cbindgen "$SRC/alvr/alvr/client_core" \
  --config "$SRC/alvr/alvr/client_core/cbindgen.toml" \
  --lockfile "$SRC/alvr/Cargo.lock" \
  --output "$OUT_DIR/include/alvr_client_core.h"

# ---- 5. Stage artifacts where the Gradle/CMake build expects them ----
mkdir -p "$OUT_DIR/$SO_ABI"
cp "$SO_SRC" "$OUT_DIR/$SO_ABI/libalvr_client_core.so"
cp "$OUT_DIR/include/alvr_client_core.h" "$OUT_DIR/alvr_client_core.h"

# Best-effort: bundle libc++_shared.so if the NDK provides it (alvr_client_core
# may be linked against it). Harmless if unused.
if [ -n "${ANDROID_NDK:-}" ]; then
  LIBCXX="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
  if [ -f "$LIBCXX" ]; then
    mkdir -p "$ROOT/app/src/main/jniLibs/$SO_ABI"
    cp "$LIBCXX" "$ROOT/app/src/main/jniLibs/$SO_ABI/libc++_shared.so"
    echo "==> Bundled libc++_shared.so"
  fi
fi

echo "==> Artifacts staged:"
echo "   $OUT_DIR/$SO_ABI/libalvr_client_core.so"
echo "   $OUT_DIR/alvr_client_core.h"
echo ""
echo "==> Next: run 'gradle assembleRelease' (locally) or push to GitHub and let CI build the APK."
