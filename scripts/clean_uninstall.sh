#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Sentinel Node Wallet BTCB2 - Clean Uninstallation & Storage Wipe Script
# ==============================================================================
# Completely terminates background node daemons and recursively deletes all
# synchronized blockchain data (~18 GB), chainstate UTXOs, wallet databases,
# application support files, and containers from macOS.
# ==============================================================================

echo "=================================================================="
echo " Sentinel Node Wallet BTCB2 - Complete Data Wipe & Uninstall"
echo "=================================================================="
echo ""
echo "This operation will permanently delete:"
echo "  1. Synced blockchain blocks and undo data (~18 GB)"
echo "  2. Chainstate UTXO database and transaction indices"
echo "  3. Local wallet files, auth registries, and configuration"
echo "  4. Mac App Store sandboxed container (if present)"
echo "  5. Application bundle from /Applications (if present)"
echo ""
read -r -p "Are you sure you want to completely erase all data? (y/N): " confirm
if [[ "${confirm:-n}" != "y" && "${confirm:-n}" != "Y" ]]; then
    echo "Aborted. No files were deleted."
    exit 0
fi

echo ""
echo "[1/4] Stopping any active Bitcoin Knots or Sentinel Node Wallet processes..."
killall bitcoind 2>/dev/null || true
pkill -f "Sentinel Node Wallet" 2>/dev/null || true
sleep 1

echo "[2/4] Purging Application Support data directory (~18 GB)..."
APP_SUPPORT="$HOME/Library/Application Support/NodePocketBTCB2"
if [ -d "$APP_SUPPORT" ]; then
    rm -rf "$APP_SUPPORT"
    echo "  ✓ Deleted: $APP_SUPPORT"
else
    echo "  • Skipped (not present): $APP_SUPPORT"
fi

echo "[3/4] Purging Mac App Store container..."
CONTAINER="$HOME/Library/Containers/pool.sentineldefensetechnologies.co.za"
if [ -d "$CONTAINER" ]; then
    rm -rf "$CONTAINER"
    echo "  ✓ Deleted: $CONTAINER"
else
    echo "  • Skipped (not present): $CONTAINER"
fi

echo "[4/4] Removing Application Bundle from /Applications..."
APP_BUNDLE="/Applications/Sentinel Node Wallet.app"
if [ -d "$APP_BUNDLE" ]; then
    rm -rf "$APP_BUNDLE"
    echo "  ✓ Deleted: $APP_BUNDLE"
else
    echo "  • Skipped (not present): $APP_BUNDLE"
fi

echo ""
echo "=================================================================="
echo " ✅ Clean uninstallation complete! Zero residual data left on Mac."
echo "=================================================================="
