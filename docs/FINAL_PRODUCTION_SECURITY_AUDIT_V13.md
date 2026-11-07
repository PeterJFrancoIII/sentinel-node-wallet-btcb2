# Final production security audit, source cleanup and release matrix — v13

**Product:** Sentinel Node Wallet - BTCB2 | 3 native SwiftUI tabs: Node, Wallet, Network  
**Execution order:** review + merge v12 correctly (especially Ultra=4), implement and verify [final login/2FA](FINAL_WALLET_AUTH_V13.md), **FREEZE features**, conduct this exhaustive audit, remove proven unsafe/unnecessary code with tests, and only then consider signed/notarized public delivery.  
**Default verdict:** **BLOCKED / development only** until every P0 gate has documented PASS. A claimed passing test count, GitHub PR merge, DMG hash or Apple notarization is not itself evidence that funds are secure.  
**Non-negotiable:** No user fund transfers, live funded-wallet deletion, live user wallet restoration over a working wallet, chainstate destruction, DATUM, pools, mining, alternative chains, or unrestricted remote RPC during test/cleanup.

## Review of actual GitHub handoff / code (2026-11-06)

- PR #4 (pruned consensus + rolling history) is merged in main at `cb47d2f91a16373e822c8083e021dd5e9e7a9805`.
- Gemini's v12 receipt `SENTINEL-ULTRA-WALLET-UI-V12-RECEIPT-20261106-024` reported source at `dbc169a`. PR #5 is still OPEN, not a verified production deployment. Its receipt reports **Ultra maxconnections=12**; owner's later authoritative override `SENTINEL-ULTRA-CORRECTION-20261106-024` demands **4**, with `listen=0` and background CPU/disk I/O scheduling. Reconcile source, tests, docs and Mac evidence before release.
- On current main, `WalletManager.prepareSendPreview`, `executeAuthorizedSend` and legacy `send` are intentionally **fail-closed** with `signingPathUnverified`. Therefore **real-money sending is NOT IMPLEMENTED/APPROVED**. Do not turn this guard off merely to make UI work. Actual BLAKE2b `SIGHASH_UNIFIED` replay-safe signing and genuine funded PSBT with authorization bind require separate cryptographic audit.
- On current main, `KeychainHelper.savePassphrase` falls back from `SecAccessControl.userPresence` after `-50 / -34018` to a weaker `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` item and `getPassphrase` can retry retrieval without the `LAContext`. This is a concrete **P0 security regression** that needs removal/rework with real Developer ID signing/entitlement diagnostics and seamless **reversible** handling of previously created items. A fallback is not evidence that per-send user presence is enforced.
- On current main, `BitcoinRPCClient.walletPassphrase` and `walletLock` use `try?` patterns that can suppress important errors. Fix or prove return-value decoding and enforce guaranteed relock on every signing exception/cancel/timeout.
- On current main, `scripts/fetch-verify-knots.sh` prints a binary-verification heading, fetches a SHA256SUMS.asc if available, and checks only for locally installed `bitcoind`. It **does not authenticate signatures or verify the embedded binary's SHA256**. This is a release-blocking supply-chain assurance gap; implement real Knots fingerprint/signature or signed manifest verification before packaging.
- On current main, `scripts/build_app.sh` uses ad-hoc `codesign --sign -`. This can support local development, but is **not Developer ID signature/notarization**. All embedded executable signatures, hardened runtime, entitlements and Gatekeeper require real release proof.
- On current main, `Sources/NodePocketApp/Views/ContentView.swift` contains a toolbar Settings gear. NodeView may have a separate Settings affordance depending on v12 branch; verify a **single** Settings control in the actual installed app, not just one source file.
- On current main, `WalletManager.generateRegtestBlocks` and `BitcoinRPCClient.generateToAddress` exist in source although the product is MainNet-only. Confirm references; if unneeded at runtime, remove or confine to test-only mocks without breaking tests. These are **unnecessary exposure candidates, not evidence of malware**.
- On current main, `Sources/NodePocketCore/Isolation/SecurityAuditor.swift` performs substring-based isolated-project/secret checks. It is not a general malicious-code scanner, dependency audit or binary provenance proof. Do not equate passing its tests with no malicious code.

## Mandatory audit tracks — each needs owner-verifiable evidence

| Track | Test / repair | Release decision |
| --- | --- | --- |
| **Authentication** | Full local username/password/TOTP enrolled, no default account, safe credential verifier/attempt throttling, Apple Passwords domain/signing and actual save/autofill; unlock blocked before login | P0 |
| **Device owner protection** | Keychain item `userPresence` enforced, -34018/-50 fail-closed, Touch ID/device-owner deny/cancel/timeout, no bypass through fallback or direct RPC | P0 |
| **Knots executable** | Authenticate signed version-specific BLAKE2b Knots archive and its signer+sha, no substitution from system PATH; independent fork hash 961640 and later trusted checkpoint plus fresh tip | P0 |
| **Spending** | Fully verified BTCB2 `SIGHASH_UNIFIED`, PSBT funded fee, exact sat arithmetic, immutable destination/fee/change preview, allowlist and fresh per-send approval; fail closed otherwise | P0 |
| **Wallet creation** | Encrypted descriptor wallet creation, named wallet, Apple Keychain password save/retrieval and duplicate/timeout recovery on installed Mac | P0 |
| **Wallet inventory** | All on-disk wallets by name, correct wallet-scoped balances, freshness and no cross-wallet RPC/account mix | P0 |
| **Archive/restore/delete** | Archive reversible/unload, encrypted backup independently restore-verified, no deletion with any nonzero/unknown balance, typed consent/owner auth, app-owned path only and macOS Trash rollback | P0 |
| **Storage & IBD** | 2048MiB new-install prune, 550MiB during IBD, preserve existing 550/custom/archive choices, no accidental historical redownload, total disk peak/alerts/stop | P0 |
| **Peers and network** | Current inbound/outbound/max truth, block/tx relay, `natpmp=0`/`upnp=0`, no RPC outside 127.0.0.1 and no unauthorized port mapping | P0 |
| **Ultra Battery/Charging** | Exactly **4 maximum peers**, `listen=0`, low process CPU + disk IO scheduling, cache 128–256MiB empirically tuned, stable restoration, no repeated restart loops, unchanged prior preferred mode | P0 |
| **Node sync/consensus** | OEM BLAKE2b correct node, pre-/post-activation proof, real consensus validation, strict fork fail-close, IBD progress and timeline, no false 100% | P0 |
| **Rolling coverage** | Local pruneheight/oldest/tip timestamps and block bytes; calibrated 550/1024/2048/4096/custom dynamic units; no false insurance/deep-reorg claims, minimal RPC | P1 |
| **Wallet economics** | Coinbase maturity 100/6480/25920 origin-height and 2027 MTP expiry with reorg; spendable/pending/immature balances; correct node trusted funds | P0 |
| **Fiat quotes** | Two independent public NonKYC/NeoxEX BTCB2→USDC/USDT feeds, bid/ask/volume/freshness, USD indicative proxy/depeg warning, no fake live last price or wallet-data leakage | P1 |
| **TX history/explorer** | Complete wallet available history, pagination, RBF/conflict/reorg labels, correct BTCB2 `mempool.guide` link only on deliberate click, not ordinary BTC explorer | P1 |
| **Software updater** | Only trusted signed app release updates; Knots upgrades separately present consensus-affecting release notes and require explicit approval, verify full signature and rollback/prune compatibility. Never install prerelease automatically | P0 |
| **Production macOS binary** | Real Apple Developer ID signed app+Knots, hardened runtime and authorized Keychain/associated-domain entitlements, notarized and stapled DMG, `spctl`/Gatekeeper fresh-machine verification, signed updater | P0 |
| **Minimalism and privacy** | No miner/pool/DATUM/server, no web wallet, no unrelated services, no telemetry/secret uploads, no unnecessary TestNet/RegTest execution commands or unused shipped runtime | P0 |
| **Open-source/release legal** | Explicit owner-approved `LICENSE`, Knots license and bundled third-party notices, SBOM/provenance and redistributable rights | P0 |

## Source/supply-chain and malicious-code review: zero trust, no careless deletion

1. **Inventory everything shipped:** all Swift source, npm/Python/shell tools even if dev-only, GitHub Actions, packages, compiled bundle entitlements/resources, binaries, dynamic libraries, extra launch agents, update URLs, DNS/explorer/exchange endpoints, Xcode signing profiles and macOS background tasks. Generate a reproducible bill of materials by SHA/license/origin.
2. **Review code paths and dependencies:** unexpectedly broad file I/O, reads outside the dedicated application directory, unsafe shell or command composition, `Process` spawns, dynamic loading, reflection, `eval`-like execution, URLSession hosts, unexpected POST/UPLOAD calls, hardcoded secrets or telemetry tokens, clipboard/pasteboard exfiltration, hidden dev menus/test-only RPC exposure, unbounded network listener, permissions changes, insecure backup/export, wallet credential copying, unreviewed binary auto-downloader, bot/mining/DATUM imports. Classification must be supported by code evidence; don't falsely accuse a legitimate dependency of malware.
3. **Validate provenance:** every upstream executable and binary library against an authenticated signed release/checksum, with pinned version and signer; check build scripts/CI for supply-chain substitution and self-update signature skip, no `curl | sh` or arbitrary fetched code on user machines. Run independent malware scanning on final build, but **a scanner pass is not proof of safety**.
4. **Secrets and history:** detect real private keys, seed phrases, wallet.dat, rpc cookies, account/TOTP verifier seeds, static passwords, address books, developer signing keys and user telemetry in Git history/CI/dist and generated assets; revoke if exposed and purge only after secure user-controlled remediation. Do not print secret values in audit receipts.
5. **Reachability and removal:** for every suspicious/non-essential symbol/file, classify **REQUIRED / DEVELOPMENT-ONLY / DEAD / UNVERIFIED** with a clear caller map. Remove or compile-gate only **proven dead/unsafe** runtime code, in reviewed minimal commits, with regression tests and rollback. Candidate examples: testnet/regtest mining RPC helpers, secretless stub code, unused routes, stale duplicate Settings buttons, fake historical/price placeholders. Do not touch wallet datadir, Keychain, chainstate, backups or user-owned files.
6. **Least privilege:** app sandbox choice consistent with user-approved filesystem/Knots backend; only required associated-domain/Keychain entitlements, strictly local RPC cookie file, OS-permission checks. No remote RPC, LAN control-plane or broad inbound firewall changes.
7. **Independent manual review:** a reviewer other than the author inspects security-sensitive code paths, verifying wallet signing is genuinely replay safe, Keychain hardware consent, local login gates, backup restoration, binary verification and no silent escalation. Document limitations for fully compromised user/root host.

## Execution protocol and receipts

**Stage A — PR reconciliation:** verify PR #4 already merged, review PR #5 (open) and fix Ultra=12→**4**, safe archive/delete, UI duplication. Merge code only after native Mac proof, preserving existing saved wallet/IBD/prune. Avoid editing the original private Admin Console or pool.

**Stage B — Final feature v13:** implement [Wallet Authentication](FINAL_WALLET_AUTH_V13.md) as a **separate small PR** rebased on validated v12. Add no extra process, web backend or datadir and no unrelated feature. Show full identity and TOTP recovery/Apple credential end-to-end evidence.

**Stage C — Freeze and test:** lock feature scope, run clean Swift release/Debug builds and the macOS/XCTest/QA suite; deterministic local test doubles for danger paths and **real hardware tests on an empty authorized wallet**. Exercise every row above including intentionally invalid inputs, RPC 401, no node, disk low, battery transitions, sleep/wake, rejected signed update, dead P2P peer and wrong chain. Preserve MainNet production wallet data; no real user funds may move.

**Stage D — Surgical cleanup:** apply only code-evidenced removals, rerun all tests, review before/after diff and redacted secret scan; release candidate hash changes => rerun signing/notarization/QA.

**Stage E — Release gates:** real signed app, embedded fork-specific bitcoind and updater with authenticated provenance; test fresh user macOS account, offline/low-power conditions, existing wallet migration/restore, Gatekeeper and AASA/Apple Passwords on the actual signed artifact. Run at least one independent security code review. NO P0 outstanding.

**Required evidence receipt:**
- full git SHA/branch/PRs; macOS/Xcode/Swift version; bundled bitcoind version, signed archive & SHA/signature proof; Node process PID and fork/checkpoint validation with redacted logs.
- test command, total/pass/fail/skip counts; native device owner prompts observed, Apple Passwords save/OTP autofill pass or explicit environment-blocked status; all-wallet inventory and empty test wallet restore; 4-peer Ultra resource metrics.
- complete source file/dependency inventory and removed-code diff; SBOM and secret scan with zero leaked material; app/DMG notarization and Gatekeeper verification; license and dependency audit; update release notes consent, full backup/migration tests.
- per test line **PASS / FAIL / NOT RUN / BLOCKED**, with responsible issue and actual evidence. A skipped hardware test must NEVER be counted as passed. No screenshots with keys, account TOTP or private wallet data.

**Do not claim 'malicious code removed', 'security perfect', 'verified all surfaces' or 'production ready' without the actual audit. A username/password/TOTP screen alone is not evidence that wallet signing or unauthorized local RPC access is safe.**
