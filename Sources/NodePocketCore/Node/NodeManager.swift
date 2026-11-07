import Foundation

public enum NodeState: Equatable, Sendable {
    case stopped
    case starting
    case running(pid: Int32)
    case stopping
    case error(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

public final class NodeManager: @unchecked Sendable {
    public private(set) var state: NodeState = .stopped
    public var config: NodeConfig
    public private(set) var rpcClient: BitcoinRPCClient
    public let hashrateTracker: HashrateTracker
    public let etaEngine: AdaptiveETAEngine

    private var process: Process?
    public private(set) var adoptedPid: Int32?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let stateLock = NSLock()
    @MainActor private var settingsInFlight = false
    private var monitorTask: Task<Void, Never>?

    public private(set) var isUltraActive: Bool = false
    public var onStateChange: (@Sendable (NodeState) -> Void)?
    public var onLogMessage: (@Sendable (String) -> Void)?
    public var onBlockchainUpdate: (@Sendable (BlockchainInfo, HashrateReport, NetworkInfo?, (state: ETAState, display: String)) -> Void)?

    public init(config: NodeConfig = NodeConfig()) {
        self.config = config
        self.rpcClient = BitcoinRPCClient(
            host: "127.0.0.1",
            port: config.rpcPort,
            user: config.rpcUser,
            password: config.rpcPassword
        )
        self.hashrateTracker = HashrateTracker(windowSize: 30)
        self.etaEngine = AdaptiveETAEngine()
    }

    public func readPidFile() -> Int32? {
        let pidFile = config.dataDirectory.appendingPathComponent("bitcoind.pid")
        guard let content = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else {
            return nil
        }
        return pid
    }

    public func verifyAdoptedDaemon() async -> Bool {
        guard FileManager.default.fileExists(atPath: config.dataDirectory.path) else { return false }
        let cookieFile = config.dataDirectory.appendingPathComponent(".cookie")
        guard FileManager.default.fileExists(atPath: cookieFile.path) else { return false }
        guard let binfo = try? await rpcClient.getBlockchainInfo(), binfo.chain == "main" else {
            return false
        }
        if let pid = readPidFile() {
            guard kill(pid, 0) == 0 else { return false }
        }
        return true
    }

    public func adoptRunningDaemon(pid: Int32 = 0) {
        let resolvedPid = pid > 0 ? pid : (readPidFile() ?? 0)
        self.adoptedPid = resolvedPid > 0 ? resolvedPid : nil
        updateState(.running(pid: resolvedPid))
        startMonitoring()
    }

    private func updateState(_ newState: NodeState) {
        stateLock.lock()
        self.state = newState
        stateLock.unlock()
        onStateChange?(newState)
    }

    /// Starts the node subprocess using the configured bitcoind binary or a simulator if not present.
    /// Strictly pinned to BTCB2 BIP-110 BLAKE2b MainNet.
    public func start(binaryURL: URL? = nil, ultraOverride: Bool = false) throws {
        stateLock.lock()
        guard state == .stopped || caseMatchesError(state) else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        updateState(.starting)

        // Write configuration
        try config.writeToDisk()

        guard let executableURL = binaryURL ?? findBitcoindBinary() else {
            let message = "Verified app-bundled Knots bitcoind is unavailable. Refusing system-wide fallback."
            updateState(.error(message))
            throw RPCClientError.serializationError(message)
        }

        let proc = Process()
        proc.executableURL = executableURL
        // Strictly MainNet arguments only
        var arguments = [
            "-conf=\(config.configFileURL.path)",
            "-datadir=\(config.dataDirectory.path)"
        ]
        if ultraOverride {
            self.isUltraActive = true
            arguments.append(contentsOf: [
                "-par=1",
                "-dbcache=128",
                "-maxconnections=12",
                "-maxuploadtarget=128"
            ])
        } else {
            self.isUltraActive = false
        }
        proc.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let tipLock = NSLock()
        var lastTipForwardTime: TimeInterval = 0

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let str = String(data: data, encoding: .utf8), !str.isEmpty else { return }

            let lines = str.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                if trimmed.contains("UpdateTip:") {
                    tipLock.lock()
                    let now = Date().timeIntervalSince1970
                    let shouldForward = (now - lastTipForwardTime) >= 1.5
                    if shouldForward {
                        lastTipForwardTime = now
                    }
                    tipLock.unlock()

                    if shouldForward {
                        self?.onLogMessage?(trimmed)
                    }
                } else {
                    self?.onLogMessage?(trimmed)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                self?.onLogMessage?("[STDERR] \(str.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        proc.terminationHandler = { [weak self] p in
            self?.updateState(.stopped)
            self?.onLogMessage?("[NODE] Subprocess terminated with exit code \(p.terminationStatus)")
        }

        do {
            try proc.run()
            self.process = proc
            self.stdoutPipe = outPipe
            self.stderrPipe = errPipe
            updateState(.running(pid: proc.processIdentifier))
            startMonitoring()
        } catch {
            updateState(.error("Failed to spawn node: \(error.localizedDescription)"))
            throw error
        }
    }

    /// Graceful shutdown is mandatory for a node writing chainstate.
    /// Never SIGKILL the owned bitcoind on an ordinary stop or upgrade.
    public func stop() async {
        updateState(.stopping)
        monitorTask?.cancel()
        monitorTask = nil

        do {
            _ = try await rpcClient.stopNode()
            onLogMessage?("[NODE] Requested graceful Knots shutdown; waiting for clean exit.")
        } catch {
            // If RPC is unavailable, do not assume that force terminating a process is safe.
            if let owned = process, !owned.isRunning {
                process = nil
                updateState(.stopped)
                return
            }
            updateState(.error("Cannot confirm graceful node shutdown: \(error.localizedDescription)"))
            return
        }

        let deadline = Date().addingTimeInterval(120)
        let pidToCheck = adoptedPid ?? readPidFile()
        while Date() < deadline {
            if let owned = process {
                if !owned.isRunning { break }
            } else {
                // Adopted daemons do not have a Process handle; wait until RPC closes and PID exits.
                let rpcAlive = (try? await rpcClient.getBlockchainInfo()) != nil
                if !rpcAlive {
                    if let pid = pidToCheck, pid > 0 {
                        if kill(pid, 0) != 0 { break }
                    } else {
                        break
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        if let owned = process, owned.isRunning {
            updateState(.error("Knots is still shutting down. No force-kill was issued; inspect its logs before retrying."))
            return
        }
        if process == nil, (try? await rpcClient.getBlockchainInfo()) != nil {
            updateState(.error("Adopted Knots daemon is still responding; shutdown not yet confirmed."))
            return
        }

        process = nil
        adoptedPid = nil
        stdoutPipe = nil
        stderrPipe = nil
        updateState(.stopped)
    }

    /// Apply the selected profile and storage atomically: one graceful restart,
    /// one config write, no concurrent profile/storage racing or swallowed errors.
    @MainActor public func applyConfiguration(
        profile newProfile: SyncProfile,
        storageMode newMode: StorageMode
    ) async throws -> String {
        guard !settingsInFlight else {
            throw RPCClientError.serializationError("A node configuration change is already in progress.")
        }
        settingsInFlight = true
        defer { settingsInFlight = false }

        switch newMode {
        case .compact(let mb):
            guard mb >= StorageMode.minimumPruneMB else {
                throw StorageValidationError.belowMinimumPruneSize(mb)
            }
        case .archival:
            throw RPCClientError.serializationError(
                "A pruned node cannot become archival by changing prune=0. " +
                "A verified full-history re-download and wallet-safe migration are required."
            )
        }
        guard (1...8).contains(newProfile.parThreads),
              (128...4096).contains(newProfile.dbCacheMB),
              (1...64).contains(newProfile.maxConnections) else {
            throw RPCClientError.serializationError("Invalid resource profile limits.")
        }

        if config.profile == newProfile && config.storageMode == newMode {
            return "Settings are already configured."
        }
        let previous = config
        let wasRunning: Bool
        switch state {
        case .running:
            wasRunning = true
        case .stopped, .error:
            wasRunning = false
        case .starting, .stopping:
            throw RPCClientError.serializationError("Wait for the node to finish starting or stopping.")
        }

        if wasRunning {
            if process != nil {
                await stop()
                guard state == .stopped else {
                    throw RPCClientError.serializationError("Knots did not finish its graceful shutdown.")
                }
            } else {
                let isVerified = await verifyAdoptedDaemon()
                guard isVerified else {
                    throw RPCClientError.serializationError(
                        "Cannot safely apply settings: running node daemon is unverified. " +
                        "Stop the background node manually and relaunch Sentinel Node Wallet."
                    )
                }
                onLogMessage?("[CONFIG] Safely shutting down verified adopted Knots daemon to apply profile...")
                await stop()
                guard state == .stopped else {
                    throw RPCClientError.serializationError("Adopted Knots daemon did not finish its graceful shutdown.")
                }
            }
        }

        config.profile = newProfile
        config.storageMode = newMode
        do {
            try config.writeToDisk()
            if wasRunning {
                try start(ultraOverride: isUltraActive)
                try await waitForRPCReadiness(timeoutSeconds: 90)
            }
            let status = wasRunning ? "Applied after clean restart and verified RPC connectivity." :
                "Saved. Settings will take effect on the next node startup."
            onLogMessage?("[CONFIG] \(newProfile.type.rawValue) par=\(newProfile.parThreads) " +
                          "dbcache=\(newProfile.dbCacheMB) maxconnections=\(newProfile.maxConnections). " + status)
            return status
        } catch {
            // Restore last known configuration on any failed change. Never erase wallet/chain.
            config = previous
            try? config.writeToDisk()
            if wasRunning, case .stopped = state { try? start(ultraOverride: isUltraActive) }
            throw error
        }
    }

    @MainActor public func applyUltraMode(active: Bool) async throws -> Bool {
        guard isUltraActive != active else { return true }
        let wasRunning = state.isRunning

        if wasRunning {
            if process == nil && adoptedPid != nil {
                let verified = await verifyAdoptedDaemon()
                guard verified else {
                    return false
                }
            }
            await stop()
            for _ in 0..<20 {
                if state == .stopped { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            try start(ultraOverride: active)
            try await waitForRPCReadiness(timeoutSeconds: 30)
        } else {
            self.isUltraActive = active
        }
        return true
    }

    @MainActor public func switchProfile(_ newProfile: SyncProfile) async throws {
        _ = try await applyConfiguration(profile: newProfile, storageMode: config.storageMode)
    }

    @MainActor public func switchStorageMode(_ newMode: StorageMode) async throws {
        _ = try await applyConfiguration(profile: config.profile, storageMode: newMode)
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                guard let self = self else { break }

                do {
                    let binfo = try await self.rpcClient.getBlockchainInfo()
                    let netInfo = try? await self.rpcClient.getNetworkInfo()
                    let bhash = binfo.bestblockhash
                    if !bhash.isEmpty {
                        let header = try await self.rpcClient.getBlockHeader(hash: bhash)
                        if let target = TargetConverter.targetHexFromBits(UInt32(header.bits, radix: 16) ?? 0) {
                            self.hashrateTracker.addBlock(
                                height: header.height,
                                hash: header.hash,
                                timestamp: TimeInterval(header.time),
                                targetHex: target
                            )
                        }
                    }

                    let report = self.hashrateTracker.generateReport()

                    // Adaptive Verification Progress ETA
                    self.etaEngine.addSample(progress: binfo.verificationprogress, height: binfo.blocks)
                    let peerCount = netInfo?.connections ?? 8
                    let eta = self.etaEngine.calculateETA(isIBD: binfo.initialblockdownload, peerCount: peerCount)

                    self.onBlockchainUpdate?(binfo, report, netInfo, eta)
                } catch {
                    // Suppress connection errors during initial startup
                }
            }
        }
    }

    public func waitForRPCReadiness(timeoutSeconds: TimeInterval = 60.0) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeoutSeconds {
            do {
                _ = try await rpcClient.getBlockchainInfo()
                onLogMessage?("[RPC] Connected to Bitcoin Knots RPC server successfully.")
                return
            } catch {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            }
        }
        throw RPCClientError.networkError("Timed out waiting for bitcoind RPC server to respond after \(Int(timeoutSeconds))s.")
    }

    /// Only use the app-bundled, release-manifest-verified Knots daemon.
    /// Never silently substitute arbitrary global/homebrew bitcoind or another chain.
    public func findBitcoindBinary() -> URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/bitcoind")
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil
    }

    private func caseMatchesError(_ state: NodeState) -> Bool {
        if case .error = state { return true }
        return false
    }
}
