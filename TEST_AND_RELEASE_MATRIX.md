# Test and Release Matrix: Sentinel Node Wallet - BTCB2

**Date:** 2026-11-06  
**Architecture:** Apple Silicon (`arm64`)  
**macOS Target:** macOS 13.0+ (Ventura, Sonoma, Sequoia)

---

## 1. Test Execution Summary

| Test Suite | Framework | Target / Test File | Test Count | Result | Execution Time |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Adaptive ETA Formatting & States** | Swift XCTest | `AdaptiveETATests.swift` | 2 | **PASS** | 0.001s |
| **BIP-110 Consensus & Checkpoints** | Swift XCTest | `ConsensusTests.swift` | 4 | **PASS** | 0.001s |
| **Hashrate Tracker & Anomaly Defense** | Swift XCTest | `HashrateTrackerTests.swift` | 3 | **PASS** | 0.001s |
| **Isolation & Zero-Leak Auditing** | Swift XCTest | `IsolationSecurityTests.swift` | 4 | **PASS** | 0.001s |
| **Subprocess Perms & Fork Rejection** | Swift XCTest | `NodeSubprocessIntegrationTests.swift` | 2 | **PASS** | 0.003s |
| **1-Click Adoption & Mainnet RPC** | Swift XCTest | `OneClickIntegrationTests.swift` | 1 | **PASS** | 0.008s |
| **Compact 550M & Archival 1TB Gates**| Swift XCTest | `StorageModeTests.swift` | 2 | **PASS** | 0.001s |
| **Profile Presets & bitcoin.conf** | Swift XCTest | `SyncProfileTests.swift` | 2 | **PASS** | 0.001s |
| **Host System Health (Disk & Power)** | Swift XCTest | `SystemHealthTests.swift` | 2 | **PASS** | 0.020s |
| **Keychain Passphrase & Send Gating**| Swift XCTest | `WalletIntegrationTests.swift` | 3 | **PASS** | 0.027s |
| **Deterministic ETA Trajectory** | Python 3 | `tools/test_eta_engine.py` | 3 | **PASS** | 0.001s |
| **Governance & Topic Compliance** | Python 3 | `tools/verify_governance.py` | 3 | **PASS** | 0.008s |
| **Secret & Cross-Project Isolation** | Shell / Regex | `scripts/secret_scan.sh` | 4 | **PASS** | 0.012s |

**Total Tests:** 35 / 35 Passed (0 Failures, 0 Regressions)

---

## 2. Release Gate Status Matrix

| Release Gate | Gate Description | Target Verification | Status in v0.1.0 Dev Build |
| :--- | :--- | :--- | :--- |
| **Gate 1** | Clean-Room Consensus Tests | 25/25 Swift XCTest & Python suites passing | **PASS** (Local arm64) |
| **Gate 2** | Secret & Isolation Audit | Zero credentials, private keys, or cross-project leaks | **PASS** (`secret_scan.sh`) |
| **Gate 3** | Discrete Prune Storage Protection | 550 MiB default, warn at 35 GB, stop at $\le 10$ GB free | **PASS** (`StorageModeTests`) |
| **Gate 4** | Adaptive ETA Engine | Multi-window smoothing, auto-scaled unit formatting | **PASS** (`AdaptiveETATests`) |
| **Gate 5** | Apple Developer ID Signing | Valid Apple Developer ID certificate code sign | **BLOCKED (Operator Credentials Needed)** |
| **Gate 6** | Apple Notarization & Stapling | `xcrun notarytool` ticket stapled to DMG | **BLOCKED (Operator Credentials Needed)** |
| **Gate 7** | Gatekeeper Qualification | Clean execution under macOS Gatekeeper default policy | **BLOCKED (Awaiting Gate 5 & 6)** |
| **Gate 8** | Sparkle Update Infrastructure | EdDSA signed delta release appcast | **BLOCKED (Awaiting Release Key)** |
| **Gate 9** | Independent Security Audit | Third-party cryptographic & descriptor wallet review | **BLOCKED (Scheduled Post-Alpha)** |
