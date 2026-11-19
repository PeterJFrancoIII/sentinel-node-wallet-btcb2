# Sentinel Node Wallet (BTCB2 / XBT) — Release Candidate

### Production macOS Apple Silicon Release (.DMG)

Sentinel Node Wallet is an autonomous, self-sovereign Bitcoin Knots node and multi-operator wallet built natively in Swift for Apple Silicon macOS (13.0+).

---

## 🌟 Highlights & New Features

### 1. 🔄 Built-in Secure Sparkle 2 Auto-Updater
- **Native macOS Menu Integration:** Direct access via `Sentinel Node Wallet > Check for Updates…` and `Help > Check for Updates…`.
- **Dedicated Software Updates Panel:** Full visibility into installed build version, architecture, release channel, and check frequency.
- **Strict User Consent:** Silent background installation is strictly prohibited. Operators are always prompted to review release notes and confirm before any update is applied.
- **Daemon Safety:** The updater enforces strict busy guards: updates are deferred if blockchain synchronization or wallet operations are active, and Bitcoin Knots is shut down gracefully before replacing binaries.

### 2. 🔐 Hardened Release & Credential Boundaries
- **Keychain Isolation:** Independent custom Keychain service namespaces preventing any cross-wallet or cross-operator credential collisions.
- **Atomic Deletion / Purge CAS:** Point-of-no-return intermediate staged state ensuring that account purge operations are completely fail-closed and cannot be intercepted or partially executed.
- **Hardware User Presence:** Per-send and per-action local biometric / Touch ID authorization enforcement.

---

## 📦 Binary Verification & Consensus Invariants

- **Pinned Bitcoin Knots Core:** `29.4.3.knots20260508` (ARM64 Apple Silicon)
- **Minimum macOS Version:** macOS 13.0 (Ventura) or newer
- **Consensus Rule:** Replay-protected BTCB2 network consensus validator
- **Architecture:** Mach-O thin arm64
