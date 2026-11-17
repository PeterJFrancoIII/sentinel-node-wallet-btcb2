import Foundation
import NodePocketCore

final class BroadcastLockSpyURLProtocol: URLProtocol {
    static var outboundRequestCount: Int = 0
    static var interceptedRequests: [URLRequest] = []

    static func reset() {
        outboundRequestCount = 0
        interceptedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        outboundRequestCount += 1
        interceptedRequests.append(request)
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1:59999")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let responseData = """
        {"result":{"chain":"main","blocks":900000,"headers":900000,"bestblockhash":"0000000000000000000000000000000000000000000000000000000000000000","verificationprogress":0.99999,"initialblockdownload":false,"pruned":false},"error":null,"id":"1"}
        """.data(using: .utf8)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
struct ReleaseLockVerifier {
    static func main() async {
        print("=== Sentinel Node Wallet BTCB2: Release Mode Broadcast Gate Verifier (WO-25 CI) ===")

        BroadcastLockSpyURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BroadcastLockSpyURLProtocol.self]
        let spySession = URLSession(configuration: config)

        // 1. Instantiate with isBroadcastRestricted: false
        let client = BitcoinRPCClient(
            host: "127.0.0.1",
            port: 59999,
            user: "testuser",
            password: "testpassword",
            urlSession: spySession,
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

        // 6. Assert Spy URLProtocol intercepted EXACTLY ZERO outbound network requests for blocked RPCs
        guard BroadcastLockSpyURLProtocol.outboundRequestCount == 0 else {
            fatalError("FAILURE: Spy URLProtocol intercepted \(BroadcastLockSpyURLProtocol.outboundRequestCount) outbound requests! Expected exactly 0 for blocked spend RPCs.")
        }
        print("✓ Verified: Spy URLProtocol intercepted exactly ZERO outbound requests for blocked spend RPC methods.")

        // 7. Verify read-only RPC is NOT blocked by broadcast restriction and successfully reaches URLSession transport
        do {
            let info = try await client.getBlockchainInfo()
            print("✓ Verified: Read-only getBlockchainInfo passed broadcast gate and reached transport (chain: \(info.chain), blocks: \(info.blocks)).")
        } catch {
            fatalError("FAILURE: Read-only getBlockchainInfo unexpectedly failed: \(error)")
        }

        guard BroadcastLockSpyURLProtocol.outboundRequestCount == 1 else {
            fatalError("FAILURE: Expected exactly 1 outbound request for read-only getBlockchainInfo, got \(BroadcastLockSpyURLProtocol.outboundRequestCount)")
        }
        print("✓ Verified: Read-only RPC successfully executed exactly 1 outbound transport request.")

        print("=== RELEASE BROADCAST GATE VERIFICATION: 100% SUCCESS ===")
    }
}
