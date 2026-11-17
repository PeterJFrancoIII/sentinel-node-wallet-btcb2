import Foundation
import NodePocketCore

@main
struct ReleaseLockVerifier {
    static func main() async {
        print("=== Sentinel Node Wallet BTCB2: Release Mode Broadcast Gate Verifier ===")

        // 1. Instantiate with isBroadcastRestricted: false
        let client = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "testuser",
            password: "testpassword",
            isBroadcastRestricted: false
        )

        // 2. Assert that in Release mode, isBroadcastRestricted unconditionally returns true
        print("Initial client.isBroadcastRestricted:", client.isBroadcastRestricted)
        guard client.isBroadcastRestricted == true else {
            fatalError("FAILURE: isBroadcastRestricted returned false in release binary!")
        }
        print("✓ Verified: isBroadcastRestricted evaluates to true upon instantiation.")

        // 3. Attempt to mutate isBroadcastRestricted to false
        client.isBroadcastRestricted = false
        print("After mutation attempt client.isBroadcastRestricted:", client.isBroadcastRestricted)
        guard client.isBroadcastRestricted == true else {
            fatalError("FAILURE: isBroadcastRestricted was mutated to false in release binary!")
        }
        print("✓ Verified: Mutation setter is discarded in release binary.")

        // 4. Verify negative spend gating on all 12 methods via generic call
        let spendMethods = [
            "sendtoaddress", "sendmany", "send", "sendall", "sendrawtransaction",
            "submitpackage", "bumpfee", "psbtbumpfee", "walletprocesspsbt",
            "signrawtransactionwithwallet", "signrawtransactionwithkey", "finalizepsbt"
        ]

        var blockedCount = 0
        for method in spendMethods {
            do {
                let _: String = try await client.call(method: method, params: [])
                fatalError("FAILURE: Method '\(method)' did not fail closed!")
            } catch let err as RPCClientError {
                if case .transactionBroadcastDisabled = err {
                    blockedCount += 1
                } else {
                    fatalError("FAILURE: Method '\(method)' threw unexpected RPCClientError: \(err)")
                }
            } catch {
                fatalError("FAILURE: Method '\(method)' threw unexpected error: \(error)")
            }
        }

        print("✓ Verified: Exactly \(blockedCount)/12 spend/signing RPC methods failed closed via generic call.")
        guard blockedCount == 12 else {
            fatalError("FAILURE: Expected 12 gated methods, got \(blockedCount)")
        }

        // 5. Verify high-level client helper methods fail closed
        do {
            _ = try await client.sendToAddress(address: "tb1qtestaddress0000000000000000000000000000", amount: 0.001)
            fatalError("FAILURE: sendToAddress helper did not fail closed!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: sendToAddress helper threw RPCClientError.transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: sendToAddress helper threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: sendToAddress helper threw unexpected error: \(error)")
        }

        do {
            _ = try await client.bumpFee(txid: "0000000000000000000000000000000000000000000000000000000000000000")
            fatalError("FAILURE: bumpFee helper did not fail closed!")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                print("✓ Verified: bumpFee helper threw RPCClientError.transactionBroadcastDisabled.")
            } else {
                fatalError("FAILURE: bumpFee helper threw unexpected RPCClientError: \(err)")
            }
        } catch {
            fatalError("FAILURE: bumpFee helper threw unexpected error: \(error)")
        }

        // 6. Verify read-only RPC is NOT blocked by broadcast restriction
        do {
            _ = try await client.getBlockchainInfo()
            fatalError("Unexpected success on closed port")
        } catch let err as RPCClientError {
            if case .transactionBroadcastDisabled = err {
                fatalError("FAILURE: Read-only getBlockchainInfo was incorrectly blocked by broadcast restriction!")
            } else if case .networkError = err {
                print("✓ Verified: Read-only getBlockchainInfo passed broadcast gate (expected network error on closed port: \(err)).")
            } else {
                print("✓ Verified: Read-only getBlockchainInfo passed broadcast gate (error: \(err)).")
            }
        } catch {
            print("✓ Verified: Read-only getBlockchainInfo passed broadcast gate (error: \(error)).")
        }

        print("=== RELEASE BROADCAST GATE VERIFICATION: 100% SUCCESS ===")
    }
}
