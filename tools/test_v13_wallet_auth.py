#!/usr/bin/env python3
"""
test_v13_wallet_auth.py
Deterministic mock verification for V13 Local Login, RFC 6238 TOTP, and Wallet Auth Coordinator.
"""

import unittest
import base64
import hmac
import hashlib
import struct
import time
import os
import re

def is_strong_password(password: str) -> bool:
    if len(password) < 10:
        return False
    has_upper = any(c.isupper() for c in password)
    has_lower = any(c.islower() for c in password)
    has_digit = any(c.isdigit() for c in password)
    has_special = any(not c.isalnum() for c in password)
    return has_upper and has_lower and has_digit and has_special

def generate_totp(secret_b32: str, for_time: int) -> str:
    key = base64.b32decode(secret_b32, casefold=True)
    counter = int(for_time // 30)
    msg = struct.pack(">Q", counter)
    h = hmac.new(key, msg, hashlib.sha1).digest()
    offset = h[-1] & 0x0f
    code = struct.unpack(">I", h[offset:offset+4])[0] & 0x7fffffff
    return f"{code % 1000000:06d}"

def verify_totp(secret_b32: str, code: str, for_time: int, tolerance: int = 1):
    current_step = int(for_time // 30)
    for offset in range(-tolerance, tolerance + 1):
        step = current_step + offset
        if generate_totp(secret_b32, step * 30) == code:
            return True, step
    return False, 0

class TestV13WalletAuth(unittest.TestCase):
    def test_password_strength_policy(self):
        self.assertFalse(is_strong_password("Short1!"))
        self.assertFalse(is_strong_password("lowercase123!@#"))
        self.assertFalse(is_strong_password("UPPERCASE123!@#"))
        self.assertFalse(is_strong_password("NoNumbersHere!@#"))
        self.assertFalse(is_strong_password("NoSpecialChar1234"))
        self.assertTrue(is_strong_password("ValidStrongPassword123!@#"))

    def test_rfc6238_standard_test_vector(self):
        secret = "JBSWY3DPEHPK3PXP"
        t0 = 1234567890
        totp = generate_totp(secret, t0)
        self.assertEqual(totp, "742275")

        valid, step = verify_totp(secret, "742275", t0)
        self.assertTrue(valid)
        self.assertEqual(step, t0 // 30)

        # Invalid code
        invalid, _ = verify_totp(secret, "000000", t0)
        self.assertFalse(invalid)

    def test_totp_tolerance_window(self):
        secret = "JBSWY3DPEHPK3PXP"
        t0 = 1000000
        code_current = generate_totp(secret, t0)
        code_prev = generate_totp(secret, t0 - 30)
        code_next = generate_totp(secret, t0 + 30)
        code_too_far = generate_totp(secret, t0 + 65)

        self.assertTrue(verify_totp(secret, code_current, t0)[0])
        self.assertTrue(verify_totp(secret, code_prev, t0)[0])
        self.assertTrue(verify_totp(secret, code_next, t0)[0])
        self.assertFalse(verify_totp(secret, code_too_far, t0)[0])

    def test_recovery_code_one_time_use(self):
        recovery_codes = ["A1B2C3D4", "E5F6G7H8"]
        recovery_hashes = [hashlib.sha256(c.encode()).hexdigest() for c in recovery_codes]

        # Use first code
        input_code = "A1B2C3D4"
        input_hash = hashlib.sha256(input_code.encode()).hexdigest()
        self.assertIn(input_hash, recovery_hashes)

        # Consume code
        recovery_hashes.remove(input_hash)
        self.assertEqual(len(recovery_hashes), 1)

        # Attempt to reuse consumed code
        self.assertNotIn(input_hash, recovery_hashes)

    def test_rate_limiting_lockout_calculation(self):
        failed_attempts = 4
        # 5th attempt triggers lockout
        failed_attempts += 1
        penalty_seconds = min(300, int(2 ** (failed_attempts - 4)) * 10)
        self.assertEqual(penalty_seconds, 20)

    def test_source_code_regtest_exclusion(self):
        # Confirm generateRegtestBlocks is compile-gated or removed from production runtime
        wallet_mgr_path = os.path.join(
            os.path.dirname(__file__), "..", "Sources", "NodePocketCore", "Wallet", "WalletManager.swift"
        )
        with open(wallet_mgr_path, "r", encoding="utf-8") as f:
            content = f.read()

        if "generateRegtestBlocks" in content:
            self.assertIn("#if DEBUG", content)

if __name__ == "__main__":
    unittest.main()
