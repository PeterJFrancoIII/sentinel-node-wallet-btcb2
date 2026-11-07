import Foundation

public struct NodeConfig: Sendable {
    public var rpcPort: Int
    public let rpcUser: String
    public let rpcPassword: String
    public var p2pPort: Int
    public var profile: SyncProfile
    public var storageMode: StorageMode
    public let dataDirectory: URL

    public var configFileURL: URL {
        dataDirectory.appendingPathComponent("bitcoin.conf")
    }

    public init(
        rpcPort: Int = 8332,
        rpcUser: String? = nil,
        rpcPassword: String? = nil,
        p2pPort: Int = 8333,
        profile: SyncProfile = .preset(for: .quiet),
        storageMode: StorageMode = .compact(pruneMB: StorageMode.defaultPruneMB),
        dataDirectory: URL? = nil
    ) {
        let dir: URL
        if let d = dataDirectory {
            dir = d
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            // Retain existing datadir to prevent orphaning wallet, keychain, or synchronized block headers
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

        self.rpcPort = rpcPort
        self.rpcUser = user
        self.rpcPassword = pass
        self.p2pPort = p2pPort
        // Use the last effective on-disk settings, not a new Quiet/Balance default
        // that would silently overwrite the profile selected in a prior session.
        self.profile = Self.persistedProfile(at: dir.appendingPathComponent("bitcoin.conf"), fallback: profile)
        self.storageMode = storageMode
    }

    /// Recover the persisted profile selection and operational resource limits.
    /// This is deliberately restricted to known numeric options; the node does
    /// not execute arbitrary settings from this parser.
    private static func persistedProfile(at url: URL, fallback: SyncProfile) -> SyncProfile {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return fallback }
        var found: [String: Int] = [:]
        var type = fallback.type
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let prefix = "# Sync Profile Settings ("
            if line.hasPrefix(prefix), line.hasSuffix(")") {
                let label = String(line.dropFirst(prefix.count).dropLast())
                if let parsed = SyncProfileType(rawValue: label) { type = parsed }
            }
            for key in ["par", "dbcache", "maxconnections", "maxuploadtarget"] {
                if line.hasPrefix(key + "="), let value = Int(line.dropFirst(key.count + 1)) {
                    found[key] = value
                }
            }
        }
        var output = SyncProfile.preset(for: type)
        output.parThreads = (1...8).contains(found["par"] ?? -1) ? found["par"]! : fallback.parThreads
        output.dbCacheMB = (128...4096).contains(found["dbcache"] ?? -1) ? found["dbcache"]! : fallback.dbCacheMB
        output.maxConnections = (1...64).contains(found["maxconnections"] ?? -1) ? found["maxconnections"]! : fallback.maxConnections
        output.maxUploadTargetMB = (1...20_000).contains(found["maxuploadtarget"] ?? -1) ? found["maxuploadtarget"]! : fallback.maxUploadTargetMB
        output.pruneMB = fallback.pruneMB
        return output
    }

    /// Renders safe bitcoin.conf contents with strict localhost binding and profile options.
    /// Strict MainNet-only configuration with 550 MiB compact pruning by default.
    public func renderBitcoinConf() -> String {
        var lines: [String] = []
        lines.append("# Sentinel Node Wallet - BTCB2 Autonomous Configuration")
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
        lines.append("")
        lines.append("# Storage & Pruning Configuration")
        if storageMode.isPruned {
            lines.append("prune=\(storageMode.pruneMB)")
            lines.append("pruneduringinit=550")
        } else {
            lines.append("prune=0")
        }
        lines.append("")
        lines.append("# MainNet Configuration Section (BIP-110 BLAKE2b)")
        lines.append("[main]")
        lines.append("port=\(p2pPort)")
        lines.append("rpcport=\(rpcPort)")
        lines.append("rpcbind=127.0.0.1")
        lines.append("rpcallowip=127.0.0.1")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes configuration file to disk with strict 0600 file permissions.
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
