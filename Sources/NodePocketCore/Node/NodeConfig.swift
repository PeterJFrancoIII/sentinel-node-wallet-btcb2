import Foundation

public struct NodeConfig: Sendable {
    public let network: BTCB2Network
    public let rpcPort: Int
    public let rpcUser: String
    public let rpcPassword: String
    public let p2pPort: Int
    public var profile: SyncProfile
    public let dataDirectory: URL

    public var configFileURL: URL {
        dataDirectory.appendingPathComponent("bitcoin.conf")
    }

    public init(
        network: BTCB2Network = .mainnet,
        rpcPort: Int? = nil,
        rpcUser: String = "nodepocket_user",
        rpcPassword: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        p2pPort: Int? = nil,
        profile: SyncProfile = .preset(for: .quiet),
        dataDirectory: URL? = nil
    ) {
        self.network = network
        self.rpcPort = rpcPort ?? network.defaultRPCPort
        self.rpcUser = rpcUser
        self.rpcPassword = rpcPassword
        self.p2pPort = p2pPort ?? network.defaultP2PPort
        self.profile = profile

        if let dir = dataDirectory {
            self.dataDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.dataDirectory = appSupport.appendingPathComponent("NodePocketBTCB2", isDirectory: true)
        }
    }

    /// Renders safe bitcoin.conf contents with strict localhost binding and profile options.
    public func renderBitcoinConf() -> String {
        var lines: [String] = []
        lines.append("# NODE Pocket BTCB2 Autonomous Configuration")
        lines.append("# Strict Localhost RPC Enforcement - Zero Public Ingress")
        lines.append("server=1")
        lines.append("listen=1")
        lines.append("daemon=0")
        lines.append("rpcbind=127.0.0.1")
        lines.append("rpcallowip=127.0.0.1")
        lines.append("rpcport=\(rpcPort)")
        lines.append("port=\(p2pPort)")
        lines.append("rpcuser=\(rpcUser)")
        lines.append("rpcpassword=\(rpcPassword)")
        lines.append("")
        lines.append("# Sync Profile Settings (\(profile.type.rawValue))")
        lines.append("par=\(profile.parThreads)")
        lines.append("dbcache=\(profile.dbCacheMB)")
        lines.append("maxconnections=\(profile.maxConnections)")
        lines.append("maxuploadtarget=\(profile.maxUploadTargetMB)")
        if profile.pruneMB > 0 {
            lines.append("prune=\(profile.pruneMB)")
        } else {
            lines.append("prune=0")
        }
        lines.append("")
        lines.append("# Network Specific Section")
        switch network {
        case .mainnet:
            lines.append("[main]")
        case .testnet4:
            lines.append("[testnet4]")
            lines.append("testnet4=1")
        case .regtest:
            lines.append("[regtest]")
            lines.append("regtest=1")
            lines.append("testactivationheight=blake2b@20")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes configuration to disk ensuring 0700 dir and 0600 file permissions.
    public func writeToDisk() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dataDirectory.path) {
            try fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }

        let content = renderBitcoinConf()
        try content.write(to: configFileURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFileURL.path)
    }
}
