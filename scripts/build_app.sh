#!/usr/bin/env bash
set -euo pipefail

echo "=== Building Sentinel Node Wallet - BTCB2 LOCAL DEVELOPMENT BUNDLE (ad-hoc signed, NOT production) ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

# Build release configuration with Swift Package Manager
swift build -c release --arch arm64

BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BIN_PATH="${BIN_DIR}/NodePocketApp"
APP_BUNDLE="${ROOT_DIR}/dist/Sentinel Node Wallet.app"

rm -rf "${ROOT_DIR}/dist"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/SentinelNodeWallet"
chmod +x "${APP_BUNDLE}/Contents/MacOS/SentinelNodeWallet"

# Run binary provenance verification
"${SCRIPT_DIR}/fetch-verify-knots.sh"

# Embed official verified Bitcoin Knots binaries
KNOTS_CACHE_DIR="${ROOT_DIR}/.cache/bitcoin-29.4.3.knots20260508/bin"
if [ ! -f "${KNOTS_CACHE_DIR}/bitcoind" ] || [ ! -f "${KNOTS_CACHE_DIR}/bitcoin-cli" ]; then
    echo "ERROR: Required Bitcoin Knots binaries missing in ${KNOTS_CACHE_DIR}. Packaging aborted." >&2
    exit 1
fi

echo "Embedding official Bitcoin Knots bitcoind into bundle..."
cp "${KNOTS_CACHE_DIR}/bitcoind" "${APP_BUNDLE}/Contents/MacOS/bitcoind"
chmod +x "${APP_BUNDLE}/Contents/MacOS/bitcoind"
codesign --force --sign - "${APP_BUNDLE}/Contents/MacOS/bitcoind"

echo "Embedding official Bitcoin Knots bitcoin-cli into bundle..."
cp "${KNOTS_CACHE_DIR}/bitcoin-cli" "${APP_BUNDLE}/Contents/MacOS/bitcoin-cli"
chmod +x "${APP_BUNDLE}/Contents/MacOS/bitcoin-cli"
codesign --force --sign - "${APP_BUNDLE}/Contents/MacOS/bitcoin-cli"

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
    <string>pool.sentineldefensetechnologies.co.za</string>
    <key>CFBundleName</key>
    <string>Sentinel Node Wallet</string>
    <key>CFBundleDisplayName</key>
    <string>Sentinel Node Wallet</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
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

# Code sign with Apple Development identity or ad-hoc fallback
DEV_IDENTITY="Apple Development: Peter Franco (89V8F6QJC2)"
ENTITLEMENTS="${ROOT_DIR}/dist/AppStore.entitlements.plist"
if security find-identity -v -p codesigning | grep -q "${DEV_IDENTITY}"; then
    echo "Signing with Developer Identity: ${DEV_IDENTITY}"
    if [ -f "${ENTITLEMENTS}" ]; then
        codesign --force --deep --sign "${DEV_IDENTITY}" --entitlements "${ENTITLEMENTS}" --options runtime "${APP_BUNDLE}"
    else
        codesign --force --deep --sign "${DEV_IDENTITY}" --options runtime "${APP_BUNDLE}"
    fi
else
    echo "Signing with ad-hoc identity"
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

# Generate reproducible Build Manifest
GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"
CI_CHECKOUT_COMMIT="${GIT_COMMIT}"
if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ]; then
    # GitHub PR workflows normally check out a synthetic MERGE commit; report
    # the actual reviewed source HEAD SHA as well as the checkout SHA.
    GIT_COMMIT="${SENTINEL_PR_HEAD_SHA:-}"
fi
[[ "${GIT_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || {
    echo "ERROR: Cannot identify exact Git source SHA for build manifest." >&2
    exit 1
}
BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
APP_SHA="$(shasum -a 256 "${APP_BUNDLE}/Contents/MacOS/SentinelNodeWallet" | awk '{print $1}')"
BITCOIND_SHA="$(shasum -a 256 "${APP_BUNDLE}/Contents/MacOS/bitcoind" | awk '{print $1}')"
BITCOIN_CLI_SHA="$(shasum -a 256 "${APP_BUNDLE}/Contents/MacOS/bitcoin-cli" | awk '{print $1}')"
CONSENSUS_SHA="$(shasum -a 256 "${ROOT_DIR}/Resources/consensus-manifest.json" | awk '{print $1}')"

cat <<EOF > "${ROOT_DIR}/dist/BUILD_MANIFEST.json"
{
  "build_timestamp": "${BUILD_DATE}",
  "git_commit": "${GIT_COMMIT}",
  "ci_checkout_commit": "${CI_CHECKOUT_COMMIT}",
  "artifacts": {
    "SentinelNodeWallet_sha256": "${APP_SHA}",
    "bitcoind_sha256": "${BITCOIND_SHA}",
    "bitcoin_cli_sha256": "${BITCOIN_CLI_SHA}",
    "consensus_manifest_sha256": "${CONSENSUS_SHA}"
  }
}
EOF

echo "=== Successfully built ${APP_BUNDLE} ==="
cat "${ROOT_DIR}/dist/BUILD_MANIFEST.json"
