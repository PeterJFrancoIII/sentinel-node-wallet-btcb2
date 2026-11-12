#!/usr/bin/env bash
# Explicitly owner-authorized, Developer ID signed, notarized macOS candidate.
# Does not deploy or publish, and requires all independent P0 release approvals.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP="${ROOT_DIR}/dist/Sentinel Node Wallet.app"
DIST="${ROOT_DIR}/dist"
BUNDLE_ID="app.nodepocket.btcb2"
fail() { printf "RELEASE BLOCKED: %s\n" "$*" >&2; exit 1; }
require() { local key="$1"; [ -n "${!key:-}" ] || fail "Missing required setting ${key}"; }

[ "${SENTINEL_RELEASE_SECURITY_APPROVED:-}" = "1" ] ||
    fail "Release approval missing. Source and CI alone do not authorize distribution."
for key in SENTINEL_DEVELOPER_ID_APPLICATION SENTINEL_APPLE_TEAM_ID SENTINEL_WEBCREDENTIALS_DOMAIN SENTINEL_NOTARY_PROFILE; do
    require "${key}"
done
[[ "${SENTINEL_DEVELOPER_ID_APPLICATION}" == "Developer ID Application:"* ]] ||
    fail "Require a Developer ID Application identity (not ad-hoc)."
[[ "${SENTINEL_APPLE_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]] || fail "Invalid Apple Team ID."
DOMAIN="${SENTINEL_WEBCREDENTIALS_DOMAIN}"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9.-]+$ ]] && [[ "${DOMAIN}" == *.* ]] &&
    [[ "${DOMAIN}" != *..* ]] && [[ "${DOMAIN}" != .* ]] && [[ "${DOMAIN}" != *. ]] ||
    fail "Provide an approved HTTPS webcredentials domain without scheme/path/wildcards."
command -v codesign >/dev/null || fail "macOS codesign is required."
command -v xcrun >/dev/null || fail "Xcode's xcrun is required."
command -v hdiutil >/dev/null || fail "macOS hdiutil is required."

AASA_TMP="$(mktemp -t sentinel-aasa)"
NOTARY_TMP="$(mktemp -t sentinel-notary)"
cleanup() { rm -f "${AASA_TMP}" "${NOTARY_TMP}"; }
trap cleanup EXIT
curl --fail --silent --show-error --location --max-time 20 \
    "https://${DOMAIN}/.well-known/apple-app-site-association" -o "${AASA_TMP}" ||
    fail "Approved domain does not serve HTTPS Apple app association metadata."
python3 - "${AASA_TMP}" "${SENTINEL_APPLE_TEAM_ID}.${BUNDLE_ID}" <<'PY' ||
    fail "Apple association metadata does not include this exact Team ID and app ID."
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
apps = data.get("webcredentials", {}).get("apps", [])
if not isinstance(apps, list) or sys.argv[2] not in apps:
    raise SystemExit(1)
PY

# Existing builder creates an ad-hoc local bundle after SHA pinning the Knots
# archive and bitcoind. Re-sign everything before any prospective release.
"${SCRIPT_DIR}/build_app.sh"
[ -d "${APP}" ] || fail "Missing built macOS app."
plutil -lint "${APP}/Contents/Info.plist" >/dev/null
ENTITLEMENTS="${DIST}/Production.entitlements.plist"
cat > "${ENTITLEMENTS}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.developer.associated-domains</key>
<array><string>webcredentials:${DOMAIN}</string></array>
</dict></plist>
EOF
plutil -lint "${ENTITLEMENTS}" >/dev/null
for binary in bitcoind bitcoin-cli; do
    codesign --force --options runtime --timestamp \
        --sign "${SENTINEL_DEVELOPER_ID_APPLICATION}" "${APP}/Contents/MacOS/${binary}"
done
codesign --force --options runtime --timestamp --entitlements "${ENTITLEMENTS}" \
    --sign "${SENTINEL_DEVELOPER_ID_APPLICATION}" "${APP}"
codesign --verify --strict --deep --verbose=2 "${APP}"
SIGNATURE="$(codesign --display --verbose=4 "${APP}" 2>&1)"
[[ "${SIGNATURE}" == *"TeamIdentifier=${SENTINEL_APPLE_TEAM_ID}"* ]] ||
    fail "Signed bundle Team ID does not match approved Apple Team ID."
[[ "${SIGNATURE}" == *"Authority=Developer ID Application:"* ]] ||
    fail "App lacks the required Developer ID Application signature."
SIGNED_ENTITLEMENTS="$(codesign --display --entitlements - "${APP}" 2>/dev/null)"
[[ "${SIGNED_ENTITLEMENTS}" == *"webcredentials:${DOMAIN}"* ]] ||
    fail "Missing webcredentials entitlement on signed bundle."

# The ad-hoc manifest contains pre-signing hashes. Overwrite with hashes of
# the final signed Mach-O binaries; do not publish stale provenance.
APP_SHA="$(shasum -a 256 "${APP}/Contents/MacOS/SentinelNodeWallet" | awk '{print $1}')"
NODE_SHA="$(shasum -a 256 "${APP}/Contents/MacOS/bitcoind" | awk '{print $1}')"
CLI_SHA="$(shasum -a 256 "${APP}/Contents/MacOS/bitcoin-cli" | awk '{print $1}')"
CONS_SHA="$(shasum -a 256 "${APP}/Contents/Resources/consensus-manifest.json" | awk '{print $1}')"
cat > "${DIST}/BUILD_MANIFEST.json" <<EOF
{
  "build_type": "developer_id_notarized_candidate",
  "git_commit": "$(git -C "${ROOT_DIR}" rev-parse HEAD)",
  "team_id": "${SENTINEL_APPLE_TEAM_ID}",
  "bundle_id": "${BUNDLE_ID}",
  "associated_domain": "${DOMAIN}",
  "artifacts": {
    "SentinelNodeWallet_sha256": "${APP_SHA}",
    "bitcoind_sha256": "${NODE_SHA}",
    "bitcoin_cli_sha256": "${CLI_SHA}",
    "consensus_manifest_sha256": "${CONS_SHA}"
  }
}
EOF

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
DMG="${DIST}/Sentinel-Node-Wallet-BTCB2-v${VERSION}-macOS-arm64-notarized.dmg"
STAGING="${DIST}/dmg_staging"
mkdir -p "${STAGING}"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
hdiutil create -volname "Sentinel Node Wallet BTCB2" \
    -srcfolder "${STAGING}" -ov -format UDZO "${DMG}"
codesign --force --timestamp --sign "${SENTINEL_DEVELOPER_ID_APPLICATION}" "${DMG}"
xcrun notarytool submit "${DMG}" \
    --keychain-profile "${SENTINEL_NOTARY_PROFILE}" \
    --wait --output-format json > "${NOTARY_TMP}" || fail "Apple notarization failed."
python3 - "${NOTARY_TMP}" <<'PY' || fail "Notary service did not accept this build."
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    outcome = json.load(stream)
if outcome.get("status") != "Accepted":
    raise SystemExit(1)
PY
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"
hdiutil verify "${DMG}" >/dev/null
shasum -a 256 "${DMG}" > "${DIST}/SHA256SUMS.txt"
printf "Notarized build candidate: %s\n" "${DMG}"
printf "No production deployment or real-funds authorization is implied.\n"
