#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Packaging Sentinel Node Wallet - BTCB2 DMG ==="

# First ensure app is built
"${SCRIPT_DIR}/build_app.sh"

DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/Sentinel Node Wallet.app"
DMG_STAGING="${DIST_DIR}/dmg_staging"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || echo "1.0")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || echo "3")"
DMG_NAME="Sentinel-Node-Wallet-v${VERSION}-Build${BUILD_NUMBER}-macOS-arm64.dmg"
DMG_OUTPUT="${DIST_DIR}/${DMG_NAME}"

echo "Target DMG: ${DMG_OUTPUT} (Version ${VERSION}, Build ${BUILD_NUMBER})"

rm -rf "${DMG_STAGING}" "${DMG_OUTPUT}"
mkdir -p "${DMG_STAGING}"

cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create -volname "Sentinel Node Wallet BTCB2" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_OUTPUT}"

# Clean up staging directory
rm -rf "${DMG_STAGING}"

# Code sign DMG if identity is available
DEV_IDENTITY="Apple Development: Peter Franco (89V8F6QJC2)"
if security find-identity -v -p codesigning | grep -q "${DEV_IDENTITY}"; then
    echo "Signing DMG with Developer Identity: ${DEV_IDENTITY}"
    codesign --force --sign "${DEV_IDENTITY}" "${DMG_OUTPUT}"
fi

# Verify DMG integrity
hdiutil verify "${DMG_OUTPUT}"

# Generate detached checksum
cd "${DIST_DIR}"
shasum -a 256 "$(basename "${DMG_OUTPUT}")" > SHA256SUMS.txt
ln -sf "${DMG_NAME}" "${DIST_DIR}/Sentinel-Node-Wallet-macOS-arm64.dmg"

echo "=== Successfully Generated DMG: ${DMG_OUTPUT} ==="
cat "${DIST_DIR}/SHA256SUMS.txt"
