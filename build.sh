#!/usr/bin/env bash
#
# build.sh — One-shot build for the ALVR Qiyu Dream client.
#
# What it does:
#   1. Clones ALVR v20.14.1 (pinned, so the C ABI always matches this client).
#   2. Builds alvr_client_core for aarch64 (the Rust streaming/decoding core).
#   3. Generates alvr_client_core.h with cbindgen (exact ABI the C++ bridges to).
#   4. Copies the .so + header into build/alvr_client_core/ where CMake/gradle expect them.
#   5. Builds the signed release APK with Gradle.
#
# Prerequisites (install once):
#   - Android SDK with NDK r25 (ANDROID_NDK / $ANDROID_HOME set)
#   - Rust + cargo (rustup), plus: rustup target add aarch64-linux-android
#   - cargo install cargo-ndk cbindgen
#   - JDK 17
#
set -euo pipefail

ALVR_TAG="v20.14.1"
ALVR_REPO="https://github.com/alvr-org/ALVR.git"
NDK_TARGET="arm64-v8a"
MIN_SDK=26
CBINDGEN_VER="0.26.0"
CARGO_NDK_VER="2.16.0"
SO_ABI="arm64-v8a"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$ROOT/build/alvr_client_core"

echo "=================================================="
echo " ALVR Qiyu Dream client builder"
echo " ALVR version : $ALVR_TAG"
echo " Output dir   : $OUT_DIR"
echo "=================================================="

# ---- 1. Fetch ALVR source (shallow clone of the exact tag) ----
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
echo "==> Cloning ALVR $ALVR_TAG"
git clone --depth 1 --branch "$ALVR_TAG" "$ALVR_REPO" "$TMP/alvr"

# ---- 2. Toolchain ----
echo "==> Rust target + tools"
rustup target add aarch64-linux-android >/dev/null 2>&1 || true
cargo install cargo-ndk --version "$CARGO_NDK_VER" 2>/dev/null || true
cargo install cbindgen --version "$CBINDGEN_VER" 2>/dev/null || true

# ---- 3. Build alvr_client_core (aarch64, release) ----
echo "==> Building alvr_client_core (this is the slow step, ~10-40 min)"
cd "$TMP/alvr"
cargo ndk -t "$NDK_TARGET" -p "$MIN_SDK" build -p alvr_client_core --release

SO_SRC="$TMP/alvr/target/aarch64-linux-android/release/libalvr_client_core.so"
[ -f "$SO_SRC" ] || { echo "ERROR: $SO_SRC not found" >&2; exit 1; }

# ---- 4. Generate the C header ----
mkdir -p "$OUT_DIR/include"
echo "==> Generating alvr_client_core.h (cbindgen)"
cbindgen "$TMP/alvr/alvr/client_core" \
  --config "$TMP/alvr/alvr/client_core/cbindgen.toml" \
  --lockfile "$TMP/alvr/Cargo.lock" \
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

# ---- 6. Build the APK ----
cd "$ROOT"
echo "==> Building release APK"
if [ -x ./gradlew ]; then
  ./gradlew assembleRelease
else
  gradle assembleRelease
fi

echo "=================================================="
echo " DONE. APK: app/build/outputs/apk/release/"
echo "=================================================="
