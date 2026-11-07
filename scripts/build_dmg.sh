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
DMG_OUTPUT="${DIST_DIR}/Sentinel-Node-Wallet-BTCB2-v0.1.0-macOS-arm64.dmg"

rm -rf "${DMG_STAGING}" "${DMG_OUTPUT}"
mkdir -p "${DMG_STAGING}"

cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create -volname "Sentinel Node Wallet BTCB2" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_OUTPUT}"

# Generate detached checksum
cd "${DIST_DIR}"
shasum -a 256 "$(basename "${DMG_OUTPUT}")" > SHA256SUMS.txt

echo "=== Generated DMG: ${DMG_OUTPUT} ==="
cat "${DIST_DIR}/SHA256SUMS.txt"
