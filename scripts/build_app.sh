#!/usr/bin/env bash
set -euo pipefail

echo "=== Building Sentinel Node Wallet - BTCB2 Native macOS Release Binary ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

# Build release configuration with Swift Package Manager
swift build -c release --arch arm64

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/NodePocketApp"
APP_BUNDLE="${ROOT_DIR}/dist/Sentinel Node Wallet.app"

rm -rf "${ROOT_DIR}/dist"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/SentinelNodeWallet"
chmod +x "${APP_BUNDLE}/Contents/MacOS/SentinelNodeWallet"

# Embed official verified Bitcoin Knots binaries
KNOTS_CACHE_DIR="${ROOT_DIR}/.cache/bitcoin-29.4.3.knots20260508/bin"
if [ -f "${KNOTS_CACHE_DIR}/bitcoind" ]; then
    echo "Embedding official Bitcoin Knots bitcoind into bundle..."
    cp "${KNOTS_CACHE_DIR}/bitcoind" "${APP_BUNDLE}/Contents/MacOS/bitcoind"
    chmod +x "${APP_BUNDLE}/Contents/MacOS/bitcoind"
    codesign --force --sign - "${APP_BUNDLE}/Contents/MacOS/bitcoind"
fi

if [ -f "${KNOTS_CACHE_DIR}/bitcoin-cli" ]; then
    echo "Embedding official Bitcoin Knots bitcoin-cli into bundle..."
    cp "${KNOTS_CACHE_DIR}/bitcoin-cli" "${APP_BUNDLE}/Contents/MacOS/bitcoin-cli"
    chmod +x "${APP_BUNDLE}/Contents/MacOS/bitcoin-cli"
    codesign --force --sign - "${APP_BUNDLE}/Contents/MacOS/bitcoin-cli"
fi

codesign --force --sign - "${APP_BUNDLE}/Contents/MacOS/SentinelNodeWallet"

# Copy resources
if [ -f "${ROOT_DIR}/Resources/consensus-manifest.json" ]; then
    cp "${ROOT_DIR}/Resources/consensus-manifest.json" "${APP_BUNDLE}/Contents/Resources/"
fi

# Copy AppIcon.icns
if [ -f "${ROOT_DIR}/Resources/AppIcon.icns" ]; then
    echo "Embedding AppIcon.icns into bundle..."
    cp "${ROOT_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Create Info.plist
cat <<EOF > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SentinelNodeWallet</string>
    <key>CFBundleIdentifier</key>
    <string>app.nodepocket.btcb2</string>
    <key>CFBundleName</key>
    <string>Sentinel Node Wallet</string>
    <key>CFBundleDisplayName</key>
    <string>Sentinel Node Wallet</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.finance</string>
</dict>
</plist>
EOF

# Code sign with ad-hoc signature for local arm64 execution
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "=== Successfully built ${APP_BUNDLE} ==="
