#!/usr/bin/env bash
# Official Sparkle 2 EdDSA Enclosure Signing and Verification Helper
# Produces cryptographically valid sparkle:edSignature attributes for appcast.xml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIGN_UPDATE="${ROOT_DIR}/.build/artifacts/sparkle/Sparkle/bin/sign_update"
if [ ! -x "${SIGN_UPDATE}" ]; then
    SIGN_UPDATE="$(find "${ROOT_DIR}/.build" -name "sign_update" -type f -perm +111 2>/dev/null | head -n 1 || true)"
fi

if [ -z "${SIGN_UPDATE}" ] || [ ! -x "${SIGN_UPDATE}" ]; then
    echo "ERROR: Sparkle 'sign_update' binary not found. Run 'swift build' first." >&2
    exit 1
fi

usage() {
    cat <<EOF
Usage:
  $0 sign <archive-file> [--key-file <key> | --key-env]
  $0 verify <archive-file> <ed-signature>

Commands:
  sign    Generates an EdDSA signature and enclosure snippet for the given archive (.dmg/.zip).
  verify  Verifies that <archive-file> matches <ed-signature>.
EOF
    exit 1
}

[ $# -ge 2 ] || usage

COMMAND="$1"
ARCHIVE="$2"
shift 2

[ -f "${ARCHIVE}" ] || { echo "ERROR: File '${ARCHIVE}' not found." >&2; exit 1; }

ARCHIVE_SIZE="$(python3 -c "import os, sys; print(os.path.getsize(sys.argv[1]))" "${ARCHIVE}")"
ARCHIVE_SHA="$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')"

case "${COMMAND}" in
    sign)
        KEY_ARGS=()
        if [ "${1:-}" = "--key-file" ] && [ -n "${2:-}" ]; then
            KEY_ARGS=(--ed-key-file "$2")
        elif [ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
            # Pipe key securely via stdin to prevent process list exposure
            SIG="$(printf "%s" "${SPARKLE_PRIVATE_ED_KEY}" | "${SIGN_UPDATE}" -p --ed-key-file - "${ARCHIVE}")"
        else
            # Default to reading from macOS Keychain
            SIG="$("${SIGN_UPDATE}" -p "${ARCHIVE}")"
        fi

        if [ -z "${SIG:-}" ] && [ ${#KEY_ARGS[@]} -gt 0 ]; then
            SIG="$("${SIGN_UPDATE}" -p "${KEY_ARGS[@]}" "${ARCHIVE}")"
        fi

        echo "=== Sparkle 2 Enclosure Metadata ==="
        echo "File: $(basename "${ARCHIVE}")"
        echo "Length: ${ARCHIVE_SIZE} bytes"
        echo "SHA-256: ${ARCHIVE_SHA}"
        echo "sparkle:edSignature: ${SIG}"
        echo ""
        echo "XML Enclosure Snippet:"
        cat <<EOF
<enclosure
    url="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v<VERSION>/$(basename "${ARCHIVE}")"
    sparkle:edSignature="${SIG}"
    sparkle:version="<BUILD_NUMBER>"
    sparkle:shortVersionString="<VERSION>"
    sparkle:os="macos"
    sparkle:cpu="arm64"
    length="${ARCHIVE_SIZE}"
    type="application/octet-stream" />
EOF
        ;;

    verify)
        [ $# -ge 1 ] || { echo "ERROR: Missing signature for verification." >&2; usage; }
        TARGET_SIG="$1"
        echo "Verifying '${ARCHIVE}' against EdDSA signature..."
        "${SIGN_UPDATE}" --verify "${ARCHIVE}" "${TARGET_SIG}"
        echo "✓ Signature Verified Successfully!"
        ;;

    *)
        usage
        ;;
esac
