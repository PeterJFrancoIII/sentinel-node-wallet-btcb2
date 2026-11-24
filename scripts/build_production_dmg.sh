#!/usr/bin/env bash
# Explicitly owner-authorized, Developer ID signed, provisioned, and notarized macOS candidate.
# Does not deploy or publish, and requires all independent P0 release approvals.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP="${ROOT_DIR}/dist/Sentinel Node Wallet.app"
DIST="${ROOT_DIR}/dist"
BUNDLE_ID="${SENTINEL_BUNDLE_ID:-pool.sentineldefensetechnologies.co.za}"
PROVISIONING_PROFILE_PATH="${SENTINEL_PROVISIONING_PROFILE_PATH:-}"
VERIFIER_PY="${SCRIPT_DIR}/verify_production_bundle.py"

fail() { printf "RELEASE BLOCKED: %s\n" "$*" >&2; exit 1; }
require() { local key="$1"; [ -n "${!key:-}" ] || fail "Missing required setting ${key}"; }

SIGN_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --sign-only)
            SIGN_ONLY=1
            shift
            ;;
        --app-bundle)
            [ $# -ge 2 ] || fail "Missing argument for --app-bundle"
            APP="$2"
            shift 2
            ;;
        --profile)
            [ $# -ge 2 ] || fail "Missing argument for --profile"
            PROVISIONING_PROFILE_PATH="$2"
            shift 2
            ;;
        *)
            fail "Unknown option '$1'"
            ;;
    esac
done

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
command -v security >/dev/null || fail "macOS security CLI is required."
command -v openssl >/dev/null || fail "openssl is required."
command -v python3 >/dev/null || fail "python3 is required."
[ -f "${VERIFIER_PY}" ] || fail "Missing required verifier script ${VERIFIER_PY}"

AASA_TMP="$(mktemp -t sentinel-aasa)"
NOTARY_TMP="$(mktemp -t sentinel-notary)"
TEMP_DIR="$(mktemp -d -t sentinel-prod-stage)"
MOUNT_POINT=""
cleanup() {
    if [ -n "${MOUNT_POINT}" ] && [ -d "${MOUNT_POINT}" ]; then
        hdiutil detach "${MOUNT_POINT}" -force >/dev/null 2>&1 || true
    fi
    rm -rf "${AASA_TMP}" "${NOTARY_TMP}" "${TEMP_DIR}"
}
trap cleanup EXIT

if [ "${SIGN_ONLY}" = "1" ]; then
    [ -d "${APP}" ] || fail "Missing pre-built macOS app at '${APP}' for sign-only mode."
fi

# Fail-closed provisioning profile input resolution BEFORE compilation/signing
RESOLVED_PROFILE="${TEMP_DIR}/candidate.provisionprofile"
if [ -n "${PROVISIONING_PROFILE_PATH}" ]; then
    [ -f "${PROVISIONING_PROFILE_PATH}" ] && [ ! -L "${PROVISIONING_PROFILE_PATH}" ] ||
        fail "Specified --profile path does not exist or is a symlink: ${PROVISIONING_PROFILE_PATH}"
    cp "${PROVISIONING_PROFILE_PATH}" "${RESOLVED_PROFILE}"
elif [ -n "${APPLE_PROVISIONING_PROFILE_BASE64:-}" ]; then
    python3 - "${RESOLVED_PROFILE}" <<'PY' || fail "Failed to decode APPLE_PROVISIONING_PROFILE_BASE64."
import base64, os, sys
raw = os.environ.get("APPLE_PROVISIONING_PROFILE_BASE64", "").strip()
data = base64.b64decode(raw, validate=True)
if not data:
    raise SystemExit(1)
with open(sys.argv[1], "wb") as f:
    f.write(data)
PY
elif [ -f "${APP}/Contents/embedded.provisionprofile" ] && [ ! -L "${APP}/Contents/embedded.provisionprofile" ]; then
    cp "${APP}/Contents/embedded.provisionprofile" "${RESOLVED_PROFILE}"
else
    fail "Missing mandatory Developer ID provisioning profile (--profile, SENTINEL_PROVISIONING_PROFILE_PATH, APPLE_PROVISIONING_PROFILE_BASE64, or Contents/embedded.provisionprofile). Refusing to ship unlaunchable bundle."
fi
chmod 0600 "${RESOLVED_PROFILE}"

# Resolve exact signing leaf certificate DER SHA-256 fingerprint from active keychain
SIGNER_CERT_SHA256="$(
    security find-certificate -c "${SENTINEL_DEVELOPER_ID_APPLICATION}" -p 2>/dev/null \
    | openssl x509 -outform DER 2>/dev/null \
    | shasum -a 256 | awk '{print toupper($1)}' || true
)"
[[ "${SIGNER_CERT_SHA256}" =~ ^[0-9A-F]{64}$ ]] ||
    fail "Unable to resolve exact DER SHA-256 leaf fingerprint for signing identity '${SENTINEL_DEVELOPER_ID_APPLICATION}'."

# Verify Apple CMS authenticity and bind profile to exact team, bundle, domain, and signing leaf cert BEFORE signing
VERIFIED_PROFILE_PLIST="${TEMP_DIR}/verified_profile.plist"
PROFILE_SUMMARY_JSON="${TEMP_DIR}/profile_summary.json"
python3 "${VERIFIER_PY}" verify-profile-cms \
    --profile "${RESOLVED_PROFILE}" \
    --out-plist "${VERIFIED_PROFILE_PLIST}"
chmod 0600 "${VERIFIED_PROFILE_PLIST}"

python3 "${VERIFIER_PY}" validate-profile-plist \
    --plist "${VERIFIED_PROFILE_PLIST}" \
    --team-id "${SENTINEL_APPLE_TEAM_ID}" \
    --bundle-id "${BUNDLE_ID}" \
    --domain "${DOMAIN}" \
    --cert-sha256 "${SIGNER_CERT_SHA256}" \
    --raw-profile "${RESOLVED_PROFILE}" \
    --json-out "${PROFILE_SUMMARY_JSON}" >/dev/null

APP_ID_PREFIX="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["app_id_prefix"])' "${PROFILE_SUMMARY_JSON}")"
PROFILE_UUID="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["uuid"])' "${PROFILE_SUMMARY_JSON}")"
PROFILE_SHA256="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["profile_sha256"])' "${PROFILE_SUMMARY_JSON}")"
PROFILE_EXPIRY="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["expiration_iso"])' "${PROFILE_SUMMARY_JSON}")"
echo "✓ Verified Apple MAC_APP_DIRECT profile (UUID: ${PROFILE_UUID}, Prefix: ${APP_ID_PREFIX}, SHA-256: ${PROFILE_SHA256}, Expires: ${PROFILE_EXPIRY})."

curl --fail --silent --show-error --location --max-time 20 \
    "https://${DOMAIN}/.well-known/apple-app-site-association" -o "${AASA_TMP}" ||
    fail "Approved domain does not serve HTTPS Apple app association metadata."
python3 - "${AASA_TMP}" "${APP_ID_PREFIX}.${BUNDLE_ID}" <<'PY' ||
    fail "Apple association metadata does not include this exact App ID Prefix + Bundle ID."
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
apps = data.get("webcredentials", {}).get("apps", [])
if not isinstance(apps, list) or sys.argv[2] not in apps:
    raise SystemExit(1)
PY

if [ "${SIGN_ONLY}" = "1" ]; then
    echo "✓ Running in --sign-only mode: skipping SwiftPM build / compilation in privileged environment."
    [ -d "${APP}" ] || fail "Missing pre-built macOS app at '${APP}' for sign-only mode."
else
    # Existing builder creates an ad-hoc local bundle after SHA pinning the Knots
    # archive and bitcoind. Re-sign everything before any prospective release.
    "${SCRIPT_DIR}/build_app.sh"
fi

[ -d "${APP}" ] || fail "Missing built macOS app."
plutil -lint "${APP}/Contents/Info.plist" >/dev/null
ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Contents/Info.plist" 2>/dev/null || echo "${BUNDLE_ID}")"
[ "${ACTUAL_BUNDLE_ID}" = "${BUNDLE_ID}" ] || fail "CFBundleIdentifier in Info.plist (${ACTUAL_BUNDLE_ID}) does not match expected BUNDLE_ID (${BUNDLE_ID})"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${APP}/Contents/Info.plist" 2>/dev/null || true)"
[ -n "${PUBLIC_KEY}" ] || fail "App bundle Info.plist missing mandatory SUPublicEDKey for production auto-update."

ENTITLEMENTS="${TEMP_DIR}/Production.entitlements.plist"
cat > "${ENTITLEMENTS}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.application-identifier</key>
<string>${APP_ID_PREFIX}.${ACTUAL_BUNDLE_ID}</string>
<key>com.apple.developer.team-identifier</key>
<string>${SENTINEL_APPLE_TEAM_ID}</string>
<key>com.apple.developer.associated-domains</key>
<array><string>webcredentials:${DOMAIN}</string></array>
<key>keychain-access-groups</key>
<array><string>${APP_ID_PREFIX}.${ACTUAL_BUNDLE_ID}</string></array>
</dict></plist>
EOF
plutil -lint "${ENTITLEMENTS}" >/dev/null
ENTITLEMENTS_SHA256="$(shasum -a 256 "${ENTITLEMENTS}" | awk '{print $1}')"

# Embed actual Apple-signed provisioning profile at Contents/embedded.provisionprofile BEFORE signing outer bundle
cp "${RESOLVED_PROFILE}" "${APP}/Contents/embedded.provisionprofile"

# Normalize ONLY the distributable bundle permissions (0755 dirs & Mach-O binaries, 0644 resources/profile) preserving symlinks
python3 "${VERIFIER_PY}" normalize-and-audit-permissions \
    --app "${APP}" \
    --require-profile \
    --expected-profile-sha256 "${PROFILE_SHA256}"

# Sign nested frameworks and outer bundle with standard 022 umask inside subshell so _CodeSignature and DMG assets get 0644/0755
(
    umask 022
    if [ -d "${APP}/Contents/Frameworks/Sparkle.framework" ]; then
        find "${APP}/Contents/Frameworks/Sparkle.framework" -type f -perm +111 -exec \
            codesign --force --options runtime --timestamp \
            --sign "${SENTINEL_DEVELOPER_ID_APPLICATION}" {} +
        codesign --force --options runtime --timestamp \
            --sign "${SENTINEL_DEVELOPER_ID_APPLICATION}" "${APP}/Contents/Frameworks/Sparkle.framework"
    fi

    for binary in bitcoind bitcoin-cli; do
        codesign --force --options runtime --timestamp \
            --sign "${SENTINEL_DEVELOPER_ID_APPLICATION}" "${APP}/Contents/MacOS/${binary}"
    done
    codesign --force --options runtime --timestamp --entitlements "${ENTITLEMENTS}" \
        --sign "${SENTINEL_DEVELOPER_ID_APPLICATION}" "${APP}"
)

# Verify post-signing permissions, embedded profile, codesign, and exact entitlement allowlist compliance
python3 "${VERIFIER_PY}" normalize-and-audit-permissions \
    --app "${APP}" \
    --audit-only \
    --require-profile \
    --expected-profile-sha256 "${PROFILE_SHA256}"
python3 "${VERIFIER_PY}" verify-signed-claims \
    --app "${APP}" \
    --team-id "${SENTINEL_APPLE_TEAM_ID}" \
    --bundle-id "${ACTUAL_BUNDLE_ID}" \
    --domain "${DOMAIN}" \
    --cert-sha256 "${SIGNER_CERT_SHA256}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Contents/Info.plist" 2>/dev/null || echo "0")"
DMG="${DIST}/Sentinel-Node-Wallet-BTCB2-v${VERSION}-build${BUILD}-macOS-arm64-notarized.dmg"
STAGING="${TEMP_DIR}/dmg_staging"

(
    umask 022
    mkdir -p "${STAGING}"
    chmod 0755 "${STAGING}"
    cp -RP "${APP}" "${STAGING}/"
    ln -s /Applications "${STAGING}/Applications"
    hdiutil create -volname "Sentinel Node Wallet BTCB2" \
        -srcfolder "${STAGING}" -ov -format UDZO "${DMG}"
)
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

# Mount final notarized DMG read-only and assert embedded profile, permissions, signatures, entitlements, and Gatekeeper on the actual shipped artifact
MOUNT_BASE="${TEMP_DIR}/mnt"
mkdir -p "${MOUNT_BASE}"
MOUNT_POINT="$(hdiutil attach -nobrowse -readonly -mountrandom "${MOUNT_BASE}" "${DMG}" | tail -n 1 | awk -F'\t' '{print $NF}')"
[ -d "${MOUNT_POINT}" ] || fail "Failed to mount final notarized DMG for artifact verification."
MOUNTED_APP="${MOUNT_POINT}/Sentinel Node Wallet.app"
[ -d "${MOUNTED_APP}" ] || fail "Mounted DMG does not contain Sentinel Node Wallet.app."

python3 "${VERIFIER_PY}" normalize-and-audit-permissions \
    --app "${MOUNTED_APP}" \
    --audit-only \
    --require-profile \
    --expected-profile-sha256 "${PROFILE_SHA256}"
python3 "${VERIFIER_PY}" verify-signed-claims \
    --app "${MOUNTED_APP}" \
    --team-id "${SENTINEL_APPLE_TEAM_ID}" \
    --bundle-id "${ACTUAL_BUNDLE_ID}" \
    --domain "${DOMAIN}" \
    --cert-sha256 "${SIGNER_CERT_SHA256}"
spctl --assess --type execute --verbose "${MOUNTED_APP}" ||
    fail "Gatekeeper spctl assessment failed on mounted app bundle."
spctl --assess --type open --context context:primary-signature --verbose "${DMG}" ||
    fail "Gatekeeper spctl assessment failed on stapled DMG."

hdiutil detach "${MOUNT_POINT}" -force >/dev/null 2>&1 || true
MOUNT_POINT=""

# Overwrite BUILD_MANIFEST.json with hashes of final signed Mach-O binaries + non-secret profile/cert provenance
APP_SHA="$(shasum -a 256 "${APP}/Contents/MacOS/SentinelNodeWallet" | awk '{print $1}')"
NODE_SHA="$(shasum -a 256 "${APP}/Contents/MacOS/bitcoind" | awk '{print $1}')"
CLI_SHA="$(shasum -a 256 "${APP}/Contents/MacOS/bitcoin-cli" | awk '{print $1}')"
CONS_SHA="$(shasum -a 256 "${APP}/Contents/Resources/consensus-manifest.json" | awk '{print $1}')"
cat > "${DIST}/BUILD_MANIFEST.json" <<EOF
{
  "build_type": "developer_id_notarized_candidate",
  "git_commit": "$(git -C "${ROOT_DIR}" rev-parse HEAD)",
  "team_id": "${SENTINEL_APPLE_TEAM_ID}",
  "app_id_prefix": "${APP_ID_PREFIX}",
  "bundle_id": "${ACTUAL_BUNDLE_ID}",
  "associated_domain": "${DOMAIN}",
  "signing_cert_sha256": "${SIGNER_CERT_SHA256}",
  "provisioning_profile_uuid": "${PROFILE_UUID}",
  "provisioning_profile_sha256": "${PROFILE_SHA256}",
  "provisioning_profile_expiration": "${PROFILE_EXPIRY}",
  "entitlements_sha256": "${ENTITLEMENTS_SHA256}",
  "artifacts": {
    "SentinelNodeWallet_sha256": "${APP_SHA}",
    "bitcoind_sha256": "${NODE_SHA}",
    "bitcoin_cli_sha256": "${CLI_SHA}",
    "consensus_manifest_sha256": "${CONS_SHA}"
  }
}
EOF

(cd "${DIST}" && shasum -a 256 "$(basename "${DMG}")" > "${DIST}/SHA256SUMS.txt")
printf "Notarized and provisioned build candidate: %s\n" "${DMG}"
printf "No production deployment or real-funds authorization is implied.\n"
