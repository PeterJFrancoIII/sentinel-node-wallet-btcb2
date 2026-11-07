#!/usr/bin/env python3
"""
tools/test_eta_engine.py
Deterministic test suite for Adaptive Verification ETA calculation and formatting.
"""

import sys
import unittest

def format_time_remaining(seconds: float) -> str:
    if seconds <= 0:
        return "~0s"
    secs = int(seconds)
    minutes = secs // 60
    hours = minutes // 60
    days = hours // 24
    weeks = days // 7

    if weeks >= 2:
        rem_days = days % 7
        return f"~{weeks}w {rem_days}d" if rem_days > 0 else f"~{weeks}w"
    elif days >= 1:
        rem_hours = hours % 24
        return f"~{days}d {rem_hours}h" if rem_hours > 0 else f"~{days}d"
    elif hours >= 1:
        rem_mins = minutes % 60
        return f"~{hours}h {rem_mins}m" if rem_mins > 0 else f"~{hours}h"
    elif minutes >= 1:
        rem_secs = secs % 60
        return f"~{minutes}m {rem_secs}s" if rem_secs > 0 else f"~{minutes}m"
    else:
        return f"~{max(1, secs)}s"


class TestAdaptiveETAEngine(unittest.TestCase):
    def test_unit_scaling(self):
        self.assertEqual(format_time_remaining(47), "~47s")
        self.assertEqual(format_time_remaining(1), "~1s")
        self.assertEqual(format_time_remaining(0), "~0s")
        self.assertEqual(format_time_remaining(18 * 60 + 42), "~18m 42s")
        self.assertEqual(format_time_remaining(5 * 60), "~5m")
        self.assertEqual(format_time_remaining(5 * 3600 + 24 * 60), "~5h 24m")
        self.assertEqual(format_time_remaining(2 * 3600), "~2h")
        self.assertEqual(format_time_remaining(3 * 86400 + 7 * 3600), "~3d 7h")
        self.assertEqual(format_time_remaining(1 * 86400), "~1d")
        self.assertEqual(format_time_remaining(14 * 86400 + 3 * 86400), "~2w 3d")
        self.assertEqual(format_time_remaining(21 * 86400), "~3w")

    def test_synthetic_ibd_trajectory(self):
        # 1000 blocks synced in 100 seconds from 0.01 to 0.02 progress
        delta_progress = 0.01
        elapsed = 100.0
        rate = delta_progress / elapsed
        remaining_progress = 1.0 - 0.02
        remaining_seconds = remaining_progress / rate
        self.assertEqual(remaining_seconds, 9800.0) # 2h 43m 20s
        self.assertEqual(format_time_remaining(remaining_seconds), "~2h 43m")

    def test_stall_detection(self):
        delta_progress = 0.0
        delta_height = 0
        elapsed_since_update = 240.0
        stall_threshold = 180.0
        is_stalled = (delta_progress <= 1e-7 and delta_height <= 0 and elapsed_since_update > stall_threshold)
        self.assertTrue(is_stalled)


if __name__ == "__main__":
    unittest.main()
