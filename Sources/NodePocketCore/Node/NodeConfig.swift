import Foundation

public struct NodeConfig: Sendable {
    public var rpcPort: Int
    public let rpcUser: String
    public let rpcPassword: String
    public var p2pPort: Int
    public var allowInboundP2P: Bool
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
        allowInboundP2P: Bool = false,
        profile: SyncProfile = .preset(for: .balanced),
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
        ProfileSettingsStore.shared.configure(dataDirectory: dir)
        // Preserve explicit existing P2P listening policy when migrating older installations.
        self.allowInboundP2P = Self.persistedInboundP2P(at: dir.appendingPathComponent("bitcoin.conf"), fallback: allowInboundP2P)
        // Use the last effective on-disk settings, not a new Quiet/Balance default
        // that would silently overwrite the profile selected in a prior session.
        self.profile = Self.persistedProfile(at: dir.appendingPathComponent("bitcoin.conf"), fallback: profile)
        self.storageMode = Self.persistedStorageMode(at: dir.appendingPathComponent("bitcoin.conf"), fallback: storageMode)
    }

    /// A new 2 GiB recommendation must NEVER silently overwrite an existing
    /// user's 550 MiB/custom pruning target or turn archival history into pruned.
    private static func persistedStorageMode(at url: URL, fallback: StorageMode) -> StorageMode {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return fallback
        }
        let values = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("prune=") }
        guard let line = values.last else {
            // Older bitcoin.conf files without a prune option are archival by
            // default. Never rewrite them as pruned on an app update.
            return .archival(externalDataDir: url.deletingLastPathComponent())
        }
        guard let target = Int(line.dropFirst("prune=".count)) else {
            // Malformed legacy config: do not reinterpret malformed retention
            // rules as permission to delete historical blocks.
            return .archival(externalDataDir: url.deletingLastPathComponent())
        }
        if target >= StorageMode.minimumPruneMB {
            return .compact(pruneMB: target)
        }
        if target == 0 {
            // Existing archive MUST NOT be pruned just because the new default is.
            return .archival(externalDataDir: url.deletingLastPathComponent())
        }
        return fallback
    }

    /// Preserve the operator's on-disk inbound P2P selection. New installs default OFF;
    /// existing configs with listen=1 remain enabled until explicitly changed.
    private static func persistedInboundP2P(at url: URL, fallback: Bool) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return fallback }
        var enabled = fallback
        for raw in contents.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "listen=1" { enabled = true }
            if line == "listen=0" { enabled = false }
        }
        return enabled
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
        var output = ProfileSettingsStore.shared.getProfile(for: type, pruneMB: fallback.pruneMB)
        if !ProfileSettingsStore.shared.isCustomized(type: type) {
            let isOldDefaultQuiet = (type == .quiet && found["maxconnections"] == 16 && (found["dbcache"] == 256 || found["dbcache"] == nil))
            let isOldDefaultBalanced = (type == .balanced && found["maxconnections"] == 24 && (found["dbcache"] == 512 || found["dbcache"] == nil))
            let isOldDefaultFast = (type == .fast && found["maxconnections"] == 32 && (found["dbcache"] == 1024 || found["dbcache"] == nil))
            let isOldDefault = isOldDefaultQuiet || isOldDefaultBalanced || isOldDefaultFast

            if !isOldDefault {
                if let par = found["par"], (1...8).contains(par) { output.parThreads = par }
                if let cache = found["dbcache"], (128...4096).contains(cache) { output.dbCacheMB = cache }
                if let maxC = found["maxconnections"], (1...64).contains(maxC) { output.maxConnections = maxC }
                if let upload = found["maxuploadtarget"], (1...20_000).contains(upload) { output.maxUploadTargetMB = upload }
            }
        }
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
        lines.append("listen=\(allowInboundP2P ? 1 : 0)")
        // Never map a port on the user's router without their informed consent.
        lines.append("natpmp=0")
        lines.append("upnp=0")
        // Permit block, transaction and address relay over modern P2P transport.
        lines.append("blocksonly=0")
        lines.append("v2transport=1")
        lines.append("rest=0")
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

        ProfileSettingsStore.shared.saveParameters(
            for: profile.type,
            parameters: ProfileParameters(
                parThreads: profile.parThreads,
                dbCacheMB: profile.dbCacheMB,
                maxConnections: profile.maxConnections,
                maxUploadTargetMB: profile.maxUploadTargetMB
            )
        )
        ProfileSettingsStore.shared.setSelectedProfileType(profile.type)
    }
}
