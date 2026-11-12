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
    /// Estimated byte size of retained block and undo files (not chainstate or wallet).
    public let size_on_disk: Int64?
    /// Current automatic pruning target in BYTES, if supported.
    public let prune_target_size: Int64?
}

public struct NetworkInfo: Codable, Sendable {
    public let version: Int
    public let subversion: String
    public let protocolversion: Int
    public let connections: Int
    public let connections_in: Int?
    public let connections_out: Int?
    public let localservicesnames: [String]?
}

public struct MempoolInfo: Codable, Sendable {
    public let size: Int
    public let bytes: Int
    public let usage: Int
    public let mempoolminfee: Double?
    public let minrelaytxfee: Double?
}

public struct BlockHeader: Codable, Sendable {
    public let hash: String
    public let confirmations: Int
    public let height: Int
    public let time: Int
    public let mediantime: Int?
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

public struct TransactionRecord: Codable, Identifiable, Sendable {
    public var id: String { "\(txid)_\(category)_\(vout ?? 0)" }
    public let address: String?
    public let category: String // "send", "receive", "generate", "immature"
    public let amount: Double
    public let label: String?
    public let vout: Int?
    public let confirmations: Int
    public let blockhash: String?
    public let blockheight: Int?
    public let blocktime: Int?
    public let txid: String
    public let time: Int
    public let timereceived: Int?
    public let bip125Replaceable: String?

    enum CodingKeys: String, CodingKey {
        case address
        case category
        case amount
        case label
        case vout
        case confirmations
        case blockhash
        case blockheight
        case blocktime
        case txid
        case time
        case timereceived
        case bip125Replaceable = "bip125-replaceable"
    }

    public init(
        address: String?,
        category: String,
        amount: Double,
        label: String? = nil,
        vout: Int? = nil,
        confirmations: Int,
        blockhash: String? = nil,
        blockheight: Int? = nil,
        blocktime: Int? = nil,
        txid: String,
        time: Int,
        timereceived: Int? = nil,
        bip125Replaceable: String? = nil
    ) {
        self.address = address
        self.category = category
        self.amount = amount
        self.label = label
        self.vout = vout
        self.confirmations = confirmations
        self.blockhash = blockhash
        self.blockheight = blockheight
        self.blocktime = blocktime
        self.txid = txid
        self.time = time
        self.timereceived = timereceived
        self.bip125Replaceable = bip125Replaceable
    }
}

public struct BumpFeeResponse: Codable, Sendable {
    public let txid: String
    public let origfee: Double
    public let fee: Double
    public let errors: [String]?

    public init(txid: String, origfee: Double, fee: Double, errors: [String]? = nil) {
        self.txid = txid
        self.origfee = origfee
        self.fee = fee
        self.errors = errors
    }
}

public struct FundedPsbtResponse: Codable, Sendable {
    public let psbt: String
    public let fee: Double
    public let changepos: Int

    public init(psbt: String, fee: Double, changepos: Int) {
        self.psbt = psbt
        self.fee = fee
        self.changepos = changepos
    }
}

public struct MempoolTxSummary: Codable, Sendable {
    public let vsize: Int?
    public let weight: Int?
    public let fee: Double?
    public struct Fees: Codable, Sendable {
        public let base: Double?
    }
    public let fees: Fees?

    public var effectiveFeeBTC: Double {
        fees?.base ?? fee ?? 0.0
    }

    public init(vsize: Int? = nil, weight: Int? = nil, fee: Double? = nil, fees: Fees? = nil) {
        self.vsize = vsize
        self.weight = weight
        self.fee = fee
        self.fees = fees
    }
}

public struct SmartFeeResponse: Codable, Sendable {
    public let feerate: Double?
    public let blocks: Int?
    public let errors: [String]?
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

public struct EmptyResponse: Codable, Sendable {
    public init() {}
}

public struct UnloadWalletResponse: Codable, Sendable {
    public let warning: String?
}

public struct ValidateAddressResponse: Codable, Sendable {
    public let isvalid: Bool
    public let address: String?
    public let scriptPubKey: String?
    public let iswitness: Bool?
    public let witness_version: Int?
    public let witness_program: String?
}
