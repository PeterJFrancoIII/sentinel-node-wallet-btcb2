# Contributing to Sentinel Node Wallet - BTCB2

Thank you for contributing to Sentinel Node Wallet.

## Development Guidelines

1. **Clean-Room Implementation:**
   - All contributions must be clean-room code developed under the MIT license.
   - Do not import code or dependencies from non-permissive sources or proprietary mining pools.

2. **Apple Silicon First:**
   - Code must build and execute natively on macOS Apple Silicon (`arm64`) using modern Swift (Swift 5.9+ / Swift 6.x) and SwiftUI.

3. **Strict Isolation & MainNet Focus:**
   - Shipped application code must strictly target the BTCB2 MainNet (BIP-110).
   - Never add alternate network toggles, testnets, or regtest modes to user-facing UI or production configuration builders.

4. **Testing Requirements:**
   - Run the complete test suite before submitting pull requests:
     ```bash
     swift test
     python3 tools/test_eta_engine.py
     python3 tools/verify_governance.py
     ./scripts/secret_scan.sh
     ```
   - Ensure all 25+ tests pass with zero regressions.
