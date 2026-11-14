#!/usr/bin/env bash
# Package Sentinel Node Wallet for Mac App Store (App ID 6833290684)
# Produces a verified .xcarchive ready for Xcode Organizer distribution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUNDLE_ID="pool.sentineldefensetechnologies.co.za"
VERSION="1.0"
BUILD_NUMBER="3"
APP_NAME="Sentinel Node Wallet"
TEAM_ID="S8QMQZA656"
SIGNING_IDENTITY="Apple Development: Peter Franco (89V8F6QJC2)"

echo "=== Packaging ${APP_NAME} for Mac App Store ==="
echo "Target Bundle ID: ${BUNDLE_ID}"
echo "Version: ${VERSION} (${BUILD_NUMBER})"
echo "Team: ${TEAM_ID}"
echo "Identity: ${SIGNING_IDENTITY}"

cd "${ROOT_DIR}"

# 1. Swift release build
swift build -c release --arch arm64

BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BIN_PATH="${BIN_DIR}/NodePocketApp"

# 2. Prepare staging directories
DIST_DIR="${ROOT_DIR}/dist"
ARCHIVE_NAME="SentinelNodeWallet-${VERSION}-${BUILD_NUMBER}-verified.xcarchive"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"
APP_BUNDLE="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"

rm -rf "${ARCHIVE_PATH}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mkdir -p "${ARCHIVE_PATH}/dSYMs"

# 3. Copy main binary
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/SentinelNodeWallet"
chmod +x "${APP_BUNDLE}/Contents/MacOS/SentinelNodeWallet"

# 4. Verify and embed official Bitcoin Knots binaries
"${SCRIPT_DIR}/fetch-verify-knots.sh"
KNOTS_CACHE_DIR="${ROOT_DIR}/.cache/bitcoin-29.4.3.knots20260508/bin"
cp "${KNOTS_CACHE_DIR}/bitcoind" "${APP_BUNDLE}/Contents/MacOS/bitcoind"
chmod +x "${APP_BUNDLE}/Contents/MacOS/bitcoind"
cp "${KNOTS_CACHE_DIR}/bitcoin-cli" "${APP_BUNDLE}/Contents/MacOS/bitcoin-cli"
chmod +x "${APP_BUNDLE}/Contents/MacOS/bitcoin-cli"

# 5. Copy resources
if [ -f "${ROOT_DIR}/Resources/consensus-manifest.json" ]; then
    cp "${ROOT_DIR}/Resources/consensus-manifest.json" "${APP_BUNDLE}/Contents/Resources/"
fi
if [ -f "${ROOT_DIR}/Resources/AppIcon.icns" ]; then
    cp "${ROOT_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# 6. Generate Info.plist
cat <<EOF > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>BuildMachineOSBuild</key>
    <string>26A434</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SentinelNodeWallet</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Sentinel Node Wallet BTCB2/XBT</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.finance</string>
</dict>
</plist>
EOF

# 7. Generate App Sandbox Entitlements
MAIN_ENTITLEMENTS="${DIST_DIR}/AppStore.entitlements.plist"
CHILD_ENTITLEMENTS="${DIST_DIR}/AppStoreChild.entitlements.plist"

cat <<EOF > "${MAIN_ENTITLEMENTS}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>webcredentials:${BUNDLE_ID}</string>
    </array>
</dict>
</plist>
EOF

cat <<EOF > "${CHILD_ENTITLEMENTS}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.inherit</key>
    <true/>
</dict>
</plist>
EOF

# 8. Sign Mach-O binaries with Hardened Runtime & Entitlements
codesign --force --options runtime --timestamp \
    --entitlements "${CHILD_ENTITLEMENTS}" \
    --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}/Contents/MacOS/bitcoind"

codesign --force --options runtime --timestamp \
    --entitlements "${CHILD_ENTITLEMENTS}" \
    --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}/Contents/MacOS/bitcoin-cli"

codesign --force --options runtime --timestamp \
    --entitlements "${MAIN_ENTITLEMENTS}" \
    --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}/Contents/MacOS/SentinelNodeWallet"

# Sign bundle
codesign --force --options runtime --timestamp \
    --entitlements "${MAIN_ENTITLEMENTS}" \
    --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"

codesign --verify --strict --deep --verbose=2 "${APP_BUNDLE}"

# 9. Create xcarchive Info.plist
DATE_NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cat <<EOF > "${ARCHIVE_PATH}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
		<key>ApplicationPath</key>
		<string>Applications/${APP_NAME}.app</string>
		<key>Architectures</key>
		<array>
			<string>arm64</string>
		</array>
		<key>CFBundleIdentifier</key>
		<string>${BUNDLE_ID}</string>
		<key>CFBundleShortVersionString</key>
		<string>${VERSION}</string>
		<key>CFBundleVersion</key>
		<string>${BUILD_NUMBER}</string>
		<key>SigningIdentity</key>
		<string>${SIGNING_IDENTITY}</string>
		<key>Team</key>
		<string>${TEAM_ID}</string>
	</dict>
	<key>ArchiveVersion</key>
	<integer>2</integer>
	<key>CreationDate</key>
	<date>${DATE_NOW}</date>
	<key>Name</key>
	<string>${APP_NAME}</string>
	<key>SchemeName</key>
	<string>${APP_NAME}</string>
</dict>
</plist>
EOF

# 10. Copy archive to Xcode standard Archives directory
ARCHIVE_DATE_DIR="$(date +"%Y-%m-%d")"
XCODE_ARCHIVES_DIR="${HOME}/Library/Developer/Xcode/Archives/${ARCHIVE_DATE_DIR}"
mkdir -p "${XCODE_ARCHIVES_DIR}"
cp -R "${ARCHIVE_PATH}" "${XCODE_ARCHIVES_DIR}/"

# 11. Create zip artifact
cd "${DIST_DIR}"
zip -r -q "${ARCHIVE_NAME}.zip" "${ARCHIVE_NAME}"

# 12. Create manifest
GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"
APP_SHA="$(shasum -a 256 "${APP_BUNDLE}/Contents/MacOS/SentinelNodeWallet" | awk '{print $1}')"
NODE_SHA="$(shasum -a 256 "${APP_BUNDLE}/Contents/MacOS/bitcoind" | awk '{print $1}')"
CLI_SHA="$(shasum -a 256 "${APP_BUNDLE}/Contents/MacOS/bitcoin-cli" | awk '{print $1}')"
CONS_SHA="$(shasum -a 256 "${APP_BUNDLE}/Contents/Resources/consensus-manifest.json" | awk '{print $1}')"

cat <<EOF > "${DIST_DIR}/BUILD_MANIFEST_APPSTORE.json"
{
  "build_type": "app_store_archive",
  "app_apple_id": "6833290684",
  "git_commit": "${GIT_COMMIT}",
  "team_id": "${TEAM_ID}",
  "bundle_id": "${BUNDLE_ID}",
  "version": "${VERSION}",
  "build_number": "${BUILD_NUMBER}",
  "signing_identity": "${SIGNING_IDENTITY}",
  "archive_path": "${ARCHIVE_PATH}",
  "xcode_archive_install": "${XCODE_ARCHIVES_DIR}/${ARCHIVE_NAME}",
  "artifacts": {
    "SentinelNodeWallet_sha256": "${APP_SHA}",
    "bitcoind_sha256": "${NODE_SHA}",
    "bitcoin_cli_sha256": "${CLI_SHA}",
    "consensus_manifest_sha256": "${CONS_SHA}"
  }
}
EOF

# 13. Write deployment instructions
cat <<EOF > "${DIST_DIR}/DEPLOYMENT_INSTRUCTIONS_APPSTORE.txt"
================================================================================
SENTINEL NODE WALLET 1.0 (BUILD ${BUILD_NUMBER}) - APP STORE DEPLOYMENT INSTRUCTIONS
================================================================================

App Store Connect App ID: 6833290684
Registered Bundle ID: ${BUNDLE_ID}
Version: ${VERSION}
Build: ${BUILD_NUMBER}
Team: ${TEAM_ID} (Peter Franco)

Archive Location:
${ARCHIVE_PATH}

Xcode Archives Location (Automatically installed):
${XCODE_ARCHIVES_DIR}/${ARCHIVE_NAME}

--------------------------------------------------------------------------------
HOW TO DEPLOY VIA XCODE ORGANIZER
--------------------------------------------------------------------------------

Option A (Direct in Xcode):
1. Open Xcode.
2. In the top menu bar, click "Window" -> "Organizer" (Shortcut: Option + Shift + Command + O).
3. Click "Archives" in the top bar. You will see:
   "Sentinel Node Wallet" - Version 1.0 (1)
4. Select it and click the blue "Distribute App" button on the right.
5. Choose "App Store Connect" -> "Upload" and follow the prompts to submit.

Option B (From terminal or Finder):
1. Run:
   open "${ARCHIVE_PATH}"
2. It will open immediately in Xcode Organizer.
3. Click "Distribute App" -> "App Store Connect" -> "Upload".

After upload completes, App Store Connect will process the build within a few
minutes and it will become selectable under "Build" on Version 1.0.
================================================================================
EOF

echo "=== Successfully built and installed ${ARCHIVE_NAME} ==="
cat "${DIST_DIR}/BUILD_MANIFEST_APPSTORE.json"
