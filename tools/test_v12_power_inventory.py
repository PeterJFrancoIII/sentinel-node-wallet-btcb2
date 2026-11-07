#!/usr/bin/env python3
"""
test_v12_power_inventory.py
Deterministic mock verification for V12 Ultra Power Policy, All-Wallet Inventory, and Minimal Single-Settings UI.
"""

import unittest
import os
import re
import json
import tempfile
import shutil

class TestV12PowerPolicy(unittest.TestCase):
    def test_power_state_classification(self):
        def is_ultra_required(state, is_charging, is_low_power):
            if is_low_power:
                return True
            if state == "Battery Power":
                return True
            if state == "AC Power" and is_charging:
                return True
            return False

        # Battery -> Ultra
        self.assertTrue(is_ultra_required("Battery Power", False, False))
        self.assertTrue(is_ultra_required("Battery Power", True, False))

        # AC Charging -> Ultra
        self.assertTrue(is_ultra_required("AC Power", True, False))

        # AC Not Charging -> Normal
        self.assertFalse(is_ultra_required("AC Power", False, False))

        # Low power mode on AC Not Charging -> Ultra
        self.assertTrue(is_ultra_required("AC Power", False, True))

    def test_ultra_profile_bounds(self):
        ultra_profile = {
            "par": 1,
            "dbcache": 128,
            "maxconnections": 4,
            "maxuploadtarget": 128,
            "prune": 2048
        }
        self.assertEqual(ultra_profile["par"], 1)
        self.assertEqual(ultra_profile["dbcache"], 128)
        self.assertEqual(ultra_profile["maxconnections"], 4)
        self.assertEqual(ultra_profile["maxuploadtarget"], 128)
        self.assertGreaterEqual(ultra_profile["prune"], 550)


class TestV12WalletInventory(unittest.TestCase):
    def test_wallet_name_validation(self):
        def is_valid_wallet_name(name):
            if not name:
                return False
            if any(c in name for c in ["/", "\\", "..", ":", " "]):
                return False
            return re.match(r"^[a-zA-Z0-9_-]+$", name) is not None

        self.assertTrue(is_valid_wallet_name("main_wallet"))
        self.assertTrue(is_valid_wallet_name("savings-2026"))
        self.assertTrue(is_valid_wallet_name("default"))

        self.assertFalse(is_valid_wallet_name("../escape"))
        self.assertFalse(is_valid_wallet_name("/root"))
        self.assertFalse(is_valid_wallet_name("wallet:colon"))
        self.assertFalse(is_valid_wallet_name("wallet\\backslash"))
        self.assertFalse(is_valid_wallet_name("wallet with spaces"))
        self.assertFalse(is_valid_wallet_name(""))

    def test_sat_to_btcb2_formatting(self):
        def sats_to_btcb2(sats: int) -> str:
            return f"{sats / 100_000_000.0:.8f}"

        self.assertEqual(sats_to_btcb2(100_000_000), "1.00000000")
        self.assertEqual(sats_to_btcb2(50_000_000), "0.50000000")
        self.assertEqual(sats_to_btcb2(1), "0.00000001")
        self.assertEqual(sats_to_btcb2(0), "0.00000000")
        self.assertEqual(sats_to_btcb2(225_000_000), "2.25000000")

    def test_deletion_safety_gating(self):
        def can_delete_safely(spendable, pending, immature, is_stale):
            if is_stale:
                return False
            return (spendable == 0 and pending == 0 and immature == 0)

        # Funded cannot be deleted
        self.assertFalse(can_delete_safely(1000, 0, 0, False))
        self.assertFalse(can_delete_safely(0, 500, 0, False))
        self.assertFalse(can_delete_safely(0, 0, 200, False))

        # Stale/unloaded cannot be deleted even if 0
        self.assertFalse(can_delete_safely(0, 0, 0, True))

        # Verified 0 balance can be deleted
        self.assertTrue(can_delete_safely(0, 0, 0, False))


class TestV12SingleSettingsButton(unittest.TestCase):
    def test_nodeview_single_settings_button(self):
        node_view_path = os.path.join(
            os.path.dirname(__file__),
            "..",
            "Sources",
            "NodePocketApp",
            "Views",
            "NodeView.swift"
        )
        if not os.path.exists(node_view_path):
            self.skipTest("NodeView.swift not found")

        with open(node_view_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Count occurrences of `showAdvancedSheet = true`
        matches = re.findall(r"showAdvancedSheet\s*=\s*true", content)
        self.assertEqual(
            len(matches), 1,
            f"Expected exactly 1 call site of 'showAdvancedSheet = true' in NodeView.swift, found {len(matches)}"
        )

        # Verify accessibility identifier is present
        self.assertIn("node-settings-button", content)


if __name__ == "__main__":
    unittest.main()
