# Security Policy: Sentinel Node Wallet - BTCB2

## 1. Security Architecture & Threat Model

Sentinel Node Wallet enforces strict defense-in-depth isolation across multiple levels:

### Local Loopback Enforcement
- Embedded Bitcoin Knots `bitcoind` binds strictly to `127.0.0.1` (`rpcbind=127.0.0.1`, `rpcallowip=127.0.0.1`).
- P2P networking operates strictly outbound by default (`listen=0` or restricted inbound) to avoid exposing the host machine as an open routing relay.
- All remote network RPC ingress is disabled.

### Keychain-Backed Key Management
- Wallet descriptors and master seed credentials are encrypted on disk.
- Passphrases are stored in macOS Keychain Services under access group `app.nodepocket.btcb2.wallet` only with explicit operator consent.
- Passphrases are never written to disk in plaintext files.

### File Permissions & Filesystem Isolation
- Application Support Directory: `~/Library/Application Support/NodePocketBTCB2` is created with POSIX permission `0700` (owner read/write/execute only).
- Configuration Files: `bitcoin.conf` is written with POSIX permission `0600` (owner read/write only).

### Replay & Send Gating
- Transaction transmission interface is locked while Initial Block Download (IBD) is incomplete or before block height reaches BIP-110 hard-fork activation height `961,640`.

---

## 2. Reporting Security Vulnerabilities

If you identify a security vulnerability in Sentinel Node Wallet, please report it privately:
- Do NOT open a public GitHub issue.
- Contact the maintainers privately via encrypted channels or repository security advisory.
- Maintainers will acknowledge within 48 hours and coordinate remediation.
