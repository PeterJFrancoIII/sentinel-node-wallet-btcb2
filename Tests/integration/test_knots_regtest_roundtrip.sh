#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== Sentinel Node Wallet BTCB2: Native Knots Regtest Round-Trip Qualification ==="

# 1. Locate bundled or cached Knots binaries
KNOTS_BIN_DIR="${ROOT_DIR}/.cache/bitcoin-29.4.3.knots20260508/bin"
BITCOIND="${KNOTS_BIN_DIR}/bitcoind"
BITCOIN_CLI="${KNOTS_BIN_DIR}/bitcoin-cli"

if [ ! -f "${BITCOIND}" ] || [ ! -f "${BITCOIN_CLI}" ]; then
    echo "ERROR: Knots binaries not found in ${KNOTS_BIN_DIR}. Run scripts/fetch-verify-knots.sh first." >&2
    exit 1
fi

BITCOIND_SHA="$(shasum -a 256 "${BITCOIND}" | awk '{print $1}')"
echo "Binary Provenance SHA-256: ${BITCOIND_SHA}"

# 2. Setup isolated temporary regtest datadir and port
TEST_DATADIR="$(mktemp -d /tmp/knots_regtest_qualification_XXXXXX)"
TEST_RPC_PORT=28443
TEST_P2P_PORT=28444
TEST_RPC_USER="test_operator"
TEST_RPC_PASS="test_secret_passphrase_12345"

cleanup() {
    echo "Cleaning up temporary regtest environment..."
    if [ -f "${TEST_DATADIR}/regtest/bitcoind.pid" ]; then
        PID="$(cat "${TEST_DATADIR}/regtest/bitcoind.pid")"
        if kill -0 "${PID}" 2>/dev/null; then
            "${BITCOIN_CLI}" -regtest -datadir="${TEST_DATADIR}" -rpcport="${TEST_RPC_PORT}" -rpcuser="${TEST_RPC_USER}" -rpcpassword="${TEST_RPC_PASS}" stop >/dev/null 2>&1 || true
            sleep 1
        fi
    fi
    rm -rf "${TEST_DATADIR}"
}
trap cleanup EXIT

cat <<EOF > "${TEST_DATADIR}/bitcoin.conf"
regtest=1
server=1
listen=0
rpcuser=${TEST_RPC_USER}
rpcpassword=${TEST_RPC_PASS}
rpcport=${TEST_RPC_PORT}
port=${TEST_P2P_PORT}
fallbackfee=0.0001
[regtest]
rpcuser=${TEST_RPC_USER}
rpcpassword=${TEST_RPC_PASS}
rpcport=${TEST_RPC_PORT}
port=${TEST_P2P_PORT}
EOF

# 3. Start isolated bitcoind in regtest
echo "Starting isolated test bitcoind on loopback port ${TEST_RPC_PORT}..."
"${BITCOIND}" -datadir="${TEST_DATADIR}" -conf="${TEST_DATADIR}/bitcoin.conf" -daemonwait

CLI() {
    "${BITCOIN_CLI}" -regtest -datadir="${TEST_DATADIR}" -rpcport="${TEST_RPC_PORT}" -rpcuser="${TEST_RPC_USER}" -rpcpassword="${TEST_RPC_PASS}" "$@"
}

# 4. Generate initial blocks so chain has height
CLI createwallet "miner_wallet" false false "miner_pwd" false true true >/dev/null
MINER_ADDR="$(CLI -rpcwallet=miner_wallet getnewaddress "mining" "bech32")"
CLI generatetoaddress 101 "${MINER_ADDR}" >/dev/null

HEIGHT="$(CLI getblockcount)"
echo "Test chain height: ${HEIGHT}"

# 5. Qualification: Create encrypted descriptor wallet
WALLET_NAME="qual_wallet_test"
WALLET_PASS="CorrectHorseBatteryStaple_2026!"
echo "Creating encrypted descriptor wallet '${WALLET_NAME}'..."
CLI createwallet "${WALLET_NAME}" false false "${WALLET_PASS}" false true true >/dev/null

WALLET_INFO="$(CLI -rpcwallet="${WALLET_NAME}" getwalletinfo)"
DESCRIPTORS="$(echo "${WALLET_INFO}" | grep -o '"descriptors": *true' || true)"
UNLOCKED_UNTIL="$(echo "${WALLET_INFO}" | grep -o '"unlocked_until": *[0-9]*' || true)"

if [ -z "${DESCRIPTORS}" ]; then
    echo "ERROR: Created wallet is not descriptor-based!" >&2
    exit 1
fi
echo "Verified: Descriptors enabled."

# 6. Derive Bech32 receive address and verify ownership
RECV_ADDR="$(CLI -rpcwallet="${WALLET_NAME}" getnewaddress "savings" "bech32")"
ADDR_INFO="$(CLI -rpcwallet="${WALLET_NAME}" getaddressinfo "${RECV_ADDR}")"
IS_MINE="$(echo "${ADDR_INFO}" | grep -o '"ismine": *true' || true)"

if [ -z "${IS_MINE}" ]; then
    echo "ERROR: Derived address is not owned by wallet!" >&2
    exit 1
fi
echo "Verified: Derived Bech32 address ${RECV_ADDR} ismine=true."

# 7. Export atomic backup
BACKUP_PATH="${TEST_DATADIR}/wallet_backup.dat"
CLI -rpcwallet="${WALLET_NAME}" backupwallet "${BACKUP_PATH}" >/dev/null

if [ ! -f "${BACKUP_PATH}" ]; then
    echo "ERROR: Backup file was not created!" >&2
    exit 1
fi
BACKUP_SIZE="$(wc -c < "${BACKUP_PATH}" | tr -d ' ')"
BACKUP_SHA="$(shasum -a 256 "${BACKUP_PATH}" | awk '{print $1}')"
echo "Verified: Backup exported (${BACKUP_SIZE} bytes, SHA-256: ${BACKUP_SHA})"

# 8. Unload original wallet and restore to new wallet identity
CLI unloadwallet "${WALLET_NAME}" >/dev/null
RESTORED_NAME="qual_wallet_restored"
CLI restorewallet "${RESTORED_NAME}" "${BACKUP_PATH}" >/dev/null

RESTORED_INFO="$(CLI -rpcwallet="${RESTORED_NAME}" getwalletinfo)"
RESTORED_DESCRIPTORS="$(echo "${RESTORED_INFO}" | grep -o '"descriptors": *true' || true)"
RESTORED_LOCKED="$(echo "${RESTORED_INFO}" | grep -o '"unlocked_until": *0' || true)"

if [ -z "${RESTORED_DESCRIPTORS}" ] || [ -z "${RESTORED_LOCKED}" ]; then
    echo "ERROR: Restored wallet descriptors or lock verification failed!" >&2
    exit 1
fi

# Verify restored wallet owns the same address
RESTORED_ADDR_INFO="$(CLI -rpcwallet="${RESTORED_NAME}" getaddressinfo "${RECV_ADDR}")"
RESTORED_IS_MINE="$(echo "${RESTORED_ADDR_INFO}" | grep -o '"ismine": *true' || true)"
if [ -z "${RESTORED_IS_MINE}" ]; then
    echo "ERROR: Restored wallet does not own derived address!" >&2
    exit 1
fi

echo "Verified: Restored wallet '${RESTORED_NAME}' successfully restored from backup, locked, descriptors=true, ismine=true."
echo "=== Native Knots Regtest Round-Trip Qualification: 100% SUCCESS ==="
