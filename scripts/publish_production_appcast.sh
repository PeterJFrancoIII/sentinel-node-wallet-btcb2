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
cleanup() { rm -rf "${TEMP_DIR}" 2>/dev/null || true; }
trap cleanup EXIT

fail() { printf "APPCAST PUBLISHER BLOCKED: %s\n" "$*" >&2; exit 1; }

TAG=""
DRY_RUN=1
PUBLISH_TO_MAIN=0
OPERATOR_APPROVAL=""
PROVIDED_SIGNATURE=""
SIGNATURE_FILE=""
ARCHIVE_OVERRIDE=""
ALLOW_MOCK_FOR_DRY_RUN=0
PUBLIC_KEY_OVERRIDE=""
APP_BUNDLE_PATH=""
SIGN_UPDATE_OVERRIDE=""
ED_KEY_FILE=""

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
  --app-bundle <path>        Path to .app bundle to extract SUPublicEDKey from Contents/Info.plist
  --archive <dmg-file>       Local archive file override (skips network download in simulation)
  --sign-update <path>       Path to Sparkle sign_update binary override
  --ed-key-file <file>       Private key file for Sparkle sign_update tool verification
  --publish-to-main          Commit and push updated appcast.xml directly to origin/main via isolated worktree
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

if [ "${BUILD_NUM}" -le 4 ]; then
    fail "Build number ${BUILD_NUM} must be greater than 4 (active development build is 4)."
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

[ -f "${APPCAST_FILE}" ] || fail "Appcast file not found at ${APPCAST_FILE}"

# Resolve Sparkle sign_update binary and enforce pinned provenance (WO-88)
if [ -n "${SIGN_UPDATE_OVERRIDE}" ]; then
    SIGN_UPDATE="${SIGN_UPDATE_OVERRIDE}"
else
    SIGN_UPDATE="${ROOT_DIR}/.build/artifacts/sparkle/Sparkle/bin/sign_update"
    if [ ! -x "${SIGN_UPDATE}" ]; then
        SIGN_UPDATE="$(find "${ROOT_DIR}/.build" -name "sign_update" -type f -perm +111 2>/dev/null | head -n 1 || true)"
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

# Resolve Public Key (SUPublicEDKey)
PUBLIC_KEY=""
if [ -n "${PUBLIC_KEY_OVERRIDE}" ]; then
    PUBLIC_KEY="${PUBLIC_KEY_OVERRIDE}"
elif [ -n "${APP_BUNDLE_PATH}" ] && [ -d "${APP_BUNDLE_PATH}" ]; then
    INFO_PLIST="${APP_BUNDLE_PATH}/Contents/Info.plist"
    if [ -f "${INFO_PLIST}" ]; then
        PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${INFO_PLIST}" 2>/dev/null || echo "")"
    fi
elif [ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]; then
    PUBLIC_KEY="${SPARKLE_PUBLIC_ED_KEY}"
fi

# 3. Resolve & Validate EdDSA Signature (WO-82, WO-88: Strict 64-Byte Ed25519 & No-Mock)
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

    # Public key is strictly required in live mode to verify signature authenticity
    if [ -z "${PUBLIC_KEY}" ]; then
        fail "Production publish aborted: SUPublicEDKey is strictly required in live mode to verify signature authenticity before publishing feed. Pass --public-key, --app-bundle, or set SPARKLE_PUBLIC_ED_KEY."
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

# 4. Verify GitHub Release Asset HTTP Accessibility and Checksum (WO-83: Strong Asset Verification)
TARGET_ARCHIVE=""
ASSET_LENGTH=0

if [ "${DRY_RUN}" = "0" ]; then
    echo "Checking immutable GitHub Release asset availability (following redirects to final 200)..."
    HTTP_STATUS="$(curl -sIL -o /dev/null -w "%{http_code}" "${RELEASE_URL}" || echo "000")"
    if [ "${HTTP_STATUS}" != "200" ]; then
        fail "Release asset at ${RELEASE_URL} returned final HTTP ${HTTP_STATUS}. Release must be publicly accessible before feed publication."
    fi

    echo "Downloading release SHA256SUMS.txt..."
    curl -fsSL "${SHA_URL}" -o "${TEMP_DIR}/SHA256SUMS.txt" || fail "Failed to retrieve SHA256SUMS.txt from release."

    EXPECTED_SHA="$(grep -E "^[a-f0-9]{64}[[:space:]]+(\./)?${ASSET_NAME}$" "${TEMP_DIR}/SHA256SUMS.txt" | awk '{print $1}' || echo "")"
    [ -n "${EXPECTED_SHA}" ] || fail "Asset ${ASSET_NAME} not found in release SHA256SUMS.txt with valid 64-hex SHA-256."

    echo "Downloading release asset bytes into isolated verification staging..."
    TARGET_ARCHIVE="${TEMP_DIR}/${ASSET_NAME}"
    curl -fsSL "${RELEASE_URL}" -o "${TARGET_ARCHIVE}" || fail "Failed to download release archive from ${RELEASE_URL}."

    # Compute actual checksum on downloaded bytes
    ACTUAL_SHA="$(shasum -a 256 "${TARGET_ARCHIVE}" | awk '{print $1}')"
    if [ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]; then
        fail "Integrity violation: Downloaded asset SHA-256 (${ACTUAL_SHA}) does not match release manifest (${EXPECTED_SHA})."
    fi

    ASSET_LENGTH="$(python3 -c "import os, sys; print(os.path.getsize(sys.argv[1]))" "${TARGET_ARCHIVE}")"
    [ "${ASSET_LENGTH}" -gt 1000000 ] || fail "Asset size suspicious (${ASSET_LENGTH} bytes)."
    echo "✓ Verified release asset integrity: ${ASSET_NAME} (${ASSET_LENGTH} bytes, SHA-256: ${ACTUAL_SHA})"
else
    if [ -n "${ARCHIVE_OVERRIDE}" ] && [ -f "${ARCHIVE_OVERRIDE}" ]; then
        TARGET_ARCHIVE="${ARCHIVE_OVERRIDE}"
        ASSET_LENGTH="$(python3 -c "import os, sys; print(os.path.getsize(sys.argv[1]))" "${TARGET_ARCHIVE}")"
        echo "[DRY RUN] Using local archive override: ${TARGET_ARCHIVE} (${ASSET_LENGTH} bytes)"
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

    # Cross-verify via Sparkle sign_update tool if private key or key file is available
    if [ -n "${SIGN_UPDATE}" ] && [ -x "${SIGN_UPDATE}" ]; then
        if [ -n "${ED_KEY_FILE}" ] && [ -f "${ED_KEY_FILE}" ]; then
            echo "Cross-verifying via Sparkle sign_update --verify with key file..."
            "${SIGN_UPDATE}" --verify --ed-key-file "${ED_KEY_FILE}" "${TARGET_ARCHIVE}" "${ED_SIGNATURE}" ||
                fail "Sparkle sign_update --verify failed."
            echo "✓ Sparkle sign_update verification succeeded."
        elif [ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
            echo "Cross-verifying via Sparkle sign_update --verify with SPARKLE_PRIVATE_ED_KEY..."
            printf "%s" "${SPARKLE_PRIVATE_ED_KEY}" | "${SIGN_UPDATE}" --verify --ed-key-file - "${TARGET_ARCHIVE}" "${ED_SIGNATURE}" ||
                fail "Sparkle sign_update --verify failed."
            echo "✓ Sparkle sign_update verification succeeded."
        fi
    fi
fi

# 5. Monotonic Version Verification vs Existing Appcast Items (WO-89: Staged in Isolated Temp)
STAGING_ORIGINAL="${TEMP_DIR}/appcast_original.xml"
STAGING_CANDIDATE="${TEMP_DIR}/appcast_candidate.xml"

cp "${APPCAST_FILE}" "${STAGING_ORIGINAL}"

python3 - "${STAGING_ORIGINAL}" "${BUILD_NUM}" "${VERSION}" <<'PY' || fail "Appcast monotonic version check failed."
import sys
import xml.etree.ElementTree as ET

appcast_path = sys.argv[1]
new_build = int(sys.argv[2])
new_version = sys.argv[3]

tree = ET.parse(appcast_path)
root = tree.getroot()
channel = root.find("channel")
if channel is None:
    print("ERROR: <channel> element not found in appcast.xml", file=sys.stderr)
    sys.exit(1)

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
existing_builds = []
for item in channel.findall("item"):
    enc = item.find("enclosure")
    if enc is not None:
        v = enc.get(f"{{{SPARKLE_NS}}}version")
        if v and v.isdigit():
            existing_builds.append(int(v))

if existing_builds:
    max_existing = max(existing_builds)
    if new_build <= max_existing:
        print(f"ERROR: Candidate build {new_build} must be strictly greater than max existing build {max_existing}.", file=sys.stderr)
        sys.exit(1)
print(f"✓ Monotonic check passed: candidate build {new_build} > existing builds {existing_builds}")
PY

# 6. Format and Insert New Item Block into Isolated Candidate XML (WO-89: Zero Source Workspace Mutation)
PUB_DATE="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"
RELEASE_NOTES_URL="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/${TAG}"

python3 - "${STAGING_ORIGINAL}" "${STAGING_CANDIDATE}" "${BUILD_NUM}" "${VERSION}" "${RELEASE_URL}" "${ED_SIGNATURE}" "${ASSET_LENGTH}" "${PUB_DATE}" "${RELEASE_NOTES_URL}" "${DRY_RUN}" <<'PY' || fail "Failed to generate valid updated appcast.xml."
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

with open(original_path, "r", encoding="utf-8") as f:
    original_xml = f.read()

new_item = f"""        <item>
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

if "<language>en</language>" in original_xml:
    updated_xml = original_xml.replace("<language>en</language>", f"<language>en</language>\n{new_item}")
else:
    updated_xml = original_xml.replace("<channel>", f"<channel>\n{new_item}")

# Validate updated XML structure
try:
    ET.fromstring(updated_xml)
except ET.ParseError as e:
    print(f"ERROR: Generated appcast XML failed parsing: {e}", file=sys.stderr)
    sys.exit(1)

# Write updated XML to isolated staging file (never active source tree)
with open(candidate_path, "w", encoding="utf-8") as f:
    f.write(updated_xml)

if is_dry_run:
    print("=== [DRY RUN] Generated Item Block ===")
    print(new_item)
    print("======================================")
else:
    print(f"✓ Isolated staging appcast generated successfully at {candidate_path}")
PY

# 7. Transactional Feed Publish to Main via Isolated Git Worktree (WO-84, WO-89: Zero Source Workspace Mutation)
if [ "${PUBLISH_TO_MAIN}" = "1" ]; then
    echo "Publishing candidate appcast to origin/main branch via isolated git worktree..."
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
else
    echo "Dry-run validation complete. Active working directory and dist/appcast.xml were NOT mutated on disk."
fi

echo "=== Appcast Publisher Finished Successfully ==="
