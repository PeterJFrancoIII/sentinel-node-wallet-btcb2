import Foundation
import CryptoKit

public enum RPCClientError: Error, LocalizedError, Sendable {
    case invalidURL
    case networkError(String)
    case serverError(code: Int, message: String)
    case invalidResponse
    case serializationError(String)
    case unverifiedDaemon(String)
    case transactionBroadcastDisabled
    case unauthorizedVerifier
    case verifierAlreadyRegistered

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
        case .unauthorizedVerifier:
            return "Spend authorization verifier rejected: Untrusted or unauthorized verifier implementation."
        case .verifierAlreadyRegistered:
            return "Spend authorization verifier is immutable and cannot be replaced or re-registered."
        }
    }
}

public struct ProcessedPsbtResponse: Codable, Sendable {
    public let psbt: String
    public let complete: Bool

    public init(psbt: String, complete: Bool) {
        self.psbt = psbt
        self.complete = complete
    }
}

public struct FinalizedPsbtResponse: Codable, Sendable {
    public let psbt: String?
    public let hex: String?
    public let complete: Bool

    public init(psbt: String? = nil, hex: String? = nil, complete: Bool) {
        self.psbt = psbt
        self.hex = hex
        self.complete = complete
    }
}

public protocol SpendAuthorizationVerifier: Sendable {
    func verify(
        authorization: SpendAuthorization,
        method: String,
        params: [Any],
        walletName: String?
    ) -> Bool
}

public struct SpendAuthorization: Sendable, Equatable {
    public let approvalId: UUID
    public let sessionId: UUID
    public let walletName: String
    public let authorizedMethod: String
    public let destinationAddress: String
    public let amountSats: Int64
    public let maxFeeSats: Int64
    public let satPerVB: Int
    public let chain: String
    public let previewId: UUID
    public let utxoFingerprint: String
    public let token: String
    public let issuedAt: Date
    public let expiresAt: Date
    public let nonce: String

    public init(
        approvalId: UUID = UUID(),
        sessionId: UUID = UUID(),
        walletName: String,
        authorizedMethod: String = "sendtoaddress",
        destinationAddress: String,
        amountSats: Int64,
        maxFeeSats: Int64,
        satPerVB: Int = 1,
        chain: String = "main",
        previewId: UUID = UUID(),
        utxoFingerprint: String = "",
        token: String,
        issuedAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(60),
        nonce: String = UUID().uuidString
    ) {
        self.approvalId = approvalId
        self.sessionId = sessionId
        self.walletName = walletName
        self.authorizedMethod = authorizedMethod
        self.destinationAddress = destinationAddress
        self.amountSats = amountSats
        self.maxFeeSats = maxFeeSats
        self.satPerVB = satPerVB
        self.chain = chain
        self.previewId = previewId
        self.utxoFingerprint = utxoFingerprint
        self.token = token
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.nonce = nonce
    }

    public var isExpired: Bool {
        Date() > expiresAt
    }
}

public final class BitcoinRPCClient: @unchecked Sendable {
    public let host: String
    public let port: Int
    public private(set) var user: String
    public private(set) var password: String
    private var _isBroadcastRestricted: Bool
    public var isBroadcastRestricted: Bool {
        get { _isBroadcastRestricted }
        set { _isBroadcastRestricted = newValue }
    }
    private let credLock = NSLock()
    private let authLock = NSLock()
    private var consumedAuthorizationTokens = Set<String>()
    private let verifierLock = NSLock()
    private var authorizationVerifier: (any SpendAuthorizationVerifier)?

    public func registerAuthorizationVerifier(_ verifier: any SpendAuthorizationVerifier) throws {
        verifierLock.lock()
        defer { verifierLock.unlock() }
        guard authorizationVerifier == nil else {
            throw RPCClientError.verifierAlreadyRegistered
        }
        guard let trusted = verifier as? WalletAuthCoordinator.CoordinatorSpendAuthVerifier else {
            throw RPCClientError.unauthorizedVerifier
        }
        self.authorizationVerifier = trusted
    }

    public var isAuthorizationVerifierRegistered: Bool {
        verifierLock.lock()
        defer { verifierLock.unlock() }
        return authorizationVerifier != nil
    }

    private func getRegisteredVerifier() -> (any SpendAuthorizationVerifier)? {
        verifierLock.lock()
        defer { verifierLock.unlock() }
        return authorizationVerifier
    }

    private func recordAndVerifyToken(tokenKey: String) -> Bool {
        authLock.lock()
        defer { authLock.unlock() }
        if consumedAuthorizationTokens.contains(tokenKey) {
            return false
        }
        consumedAuthorizationTokens.insert(tokenKey)
        return true
    }
    private let session: URLSession

    // Defense-in-depth: the generic RPC API is publicly callable by other first-party
    // modules. Do not rely solely on SwiftUI or WalletManager to block fund outflow.
    // When isBroadcastRestricted is true (default for tests/isolated safety mode),
    // these methods fail closed unconditionally. When false, they strictly require
    // a valid, unexpired, single-use SpendAuthorization.
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
        urlSession: URLSession? = nil,
        isBroadcastRestricted: Bool = true
    ) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self._isBroadcastRestricted = isBroadcastRestricted

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval
        self.session = urlSession ?? URLSession(configuration: config)
    }

    public func updateCredentials(user: String, password: String) {
        credLock.lock()
        defer { credLock.unlock() }
        self.user = user
        self.password = password
    }

    public func getEndpointURL(walletName: String? = nil) -> URL? {
        if let wallet = walletName, !wallet.isEmpty {
            return URL(string: "http://\(host):\(port)/wallet/\(wallet)")
        }
        return URL(string: "http://\(host):\(port)/")
    }

    private var basicAuthHeader: String {
        credLock.lock()
        let currentUser = self.user
        let currentPass = self.password
        credLock.unlock()
        let authString = "\(currentUser):\(currentPass)"
        let data = authString.data(using: .utf8)!
        return "Basic \(data.base64EncodedString())"
    }

    public func call<T: Decodable>(
        method: String,
        params: [Any] = [],
        walletName: String? = nil,
        authorization: SpendAuthorization? = nil
    ) async throws -> T {
        let normalizedMethod = method.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Self.restrictedSpendMethods.contains(normalizedMethod) {
            guard !isBroadcastRestricted else {
                throw RPCClientError.transactionBroadcastDisabled
            }
            guard let auth = authorization else {
                throw RPCClientError.transactionBroadcastDisabled
            }
            guard !auth.isExpired else {
                throw RPCClientError.transactionBroadcastDisabled
            }

            guard let activeVerifier = getRegisteredVerifier() else {
                // Fail closed: No authentic coordinator verifier has been registered!
                throw RPCClientError.transactionBroadcastDisabled
            }

            guard activeVerifier.verify(
                authorization: auth,
                method: normalizedMethod,
                params: params,
                walletName: walletName
            ) else {
                throw RPCClientError.transactionBroadcastDisabled
            }

            let isIntermediate = auth.authorizedMethod.lowercased() == "sendrawtransaction" && (normalizedMethod == "walletprocesspsbt" || normalizedMethod == "finalizepsbt")
            if !isIntermediate {
                let tokenKey = "\(auth.approvalId.uuidString):\(auth.authorizedMethod):\(auth.token):\(auth.nonce)"
                guard recordAndVerifyToken(tokenKey: tokenKey) else {
                    throw RPCClientError.transactionBroadcastDisabled
                }
            }
        }
        guard let url = getEndpointURL(walletName: walletName) else {
            throw RPCClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader, forHTTPHeaderField: "Authorization")

        let wireParams: [Any]
        if normalizedMethod == "sendtoaddress" && params.count > 10 {
            wireParams = Array(params.prefix(10))
        } else {
            wireParams = params
        }

        let payload: [String: Any] = [
            "jsonrpc": "1.0",
            "id": UUID().uuidString,
            "method": method,
            "params": wireParams
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

    public func bumpFee(
        txid: String,
        options: [String: Any]? = nil,
        walletName: String? = nil,
        authorization: SpendAuthorization? = nil
    ) async throws -> BumpFeeResponse {
        if let options = options {
            return try await call(method: "bumpfee", params: [txid, options], walletName: walletName, authorization: authorization)
        } else {
            return try await call(method: "bumpfee", params: [txid], walletName: walletName, authorization: authorization)
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
        maxFeeSats: Int64? = nil,
        utxoFingerprint: String? = nil,
        walletName: String? = nil,
        authorization: SpendAuthorization? = nil
    ) async throws -> String {
        // Enforce 8-decimal fixed-point string representation for Bitcoin Core RPC compatibility
        // Prevents floating-point scientific notation (e.g. 9.718e-05) which causes "RPC Server Error (-3): Invalid amount"
        let amountStr = SatoshiMath.toBTCString(btc: amount)
        var params: [Any] = [address, amountStr, comment, "", false, replaceable]
        if let feeRate = feeRateSatPerVB, feeRate > 0 {
            let effectiveMaxFee: Int64 = maxFeeSats ?? authorization?.maxFeeSats ?? 0
            let effectiveUtxo: String = utxoFingerprint ?? authorization?.utxoFingerprint ?? ""
            params = [address, amountStr, comment, "", false, replaceable, NSNull(), "unset", NSNull(), feeRate, effectiveMaxFee, effectiveUtxo]
        }
        return try await call(method: "sendtoaddress", params: params, walletName: walletName, authorization: authorization)
    }

    public func walletProcessPsbt(
        psbt: String,
        sign: Bool = true,
        walletName: String? = nil,
        authorization: SpendAuthorization? = nil
    ) async throws -> ProcessedPsbtResponse {
        return try await call(
            method: "walletprocesspsbt",
            params: [psbt, sign],
            walletName: walletName,
            authorization: authorization
        )
    }

    public func finalizePsbt(
        psbt: String,
        extract: Bool = true,
        walletName: String? = nil,
        authorization: SpendAuthorization? = nil
    ) async throws -> FinalizedPsbtResponse {
        return try await call(
            method: "finalizepsbt",
            params: [psbt, extract],
            walletName: walletName,
            authorization: authorization
        )
    }

    public func sendRawTransaction(
        hex: String,
        maxFeeRate: Double? = nil,
        walletName: String? = nil,
        authorization: SpendAuthorization? = nil
    ) async throws -> String {
        var params: [Any] = [hex]
        if let maxRate = maxFeeRate {
            params.append(maxRate)
        }
        return try await call(
            method: "sendrawtransaction",
            params: params,
            walletName: walletName,
            authorization: authorization
        )
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
        // Output amounts must be 8-decimal fixed-point strings to avoid scientific notation serialization
        let formattedOutputs: [[String: String]] = outputs.map { [$0.key: SatoshiMath.toBTCString(btc: $0.value)] }
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
