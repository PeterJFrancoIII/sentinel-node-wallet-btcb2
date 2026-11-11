# Privacy Policy — Sentinel Node Wallet

> **Effective Date:** November 11, 2026  
> **Repository:** [PeterJFrancoIII/sentinel-node-wallet-btcb2](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2)  
> **Application Identifier:** `app.nodepocket.btcb2`

Sentinel Node Wallet is engineered from the ground up for user sovereignty, decentralization, and privacy. This Privacy Policy outlines what information is processed by the application and how that data is handled.

---

## 1. Zero Personal Data Collection & Zero Telemetry

- **No User Tracking:** Sentinel Node Wallet does not collect, record, transmit, or monetize any personally identifiable information (PII).
- **No Analytical SDKs:** There are zero third-party analytics trackers, crash-reporting SDKs, advertising frameworks, or behavior-monitoring services embedded within the application.
- **No User Accounts:** You do not create an account with any centralized service to use Sentinel Node Wallet.

---

## 2. Local Node & Network Architecture

- **Local RPC Communications:** Sentinel Node Wallet interacts with your Bitcoin Knots node via local loopback Remote Procedure Calls (`127.0.0.1`) authenticated via local random cookie credentials. Node management commands, blockchain status queries, and wallet descriptor balance lookups never leave your local machine.
- **Peer-to-Peer Blockchain Network:** The embedded Bitcoin Knots daemon connects to the decentralized peer-to-peer Bitcoin network over standard Bitcoin protocol sockets to synchronize block headers, blocks, and mempool transactions. This peer communication is inherent to running a decentralized blockchain node.

---

## 3. External Pricing Services (Market Valuation)

To display estimated fiat valuations (USD) alongside cryptocurrency balances:
- The app queries public, unauthenticated exchange rate endpoints:
  - `neoxa.exchange` (`/api/exchange/ticker/BTCB2_USDC`)
  - `api.nonkyc.io` (`/api/v2/ticker/BTCB2_USDT`)
- **Privacy Protections for Price Queries:**
  - These requests are strictly read-only public market ticker queries.
  - Zero wallet addresses, balances, transaction details, IP metadata linkage, or user credentials are ever transmitted to pricing endpoints.

---

## 4. Local Credential & Wallet Storage

- **Local Descriptor Wallets:** Wallet descriptors and blockchain chainstate are stored strictly within the local macOS application support directory (`~/Library/Application Support/NodePocketBTCB2/`).
- **macOS Keychain:** Operator credentials and wallet passphrases are stored in the local macOS Keychain using Apple's Secure Enclave and system Access Control Lists.
- **Apple Passwords Integration:** If enabled, operator credentials may utilize Apple's system Saved Passwords provider locally on macOS.

---

## 5. Security & Fail-Closed Protection

- **On-Chain Broadcasting Hold:** Transaction sending and fee broadcasting remain fail-closed pending consensus signature audits.
- **Destructive Deletion Hold:** Wallet deletion is locked to prevent accidental loss; local archive options are provided.

---

## 6. Contact & Support

For issues, bug reports, or questions regarding this Privacy Policy:
- GitHub Issues: [https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/issues](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/issues)
- Source Repository: [https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2)
