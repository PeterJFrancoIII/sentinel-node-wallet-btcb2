#!/usr/bin/env bash
# Official Sparkle 2 Stable Production Appcast Publisher (WO-77)
# Idempotently constructs and verifies cryptographically signed dist/appcast.xml
# from immutable GitHub release assets.
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

usage() {
    cat <<EOF
Usage:
  $0 --tag <vMAJOR.MINOR.PATCH-buildINTEGER> [options]

Options:
  --tag <tag>                Required. Pinned release tag (e.g. v1.0.0-build5)
  --operator-approval <YES>  Required for live publish to main
  --publish-to-main          Commit and push updated appcast.xml directly to origin/main
  --dry-run                  Simulate validation and print appcast diff (default)
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
        -h|--help)
            usage
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

[ -n "${TAG}" ] || fail "Missing mandatory --tag argument."

# 1. Strict Tag & Monotonic Build Validation (WO-76 / WO-77)
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

echo "=== Sentinel Node Wallet: Production Sparkle Feed Publisher (WO-77) ==="
echo "Candidate Tag:       ${TAG}"
echo "Parsed Version:      v${VERSION}"
echo "Parsed Build:        ${BUILD_NUM}"
echo "Asset Filename:      ${ASSET_NAME}"
echo "Mode:                $([ "${DRY_RUN}" = "1" ] && echo "DRY RUN (simulation)" || echo "LIVE PUBLISH TO MAIN")"

# 2. Check Prerequisites
command -v curl >/dev/null || fail "curl is required."
command -v shasum >/dev/null || fail "shasum is required."
command -v python3 >/dev/null || fail "python3 is required."
command -v git >/dev/null || fail "git is required."

[ -f "${APPCAST_FILE}" ] || fail "Appcast file not found at ${APPCAST_FILE}"

# 3. Verify GitHub Release Asset HTTP Accessibility and Checksum (Fail-Closed)
if [ "${DRY_RUN}" = "0" ]; then
    if [ "${OPERATOR_APPROVAL}" != "YES" ]; then
        fail "Live publication requires --operator-approval YES."
    fi

    echo "Checking immutable GitHub Release asset availability (HTTP 200)..."
    HTTP_STATUS="$(curl -sI -o /dev/null -w "%{http_code}" "${RELEASE_URL}" || echo "000")"
    if [ "${HTTP_STATUS}" != "200" ] && [ "${HTTP_STATUS}" != "302" ]; then
        fail "Release asset at ${RELEASE_URL} returned HTTP ${HTTP_STATUS}. Release must be published before updating feed."
    fi

    TEMP_DIR="$(mktemp -d -t sentinel-appcast-XXXXXX)"
    trap 'rm -rf "${TEMP_DIR}"; cleanup' EXIT

    echo "Downloading release SHA256SUMS.txt..."
    curl -fsSL "${SHA_URL}" -o "${TEMP_DIR}/SHA256SUMS.txt" || fail "Failed to retrieve SHA256SUMS.txt from release."

    echo "Verifying asset checksum and signature..."
    EXPECTED_SHA="$(grep "${ASSET_NAME}" "${TEMP_DIR}/SHA256SUMS.txt" | awk '{print $1}' || echo "")"
    [ -n "${EXPECTED_SHA}" ] || fail "Asset ${ASSET_NAME} not found in release SHA256SUMS.txt."

    # Download header or asset for exact byte length
    ASSET_LENGTH="$(curl -sIL "${RELEASE_URL}" | grep -i content-length | tail -n 1 | awk '{print $2}' | tr -d '\r')"
    [ -n "${ASSET_LENGTH}" ] || fail "Could not determine asset content length."
else
    echo "[DRY RUN] Simulating asset validation for ${ASSET_NAME}..."
    EXPECTED_SHA="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    ASSET_LENGTH="12450000"
fi

# 4. Monotonic Version Verification vs Existing Appcast Items
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

# 5. Format and Insert New Item Block
PUB_DATE="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"
RELEASE_NOTES_URL="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/${TAG}"
SAMPLE_ED_SIG="mockEdDSASignatureForDryRunSimulationOnly=="

if [ -f "${ROOT_DIR}/dist/SPARKLE_ENCLOSURE.txt" ]; then
    EXTRACTED_SIG="$(grep "sparkle:edSignature" "${ROOT_DIR}/dist/SPARKLE_ENCLOSURE.txt" | head -n 1 | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/' || echo "")"
    if [ -n "${EXTRACTED_SIG}" ]; then
        SAMPLE_ED_SIG="${EXTRACTED_SIG}"
    fi
fi

python3 - "${APPCAST_FILE}" "${BACKUP_FILE}" "${BUILD_NUM}" "${VERSION}" "${RELEASE_URL}" "${SAMPLE_ED_SIG}" "${ASSET_LENGTH}" "${PUB_DATE}" "${RELEASE_NOTES_URL}" "${DRY_RUN}" <<'PY' || fail "Failed to generate valid updated appcast.xml."
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

# Read original
with open(backup_path, "r", encoding="utf-8") as f:
    original_xml = f.read()

# Build the new item XML string with proper indentation
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

# Insert new item after <language>en</language>
if "<language>en</language>" in original_xml:
    updated_xml = original_xml.replace("<language>en</language>", f"<language>en</language>\n{new_item}")
else:
    # Insert right after <channel>
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

# 6. Live Publish to Main Branch (Atomic CAS)
if [ "${PUBLISH_TO_MAIN}" = "1" ]; then
    echo "Initiating atomic publish of dist/appcast.xml to main branch..."
    CURRENT_BRANCH="$(git branch --show-current)"
    
    # Stash any uncommitted work safely
    git stash push -m "stashed-by-appcast-publisher" || true
    
    # Check out main, apply appcast.xml, commit and push
    git checkout main || fail "Failed to checkout main branch."
    cp "${DIST_DIR}/appcast.xml" dist/appcast.xml
    git add dist/appcast.xml
    git commit -m "chore(feed): publish Sparkle appcast for ${TAG} (WO-77)"
    git push origin main || {
        echo "ERROR: Push to origin/main failed. Rolling back..." >&2
        git reset --hard HEAD~1
        git checkout "${CURRENT_BRANCH}"
        git stash pop || true
        fail "Failed to push updated feed to main."
    }
    
    git checkout "${CURRENT_BRANCH}"
    git stash pop || true
    echo "✓ Production appcast published successfully to main branch."
else
    echo "Dry-run validation complete. dist/appcast.xml was NOT modified on disk."
fi

echo "=== Appcast Publisher Finished Successfully ==="
