#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

KNOTS_VERSION="29.4.3.knots20260508"
BASE_URL="https://bitcoinknots.org/files/29.x/${KNOTS_VERSION}"
ARCHIVE_NAME="bitcoin-${KNOTS_VERSION}-arm64-apple-darwin.tar.gz"
EXPECTED_ARCHIVE_SHA256="5c1a8a4df75acde2f15accc4358c678c3597b0244206ba472774e10cf9e86115"
EXPECTED_BITCOIND_SHA256="90470865255cf4ef5d45e47ccbb4fe99908182de57198c9b0984b56ed9045d1c"

echo "=== Bitcoin Knots Binary Verification Utility ==="
echo "Pinned Version: ${KNOTS_VERSION}"
echo "Target Archive: ${ARCHIVE_NAME}"

CACHE_DIR="${ROOT_DIR}/.cache"
mkdir -p "${CACHE_DIR}"

ARCHIVE_PATH="${CACHE_DIR}/${ARCHIVE_NAME}"

if [ ! -f "${ARCHIVE_PATH}" ]; then
    echo "Fetching release archive from ${BASE_URL}/${ARCHIVE_NAME}..."
    curl -sSL -o "${ARCHIVE_PATH}" "${BASE_URL}/${ARCHIVE_NAME}" || {
        echo "ERROR: Failed to download ${ARCHIVE_NAME} from ${BASE_URL}." >&2
        exit 1
    }
fi

echo "Verifying SHA-256 checksum of archive..."
CALCULATED_SHA256="$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}')"
if [ "${CALCULATED_SHA256}" != "${EXPECTED_ARCHIVE_SHA256}" ]; then
    echo "ERROR: Archive checksum mismatch!" >&2
    echo "Expected:   ${EXPECTED_ARCHIVE_SHA256}" >&2
    echo "Calculated: ${CALCULATED_SHA256}" >&2
    exit 1
fi
echo "Archive SHA-256 verified: ${CALCULATED_SHA256}"

# Extract if needed
EXTRACT_DIR="${CACHE_DIR}/bitcoin-${KNOTS_VERSION}"
if [ ! -d "${EXTRACT_DIR}/bin" ]; then
    echo "Extracting archive to ${CACHE_DIR}..."
    tar -xzf "${ARCHIVE_PATH}" -C "${CACHE_DIR}"
fi

# Verify extracted binaries
BITCOIND_PATH="${EXTRACT_DIR}/bin/bitcoind"
BITCOIN_CLI_PATH="${EXTRACT_DIR}/bin/bitcoin-cli"

if [ ! -f "${BITCOIND_PATH}" ] || [ ! -f "${BITCOIN_CLI_PATH}" ]; then
    echo "ERROR: Required Knots binaries missing in ${EXTRACT_DIR}/bin" >&2
    exit 1
fi

echo "Verifying bitcoind Mach-O architecture..."
ARCH_CHECK="$(file "${BITCOIND_PATH}")"
if [[ "${ARCH_CHECK}" != *"arm64"* ]]; then
    echo "ERROR: bitcoind binary is not arm64 architecture: ${ARCH_CHECK}" >&2
    exit 1
fi

BITCOIND_SHA="$(shasum -a 256 "${BITCOIND_PATH}" | awk '{print $1}')"
if [ "${BITCOIND_SHA}" != "${EXPECTED_BITCOIND_SHA256}" ]; then
    echo "ERROR: bitcoind binary checksum mismatch!" >&2
    echo "Expected:   ${EXPECTED_BITCOIND_SHA256}" >&2
    echo "Calculated: ${BITCOIND_SHA}" >&2
    exit 1
fi
echo "bitcoind binary SHA-256 verified: ${BITCOIND_SHA}"
echo "SUCCESS: Bitcoin Knots binary provenance verified. No system PATH fallback permitted."
