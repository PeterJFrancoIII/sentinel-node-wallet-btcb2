# Privacy Policy — Sentinel Node Wallet

> **Effective Date:** November 11, 2026  
> **Repository:** [PeterJFrancoIII/sentinel-node-wallet-btcb2](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2)  
> **Application Identifier:** `app.nodepocket.btcb2`

Sentinel Node Wallet is engineered for user sovereignty, decentralization, and privacy. This Privacy Policy accurately describes the network communications, data handling, and local storage practices of the application.

---

## 1. Zero Personal Data Collection & Zero Telemetry

- **No User Tracking:** Sentinel Node Wallet does not collect, record, transmit, or monetize any personally identifiable information (PII).
- **No Analytical SDKs:** There are zero third-party analytics trackers, crash-reporting SDKs, advertising frameworks, or behavior-monitoring services embedded within the application.
- **No Centralized User Accounts:** You do not create an account with any centralized entity to use Sentinel Node Wallet.

---

## 2. Local Node & Network Architecture

- **Local RPC Communications:** Sentinel Node Wallet interacts with your Bitcoin Knots node via local loopback Remote Procedure Calls (`127.0.0.1`) authenticated via local random cookie credentials. Node management commands, blockchain status queries, and wallet descriptor balance lookups never leave your local machine.
- **Peer-to-Peer Blockchain Network:** The embedded Bitcoin Knots daemon connects to the decentralized peer-to-peer Bitcoin network over standard Bitcoin protocol sockets to synchronize block headers, blocks, and mempool transactions. As with any blockchain peer-to-peer client, counterpart peer nodes on the network can observe your client egress IP address during socket connections.

---

## 3. External Pricing Services (Market Valuation)

To display estimated fiat valuations (USD) alongside cryptocurrency balances:
- The app performs read-only HTTP GET queries against public exchange endpoints:
  - `neoxa.exchange` (`/api/exchange/ticker/BTCB2_USDC`)
  - `api.nonkyc.io` (`/api/v2/ticker/BTCB2_USDT`)
- **Privacy Protections and Disclosures for Price Queries:**
  - **No Sensitive Payload:** Zero wallet addresses, balances, transaction histories, or user credentials are ever included in ticker queries or request payloads.
  - **Network Metadata Exposure:** Standard TCP/IP networking inherently exposes your client egress IP address, standard HTTP request headers, and request timing to the remote exchange hosting providers, subject to their respective privacy policies.

---

## 4. Local Credential & Wallet Storage

- **Local Operator Credentials:** Operator authentication utilizes salted, stretched password verifiers stored locally in a restricted file registry (`auth_registry.json`, permissions `0600`).
- **macOS Keychain Storage:** Time-based one-time password (TOTP) 2FA secrets are stored in the device-local macOS Keychain with user-presence protection (`kSecAccessControlUserPresence`).
- **Descriptor Wallet Passphrases:** Encrypted descriptor wallet passphrases can optionally be stored in the device-local Keychain at user choice (`storeInKeychain`), or entered manually upon wallet unlock.
- **Apple Saved Passwords Integration:** The application is architected to interface with system-level Apple Saved Passwords (`ASAuthorizationPasswordProvider`) where supported on compatible macOS versions with appropriate associated domain entitlements. Hardware Secure Enclave backing and Apple Passwords cloud-sync exclusion remain subject to local device configuration and signed app verification.

---

## 5. Security & Fail-Closed Protection

- **On-Chain Broadcasting Hold:** Transaction sending and fee broadcasting remain fail-closed pending consensus signature audits.
- **Destructive Deletion Hold:** Wallet deletion is locked to prevent accidental loss; local archive options are provided.

---

## 6. Contact & Support

For issues, bug reports, or questions regarding this Privacy Policy:
- GitHub Issues: [https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/issues](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/issues)
- Source Repository: [https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2)
