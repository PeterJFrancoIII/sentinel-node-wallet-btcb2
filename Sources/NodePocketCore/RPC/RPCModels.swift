import Foundation

public struct RPCError: Codable, Error, Sendable {
    public let code: Int
    public let message: String
}

public struct BlockchainInfo: Codable, Sendable {
    public let chain: String
    public let blocks: Int
    public let headers: Int
    public let bestblockhash: String
    public let difficulty: Double?
    public let difficulty_blake2b: Double?
    public let verificationprogress: Double
    public let initialblockdownload: Bool
    public let pruned: Bool
    public let pruneheight: Int?
}

public struct NetworkInfo: Codable, Sendable {
    public let version: Int
    public let subversion: String
    public let protocolversion: Int
    public let connections: Int
}

public struct MempoolInfo: Codable, Sendable {
    public let size: Int
    public let bytes: Int
    public let usage: Int
}

public struct BlockHeader: Codable, Sendable {
    public let hash: String
    public let confirmations: Int
    public let height: Int
    public let time: Int
    public let bits: String
    public let difficulty: Double?
    public let chainwork: String
    public let previousblockhash: String?
}

public struct WalletBalances: Codable, Sendable {
    public let mine: BalanceBucket

    public struct BalanceBucket: Codable, Sendable {
        public let trusted: Double
        public let untrusted_pending: Double
        public let immature: Double
    }
}

public struct WalletInfo: Codable, Sendable {
    public let walletname: String
    public let walletversion: Int
    public let balance: Double
    public let unconfirmed_balance: Double
    public let immature_balance: Double
    public let txcount: Int
    public let descriptors: Bool?
    public let unlocked_until: Int?
}

public struct BlockTemplateResponse: Codable, Sendable {
    public let capabilities: [String]?
    public let version: Int?
    public let rules: [String]?
    public let target: String?
    public let bits: String?
    public let height: Int?
    public let curtime: Int?
}

public struct WalletDirResponse: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public let name: String
    }
    public let wallets: [Entry]
}

public struct CreateWalletResponse: Codable, Sendable {
    public let name: String
    public let warnings: [String]?
}

public struct LoadWalletResponse: Codable, Sendable {
    public let name: String
    public let warning: String?
}
