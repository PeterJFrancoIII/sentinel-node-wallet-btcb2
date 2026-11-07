import Foundation

public struct NodeConfig: Sendable {
    public var network: BTCB2Network
    public var rpcPort: Int
    public let rpcUser: String
    public let rpcPassword: String
    public var p2pPort: Int
    public var profile: SyncProfile
    public let dataDirectory: URL

    public var configFileURL: URL {
        dataDirectory.appendingPathComponent("bitcoin.conf")
    }

    public init(
        network: BTCB2Network = .mainnet,
        rpcPort: Int? = nil,
        rpcUser: String? = nil,
        rpcPassword: String? = nil,
        p2pPort: Int? = nil,
        profile: SyncProfile = .preset(for: .quiet),
        dataDirectory: URL? = nil
    ) {
        let dir: URL
        if let d = dataDirectory {
            dir = d
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dir = appSupport.appendingPathComponent("NodePocketBTCB2", isDirectory: true)
        }
        self.dataDirectory = dir

        // Preserve existing credentials from bitcoin.conf if present to prevent 401 mismatch
        var user = rpcUser ?? "nodepocket_user"
        var pass = rpcPassword ?? ""

        if pass.isEmpty {
            let confURL = dir.appendingPathComponent("bitcoin.conf")
            if let content = try? String(contentsOf: confURL, encoding: .utf8) {
                for line in content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("rpcuser=") {
                        user = String(trimmed.dropFirst("rpcuser=".count))
                    } else if trimmed.hasPrefix("rpcpassword=") {
                        pass = String(trimmed.dropFirst("rpcpassword=".count))
                    }
                }
            }
        }

        if pass.isEmpty {
            pass = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }

        self.network = network
        self.rpcPort = rpcPort ?? network.defaultRPCPort
        self.rpcUser = user
        self.rpcPassword = pass
        self.p2pPort = p2pPort ?? network.defaultP2PPort
        self.profile = profile
    }

    /// Renders safe bitcoin.conf contents with strict localhost binding and profile options.
    /// In Bitcoin Knots 29.x, network-specific options (rpcbind, rpcallowip, port, rpcport)
    /// MUST be placed inside network-specific sections ([main], [testnet4], [regtest]).
    public func renderBitcoinConf() -> String {
        var lines: [String] = []
        lines.append("# NODE Pocket BTCB2 Autonomous Configuration")
        lines.append("# Strict Localhost RPC Enforcement - Zero Public Ingress")
        lines.append("server=1")
        lines.append("listen=1")
        lines.append("daemon=0")
        lines.append("fallbackfee=0.0001")
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
        lines.append("# Network Specific Configuration Sections")
        lines.append("[main]")
        lines.append("port=8333")
        lines.append("rpcport=8332")
        lines.append("rpcbind=127.0.0.1")
        lines.append("rpcallowip=127.0.0.1")
        lines.append("")
        lines.append("[testnet4]")
        lines.append("port=48333")
        lines.append("rpcport=48332")
        lines.append("rpcbind=127.0.0.1")
        lines.append("rpcallowip=127.0.0.1")
        lines.append("")
        lines.append("[regtest]")
        lines.append("port=18444")
        lines.append("rpcport=18443")
        lines.append("rpcbind=127.0.0.1")
        lines.append("rpcallowip=127.0.0.1")
        lines.append("testactivationheight=blake2b@20")

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
