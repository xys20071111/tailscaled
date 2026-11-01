#!/usr/bin/env bash
set -euo pipefail

# Local build script for the Tailscaled Magisk module.
# Usage: ./build_local.sh [arm64|arm]

ARCH="${1:-arm64}"
case "$ARCH" in
  arm64) GOARCH=arm64; CC_NAME=aarch64-linux-android21-clang; CXX_NAME=aarch64-linux-android21-clang++ ;;
  arm)   GOARCH=arm;   CC_NAME=armv7a-linux-androideabi21-clang; CXX_NAME=armv7a-linux-androideabi21-clang++ ;;
  *) echo "Unknown arch: $ARCH"; exit 1 ;;
esac

ANDROID_NDK="${ANDROID_NDK:-/home/xys/tools/AndroidSDK/ndk/28.2.13676358}"
NDK_BIN="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
if [ ! -d "$NDK_BIN" ]; then
  echo "NDK not found at $NDK_BIN"; exit 1
fi

export PATH="/home/xys/.local/go/bin:$PATH"
export GOOS=android
export GOARCH
export CGO_ENABLED=1
export CC="$NDK_BIN/$CC_NAME"
export CXX="$NDK_BIN/$CXX_NAME"

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$REPO_DIR/tailscale-build"
DIST_DIR="$REPO_DIR/dist"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$REPO_DIR"

# Fetch latest tailscale source if not present
if [ ! -d "$BUILD_DIR/.git" ]; then
  git clone --depth 1 https://github.com/tailscale/tailscale.git "$BUILD_DIR"
fi

cd "$BUILD_DIR"

# Apply the Android patch
patch -p1 --no-backup-if-mismatch < "$REPO_DIR/tailscale-android.patch"

# mkversion
eval "$(CGO_ENABLED=0 GOOS="$(go env GOHOSTOS)" GOARCH="$(go env GOHOSTARCH)" go run ./cmd/mkversion)"
VERSION_SHORT="${VERSION_SHORT:-dev}"
ldflags="-X tailscale.com/version.longStamp=${VERSION_LONG} -X tailscale.com/version.shortStamp=${VERSION_SHORT} -s -w"

TAGS="ts_include_cli ts_omit_aws ts_omit_tap ts_omit_kube ts_omit_completion ts_omit_completion_scripts ts_omit_wakeonlan ts_omit_capture ts_omit_systray ts_omit_syspolicy ts_omit_appconnectors ts_omit_identityfederation ts_omit_usermetrics ts_omit_logtail ts_omit_netlog ts_omit_linuxdnsfight ts_omit_tpm ts_omit_ssh"

echo "Building tailscaled for $ARCH..."
go build -tags "$TAGS" -ldflags "$ldflags" -o "$BUILD_DIR/tailscale.combined" -trimpath ./cmd/tailscaled

# UPX compress
if command -v upx >/dev/null 2>&1; then
  upx --lzma --best "$BUILD_DIR/tailscale.combined" || true
fi

mkdir -p "$REPO_DIR/files"
cp "$BUILD_DIR/tailscale.combined" "$REPO_DIR/files/tailscale.combined"

# Update module.prop version (best effort)
VERSION="${VERSION_SHORT}"
sed -i "s/^version=.*/version=${VERSION}/" "$REPO_DIR/module.prop" 2>/dev/null || true

# Package zip
mkdir -p "$DIST_DIR"
cd "$REPO_DIR"
zip -9 -r "$DIST_DIR/Magisk-Tailscaled-${VERSION}-${ARCH}.zip" . \
  -x ".commandcode/*" "*.md" ".freebuff/*" "*git*" "dist/*" "*.zip" "*.patch" "tailscale-build/*" 2>/dev/null || true

echo "Done: $DIST_DIR/Magisk-Tailscaled-${VERSION}-${ARCH}.zip"
