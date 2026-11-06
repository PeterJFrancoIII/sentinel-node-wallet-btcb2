import Foundation

public enum RPCClientError: Error, LocalizedError, Sendable {
    case invalidURL
    case networkError(String)
    case serverError(code: Int, message: String)
    case invalidResponse
    case serializationError(String)

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
        }
    }
}

public final class BitcoinRPCClient: @unchecked Sendable {
    public let host: String
    public let port: Int
    public let user: String
    public let password: String
    private let session: URLSession

    public init(
        host: String = "127.0.0.1",
        port: Int = 8332,
        user: String,
        password: String,
        timeoutInterval: TimeInterval = 10.0
    ) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval
        self.session = URLSession(configuration: config)
    }

    private var endpointURL: URL? {
        URL(string: "http://\(host):\(port)/")
    }

    private var basicAuthHeader: String {
        let authString = "\(user):\(password)"
        let data = authString.data(using: .utf8)!
        return "Basic \(data.base64EncodedString())"
    }

    public func call<T: Decodable>(method: String, params: [Any] = []) async throws -> T {
        guard let url = endpointURL else {
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

        if T.self == String.self, let stringResult = result as? T {
            return stringResult
        } else if T.self == Double.self, let doubleResult = result as? T {
            return doubleResult
        } else if T.self == Int.self, let intResult = result as? T {
            return intResult
        } else if T.self == Bool.self, let boolResult = result as? T {
            return boolResult
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

    public func getWalletInfo() async throws -> WalletInfo {
        try await call(method: "getwalletinfo")
    }

    public func getBalances() async throws -> WalletBalances {
        try await call(method: "getbalances")
    }

    public func getNewAddress(label: String = "", addressType: String = "bech32") async throws -> String {
        try await call(method: "getnewaddress", params: [label, addressType])
    }

    public func backupWallet(destinationPath: String) async throws {
        let _: String = try await call(method: "backupwallet", params: [destinationPath])
    }

    public func stopNode() async throws -> String {
        try await call(method: "stop")
    }
}
