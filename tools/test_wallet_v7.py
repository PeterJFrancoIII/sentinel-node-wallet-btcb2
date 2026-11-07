#!/usr/bin/env python3
"""
tools/test_wallet_v7.py
Deterministic Python test suite for Sentinel Node Wallet - BTCB2 Wallet Manager V7.
Tests coinbase maturity epochs, integer satoshi math, fee rate conversions,
allowlist validation, explorer URL security, and immutable origin invariants.
"""

import sys
import unittest
import re
from typing import Optional, Tuple

# Constants matching BTCB2ConsensusConstants & CoinbaseMaturity
MTP_EXPIRY_TIMESTAMP = 1820016000  # 2027-09-01 00:00:00 UTC
SHORT_MATURITY = 100
MEDIUM_MATURITY = 6480
LONG_MATURITY = 25920

def classify_epoch(creation_height: int, creation_mtp: int = 0) -> Tuple[str, int]:
    if creation_mtp >= MTP_EXPIRY_TIMESTAMP and creation_height >= 979919:
        return ("postExpiry", SHORT_MATURITY)
    elif creation_height >= 979919:
        return ("longTerm", LONG_MATURITY)
    elif creation_height >= 973440:
        return ("mediumTerm", MEDIUM_MATURITY)
    else:
        return ("standard", SHORT_MATURITY)

def required_confirmations_for_reward(creation_height: int, creation_mtp: int = 0) -> int:
    # Immutable origin height invariant:
    # Once minted, required depth is permanently fixed by creation block height and creation MTP.
    _, req = classify_epoch(creation_height, creation_mtp)
    return req

def btc_to_sat(btc: float) -> int:
    return int(round(btc * 100_000_000))

def sat_to_btc(sats: int) -> float:
    return sats / 100_000_000.0

def btcb2_per_kb_to_sat_per_vb(btc_per_kb: float) -> int:
    # 1 BTC/kB = 100,000,000 sat / 1,000 vB = 100,000 sat/vB
    sats = int(round(btc_per_kb * 100_000.0))
    return max(1, sats)

def reconcile_fee_rates(cheapest: int, normal: int, fast: int, relay_floor: int = 1) -> Tuple[int, int, int]:
    r_cheapest = max(cheapest, relay_floor)
    r_normal = max(normal, r_cheapest)
    r_fast = max(fast, r_normal)
    return (r_cheapest, r_normal, r_fast)

def validate_mainnet_address(address: str) -> bool:
    if not address.startswith("bc1"):
        return False
    if len(address) < 14 or len(address) > 90:
        return False
    # Bech32 character set: [02-9ac-hj-np-z]
    bech32_charset = set("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    payload = address[3:]
    return all(c in bech32_charset for c in payload)

def build_explorer_tx_url(txid: str) -> Optional[str]:
    clean_txid = txid.strip().lower()
    if not re.fullmatch(r"^[0-9a-f]{64}$", clean_txid):
        return None
    return f"https://mempool.guide/tx/{clean_txid}"


class TestCoinbaseMaturityEpochs(unittest.TestCase):
    def test_epoch_boundary_973439_vs_973440(self):
        # Boundary 1: Standard (100) vs Medium (6480)
        epoch_before, depth_before = classify_epoch(973439)
        self.assertEqual(epoch_before, "standard")
        self.assertEqual(depth_before, 100)

        epoch_at, depth_at = classify_epoch(973440)
        self.assertEqual(epoch_at, "mediumTerm")
        self.assertEqual(depth_at, 6480)

    def test_epoch_boundary_979918_vs_979919(self):
        # Boundary 2: Medium (6480) vs Long (25920)
        epoch_before, depth_before = classify_epoch(979918)
        self.assertEqual(epoch_before, "mediumTerm")
        self.assertEqual(depth_before, 6480)

        epoch_at, depth_at = classify_epoch(979919)
        self.assertEqual(epoch_at, "longTerm")
        self.assertEqual(depth_at, 25920)

    def test_mtp_expiry_2027_09_01(self):
        # Before MTP expiry: longTerm 25920
        epoch_pre, depth_pre = classify_epoch(1000000, creation_mtp=MTP_EXPIRY_TIMESTAMP - 1)
        self.assertEqual(epoch_pre, "longTerm")
        self.assertEqual(depth_pre, 25920)

        # At/after MTP expiry: postExpiry 100
        epoch_post, depth_post = classify_epoch(1000000, creation_mtp=MTP_EXPIRY_TIMESTAMP)
        self.assertEqual(epoch_post, "postExpiry")
        self.assertEqual(depth_post, 100)

    def test_immutable_origin_invariant(self):
        # Invariant: A coinbase created at height 975000 requires 6480 confirmations,
        # even if current tip is 1050000 or MTP has passed 2027-09-01.
        req_depth = required_confirmations_for_reward(creation_height=975000, creation_mtp=0)
        self.assertEqual(req_depth, 6480)

        # Standard legacy coinbase at block 500000 remains 100 forever
        req_legacy = required_confirmations_for_reward(creation_height=500000, creation_mtp=0)
        self.assertEqual(req_legacy, 100)


class TestIntegerSatoshiMathAndFees(unittest.TestCase):
    def test_sat_conversion(self):
        self.assertEqual(btc_to_sat(1.0), 100_000_000)
        self.assertEqual(btc_to_sat(0.00000001), 1)
        self.assertEqual(btc_to_sat(21_000_000.0), 2_100_000_000_000_000)
        self.assertEqual(sat_to_btc(100_000_000), 1.0)
        self.assertEqual(sat_to_btc(50_000), 0.0005)

    def test_rate_conversion_btcb2_per_kb(self):
        # 0.00001000 BTCB2/kB = 1 sat/vB
        self.assertEqual(btcb2_per_kb_to_sat_per_vb(0.00001000), 1)
        # 0.00012000 BTCB2/kB = 12 sat/vB
        self.assertEqual(btcb2_per_kb_to_sat_per_vb(0.00012000), 12)
        # 0.00000100 BTCB2/kB (sub-floor) clamps to minimum 1 sat/vB
        self.assertEqual(btcb2_per_kb_to_sat_per_vb(0.00000100), 1)

    def test_fee_reconciliation_ordering(self):
        # Out-of-order raw estimates (e.g. erratic node fee estimates)
        c, n, f = reconcile_fee_rates(cheapest=8, normal=5, fast=6, relay_floor=2)
        self.assertEqual(c, 8)
        self.assertEqual(n, 8)  # clamped up to cheapest
        self.assertEqual(f, 8)  # clamped up to normal

        # Relay floor enforcement
        c2, n2, f2 = reconcile_fee_rates(cheapest=0, normal=1, fast=2, relay_floor=5)
        self.assertEqual(c2, 5)
        self.assertEqual(n2, 5)
        self.assertEqual(f2, 5)

        # Proper ordering
        c3, n3, f3 = reconcile_fee_rates(cheapest=3, normal=7, fast=15, relay_floor=1)
        self.assertEqual(c3, 3)
        self.assertEqual(n3, 7)
        self.assertEqual(f3, 15)


class TestAddressBookValidation(unittest.TestCase):
    def test_valid_mainnet_native_segwit(self):
        valid_addresses = [
            "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",  # P2WPKH
            "bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3",  # P2WSH
            "bc1p5d7rx65gn2nwy0yzgahfdhcsts63er5w252xq38hg79aj5pqndqszqfkwt",  # P2TR (Taproot)
        ]
        for addr in valid_addresses:
            self.assertTrue(validate_mainnet_address(addr), f"Expected {addr} to be valid")

    def test_rejection_of_non_mainnet_and_legacy(self):
        invalid_addresses = [
            "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx",  # Testnet Bech32
            "bcrt1q5d7rx65gn2nwy0yzgahfdhcsts63er5w252x",  # Regtest Bech32
            "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2",          # Legacy Base58 P2PKH
            "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy",          # Legacy Base58 P2SH
            "bc1invalidchar123!!!",                         # Invalid characters
            "bc1",                                          # Too short
            "bc1" + "q" * 95,                               # Too long
        ]
        for addr in invalid_addresses:
            self.assertFalse(validate_mainnet_address(addr), f"Expected {addr} to be rejected")


class TestExplorerUrlSecurity(unittest.TestCase):
    def test_valid_txid_url(self):
        txid = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
        url = build_explorer_tx_url(txid)
        self.assertEqual(url, f"https://mempool.guide/tx/{txid}")

    def test_rejection_of_malformed_txid(self):
        invalid_txids = [
            "",
            "not-a-txid",
            "a1b2c3d4",  # too short
            "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90extra",  # too long
            "https://mempool.space/tx/abc",  # Attempted URL injection
            "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9g",  # invalid hex 'g'
        ]
        for invalid in invalid_txids:
            self.assertIsNone(build_explorer_tx_url(invalid), f"Expected {invalid} to be rejected")


if __name__ == "__main__":
    unittest.main()
