# Apple Deployment Assessment & App Store Connect Metadata Specification (v14)

> **Canonical Operating Authority:**  
> `Shared Memory MCP Rules: https://github.com/PeterJFrancoIII/Shared-Cognitive-Memory-for-Cross-Platform-AI-Conversations/tree/main/docs/SHARED_MEMORY_AGENT_RULES.md`  
> Directives Reference: `MSG:SENTINEL-NODE-WALLET-APPLE-DEPLOYMENT-HANDOFF-20261110-GPT6-083`, `PRODUCTION_RELEASE_CHECKLIST.md`, `PROJECT_STATUS.md`

---

## 1. Executive Summary & Audit Baseline

In accordance with owner directive and architectural handoff `MSG:SENTINEL-NODE-WALLET-APPLE-DEPLOYMENT-HANDOFF-20261110-GPT6-083`, this document provides the comprehensive local read-only inventory, release channel qualification, App Store Connect metadata staging, and screenshot assets for **Sentinel Node Wallet** (`app.nodepocket.btcb2`).

- **Repository:** `PeterJFrancoIII/sentinel-node-wallet-btcb2`
- **Branch:** `fix/v13-1-security-remediation-20261107` (Head: `f17faec`)
- **PR:** [#10](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/pull/10)
- **CI Status:** GitHub Actions Run [#42941042667](https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/actions/runs/42941042667) — SUCCESS (132 passed, 0 failed, 1 Keychain interactive skip).
- **Security Posture:** Transaction broadcast and destructive wallet deletion remain strictly **FAIL-CLOSED** (`signingPathUnverified`) pending independent consensus signing audit ($0.00 spent).

---

## 2. Local Credential & Signing Inventory (Read-Only)

### A. Apple Developer API Key Folder
- **Path:** `/Users/computer/App Development/Apple Developer/API Key`
- **File:** `AuthKey_C9XYR2HH83.p8` (257 bytes, PKCS#8 ECDSA private key).
- **Key ID:** `C9XYR2HH83`.
- **Download Provenance:** Downloaded directly via Safari from `appstoreconnect.apple.com` on `2026-11-10 22:22 EST`.
- **App Store Connect REST API Status:**
  - An App Store Connect API token requires both the Key ID (`C9XYR2HH83`) and the organization's **Issuer ID** (UUID format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`).
  - The Issuer ID is displayed on the App Store Connect web portal under *Users and Access → Integrations → App Store Connect API*.
  - Candidate Xcode UUIDs (`DE82A39A-00AD-4CB0-86DC-ADD0ABC9664E` and `943F31B0-C4EE-4E77-9F8E-AEA1F42915F9`) return HTTP 401 Not Authorized against `https://api.appstoreconnect.apple.com/v1/apps`. Programmatic REST API automation requires the exact Issuer ID UUID from that portal page.

### B. TimeProof Reference Project (Read-Only)
- **Path:** `/Users/computer/App Development/TimeProof/TimeProof (App Store)/Current/TimeProof_1.3.1_Release`
- **Archive:** `TimeProof-1.3.1-202611080001-verified.xcarchive`
- **Public Team ID:** `S8QMQZA656`
- **Team Name:** `Peter Franco`
- **Team Type (Xcode):** `Individual` (`isFreeProvisioningTeam = 0; teamID = S8QMQZA656; teamName = "Peter Franco"; teamType = Individual;`)
- **Signing Identity:** `Apple Development: Peter Franco (89V8F6QJC2)`
- **Entitlements:** Sandboxed (`com.apple.security.app-sandbox = true`), scope bookmarks, and read-write user-selected files.

### C. Host Code Signing Identities
- `security find-identity -v -p codesigning`:
  - `1) 2D5961BBD628EA81C8901392526869E29FDB7D37 "Apple Development: Peter Franco (89V8F6QJC2)"`
  - Valid identities found: 1 (Development only).
  - `Developer ID Application` identity: **Not currently installed in Keychain**.
  - `Apple Distribution` identity: **Not currently installed in Keychain**.

---

## 3. Release Channel Qualification & Regulatory Analysis

### Channel A: Mac App Store (MAS)
- **Apple App Store Review Guideline 3.1.5(i) (Cryptocurrency Wallets):**
  > *"Wallets: The app may facilitate transmission of approved virtual currencies, provided that it may only be offered in countries or regions where the developer has appropriate licensing and permissions to do so, and the app must be submitted by an organization, not an individual developer."*
- **Regulatory Gate:** Account `S8QMQZA656` is currently enrolled as an **Individual** account (`teamType = Individual`).
- **Remediation Required for MAS:** The owner must initiate an account conversion in Apple Developer Account settings from Individual to **Organization** (e.g. `Peter J. Franco III LLC`, requiring D-U-N-S verification).
- **Technical Sandbox Barrier:** Mac App Store mandates `com.apple.security.app-sandbox`. Running an embedded full Bitcoin Knots daemon (`bitcoind`) with local peer P2P sockets and database datadir within MAS App Sandbox requires specific network client/server entitlements and security-scoped bookmark architecture.

### Channel B: Developer ID Notarized Outside-Store Distribution (DMG)
- **Eligibility:** **100% Eligible** for both Individual and Organization accounts.
- **Guideline 3.1.5(i) Applicability:** Does **not** apply to outside-store Developer ID notarization.
- **Sandboxing:** Uses macOS Hardened Runtime (`--options runtime`) without App Sandbox constraints, allowing embedded `bitcoind` full native performance and isolated datadir management.
- **Automated Pipeline:** Fully scripted and validated via `scripts/build_production_dmg.sh`.
- **Prerequisites for DMG Signing:**
  1. Generate / install `Developer ID Application: Peter Franco (89V8F6QJC2)` certificate in Keychain.
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

Designed for sovereignty and privacy, Sentinel Node Wallet embeds a verified Bitcoin Knots node daemon directly on your Mac, allowing you to validate the blockchain locally without relying on third-party APIs or external hosted nodes.

KEY CAPABILITIES:
• EMBEDDED BITCOIN KNOTS DAEMON: Automatic adoption and management of local bitcoind, displaying live block synchronization progress, peer connections, and pruned storage metrics.
• CONSENSUS NETWORK HASHRATE TRACKER: Real-time 30-block difficulty trend and 120-block smoothed network hashrate analytics, computed entirely from local block headers with an interactive 30-sample sparkline history.
• PASSKEY & KEYCHAIN INTEGRATION: Protected by macOS Keychain and Passkey security, supporting operator credentials and Apple Passwords autofill.
• LOCAL WALLET INVENTORY: Track receiving addresses, transaction history, and wallet confirmations with zero external tracking.
• FAIL-CLOSED SECURITY: On-chain transaction broadcast and destructive wallet deletion remain fail-closed pending consensus SIGHASH audit. Balance tracking and receiving are fully functional.

Sentinel Node Wallet communicates strictly over local RPC to your Bitcoin Knots daemon. No user data, telemetry, or private keys are ever transmitted to external servers.
```

### Keywords (89 / 100 characters)
```text
bitcoin,knots,node,btcb2,hashrate,crypto,blockchain,wallet,pruned,consensus,mining,monitor
```

### Promotional Text
```text
Run a verified Bitcoin Knots node natively on macOS with real-time local consensus hashrate analytics and passkey-protected wallet monitoring.
```

### URLs & Support
- **Support URL:** `https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/issues`
- **Marketing URL:** `https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2`
- **Privacy Policy URL:** `https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/blob/main/docs/PRIVACY.md`

### App Privacy Questionnaire
- **Data Collection:** No data collected.
- **Telemetry:** Zero third-party trackers, zero analytical SDKs.
- **Network Access:** Localhost loopback RPC (127.0.0.1) and peer-to-peer Bitcoin protocol network sockets.

### Export Compliance & Cryptography
- **Uses Encryption:** Yes (Standard system TLS/HTTPS and CryptoKit/CommonCrypto).
- **Exemption:** Qualifies for US EAR ENC exemption (mass-market cryptographic software / standard operating system cryptography).

---

## 5. Authentic macOS Screenshot Matrix (2880 x 1800 RGB)

Generated from live, unmanipulated native SwiftUI window captures on macOS (Retina 2x resolution, framed on standard 2880 x 1800 sRGB canvas, flattened without alpha channel per App Store guidelines):

| Asset Filename | Dimensions | Color Space | Alpha | Description |
| :--- | :---: | :---: | :---: | :--- |
| `01_Sentinel_Node_Status_2880x1800.png` | 2880 × 1800 | RGB | None | Live Node status: 100.00% sync, block 981,450+, 4 peers, pruned 550MB, Ultra mode. |
| `02_Sentinel_Network_Hashrate_2880x1800.png` | 2880 × 1800 | RGB | None | Live Network view: 46.85 PH/s 30-block trend, 45.34 PH/s 120-block smoothed, 30-sample sparkline. |
| `03_Sentinel_Wallet_Authentication_2880x1800.png` | 2880 × 1800 | RGB | None | Operator authentication view: Passkey / Keychain protection and Apple Passwords autofill. |

*Local directory:* `/Users/computer/Developer/NodePocketBTCB2/dist/app_store_screenshots/`

---

## 6. Security Gates & Release Matrix Status

- **Spend / Broadcast:** `FAIL-CLOSED` (`signingPathUnverified`). Real mainnet funds cannot be spent ($0.00 risk).
- **Wallet Deletion:** `HARD-DISABLED`. Destructive deletion blocked; non-destructive Archive enabled.
- **Host Daemon:** PID 96536 / 54484 running synchronized at block 981,450+; undisturbed.
- **Operator Wallet:** `Kevin` untouched and locked.
