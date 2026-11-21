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

usage() {
    cat <<EOF
Usage:
  $0 sign <archive-file> [--key-file <key>] [--signature-file-output <file>] [--signature-only] [--trusted-tool-hash <sha256>] [--sign-update-bin <path>]
  $0 verify <archive-file> <ed-signature> [--trusted-tool-hash <sha256>] [--sign-update-bin <path>]

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

KEY_ARGS=()
SIG_OUTPUT_FILE=""
SIG_ONLY=0
EXPECTED_TOOL_HASH="${SPARKLE_SIGN_UPDATE_EXPECTED_SHA256:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --key-file)
            [ $# -ge 2 ] || { echo "ERROR: Missing argument for --key-file" >&2; exit 1; }
            KEY_ARGS=(--ed-key-file "$2")
            shift 2
            ;;
        --signature-file-output)
            [ $# -ge 2 ] || { echo "ERROR: Missing argument for --signature-file-output" >&2; exit 1; }
            SIG_OUTPUT_FILE="$2"
            shift 2
            ;;
        --signature-only)
            SIG_ONLY=1
            shift
            ;;
        --trusted-tool-hash)
            [ $# -ge 2 ] || { echo "ERROR: Missing argument for --trusted-tool-hash" >&2; exit 1; }
            EXPECTED_TOOL_HASH="$2"
            shift 2
            ;;
        --sign-update-bin)
            [ $# -ge 2 ] || { echo "ERROR: Missing argument for --sign-update-bin" >&2; exit 1; }
            SIGN_UPDATE="$2"
            shift 2
            ;;
        *)
            # For verify command, first extra argument might be the target signature
            if [ "${COMMAND}" = "verify" ] && [ -z "${TARGET_SIG:-}" ]; then
                TARGET_SIG="$1"
                shift
            else
                echo "WARNING: Unknown option '$1' ignored" >&2
                shift
            fi
            ;;
    esac
done

if [ -z "${SIGN_UPDATE}" ] || [ ! -x "${SIGN_UPDATE}" ]; then
    echo "ERROR: Sparkle 'sign_update' binary not found at '${SIGN_UPDATE}'." >&2
    exit 1
fi

# Verify sign_update tool binary hash if expected hash is provided (WO-122-R4 / O1-G1A-03)
if [ -n "${EXPECTED_TOOL_HASH}" ]; then
    ACTUAL_TOOL_HASH="$(shasum -a 256 "${SIGN_UPDATE}" | awk '{print $1}')"
    if [ "${ACTUAL_TOOL_HASH}" != "${EXPECTED_TOOL_HASH}" ]; then
        echo "ERROR: Sparkle sign_update binary SHA-256 (${ACTUAL_TOOL_HASH}) does not match trusted tool hash (${EXPECTED_TOOL_HASH}). Execution blocked." >&2
        exit 1
    fi
    echo "✓ Verified Sparkle sign_update tool binary hash: ${ACTUAL_TOOL_HASH}" >&2
fi

case "${COMMAND}" in
    sign)
        SIG=""
        if [ ${#KEY_ARGS[@]} -gt 0 ]; then
            SIG="$("${SIGN_UPDATE}" -p "${KEY_ARGS[@]}" "${ARCHIVE}")"
        elif [ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
            # Pipe key securely via stdin to prevent process list exposure
            SIG="$(printf "%s" "${SPARKLE_PRIVATE_ED_KEY}" | "${SIGN_UPDATE}" -p --ed-key-file - "${ARCHIVE}")"
        else
            # Default to reading from macOS Keychain
            SIG="$("${SIGN_UPDATE}" -p "${ARCHIVE}")"
        fi

        # Canonicalize signature string: strip leading/trailing whitespace and line breaks
        SIG="$(printf "%s" "${SIG}" | tr -d '\r\n ')"

        if [ -z "${SIG}" ]; then
            echo "ERROR: Sparkle sign_update produced empty signature." >&2
            exit 1
        fi

        # Validate that signature is strictly valid Base64 decoding to exactly 64 bytes (WO-122-R3)
        python3 - "${SIG}" <<'PY' || { echo "ERROR: Generated signature is not valid 64-byte Base64." >&2; exit 1; }
import base64, sys
sig = sys.argv[1].strip()
try:
    decoded = base64.b64decode(sig, validate=True)
    if len(decoded) != 64:
        print(f"ERROR: Decoded signature length is {len(decoded)} bytes (expected exactly 64 bytes).", file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f"ERROR: Failed to Base64 decode signature: {e}", file=sys.stderr)
    sys.exit(1)
PY

        # Write dedicated machine-readable public signature sidecar if requested (WO-122-R3)
        if [ -n "${SIG_OUTPUT_FILE}" ]; then
            mkdir -p "$(dirname "${SIG_OUTPUT_FILE}")"
            printf "%s\n" "${SIG}" > "${SIG_OUTPUT_FILE}"
            echo "✓ Pure Base64 signature written to sidecar: ${SIG_OUTPUT_FILE}" >&2
        fi

        if [ "${SIG_ONLY}" = "1" ]; then
            printf "%s\n" "${SIG}"
            exit 0
        fi

        echo "=== Sparkle 2 Enclosure Metadata ==="
        echo "File: $(basename "${ARCHIVE}")"
        echo "Length: ${ARCHIVE_SIZE} bytes"
        echo "SHA-256: ${ARCHIVE_SHA}"
        echo "EdDSA Signature (Base64): ${SIG}"
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
        [ -n "${TARGET_SIG:-}" ] || { echo "ERROR: Missing signature for verification." >&2; usage; }
        echo "Verifying '${ARCHIVE}' against EdDSA signature..."
        "${SIGN_UPDATE}" --verify "${ARCHIVE}" "${TARGET_SIG}"
        echo "✓ Signature Verified Successfully!"
        ;;

    *)
        usage
        ;;
esac
