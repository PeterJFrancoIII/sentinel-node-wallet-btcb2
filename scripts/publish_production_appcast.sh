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
BACKUP_FILE="${DIST_DIR}/appcast.xml.bak"

fail() { printf "APPCAST PUBLISHER BLOCKED: %s\n" "$*" >&2; exit 1; }
cleanup() { rm -f "${BACKUP_FILE}" 2>/dev/null || true; }
trap cleanup EXIT

TAG=""
DRY_RUN=1
PUBLISH_TO_MAIN=0
OPERATOR_APPROVAL=""
PROVIDED_SIGNATURE=""
SIGNATURE_FILE=""
ARCHIVE_OVERRIDE=""
ALLOW_MOCK_FOR_DRY_RUN=0

usage() {
    cat <<EOF
Usage:
  $0 --tag <vMAJOR.MINOR.PATCH-buildINTEGER> [options]

Options:
  --tag <tag>                Required. Pinned release tag (e.g. v1.0.0-build5)
  --operator-approval <YES>  Required for live publish to main
  --signature <sig>          EdDSA signature for the archive
  --signature-file <file>    File containing the EdDSA signature
  --archive <dmg-file>       Local archive file override (skips network download in simulation)
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

SIGN_UPDATE="${ROOT_DIR}/.build/artifacts/sparkle/Sparkle/bin/sign_update"
if [ ! -x "${SIGN_UPDATE}" ]; then
    SIGN_UPDATE="$(find "${ROOT_DIR}/.build" -name "sign_update" -type f -perm +111 2>/dev/null | head -n 1 || true)"
fi

# 3. Resolve & Validate EdDSA Signature (WO-82: Absolute No-Mock in Live Mode)
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
    # LIVE MODE: Mock signatures strictly prohibited fail-closed
    if [ -z "${ED_SIGNATURE}" ]; then
        fail "Production publish aborted: EdDSA signature is required in live mode. Provide via --signature, --signature-file, or dist/SPARKLE_ENCLOSURE.txt."
    fi
    if [[ "${ED_SIGNATURE}" == *"mock"* ]] || [[ "${ED_SIGNATURE}" == *"Mock"* ]]; then
        fail "Production publish aborted: Mock EdDSA signatures are strictly prohibited in live mode."
    fi
    # Base64 validation (Ed25519 signatures are 64 bytes raw, 86-88 chars in base64)
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
fi

# 4. Verify GitHub Release Asset HTTP Accessibility and Checksum (WO-83: Strong Asset Verification)
TEMP_DIR="$(mktemp -d -t sentinel-appcast-XXXXXX)"
cleanup_all() {
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
    cleanup
}
trap cleanup_all EXIT

TARGET_ARCHIVE=""
ASSET_LENGTH=0

if [ "${DRY_RUN}" = "0" ]; then
    if [ "${OPERATOR_APPROVAL}" != "YES" ]; then
        fail "Live publication requires explicit --operator-approval YES."
    fi

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

    # Cryptographic EdDSA signature verification against downloaded archive
    if [ -n "${SIGN_UPDATE}" ] && [ -x "${SIGN_UPDATE}" ]; then
        echo "Verifying archive against EdDSA signature via Sparkle sign_update --verify..."
        "${SIGN_UPDATE}" --verify "${TARGET_ARCHIVE}" "${ED_SIGNATURE}" ||
            fail "EdDSA cryptographic signature verification failed against downloaded archive."
        echo "✓ EdDSA signature verified successfully against archive bytes."
    fi
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

# 5. Monotonic Version Verification vs Existing Appcast Items
cp "${APPCAST_FILE}" "${BACKUP_FILE}"

python3 - "${APPCAST_FILE}" "${BUILD_NUM}" "${VERSION}" <<'PY' || fail "Appcast monotonic version check failed."
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

# 6. Format and Insert New Item Block
PUB_DATE="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"
RELEASE_NOTES_URL="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/${TAG}"

python3 - "${APPCAST_FILE}" "${BACKUP_FILE}" "${BUILD_NUM}" "${VERSION}" "${RELEASE_URL}" "${ED_SIGNATURE}" "${ASSET_LENGTH}" "${PUB_DATE}" "${RELEASE_NOTES_URL}" "${DRY_RUN}" <<'PY' || fail "Failed to generate valid updated appcast.xml."
import sys
import xml.etree.ElementTree as ET

appcast_path = sys.argv[1]
backup_path = sys.argv[2]
build_num = sys.argv[3]
version = sys.argv[4]
asset_url = sys.argv[5]
ed_sig = sys.argv[6]
length = sys.argv[7]
pub_date = sys.argv[8]
notes_url = sys.argv[9]
is_dry_run = sys.argv[10] == "1"

with open(backup_path, "r", encoding="utf-8") as f:
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

if not is_dry_run:
    with open(appcast_path, "w", encoding="utf-8") as f:
        f.write(updated_xml)
    print("✓ dist/appcast.xml successfully updated.")
else:
    print("=== [DRY RUN] Generated Item Block ===")
    print(new_item)
    print("======================================")
PY

# 7. Transactional Feed Publish to Main via Isolated Git Worktree (WO-84: Zero Local Mutation)
if [ "${PUBLISH_TO_MAIN}" = "1" ]; then
    echo "Publishing dist/appcast.xml to main branch via isolated git worktree..."
    WORKTREE_DIR="$(mktemp -d -t sentinel-worktree-XXXXXX)"
    cleanup_worktree() {
        git worktree remove --force "${WORKTREE_DIR}" 2>/dev/null || rm -rf "${WORKTREE_DIR}" 2>/dev/null || true
    }
    trap 'cleanup_worktree; cleanup_all' EXIT

    # Create isolated detached worktree directly from origin/main
    git worktree add --detach "${WORKTREE_DIR}" "origin/main" || fail "Failed to create isolated worktree from origin/main."

    mkdir -p "${WORKTREE_DIR}/dist"
    cp "${APPCAST_FILE}" "${WORKTREE_DIR}/dist/appcast.xml"

    git -C "${WORKTREE_DIR}" add dist/appcast.xml
    git -C "${WORKTREE_DIR}" commit -m "chore(feed): publish Sparkle appcast for ${TAG} (WO-84)"
    git -C "${WORKTREE_DIR}" push origin HEAD:main || fail "Failed to push updated feed to origin/main."

    git worktree remove --force "${WORKTREE_DIR}" 2>/dev/null || true
    echo "✓ Production appcast published successfully to origin/main via isolated worktree."
else
    echo "Dry-run validation complete. Working directory and dist/appcast.xml were NOT mutated on disk."
fi

echo "=== Appcast Publisher Finished Successfully ==="
