import Foundation

public enum RPCClientError: Error, LocalizedError, Sendable {
    case invalidURL
    case networkError(String)
    case serverError(code: Int, message: String)
    case invalidResponse
    case serializationError(String)
    case unverifiedDaemon(String)
    case transactionBroadcastDisabled

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid RPC URL."
        case .networkError(let msg):
            return "Network connection error: \(msg)"
        case .serverError(let code, let msg):
            return "RPC Server Error (\(code)): \(msg)"
        case .invalidResponse:
            return "Invalid response from RPC server."
        case .serializationError(let msg):
            return "JSON Serialization error: \(msg)"
        case .unverifiedDaemon(let msg):
            return "Daemon verification rejected: \(msg)"
        case .transactionBroadcastDisabled:
            return "Wallet signing, broadcasting and fee replacement are disabled pending independent BTCB2 SIGHASH_UNIFIED security approval."
        }
    }
}

public final class BitcoinRPCClient: @unchecked Sendable {
    public let host: String
    public let port: Int
    public let user: String
    public let password: String
    private let session: URLSession

    // Defense-in-depth: the generic RPC API is publicly callable by other first-party
    // modules. Do not rely solely on SwiftUI or WalletManager to block fund outflow.
    // No release-mode override or test-mode bypass exists for these dangerous RPCs.
    private static let restrictedSpendMethods: Set<String> = [
        "sendtoaddress", "sendmany", "send", "sendall", "sendrawtransaction",
        "submitpackage", "bumpfee", "psbtbumpfee", "walletprocesspsbt",
        "signrawtransactionwithwallet", "signrawtransactionwithkey", "finalizepsbt"
    ]

    public init(
        host: String = "127.0.0.1",
        port: Int = 8332,
        user: String,
        password: String,
        timeoutInterval: TimeInterval = 10.0,
        urlSession: URLSession? = nil
    ) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval
        self.session = urlSession ?? URLSession(configuration: config)
    }

    public func getEndpointURL(walletName: String? = nil) -> URL? {
        if let wallet = walletName, !wallet.isEmpty {
            return URL(string: "http://\(host):\(port)/wallet/\(wallet)")
        }
        return URL(string: "http://\(host):\(port)/")
    }

    private var basicAuthHeader: String {
        let authString = "\(user):\(password)"
        let data = authString.data(using: .utf8)!
        return "Basic \(data.base64EncodedString())"
    }

    public func call<T: Decodable>(method: String, params: [Any] = [], walletName: String? = nil) async throws -> T {
        guard !Self.restrictedSpendMethods.contains(method.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            throw RPCClientError.transactionBroadcastDisabled
        }
        guard let url = getEndpointURL(walletName: walletName) else {
            throw RPCClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "jsonrpc": "1.0",
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            throw RPCClientError.serializationError("Failed to serialize request payload.")
        }
        request.httpBody = httpBody

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RPCClientError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RPCClientError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw RPCClientError.serverError(code: 401, message: "Unauthorized - check RPC credentials")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RPCClientError.invalidResponse
        }

        if let errorObj = json["error"] as? [String: Any],
           let code = errorObj["code"] as? Int,
           let message = errorObj["message"] as? String {
            throw RPCClientError.serverError(code: code, message: message)
        }

        guard let result = json["result"] else {
            throw RPCClientError.invalidResponse
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        if result is NSNull {
            if T.self == String.self {
                return "" as! T
            }
            if let empty = EmptyResponse() as? T {
                return empty
            }
        }

        if T.self == String.self, let stringResult = result as? T {
            return stringResult
        } else if T.self == Double.self, let doubleResult = result as? T {
            return doubleResult
        } else if T.self == Int.self, let intResult = result as? T {
            return intResult
        } else if T.self == Bool.self, let boolResult = result as? T {
            return boolResult
        }

        guard JSONSerialization.isValidJSONObject(result) else {
            if let empty = EmptyResponse() as? T {
                return empty
            }
            throw RPCClientError.invalidResponse
        }

        let resultData = try JSONSerialization.data(withJSONObject: result, options: [])
        return try JSONDecoder().decode(T.self, from: resultData)
    }

    public func getBlockchainInfo() async throws -> BlockchainInfo {
        try await call(method: "getblockchaininfo")
    }

    public func getNetworkInfo() async throws -> NetworkInfo {
        try await call(method: "getnetworkinfo")
    }

    public func getMempoolInfo() async throws -> MempoolInfo {
        try await call(method: "getmempoolinfo")
    }

    public func getBlockHash(height: Int) async throws -> String {
        try await call(method: "getblockhash", params: [height])
    }

    public func getBlockHeader(hash: String) async throws -> BlockHeader {
        try await call(method: "getblockheader", params: [hash, true])
    }

    public func getNetworkHashps(blocks: Int = 120) async throws -> Double {
        try await call(method: "getnetworkhashps", params: [blocks])
    }

    public func getBlockTemplate(rules: [String] = ["segwit", "blake2b"]) async throws -> BlockTemplateResponse {
        try await call(method: "getblocktemplate", params: [["rules": rules]])
    }

    public func listWallets() async throws -> [String] {
        try await call(method: "listwallets")
    }

    public func listWalletDir() async throws -> WalletDirResponse {
        try await call(method: "listwalletdir")
    }

    public func loadWallet(name: String) async throws -> LoadWalletResponse {
        try await call(method: "loadwallet", params: [name])
    }

    public func unloadWallet(name: String, loadOnStartup: Bool = false) async throws -> UnloadWalletResponse {
        try await call(method: "unloadwallet", params: [name, loadOnStartup])
    }

    public func restoreWallet(name: String, backupFile: String) async throws -> LoadWalletResponse {
        try await call(method: "restorewallet", params: [name, backupFile])
    }

    public func createWallet(name: String, passphrase: String, descriptors: Bool = true, loadOnStartup: Bool = true) async throws -> CreateWalletResponse {
        let params: [Any] = [name, false, false, passphrase, false, descriptors, loadOnStartup]
        return try await call(method: "createwallet", params: params)
    }

    #if DEBUG
    /// Development/Test only: regtest mining helper. Strictly excluded from production release builds.
    public func generateToAddress(blocks: Int, address: String) async throws -> [String] {
        try await call(method: "generatetoaddress", params: [blocks, address])
    }
    #endif

    public func getWalletInfo(walletName: String? = nil) async throws -> WalletInfo {
        try await call(method: "getwalletinfo", walletName: walletName)
    }

    public func getBalances(walletName: String? = nil) async throws -> WalletBalances {
        try await call(method: "getbalances", walletName: walletName)
    }

    public func listTransactions(walletName: String? = nil, count: Int = 30) async throws -> [TransactionRecord] {
        try await call(method: "listtransactions", params: ["*", count, 0, true], walletName: walletName)
    }

    public func bumpFee(txid: String, options: [String: Any]? = nil, walletName: String? = nil) async throws -> BumpFeeResponse {
        if let options = options {
            return try await call(method: "bumpfee", params: [txid, options], walletName: walletName)
        } else {
            return try await call(method: "bumpfee", params: [txid], walletName: walletName)
        }
    }

    public func getRawMempoolVerbose() async throws -> [String: MempoolTxSummary] {
        try await call(method: "getrawmempool", params: [true])
    }

    public func sendToAddress(
        address: String,
        amount: Double,
        comment: String = "",
        feeRateSatPerVB: Int? = nil,
        replaceable: Bool = true,
        walletName: String? = nil
    ) async throws -> String {
        var params: [Any] = [address, amount, comment, "", false, replaceable]
        if let feeRate = feeRateSatPerVB, feeRate > 0 {
            params = [address, amount, comment, "", false, replaceable, NSNull(), "unset", NSNull(), feeRate]
        }
        return try await call(method: "sendtoaddress", params: params, walletName: walletName)
    }

    public func walletCreateFundedPsbt(
        outputs: [String: Double],
        feeRateSatPerVB: Int? = nil,
        walletName: String? = nil
    ) async throws -> FundedPsbtResponse {
        var options: [String: Any] = [
            "add_inputs": true,
            "replaceable": true
        ]
        if let rate = feeRateSatPerVB, rate > 0 {
            options["fee_rate"] = rate
        }
        let formattedOutputs = outputs.map { [$0.key: $0.value] }
        return try await call(
            method: "walletcreatefundedpsbt",
            params: [[], formattedOutputs, 0, options],
            walletName: walletName
        )
    }

    public func walletPassphrase(passphrase: String, timeout: Int = 60, walletName: String? = nil) async throws {
        let _: EmptyResponse = try await call(method: "walletpassphrase", params: [passphrase, timeout], walletName: walletName)
    }

    public func walletLock(walletName: String? = nil) async throws {
        let _: EmptyResponse = try await call(method: "walletlock", walletName: walletName)
    }

    public func estimateSmartFee(confTarget: Int = 6) async throws -> SmartFeeResponse {
        try await call(method: "estimatesmartfee", params: [confTarget])
    }

    public func validateAddress(address: String) async throws -> ValidateAddressResponse {
        try await call(method: "validateaddress", params: [address])
    }

    public func getNewAddress(label: String = "", addressType: String = "bech32", walletName: String? = nil) async throws -> String {
        try await call(method: "getnewaddress", params: [label, addressType], walletName: walletName)
    }

    public func backupWallet(destinationPath: String, walletName: String? = nil) async throws {
        let _: EmptyResponse = try await call(method: "backupwallet", params: [destinationPath], walletName: walletName)
    }

    public func stopNode() async throws -> String {
        try await call(method: "stop")
    }
}
