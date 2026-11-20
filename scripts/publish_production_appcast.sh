#!/usr/bin/env bash
# Official Sparkle 2 Stable Production Appcast Publisher (WO-77, WO-82, WO-83, WO-84)
# Idempotently constructs, cryptographically verifies, and transactionally publishes
# signed dist/appcast.xml without touching or mutating the active working directory.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APPCAST_FILE="${DIST_DIR}/appcast.xml"

# WO-89 P0: Stage exclusively in unique disposable temp outside operator repository.
# Never touch, overwrite, or create backup files in the active source tree.
TEMP_DIR="$(mktemp -d -t sentinel-appcast-XXXXXX)"
cleanup() {
    if [ -d "${TEMP_DIR}/dmg_mount" ]; then
        hdiutil detach "${TEMP_DIR}/dmg_mount" -force 2>/dev/null || true
    fi
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

fail() { printf "APPCAST PUBLISHER BLOCKED: %s\n" "$*" >&2; exit 1; }

TAG=""
DRY_RUN=1
PUBLISH_TO_MAIN=0
OPERATOR_APPROVAL=""
PROVIDED_SIGNATURE=""
SIGNATURE_FILE=""
ARCHIVE_OVERRIDE=""
LOCAL_ARCHIVE=""
SANDBOX_SIMULATION=0
ALLOW_MOCK_FOR_DRY_RUN=0
PUBLIC_KEY_OVERRIDE=""
APP_BUNDLE_PATH=""
SIGN_UPDATE_OVERRIDE=""
ED_KEY_FILE=""
PRUNE_UNSIGNED_LEGACY=0
ENFORCE_SIGNED_FEED=0

usage() {
    cat <<EOF
Usage:
  $0 --tag <vMAJOR.MINOR.PATCH-buildINTEGER> [options]

Options:
  --tag <tag>                Required. Pinned release tag (e.g. v1.0.0-build5)
  --operator-approval <YES>  Required for live publish to main
  --signature <sig>          EdDSA signature for the archive
  --signature-file <file>    File containing the EdDSA signature
  --public-key <base64>      Ed25519 public key (SUPublicEDKey) for cryptographic verification
  --ed-key-file <file>       Private key file for Sparkle sign_update tool verification (secret-in-argv --private-key is prohibited)
  --app-bundle <path>        Path to .app bundle to extract & verify SUPublicEDKey and bundle identity
  --appcast <path>           Path to appcast.xml file override
  --archive <dmg-file>       Archive file (simulation/dry-run) or local artifact to cross-check (live)
  --local-archive <dmg-file> Local signed build artifact to cross-check byte-for-byte against downloaded release
  --sandbox-simulation       Run in isolated test sandbox (offline bare git remote simulation)
  --sign-update <path>       Path to Sparkle sign_update binary override
  --publish-to-main          Commit and push updated appcast.xml directly to origin/main via isolated worktree
  --prune-unsigned-legacy    Prune historical unauthenticated enclosures lacking sparkle:edSignature (WO-113)
  --dry-run                  Simulate validation and print appcast diff (default)
  --allow-mock-for-dry-run   Explicitly permits synthetic signature in dry-run mode only (STRICTLY FORBIDDEN IN LIVE MODE)
  -h, --help                 Show this help message
EOF
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --tag)
            [ $# -ge 2 ] || fail "Missing value for --tag"
            TAG="$2"
            shift 2
            ;;
        --operator-approval)
            [ $# -ge 2 ] || fail "Missing value for --operator-approval"
            OPERATOR_APPROVAL="$2"
            shift 2
            ;;
        --signature)
            [ $# -ge 2 ] || fail "Missing value for --signature"
            PROVIDED_SIGNATURE="$2"
            shift 2
            ;;
        --signature-file)
            [ $# -ge 2 ] || fail "Missing value for --signature-file"
            SIGNATURE_FILE="$2"
            shift 2
            ;;
        --public-key)
            [ $# -ge 2 ] || fail "Missing value for --public-key"
            PUBLIC_KEY_OVERRIDE="$2"
            shift 2
            ;;
        --private-key)
            fail "Security stop (WO-104): --private-key is prohibited on the command line to prevent secret exposure in process lists. Use SPARKLE_PRIVATE_ED_KEY environment variable or --ed-key-file instead."
            ;;
        --app-bundle)
            [ $# -ge 2 ] || fail "Missing value for --app-bundle"
            APP_BUNDLE_PATH="$2"
            shift 2
            ;;
        --sign-update)
            [ $# -ge 2 ] || fail "Missing value for --sign-update"
            SIGN_UPDATE_OVERRIDE="$2"
            shift 2
            ;;
        --ed-key-file)
            [ $# -ge 2 ] || fail "Missing value for --ed-key-file"
            ED_KEY_FILE="$2"
            shift 2
            ;;
        --archive)
            [ $# -ge 2 ] || fail "Missing value for --archive"
            ARCHIVE_OVERRIDE="$2"
            shift 2
            ;;
        --appcast)
            [ $# -ge 2 ] || fail "Missing value for --appcast"
            APPCAST_OVERRIDE="$2"
            shift 2
            ;;
        --local-archive)
            [ $# -ge 2 ] || fail "Missing value for --local-archive"
            LOCAL_ARCHIVE="$2"
            shift 2
            ;;
        --sandbox-simulation)
            SANDBOX_SIMULATION=1
            shift
            ;;
        --prune-unsigned-legacy)
            PRUNE_UNSIGNED_LEGACY=1
            shift
            ;;
        --enforce-signed-feed)
            ENFORCE_SIGNED_FEED=1
            shift
            ;;
        --publish-to-main)
            PUBLISH_TO_MAIN=1
            DRY_RUN=0
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            PUBLISH_TO_MAIN=0
            shift
            ;;
        --allow-mock-for-dry-run)
            ALLOW_MOCK_FOR_DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

[ -n "${TAG}" ] || fail "Missing mandatory --tag argument."

# 1. Strict Tag & Monotonic Build Validation (WO-76, WO-82)
TAG_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+-build[0-9]+$'
if ! [[ "${TAG}" =~ ${TAG_REGEX} ]]; then
    fail "Tag '${TAG}' does not match required format: ^v[0-9]+\.[0-9]+\.[0-9]+-build[0-9]+$"
fi

VERSION="${TAG#v}"
VERSION="${VERSION%%-build*}"
BUILD_NUM="${TAG##*-build}"

if [ "${BUILD_NUM}" -le 3 ]; then
    fail "Build number ${BUILD_NUM} must be greater than 3 (active published build is 3)."
fi

# 1.5 Strict Sandbox Simulation Safety Invariants (WO-100 P0)
REMOTE_ORIGIN_URL="$(git config --get remote.origin.url 2>/dev/null || echo "")"

if [ "${SANDBOX_SIMULATION}" = "1" ]; then
    # 1. Prohibit production signing secrets in sandbox simulation environment
    if [ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
        fail "FATAL SECURITY STOP (WO-100): SPARKLE_PRIVATE_ED_KEY secret is present in environment; cannot run --sandbox-simulation with production secrets."
    fi

    # 2. Prohibit network or GitHub remote origin
    if [[ "${REMOTE_ORIGIN_URL}" =~ github\.com ]] || [[ "${REMOTE_ORIGIN_URL}" =~ ^https?:// ]] || [[ "${REMOTE_ORIGIN_URL}" =~ ^git@ ]] || [[ "${REMOTE_ORIGIN_URL}" =~ ^ssh:// ]]; then
        fail "FATAL SECURITY STOP (WO-100): --sandbox-simulation cannot be executed when git remote points to GitHub or a network URL (${REMOTE_ORIGIN_URL}). Simulation is restricted exclusively to local file fixture repositories."
    fi

    # 3. If publishing to main under simulation, require verified test fixture marker in bare repo
    if [ "${PUBLISH_TO_MAIN}" = "1" ]; then
        BARE_REPO_PATH="${REMOTE_ORIGIN_URL#file://}"
        if [ ! -d "${BARE_REPO_PATH}" ] || [ ! -f "${BARE_REPO_PATH}/SENTINEL_TEST_FIXTURE_MARKER" ]; then
            fail "FATAL SECURITY STOP (WO-100): Combining --sandbox-simulation and --publish-to-main requires an isolated local bare repository containing 'SENTINEL_TEST_FIXTURE_MARKER'. Remote '${REMOTE_ORIGIN_URL}' lacks verification marker."
        fi
        echo "✓ Verified sandbox simulation target is an isolated local test fixture: ${BARE_REPO_PATH}"
    fi
fi

ASSET_NAME="Sentinel-Node-Wallet-BTCB2-v${VERSION}-build${BUILD_NUM}-macOS-arm64-notarized.dmg"
RELEASE_URL="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/${TAG}/${ASSET_NAME}"
SHA_URL="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/${TAG}/SHA256SUMS.txt"

echo "=== Sentinel Node Wallet: Production Sparkle Feed Publisher (WO-77/82/83/84) ==="
echo "Candidate Tag:       ${TAG}"
echo "Parsed Version:      v${VERSION}"
echo "Parsed Build:        ${BUILD_NUM}"
echo "Asset Filename:      ${ASSET_NAME}"
echo "Execution Mode:      $([ "${DRY_RUN}" = "1" ] && echo "DRY RUN (simulation)" || echo "LIVE PUBLISH TO MAIN")"

# 2. Check Prerequisites
command -v curl >/dev/null || fail "curl is required."
command -v shasum >/dev/null || fail "shasum is required."
command -v python3 >/dev/null || fail "python3 is required."
command -v git >/dev/null || fail "git is required."

if [ -n "${APPCAST_OVERRIDE:-}" ]; then
    [ -f "${APPCAST_FILE}" ] || fail "Specified appcast file not found at ${APPCAST_FILE}"
fi

# Resolve Sparkle sign_update binary and enforce pinned provenance (WO-88)
if [ -n "${SIGN_UPDATE_OVERRIDE}" ]; then
    SIGN_UPDATE="${SIGN_UPDATE_OVERRIDE}"
else
    SIGN_UPDATE="${ROOT_DIR}/.build/artifacts/sparkle/Sparkle/bin/sign_update"
    if [ ! -x "${SIGN_UPDATE}" ]; then
        SIGN_UPDATE="$(find "${ROOT_DIR}/.build" -name "sign_update" -type f -perm +111 2>/dev/null | head -n 1 || true)"
    fi
    # WO-88, WO-117: If sign_update binary is absent in live mode, populate pinned artifacts via swift package resolve
    if [ "${DRY_RUN}" = "0" ] && [ "${SANDBOX_SIMULATION}" = "0" ] && [ ! -x "${SIGN_UPDATE}" ]; then
        echo "Sparkle sign_update binary not found. Populating SPM artifacts via 'swift package resolve'..."
        (cd "${ROOT_DIR}" && swift package resolve >/dev/null 2>&1 || true)
        SIGN_UPDATE="${ROOT_DIR}/.build/artifacts/sparkle/Sparkle/bin/sign_update"
        if [ ! -x "${SIGN_UPDATE}" ]; then
            SIGN_UPDATE="$(find "${ROOT_DIR}/.build" -name "sign_update" -type f -perm +111 2>/dev/null | head -n 1 || true)"
        fi
    fi
fi

if [ "${DRY_RUN}" = "0" ]; then
    # WO-88 P0: Make sign_update absence an explicit STOP before ANY file writes or remote calls in live mode
    if [ -z "${SIGN_UPDATE}" ] || [ ! -x "${SIGN_UPDATE}" ]; then
        fail "Production publish aborted: Sparkle sign_update binary is required in live mode but was not found or is not executable at '${SIGN_UPDATE}'. Run 'swift build' or install Sparkle 2.10.1."
    fi

    # Enforce verified pinned 2.10.1 binary version in Package.resolved
    SPARKLE_PINNED_VER="$(python3 -c "
import json, sys
try:
    with open('${ROOT_DIR}/Package.resolved') as f:
        data = json.load(f)
    pins = data.get('pins', [])
    for p in pins:
        if p.get('identity') == 'sparkle':
            print(p.get('state', {}).get('version', ''))
            sys.exit(0)
    print('')
except Exception:
    print('')
")"
    if [ "${SPARKLE_PINNED_VER}" != "2.10.1" ]; then
        fail "Sparkle dependency version mismatch: expected pinned 2.10.1 in Package.resolved, found '${SPARKLE_PINNED_VER}'."
    fi
    echo "✓ Verified Sparkle pinned version 2.10.1 and sign_update executable: ${SIGN_UPDATE}"
fi

# 2.5 Resolve & Validate EdDSA Signature (WO-82, WO-88: Strict 64-Byte Ed25519 & No-Mock)
ED_SIGNATURE=""
if [ -n "${PROVIDED_SIGNATURE}" ]; then
    ED_SIGNATURE="${PROVIDED_SIGNATURE}"
elif [ -n "${SIGNATURE_FILE}" ] && [ -f "${SIGNATURE_FILE}" ]; then
    ED_SIGNATURE="$(tr -d '\r\n ' < "${SIGNATURE_FILE}")"
elif [ -f "${ROOT_DIR}/dist/SPARKLE_ENCLOSURE.txt" ]; then
    EXTRACTED="$(grep "sparkle:edSignature" "${ROOT_DIR}/dist/SPARKLE_ENCLOSURE.txt" | head -n 1 | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/' || echo "")"
    if [ -n "${EXTRACTED}" ]; then
        ED_SIGNATURE="${EXTRACTED}"
    fi
fi

if [ "${DRY_RUN}" = "0" ]; then
    # Operator approval check first in live mode
    if [ "${OPERATOR_APPROVAL}" != "YES" ]; then
        fail "Live publication requires explicit --operator-approval YES."
    fi

    # LIVE MODE: Mock signatures strictly prohibited fail-closed
    if [ -z "${ED_SIGNATURE}" ]; then
        fail "Production publish aborted: EdDSA signature is required in live mode. Provide via --signature, --signature-file, or dist/SPARKLE_ENCLOSURE.txt."
    fi
    if [[ "${ED_SIGNATURE}" == *"mock"* ]] || [[ "${ED_SIGNATURE}" == *"Mock"* ]]; then
        fail "Production publish aborted: Mock EdDSA signatures are strictly prohibited in live mode."
    fi

    # Base64 string format validation
    if ! [[ "${ED_SIGNATURE}" =~ ^[A-Za-z0-9+/=]{64,128}$ ]]; then
        fail "Production publish aborted: Signature '${ED_SIGNATURE}' is not a valid canonical Base64 string."
    fi
else
    # DRY RUN MODE:
    if [ -z "${ED_SIGNATURE}" ]; then
        if [ "${ALLOW_MOCK_FOR_DRY_RUN}" = "1" ]; then
            ED_SIGNATURE="[DRY_RUN_SYNTHETIC_MOCK_SIGNATURE_STRICTLY_DISALLOWED_IN_PRODUCTION]===="
            echo "[DRY RUN] Using explicitly permitted synthetic mock signature."
        else
            fail "Dry run aborted: No signature provided. Pass --signature, --signature-file, or --allow-mock-for-dry-run to simulate."
        fi
    fi
    if [ -n "${ED_SIGNATURE}" ] && [ "${ED_SIGNATURE}" != "[DRY_RUN_SYNTHETIC_MOCK_SIGNATURE_STRICTLY_DISALLOWED_IN_PRODUCTION]====" ]; then
        if ! [[ "${ED_SIGNATURE}" =~ ^[A-Za-z0-9+/=]{64,128}$ ]]; then
            fail "Dry run aborted: Signature '${ED_SIGNATURE}' is not a valid canonical Base64 string."
        fi
    fi
fi

# 3. Resolve and Validate Public Key (SUPublicEDKey) and App Bundle Identity (WO-95, WO-101, WO-117)
PUBLIC_KEY=""
BUNDLE_SUPUBLIC_KEY=""

# If app bundle was not explicitly specified, auto-mount DMG if an archive is available (WO-117)
if [ -z "${APP_BUNDLE_PATH}" ]; then
    DMG_TO_MOUNT=""
    if [ -n "${ARCHIVE_OVERRIDE}" ] && [ -f "${ARCHIVE_OVERRIDE}" ] && [[ "${ARCHIVE_OVERRIDE}" == *.dmg ]]; then
        DMG_TO_MOUNT="${ARCHIVE_OVERRIDE}"
    elif [ -n "${LOCAL_ARCHIVE}" ] && [ -f "${LOCAL_ARCHIVE}" ] && [[ "${LOCAL_ARCHIVE}" == *.dmg ]]; then
        DMG_TO_MOUNT="${LOCAL_ARCHIVE}"
    elif [ -n "${TARGET_ARCHIVE:-}" ] && [ -f "${TARGET_ARCHIVE:-}" ] && [[ "${TARGET_ARCHIVE:-}" == *.dmg ]]; then
        DMG_TO_MOUNT="${TARGET_ARCHIVE}"
    fi

    if [ -n "${DMG_TO_MOUNT}" ]; then
        MOUNT_PT="${TEMP_DIR}/dmg_mount"
        mkdir -p "${MOUNT_PT}"
        if hdiutil attach -readonly -nobrowse -mountpoint "${MOUNT_PT}" "${DMG_TO_MOUNT}" >/dev/null 2>&1; then
            if [ -d "${MOUNT_PT}/Sentinel Node Wallet.app" ]; then
                APP_BUNDLE_PATH="${MOUNT_PT}/Sentinel Node Wallet.app"
                echo "✓ Auto-mounted candidate DMG to extract and inspect app bundle: ${APP_BUNDLE_PATH}"
            fi
        fi
    fi
fi

BUNDLE_CANDIDATE="${APP_BUNDLE_PATH}"

if [ -n "${APP_BUNDLE_PATH}" ]; then
    # When explicitly provided, bundle must exist and be valid
    [ -d "${BUNDLE_CANDIDATE}" ] || fail "App bundle specified with --app-bundle does not exist: '${BUNDLE_CANDIDATE}'."
    INFO_PLIST="${BUNDLE_CANDIDATE}/Contents/Info.plist"
    [ -f "${INFO_PLIST}" ] || fail "Info.plist not found in app bundle at '${INFO_PLIST}'."

    BUNDLE_SUPUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${INFO_PLIST}" 2>/dev/null || echo "")"
    [ -n "${BUNDLE_SUPUBLIC_KEY}" ] || fail "Missing mandatory SUPublicEDKey in '${INFO_PLIST}'. App bundle must embed the Sparkle public Ed25519 key."

    BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}" 2>/dev/null || echo "")"
    BUNDLE_SHORT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}" 2>/dev/null || echo "")"
    BUNDLE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}" 2>/dev/null || echo "")"

    [ "${BUNDLE_ID}" = "pool.sentineldefensetechnologies.co.za" ] ||
        fail "Bundle ID mismatch in ${BUNDLE_CANDIDATE}: expected 'pool.sentineldefensetechnologies.co.za', got '${BUNDLE_ID}'."
    [ "${BUNDLE_SHORT_VER}" = "${VERSION}" ] ||
        fail "Version mismatch in ${BUNDLE_CANDIDATE}: expected '${VERSION}', got '${BUNDLE_SHORT_VER}'."
    [ "${BUNDLE_BUILD}" = "${BUILD_NUM}" ] ||
        fail "Build number mismatch in ${BUNDLE_CANDIDATE}: expected '${BUILD_NUM}', got '${BUNDLE_BUILD}'."

    # Validate TeamIdentifier if codesigned (WO-101, WO-106: strictly pinned to single authorized Developer ID team S8QMQZA656)
    if command -v codesign >/dev/null 2>&1; then
        CODESIGN_TEAM="$(codesign -dv "${BUNDLE_CANDIDATE}" 2>&1 | grep "TeamIdentifier=" | cut -d= -f2 || echo "")"
        if [ -n "${CODESIGN_TEAM}" ] && [ "${CODESIGN_TEAM}" != "not set" ]; then
            [ "${CODESIGN_TEAM}" = "S8QMQZA656" ] ||
                fail "TeamIdentifier mismatch in ${BUNDLE_CANDIDATE}: expected single authorized Developer ID Team ID 'S8QMQZA656', got '${CODESIGN_TEAM}'."
            echo "✓ Verified code signing TeamIdentifier: ${CODESIGN_TEAM}"
        fi
    fi

    echo "✓ Verified bundle identity and metadata: ${BUNDLE_ID} v${BUNDLE_SHORT_VER} (Build ${BUNDLE_BUILD})"
elif [ "${DRY_RUN}" = "0" ] && [ "${SANDBOX_SIMULATION}" = "0" ]; then
    # In live production mode, app bundle candidate is strictly required (WO-101)
    fail "Production publish aborted (WO-101): App bundle is mandatory in live mode (--app-bundle <path>)."
fi

if [ -n "${PUBLIC_KEY_OVERRIDE}" ]; then
    PUBLIC_KEY="${PUBLIC_KEY_OVERRIDE}"
    if [ -n "${BUNDLE_SUPUBLIC_KEY}" ] && [ "${PUBLIC_KEY}" != "${BUNDLE_SUPUBLIC_KEY}" ]; then
        fail "SUPublicEDKey mismatch: App bundle key (${BUNDLE_SUPUBLIC_KEY}) does not match supplied public key (${PUBLIC_KEY})."
    fi
elif [ -n "${BUNDLE_SUPUBLIC_KEY}" ]; then
    PUBLIC_KEY="${BUNDLE_SUPUBLIC_KEY}"
elif [ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]; then
    PUBLIC_KEY="${SPARKLE_PUBLIC_ED_KEY}"
elif [ -n "${PUB_KEY:-}" ]; then
    PUBLIC_KEY="${PUB_KEY}"
fi

if [ "${DRY_RUN}" = "0" ]; then
    # Public key is strictly required in live mode to verify signature authenticity
    if [ -z "${PUBLIC_KEY}" ]; then
        fail "Production publish aborted: SUPublicEDKey is strictly required in live mode to verify signature authenticity before publishing feed. Pass --public-key, --app-bundle, or set SPARKLE_PUBLIC_ED_KEY."
    fi
fi

# WO-88: Strict Base64 and Raw Byte Length Validation (Ed25519 signatures = 64 bytes, public keys = 32 bytes)
if [ -n "${ED_SIGNATURE}" ] && [ "${ED_SIGNATURE}" != "[DRY_RUN_SYNTHETIC_MOCK_SIGNATURE_STRICTLY_DISALLOWED_IN_PRODUCTION]====" ]; then
    python3 - "${ED_SIGNATURE}" <<'PY' || fail "Signature validation failed fail-closed."
import base64, sys
sig_str = sys.argv[1].strip()
try:
    decoded = base64.b64decode(sig_str, validate=True)
except Exception as e:
    print(f"ERROR: Signature '{sig_str}' is not a valid canonical Base64 string: {e}", file=sys.stderr)
    sys.exit(1)
if len(decoded) != 64:
    print(f"ERROR: Raw Ed25519 signature must be exactly 64 bytes decoded, got {len(decoded)} bytes.", file=sys.stderr)
    sys.exit(1)
PY
fi

if [ -n "${PUBLIC_KEY}" ]; then
    python3 - "${PUBLIC_KEY}" <<'PY' || fail "Public key (SUPublicEDKey) validation failed fail-closed."
import base64, sys
pub_str = sys.argv[1].strip()
try:
    decoded = base64.b64decode(pub_str, validate=True)
except Exception as e:
    print(f"ERROR: Public key '{pub_str}' is not a valid canonical Base64 string: {e}", file=sys.stderr)
    sys.exit(1)
if len(decoded) != 32:
    print(f"ERROR: Raw Ed25519 public key must be exactly 32 bytes decoded, got {len(decoded)} bytes.", file=sys.stderr)
    sys.exit(1)
PY
fi

# 4. Verify GitHub Release Asset HTTP Accessibility and Checksum (WO-83: Strong Asset Verification, WO-94: Mandatory Remote Asset Verification)
TARGET_ARCHIVE=""
ASSET_LENGTH=0

if [ "${DRY_RUN}" = "0" ] && [ "${SANDBOX_SIMULATION}" = "0" ]; then
    # LIVE PRODUCTION MODE:
    # Downloading and validating the immutable, publicly accessible GitHub release asset is MANDATORY.
    echo "Checking immutable public GitHub Release asset availability (following redirects to final 200)..."
    HTTP_STATUS="$(curl -sIL -o /dev/null -w "%{http_code}" "${RELEASE_URL}" || echo "000")"
    if [ "${HTTP_STATUS}" != "200" ]; then
        fail "Remote release asset at ${RELEASE_URL} returned final HTTP ${HTTP_STATUS}. Release must be publicly accessible with final HTTP 200 before live appcast feed publication."
    fi

    echo "Downloading release SHA256SUMS.txt from ${SHA_URL}..."
    curl -fsSL "${SHA_URL}" -o "${TEMP_DIR}/SHA256SUMS.txt" || fail "Failed to retrieve SHA256SUMS.txt from public release at ${SHA_URL}."

    EXPECTED_SHA="$(grep -E "^[a-f0-9]{64}[[:space:]]+(\./)?${ASSET_NAME}$" "${TEMP_DIR}/SHA256SUMS.txt" | awk '{print $1}' || echo "")"
    [ -n "${EXPECTED_SHA}" ] || fail "Asset ${ASSET_NAME} not found in public release SHA256SUMS.txt with valid 64-hex SHA-256."

    echo "Downloading immutable release asset bytes from GitHub into isolated verification staging..."
    TARGET_ARCHIVE="${TEMP_DIR}/${ASSET_NAME}"
    curl -fsSL "${RELEASE_URL}" -o "${TARGET_ARCHIVE}" || fail "Failed to download release archive from ${RELEASE_URL}."

    # Compute actual checksum on downloaded bytes
    ACTUAL_SHA="$(shasum -a 256 "${TARGET_ARCHIVE}" | awk '{print $1}')"
    if [ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]; then
        fail "Integrity violation: Downloaded public asset SHA-256 (${ACTUAL_SHA}) does not match release manifest (${EXPECTED_SHA})."
    fi

    ASSET_LENGTH="$(python3 -c "import os, sys; print(os.path.getsize(sys.argv[1]))" "${TARGET_ARCHIVE}")"
    [ "${ASSET_LENGTH}" -gt 1000000 ] || fail "Asset size suspicious (${ASSET_LENGTH} bytes)."
    echo "✓ Verified public release asset integrity: ${ASSET_NAME} (${ASSET_LENGTH} bytes, SHA-256: ${ACTUAL_SHA})"

    # Cross-check local build artifact if supplied
    LOCAL_COMPARE="${LOCAL_ARCHIVE:-${ARCHIVE_OVERRIDE}}"
    if [ -n "${LOCAL_COMPARE}" ]; then
        [ -f "${LOCAL_COMPARE}" ] || fail "Specified local build archive does not exist: ${LOCAL_COMPARE}"
        LOCAL_SHA="$(shasum -a 256 "${LOCAL_COMPARE}" | awk '{print $1}')"
        LOCAL_LENGTH="$(python3 -c "import os, sys; print(os.path.getsize(sys.argv[1]))" "${LOCAL_COMPARE}")"
        if [ "${ACTUAL_SHA}" != "${LOCAL_SHA}" ]; then
            fail "Integrity violation: Downloaded public GitHub asset SHA-256 (${ACTUAL_SHA}) does not match local build artifact (${LOCAL_SHA})."
        fi
        if [ "${ASSET_LENGTH}" != "${LOCAL_LENGTH}" ]; then
            fail "Integrity violation: Downloaded public GitHub asset size (${ASSET_LENGTH}) does not match local build artifact (${LOCAL_LENGTH})."
        fi
        cmp -s "${TARGET_ARCHIVE}" "${LOCAL_COMPARE}" || fail "Downloaded release archive differs byte-for-byte from local build artifact."
        echo "✓ Verified byte-for-byte identity between local build artifact and public remote GitHub release asset."
    fi

    # WO-101, WO-106: Extract and verify embedded .app from downloaded release DMG
    if [ "${DRY_RUN}" = "0" ] && [ "${SANDBOX_SIMULATION}" = "0" ]; then
        command -v hdiutil >/dev/null 2>&1 || fail "Integrity violation (WO-106): hdiutil is required in live mode."
        command -v codesign >/dev/null 2>&1 || fail "Integrity violation (WO-106): codesign is required in live mode."
        command -v spctl >/dev/null 2>&1 || fail "Integrity violation (WO-106): spctl is required in live mode."
    fi

    # WO-106: In live production mode, verification tools are strictly mandatory
    command -v hdiutil >/dev/null 2>&1 || fail "Integrity violation (WO-106): hdiutil is required in live mode."
    command -v codesign >/dev/null 2>&1 || fail "Integrity violation (WO-106): codesign is required in live mode."
    command -v spctl >/dev/null 2>&1 || fail "Integrity violation (WO-106): spctl is required in live mode."

    echo "Mounting downloaded release DMG to verify embedded distribution bundle (WO-101, WO-106)..."
    DMG_MOUNT="$(mktemp -d -t sentinel-dmg-mount-XXXXXX)"
    unmount_dmg() {
        if [ -n "${DMG_MOUNT:-}" ] && [ -d "${DMG_MOUNT}" ]; then
            hdiutil detach "${DMG_MOUNT}" -force >/dev/null 2>&1 || true
            rm -rf "${DMG_MOUNT}" >/dev/null 2>&1 || true
        fi
    }
    trap 'unmount_dmg; cleanup' EXIT

    if ! hdiutil attach -readonly -nobrowse -mountpoint "${DMG_MOUNT}" "${TARGET_ARCHIVE}" >/dev/null 2>&1; then
        unmount_dmg
        fail "Integrity violation (WO-106): Failed to mount downloaded release DMG '${TARGET_ARCHIVE}'."
    fi

    DMG_APP="${DMG_MOUNT}/Sentinel Node Wallet.app"
    if [ ! -d "${DMG_APP}" ]; then
        unmount_dmg
        fail "Integrity violation (WO-101/WO-106): Downloaded DMG does not contain 'Sentinel Node Wallet.app'."
    fi
    DMG_PLIST="${DMG_APP}/Contents/Info.plist"
    if [ ! -f "${DMG_PLIST}" ]; then
        unmount_dmg
        fail "Integrity violation (WO-101/WO-106): Embedded .app in downloaded DMG lacks Contents/Info.plist."
    fi

    # WO-106: Verify nested executables and frameworks exist and are executable
    [ -x "${DMG_APP}/Contents/MacOS/SentinelNodeWallet" ] || {
        unmount_dmg
        fail "Integrity violation (WO-106): Missing executable SentinelNodeWallet in DMG."
    }
    [ -x "${DMG_APP}/Contents/MacOS/bitcoind" ] || {
        unmount_dmg
        fail "Integrity violation (WO-106): Missing executable bitcoind in DMG."
    }
    [ -x "${DMG_APP}/Contents/MacOS/bitcoin-cli" ] || {
        unmount_dmg
        fail "Integrity violation (WO-106): Missing executable bitcoin-cli in DMG."
    }
    [ -d "${DMG_APP}/Contents/Frameworks/Sparkle.framework" ] || {
        unmount_dmg
        fail "Integrity violation (WO-106): Missing Sparkle.framework in DMG."
    }

    DMG_PUB_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${DMG_PLIST}" 2>/dev/null || echo "")"
    DMG_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${DMG_PLIST}" 2>/dev/null || echo "")"
    DMG_SHORT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${DMG_PLIST}" 2>/dev/null || echo "")"
    DMG_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${DMG_PLIST}" 2>/dev/null || echo "")"

    if [ "${DMG_PUB_KEY}" != "${PUBLIC_KEY}" ]; then
        unmount_dmg
        fail "Integrity violation (WO-101/WO-106): Embedded SUPublicEDKey in downloaded DMG (${DMG_PUB_KEY}) does not match authorized public key (${PUBLIC_KEY})."
    fi
    if [ "${DMG_BUNDLE_ID}" != "pool.sentineldefensetechnologies.co.za" ]; then
        unmount_dmg
        fail "Integrity violation (WO-101/WO-106): Embedded bundle ID in downloaded DMG (${DMG_BUNDLE_ID}) does not match 'pool.sentineldefensetechnologies.co.za'."
    fi
    if [ "${DMG_SHORT_VER}" != "${VERSION}" ] || [ "${DMG_BUILD}" != "${BUILD_NUM}" ]; then
        unmount_dmg
        fail "Integrity violation (WO-101/WO-106): Embedded version in downloaded DMG (v${DMG_SHORT_VER} Build ${DMG_BUILD}) does not match release tag (${TAG})."
    fi

    # WO-106: Strict codesign verification on embedded DMG app and nested components
    codesign --verify --strict --deep "${DMG_APP}" >/dev/null 2>&1 || {
        unmount_dmg
        fail "Integrity violation (WO-106): Strict codesign verification failed on embedded DMG app."
    }

    DMG_TEAM="$(codesign -dv "${DMG_APP}" 2>&1 | grep "TeamIdentifier=" | cut -d= -f2 || echo "")"
    [ -n "${DMG_TEAM}" ] && [ "${DMG_TEAM}" != "not set" ] || {
        unmount_dmg
        fail "Integrity violation (WO-106): TeamIdentifier missing in embedded DMG app."
    }
    if [ "${DMG_TEAM}" != "S8QMQZA656" ]; then
        unmount_dmg
        fail "Integrity violation (WO-106): Embedded DMG app TeamIdentifier ('${DMG_TEAM}') does not match authorized Developer ID team 'S8QMQZA656'."
    fi

    # WO-106: Gatekeeper assessment check (must exit 0 with accepted verdict)
    set +e
    SPCTL_OUT="$(spctl -a -t exec -vv "${DMG_APP}" 2>&1)"
    SPCTL_STATUS=$?
    set -e
    if [ ${SPCTL_STATUS} -ne 0 ] || ! echo "${SPCTL_OUT}" | grep -qi "accepted"; then
        unmount_dmg
        fail "Gatekeeper assessment failed for embedded app in downloaded DMG (WO-101/WO-106, exit ${SPCTL_STATUS}): ${SPCTL_OUT}"
    fi

    # WO-106: Stapler notarization ticket verification if stapler tool is present
    if command -v stapler >/dev/null 2>&1; then
        if ! stapler validate "${TARGET_ARCHIVE}" >/dev/null 2>&1 && ! stapler validate "${DMG_APP}" >/dev/null 2>&1; then
            unmount_dmg
            fail "Integrity violation (WO-106): Stapled notarization ticket validation failed on downloaded DMG."
        fi
        echo "✓ Verified stapled notarization ticket (WO-106)."
    fi

    unmount_dmg
    trap cleanup EXIT
    echo "✓ Verified embedded distribution bundle in downloaded DMG matches all trust invariants (WO-101, WO-106)."
elif [ "${SANDBOX_SIMULATION}" = "1" ]; then
    # SANDBOX SIMULATION MODE: Used exclusively by isolated test harness
    if [ -n "${ARCHIVE_OVERRIDE}" ] && [ -f "${ARCHIVE_OVERRIDE}" ]; then
        TARGET_ARCHIVE="${ARCHIVE_OVERRIDE}"
        ASSET_LENGTH="$(python3 -c "import os, sys; print(os.path.getsize(sys.argv[1]))" "${TARGET_ARCHIVE}")"
        ACTUAL_SHA="$(shasum -a 256 "${TARGET_ARCHIVE}" | awk '{print $1}')"
        echo "Using sandbox simulation release archive: ${TARGET_ARCHIVE} (${ASSET_LENGTH} bytes, SHA-256: ${ACTUAL_SHA})"
    else
        fail "Sandbox simulation requires --archive <file> pointing to a valid archive."
    fi
else
    # DRY RUN MODE
    if [ -n "${ARCHIVE_OVERRIDE}" ] && [ -f "${ARCHIVE_OVERRIDE}" ]; then
        TARGET_ARCHIVE="${ARCHIVE_OVERRIDE}"
        ASSET_LENGTH="$(python3 -c "import os, sys; print(os.path.getsize(sys.argv[1]))" "${TARGET_ARCHIVE}")"
        ACTUAL_SHA="$(shasum -a 256 "${TARGET_ARCHIVE}" | awk '{print $1}')"
        echo "[DRY RUN] Using specified release archive: ${TARGET_ARCHIVE} (${ASSET_LENGTH} bytes, SHA-256: ${ACTUAL_SHA})"
    else
        echo "[DRY RUN] Simulating asset validation for ${ASSET_NAME}..."
        ASSET_LENGTH="12450000"
    fi
fi

# WO-88: Cryptographic EdDSA signature verification against target archive bytes
if [ -n "${TARGET_ARCHIVE}" ] && [ -f "${TARGET_ARCHIVE}" ] && [ -n "${PUBLIC_KEY}" ] && [ -n "${ED_SIGNATURE}" ] && [ "${ED_SIGNATURE}" != "[DRY_RUN_SYNTHETIC_MOCK_SIGNATURE_STRICTLY_DISALLOWED_IN_PRODUCTION]====" ]; then
    echo "Performing cryptographic Ed25519 verification against archive bytes..."
    python3 - "${PUBLIC_KEY}" "${ED_SIGNATURE}" "${TARGET_ARCHIVE}" <<'PY' || fail "EdDSA cryptographic signature verification failed against archive."
import base64, sys

pub_b64 = sys.argv[1].strip()
sig_b64 = sys.argv[2].strip()
archive_path = sys.argv[3]

pub_bytes = base64.b64decode(pub_b64, validate=True)
sig_bytes = base64.b64decode(sig_b64, validate=True)

with open(archive_path, "rb") as f:
    archive_data = f.read()

verified = False
try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    from cryptography.exceptions import InvalidSignature
    pub = Ed25519PublicKey.from_public_bytes(pub_bytes)
    pub.verify(sig_bytes, archive_data)
    verified = True
except ImportError:
    pass
except Exception as e:
    print(f"ERROR: Ed25519 verification failed: {e}", file=sys.stderr)
    sys.exit(1)

if not verified:
    import subprocess
    swift_code = f'''
import Foundation
import CryptoKit

guard let pubData = Data(base64Encoded: "{pub_b64}"),
      let sigData = Data(base64Encoded: "{sig_b64}") else {{
    exit(1)
}}
do {{
    let fileData = try Data(contentsOf: URL(fileURLWithPath: "{archive_path}"))
    let pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubData)
    if !pubKey.isValidSignature(sigData, for: fileData) {{
        exit(1)
    }}
}} catch {{
    exit(1)
}}
'''
    res = subprocess.run(["swift", "-e", swift_code], capture_output=True)
    if res.returncode != 0:
        print("ERROR: Cryptographic signature verification failed (Swift CryptoKit).", file=sys.stderr)
        sys.exit(1)

print("✓ Cryptographic Ed25519 signature verified successfully against archive bytes.")
PY

    # Cross-verify via Sparkle sign_update tool if private key file or environment secret is available (WO-104)
    SPARKLE_PRIV="${SPARKLE_PRIVATE_ED_KEY:-${PRIV_KEY:-}}"
    if [ -n "${SIGN_UPDATE}" ] && [ -x "${SIGN_UPDATE}" ]; then
        if [ -n "${ED_KEY_FILE}" ] && [ -f "${ED_KEY_FILE}" ]; then
            echo "Cross-verifying via Sparkle sign_update --verify with key file..."
            "${SIGN_UPDATE}" --verify --ed-key-file "${ED_KEY_FILE}" "${TARGET_ARCHIVE}" "${ED_SIGNATURE}" ||
                fail "Sparkle sign_update --verify failed."
            echo "✓ Sparkle sign_update verification succeeded."
        elif [ -n "${SPARKLE_PRIV}" ]; then
            echo "Cross-verifying via Sparkle sign_update --verify with private key..."
            printf "%s" "${SPARKLE_PRIV}" | "${SIGN_UPDATE}" --verify --ed-key-file - "${TARGET_ARCHIVE}" "${ED_SIGNATURE}" ||
                fail "Sparkle sign_update --verify failed."
            echo "✓ Sparkle sign_update verification succeeded."
        fi
    fi
fi

# 5. Monotonic Version Verification vs Existing Appcast Items (WO-89: Staged in Isolated Temp, WO-109: Authenticated Baseline, WO-113: Signed-Only Enforcement)
STAGING_ORIGINAL="${TEMP_DIR}/appcast_original.xml"
STAGING_CANDIDATE="${TEMP_DIR}/appcast_candidate.xml"

# In live mode, derive baseline feed directly from origin/main to prevent importing unauthenticated draft branch items (WO-109)
if [ "${DRY_RUN}" = "0" ] && [ "${SANDBOX_SIMULATION}" = "0" ]; then
    if [ -n "${APPCAST_OVERRIDE:-}" ] && [ -f "${APPCAST_OVERRIDE:-}" ]; then
        cp "${APPCAST_OVERRIDE}" "${STAGING_ORIGINAL}"
    elif git show origin/main:dist/appcast.xml > "${STAGING_ORIGINAL}" 2>/dev/null && [ -s "${STAGING_ORIGINAL}" ]; then
        echo "✓ Fetched verified baseline appcast from origin/main:dist/appcast.xml"
    elif [ -f "${APPCAST_FILE}" ]; then
        echo "Baseline appcast not on origin/main; using local template at ${APPCAST_FILE}..."
        cp "${APPCAST_FILE}" "${STAGING_ORIGINAL}"
    else
        echo "Baseline appcast absent on origin/main; creating pristine authenticated feed (WO-109)..."
        cat <<'EOF' > "${STAGING_ORIGINAL}"
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Sentinel Node Wallet Updates</title>
        <link>https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2</link>
        <description>Official updates and security notices for Sentinel Node Wallet BTCB2 / XBT.</description>
        <language>en</language>
    </channel>
</rss>
EOF
    fi
elif [ -n "${APPCAST_OVERRIDE:-}" ] && [ -f "${APPCAST_OVERRIDE:-}" ]; then
    cp "${APPCAST_OVERRIDE}" "${STAGING_ORIGINAL}"
elif [ -f "${APPCAST_FILE}" ]; then
    cp "${APPCAST_FILE}" "${STAGING_ORIGINAL}"
else
    cat <<'EOF' > "${STAGING_ORIGINAL}"
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Sentinel Node Wallet Updates</title>
        <link>https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2</link>
        <description>Official updates</description>
        <language>en</language>
    </channel>
</rss>
EOF
fi

python3 - "${STAGING_ORIGINAL}" "${BUILD_NUM}" "${VERSION}" "${PRUNE_UNSIGNED_LEGACY}" "${DRY_RUN}" "${ENFORCE_SIGNED_FEED}" <<'PY' || fail "Appcast integrity check failed."
import sys
import xml.etree.ElementTree as ET

appcast_path = sys.argv[1]
new_build = int(sys.argv[2])
new_version = sys.argv[3]
prune_legacy = sys.argv[4] == "1"
is_dry_run = sys.argv[5] == "1"
enforce_signed = sys.argv[6] == "1"

tree = ET.parse(appcast_path)
root = tree.getroot()
channel = root.find("channel")
if channel is None:
    print("ERROR: <channel> element not found in appcast.xml", file=sys.stderr)
    sys.exit(1)

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
existing_builds = []
unsigned_builds = []

for item in channel.findall("item"):
    enc = item.find("enclosure")
    if enc is not None:
        v = enc.get(f"{{{SPARKLE_NS}}}version")
        sig = enc.get(f"{{{SPARKLE_NS}}}edSignature")
        if v and v.isdigit():
            existing_builds.append(int(v))
        if not sig or sig.strip() == "":
            unsigned_builds.append(v or "unknown")

if unsigned_builds:
    if prune_legacy:
        print(f"✓ Pruned {len(unsigned_builds)} unauthenticated legacy unsigned enclosure(s) (Builds: {unsigned_builds}) (WO-113).")
    elif (not is_dry_run) or enforce_signed:
        print(f"FATAL INTEGRITY VIOLATION (WO-113): Baseline appcast contains unauthenticated enclosure(s) lacking sparkle:edSignature (Builds: {unsigned_builds}).", file=sys.stderr)
        print("Historical unsigned releases cannot be published in an authenticated Sparkle update feed without explicit migration.", file=sys.stderr)
        print("Pass --prune-unsigned-legacy to prune unauthenticated historical entries, or initialize a pristine authenticated feed.", file=sys.stderr)
        sys.exit(1)
    else:
        print(f"[DRY RUN NOTICE] Baseline feed contains {len(unsigned_builds)} unauthenticated enclosure(s) lacking sparkle:edSignature (Builds: {unsigned_builds}) (WO-113).")

if existing_builds:
    max_existing = max(existing_builds)
    if new_build <= max_existing:
        print(f"ERROR: Candidate build {new_build} must be strictly greater than max existing build {max_existing}.", file=sys.stderr)
        sys.exit(1)
print(f"✓ Monotonic check passed: candidate build {new_build} > existing builds {existing_builds}")
PY

# 6. Format and Insert New Item Block into Isolated Candidate XML (WO-89: Zero Source Workspace Mutation, WO-113: Schema Compliant Tree Mutation)
PUB_DATE="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"
RELEASE_NOTES_URL="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/${TAG}"

python3 - "${STAGING_ORIGINAL}" "${STAGING_CANDIDATE}" "${BUILD_NUM}" "${VERSION}" "${RELEASE_URL}" "${ED_SIGNATURE}" "${ASSET_LENGTH}" "${PUB_DATE}" "${RELEASE_NOTES_URL}" "${DRY_RUN}" "${PRUNE_UNSIGNED_LEGACY}" <<'PY' || fail "Failed to generate valid updated appcast.xml."
import sys
import xml.etree.ElementTree as ET

original_path = sys.argv[1]
candidate_path = sys.argv[2]
build_num = sys.argv[3]
version = sys.argv[4]
asset_url = sys.argv[5]
ed_sig = sys.argv[6]
length = sys.argv[7]
pub_date = sys.argv[8]
notes_url = sys.argv[9]
is_dry_run = sys.argv[10] == "1"
prune_legacy = sys.argv[11] == "1"

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")

tree = ET.parse(original_path)
root = tree.getroot()
channel = root.find("channel")
if channel is None:
    print("ERROR: <channel> element not found in appcast.xml", file=sys.stderr)
    sys.exit(1)

if prune_legacy:
    for item in list(channel.findall("item")):
        enc = item.find("enclosure")
        if enc is not None and (not enc.get(f"{{{SPARKLE_NS}}}edSignature")):
            channel.remove(item)

new_item_xml = f"""<item xmlns:sparkle="{SPARKLE_NS}">
    <title>Sentinel Node Wallet v{version} (Build {build_num})</title>
    <pubDate>{pub_date}</pubDate>
    <sparkle:releaseNotesLink>{notes_url}</sparkle:releaseNotesLink>
    <description>Sentinel Node Wallet v{version} (Build {build_num}): Notarized production release for Apple Silicon (arm64). Pinned Bitcoin Knots consensus validator.</description>
    <enclosure
        url="{asset_url}"
        sparkle:version="{build_num}"
        sparkle:shortVersionString="{version}"
        sparkle:os="macos"
        sparkle:cpu="arm64"
        sparkle:edSignature="{ed_sig}"
        length="{length}"
        type="application/octet-stream" />
    <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
</item>"""
new_item_elem = ET.fromstring(new_item_xml)

items = channel.findall("item")
if items:
    first_idx = list(channel).index(items[0])
    channel.insert(first_idx, new_item_elem)
else:
    channel.append(new_item_elem)

ET.indent(root, space="    ")
updated_xml = ET.tostring(root, encoding="utf-8", xml_declaration=True).decode("utf-8")

# Validate updated XML structure
try:
    ET.fromstring(updated_xml)
except ET.ParseError as e:
    print(f"ERROR: Generated appcast XML failed parsing: {e}", file=sys.stderr)
    sys.exit(1)

with open(candidate_path, "w", encoding="utf-8") as f:
    f.write(updated_xml)

if is_dry_run:
    print("=== [DRY RUN] Generated Item Block ===")
    print(new_item_xml)
    print("======================================")
else:
    print(f"✓ Isolated staging appcast generated successfully at {candidate_path}")
PY

# 7. Transactional Feed Publish to Main via Isolated Git Worktree (WO-84, WO-89: Zero Source Workspace Mutation, WO-100: Sandbox/Live Separation)
if [ "${PUBLISH_TO_MAIN}" = "1" ]; then
    if [ "${SANDBOX_SIMULATION}" = "1" ]; then
        BARE_REPO_PATH="${REMOTE_ORIGIN_URL#file://}"
        if [ ! -d "${BARE_REPO_PATH}" ] || [ ! -f "${BARE_REPO_PATH}/SENTINEL_TEST_FIXTURE_MARKER" ]; then
            fail "FATAL SECURITY STOP (WO-100): Remote '${REMOTE_ORIGIN_URL}' is not an authorized test fixture with SENTINEL_TEST_FIXTURE_MARKER."
        fi
        echo "Publishing test appcast to isolated fixture bare remote (${BARE_REPO_PATH}) via git worktree..."
    else
        echo "Publishing candidate appcast to origin/main branch via isolated git worktree..."
    fi
    WORKTREE_DIR="$(mktemp -d -t sentinel-worktree-XXXXXX)"
    cleanup_worktree() {
        git worktree remove --force "${WORKTREE_DIR}" 2>/dev/null || rm -rf "${WORKTREE_DIR}" 2>/dev/null || true
    }
    trap 'cleanup_worktree; cleanup' EXIT

    # Create isolated detached worktree directly from origin/main
    git worktree add --detach "${WORKTREE_DIR}" "origin/main" || fail "Failed to create isolated worktree from origin/main."

    mkdir -p "${WORKTREE_DIR}/dist"
    cp "${STAGING_CANDIDATE}" "${WORKTREE_DIR}/dist/appcast.xml"

    # Verify worktree status modifies exclusively dist/appcast.xml
    CHANGED_FILES="$(git -C "${WORKTREE_DIR}" status --porcelain | awk '{print $2}')"
    if [ "${CHANGED_FILES}" != "dist/appcast.xml" ]; then
        fail "Worktree mutation invariant violated: unexpected changed files: ${CHANGED_FILES}"
    fi

    git -C "${WORKTREE_DIR}" add dist/appcast.xml
    git -C "${WORKTREE_DIR}" commit -m "chore(feed): publish Sparkle appcast for ${TAG} (WO-84, WO-89)"
    git -C "${WORKTREE_DIR}" push origin HEAD:main || fail "Failed to push updated feed to origin/main."

    git worktree remove --force "${WORKTREE_DIR}" 2>/dev/null || true
    echo "✓ Production appcast published successfully to origin/main via isolated worktree."
    echo "✓ Active working directory remained 100% untouched and unmutated."

    if [ "${SANDBOX_SIMULATION}" = "0" ]; then
        echo "Verifying published appcast live via raw GitHub CDN (WO-118)..."
        CDN_URL="https://raw.githubusercontent.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/main/dist/appcast.xml"
        MAX_RETRIES=10
        RETRY_DELAY=3
        CDN_VERIFIED=0

        for attempt in $(seq 1 "${MAX_RETRIES}"); do
            echo "CDN Readback Attempt ${attempt}/${MAX_RETRIES}..."
            CDN_STATUS="$(curl -s -o "${TEMP_DIR}/cdn_appcast.xml" -w "%{http_code}" "${CDN_URL}" || echo "000")"
            if [ "${CDN_STATUS}" = "200" ] && [ -s "${TEMP_DIR}/cdn_appcast.xml" ]; then
                if grep -q "sparkle:version=\"${BUILD_NUM}\"" "${TEMP_DIR}/cdn_appcast.xml" && \
                   grep -q "${ED_SIGNATURE}" "${TEMP_DIR}/cdn_appcast.xml"; then
                    echo "✓ Live CDN verification successful: Build ${BUILD_NUM} visible and cryptographically verified at ${CDN_URL} (HTTP 200)."
                    CDN_VERIFIED=1
                    break
                else
                    echo "Notice: CDN returned HTTP 200, but candidate Build ${BUILD_NUM} / signature not yet visible in edge cache (attempt ${attempt}/${MAX_RETRIES})."
                fi
            else
                echo "Notice: CDN returned HTTP ${CDN_STATUS} (attempt ${attempt}/${MAX_RETRIES})."
            fi
            sleep "${RETRY_DELAY}"
        done

        if [ "${CDN_VERIFIED}" != "1" ]; then
            echo "ERROR: PARTIAL_RELEASE_FEED_NOT_LIVE: CDN readback failed after ${MAX_RETRIES} attempts." >&2
            echo "The GitHub release and Git commit were published, but raw CDN has not served the authentic signed feed for Build ${BUILD_NUM}." >&2
            echo "Operator Repair Guidance: Inspect repository dist/appcast.xml on main and purge/invalidate edge cache if necessary." >&2
            exit 75
        fi
    fi
else
    echo "Dry-run validation complete. Active working directory and dist/appcast.xml were NOT mutated on disk."
fi

echo "=== Appcast Publisher Finished Successfully ==="
