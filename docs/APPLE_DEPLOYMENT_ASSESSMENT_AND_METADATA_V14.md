# Apple Deployment Assessment & App Store Connect Metadata Specification (v14)

> **Canonical Operating Authority:**  
> `Shared Memory MCP Rules: https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md`  
> Directives Reference: `MSG:SENTINEL-NODE-WALLET-APPLE-DEPLOYMENT-HANDOFF-20261110-GPT6-083`, `MSG:SENTINEL-NODE-WALLET-APPLE-REVIEW-CORRECTION-20261111-GPT6-085`, `MSG:SENTINEL-NODE-WALLET-APPLE-PRIVACY-REVIEW-20261111-GPT6-087`

---

## 1. Executive Summary & Audit Baseline

In accordance with owner directives and architect reviews `#083`, `#085`, and `#087`, this document provides the verified local inventory, release channel qualification, App Store Connect metadata staging, privacy disclosures, and screenshot assets for **Sentinel Node Wallet** (`app.nodepocket.btcb2`).

- **Repository:** `PeterJFrancoIII/sentinel-node-wallet-btcb2`
- **Branch:** `fix/v13-1-security-remediation-20261107`
- **PR:** [#10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10)
- **CI Status:** GitHub Actions Run [#42963988133](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42963988133) — **SUCCESS (GREEN)**.
- **Security Posture:** Transaction broadcast and destructive wallet deletion remain strictly **FAIL-CLOSED** (`signingPathUnverified`) pending independent consensus signing audit ($0.00 spent).

---

## 2. Local Credential & Signing Inventory (Read-Only)

### A. Apple Developer API Key Folder
- **File:** `AuthKey_<KEY_ID>.p8` (257 bytes, PKCS#8 ECDSA private key in authorized local folder).
- **Download Provenance:** Downloaded directly via Safari from `appstoreconnect.apple.com`.
- **Key Type & Authentication Evaluation:**
  - Evaluated against official Apple documentation for both **Team Keys** and **Individual Keys**.
  - Testing an Individual Key JWT structure (`"sub": "user"`, `"aud": "appstoreconnect-v1"`, with and without `"scope": ["GET /v1/apps"]`) returned HTTP `401 Not Authorized`.
  - Testing a Team Key JWT structure without the portal Issuer ID returned HTTP `401 Not Authorized`.
  - **Conclusion:** The key was generated under *Users and Access → Integrations → App Store Connect API* as a Team Key. It requires the account's **Issuer ID** (UUID format `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` displayed at the top of that portal page) to authenticate programmatic REST API calls.

### B. TimeProof Reference Project (Read-Only)
- **Public Team ID:** `S8QMQZA656`
- **Team Type (Xcode):** `Individual` (`isFreeProvisioningTeam = 0; teamID = S8QMQZA656; teamType = Individual;`)
- **Bundle ID Reference:** `com.PeterJFrancoIIILLC.TimeProof`

### C. Host Code Signing Certificate Verification
- Inspected installed identity: `"Apple Development: [REDACTED_EMAIL] ([REDACTED_USER_ID])"`
  - **X.509 Certificate Subject:**
    `UID=[REDACTED], CN=Apple Development: [REDACTED_EMAIL] ([REDACTED_USER_ID]), OU=S8QMQZA656, O=[REDACTED_NAME], C=US`
  - **Verification:** The Organizational Unit (`OU=S8QMQZA656`) exactly matches Team ID `S8QMQZA656`. The alphanumeric suffix in the Common Name is the developer user identifier, not a divergent team identifier.
  - **Distribution Identities:** Neither a `Developer ID Application` nor an `Apple Distribution` identity is currently installed in the Keychain on this Mac.

---

## 3. Release Channel Qualification & Regulatory Analysis

### Channel A: Mac App Store (MAS)
- **Apple App Store Review Guideline 3.1.5(i) (Cryptocurrency Wallets):**
  > *"Wallets: The app may facilitate transmission of approved virtual currencies, provided that it may only be offered in countries or regions where the developer has appropriate licensing and permissions to do so, and the app must be submitted by an organization, not an individual developer."*
- **Regulatory Gate:** Developer account `S8QMQZA656` is currently registered as an **Individual** account (`teamType = Individual`).
- **Remediation Required for MAS:** The owner must convert the Apple Developer account from Individual to **Organization** (e.g. `Peter J. Franco III LLC`, requiring D-U-N-S verification).
- **Technical Sandbox Barrier:** Mac App Store mandates `com.apple.security.app-sandbox`. Running an embedded full Bitcoin Knots daemon (`bitcoind`) with local peer P2P sockets and blockchain datadir within MAS App Sandbox requires specific network client/server entitlements and security-scoped bookmark architecture.

### Channel B: Developer ID Notarized Outside-Store Distribution (DMG)
- **Eligibility:** Eligible for Individual accounts once distribution certificates and notarization credentials are provisioned.
- **Guideline 3.1.5(i) Applicability:** Does **not** apply to outside-store Developer ID notarization.
- **Sandboxing:** Uses macOS Hardened Runtime (`--options runtime`) without App Sandbox constraints, allowing embedded `bitcoind` full native execution.
- **Automated Pipeline:** Scripted in `scripts/build_production_dmg.sh`.
- **Prerequisites for DMG Signing:**
  1. Generate and install a `Developer ID Application` certificate in Keychain.
  2. Configure notary credentials via `xcrun notarytool store-credentials "notarytool-profile" --apple-id ... --team-id S8QMQZA656`.
  3. Serve Apple App Site Association (AASA) JSON for `webcredentials:S8QMQZA656.app.nodepocket.btcb2` over the approved HTTPS domain.

---

## 4. App Store Connect & Storefront Metadata (Staged)

Derived strictly from truthful, current runtime functionality without unverified claims:

### General Information
- **App Name:** `Sentinel Node Wallet`
- **Subtitle:** `Bitcoin Knots Node & Wallet` (28 characters, limit 30)
- **Primary Category:** `Finance`
- **Secondary Category:** `Utilities`
- **Bundle ID:** `app.nodepocket.btcb2`
- **SKU:** `SENTINEL-NODE-WALLET-BTCB2`
- **Pricing:** Free (Tier 0)
- **Copyright:** `© 2026 Peter J. Franco III. All rights reserved.`

### Description
```text
Sentinel Node Wallet is a native macOS application engineered for running and managing an authentic Bitcoin Knots node with integrated local wallet monitoring.

Designed for sovereignty and privacy, Sentinel Node Wallet bundles and pins the Bitcoin Knots node daemon (v29.4.3) directly on your Mac, allowing you to validate the blockchain locally without relying on external hosted full nodes.

KEY CAPABILITIES:
• EMBEDDED BITCOIN KNOTS DAEMON: Automatic adoption and management of local bitcoind, displaying live block synchronization progress, peer connections, and pruned storage metrics.
• CONSENSUS NETWORK HASHRATE TRACKER: Real-time 30-block difficulty trend and 120-block smoothed network hashrate analytics, computed entirely from local block headers with an interactive 30-sample sparkline history.
• LOCAL ACCOUNT SECURITY: Protected by local operator authentication using salted password verifiers stored in a restricted local registry, with optional Keychain custody for wallet passphrases and 2FA secrets.
• LOCAL WALLET INVENTORY: Track receiving addresses, transaction history, and wallet confirmations with zero external tracking.
• FAIL-CLOSED SECURITY: On-chain transaction broadcast and destructive wallet deletion remain fail-closed pending consensus SIGHASH audit. Balance tracking and receiving are fully functional.

NETWORK & PRIVACY DISCLOSURE:
Sentinel Node Wallet communicates strictly over local loopback RPC (127.0.0.1) to your local Bitcoin Knots daemon. Zero wallet addresses, private keys, or personal telemetry are transmitted to external servers. To provide estimated USD fiat valuations, the app performs read-only public market ticker queries against public exchange endpoints (neoxa.exchange and api.nonkyc.io) without sending user identifiers or wallet balances; client network egress IP address is visible to remote services via standard TCP/IP.
```

### Keywords (89 / 100 characters)
```text
bitcoin,knots,node,btcb2,hashrate,crypto,blockchain,wallet,pruned,consensus,mining,monitor
```

### Promotional Text
```text
Run a bundled Bitcoin Knots node natively on macOS with real-time local consensus hashrate analytics and secure wallet monitoring.
```

### URLs & Support
- **Support URL:** `https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/issues`
- **Marketing URL:** `https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2`
- **Privacy Policy URL (Verified Permanent / HTTP 200):**  
  `https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/blob/main/docs/PRIVACY.md`

### App Privacy Questionnaire
- **Data Collection:** No personal data or user identity collected.
- **Telemetry:** Zero third-party analytics trackers, zero advertising frameworks.
- **Network Access:**
  - Localhost loopback RPC (`127.0.0.1`) for wallet and node management.
  - Peer-to-peer Bitcoin protocol sockets for decentralized blockchain synchronization (client IP visible to network peers).
  - Optional read-only public exchange pricing tickers (`neoxa.exchange`, `api.nonkyc.io`) for fiat estimates (client IP visible to web endpoints; zero wallet data sent).

### Export Compliance & Cryptography
- **Uses Encryption:** Yes (Standard system TLS/HTTPS and CryptoKit/CommonCrypto).
- **Classification:** Subject to owner export compliance self-classification for standard operating system cryptography.

---

## 5. Authentic macOS Screenshot Matrix (2880 x 1800 RGB)

Generated from live, unmanipulated native SwiftUI window captures on macOS (Retina 2x resolution, framed on standard 2880 x 1800 sRGB canvas, flattened without alpha channel per App Store guidelines):

| Asset Filename | Dimensions | Color Space | Alpha | Description |
| :--- | :---: | :---: | :---: | :--- |
| `01_Sentinel_Node_Status_2880x1800.png` | 2880 × 1800 | RGB | None | Live Node status: 100.00% sync, block 981,450+, 4 peers, pruned 550MB, Ultra mode. Zero PII. |
| `02_Sentinel_Network_Hashrate_2880x1800.png` | 2880 × 1800 | RGB | None | Live Network view: 46.85 PH/s 30-block trend, 45.34 PH/s 120-block smoothed, 30-sample sparkline. Zero PII. |
| `03_Sentinel_Wallet_Authentication_2880x1800.png` | 2880 × 1800 | RGB | None | Operator authentication view: Local Keychain protection and user-presence authorization. Scrubbed demo identity. |

*Local artifact directory:* `dist/app_store_screenshots/`

---

## 6. Security Gates & Release Matrix Status

- **Spend / Broadcast:** `FAIL-CLOSED` (`signingPathUnverified`). Real mainnet funds cannot be spent ($0.00 risk).
- **Wallet Deletion:** `HARD-DISABLED`. Destructive deletion blocked; non-destructive Archive enabled.
- **Local Node Daemon:** Running synchronized at block 981,450+; undisturbed.
- **Operator Wallet:** Untouched, isolated, and locked.
