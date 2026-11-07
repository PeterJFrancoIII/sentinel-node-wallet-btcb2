# Project Governance & Release Architecture

**Project:** Sentinel Node Wallet - BTCB2  
**Repository:** `PeterJFrancoIII/sentinel-node-wallet-btcb2`  
**License:** MIT

---

## 1. Governance Principles

Sentinel Node Wallet is engineered as a sovereign, self-contained desktop validating node and non-custodial wallet for the BTCB2 BLAKE2b / BIP-110 network on macOS Apple Silicon.

1. **User Sovereignty:** Full local block validation from genesis; zero reliance on trusted third parties, hosted nodes, or cloud intermediaries.
2. **Apple Silicon First:** Optimized specifically for modern macOS architectures, preserving battery life and thermal headroom via dynamic profile management.
3. **Fail-Closed Security:** Incomplete consensus validation or chain divergences immediately lock transacting capabilities.
4. **Data Preservation:** Updates, migrations, and branding changes must preserve local wallet files, Keychain secrets, and downloaded block headers.

---

## 2. Release Gates & Public Distribution Policy

Before any binary release is made publicly available for broad download or production fund custody, the following release gates must be satisfied:

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

*Local development DMGs built with ad-hoc signing (`codesign --sign -`) are strictly for local testing on the operator's machine.*

---

## 3. Branching & Commit Discipline

- `main`: Protected trunk; requires all automated test suites to pass prior to merge.
- Release tags: Follow semantic versioning `vX.Y.Z` with detached SHA-256 checksums.
