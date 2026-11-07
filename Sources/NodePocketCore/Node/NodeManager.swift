import Foundation

public enum NodeState: Equatable, Sendable {
    case stopped
    case starting
    case running(pid: Int32)
    case stopping
    case error(String)
}

public final class NodeManager: @unchecked Sendable {
    public private(set) var state: NodeState = .stopped
    public var config: NodeConfig
    public private(set) var rpcClient: BitcoinRPCClient
    public let hashrateTracker: HashrateTracker
    public let etaEngine: AdaptiveETAEngine

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let stateLock = NSLock()
    private var monitorTask: Task<Void, Never>?

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

    public func adoptRunningDaemon(pid: Int32 = 0) {
        updateState(.running(pid: pid))
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
    public func start(binaryURL: URL? = nil) throws {
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
        let arguments = [
            "-conf=\(config.configFileURL.path)",
            "-datadir=\(config.dataDirectory.path)"
        ]
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
            updateState(.error("Cannot confirm graceful node shutdown: \\(error.localizedDescription)"))
            return
        }

        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if let owned = process {
                if !owned.isRunning { break }
            } else {
                // Adopted daemons do not have a Process handle; wait until RPC closes.
                if (try? await rpcClient.getBlockchainInfo()) == nil { break }
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
        stdoutPipe = nil
        stderrPipe = nil
        updateState(.stopped)
    }

    public func switchProfile(_ newProfile: SyncProfile) async throws {
        self.config.profile = newProfile
        try config.writeToDisk()
        onLogMessage?("[CONFIG] Switched sync profile to \(newProfile.type.rawValue). Configuration written to disk.")

        if case .running = state {
            onLogMessage?("[CONFIG] Restarting node daemon to apply updated profile parameters...")
            await stop()
            try start()
        }
    }

    public func switchStorageMode(_ newStorageMode: StorageMode) async throws {
        if case .archival = newStorageMode {
            // Changing prune=0 on an already pruned data directory is NOT a valid
            // full-history conversion; it requires staged fresh IBD or -reindex.
            // Preserve the pruned wallet/chain until backup and rollback are verified.
            throw RPCClientError.serializationError(
                "Full History conversion is locked pending verified external storage, wallet backup, complete historical re-download and safe cutover. Compact mode remains available."
            )
        }
        self.config.storageMode = newStorageMode
        try config.writeToDisk()
        onLogMessage?("[STORAGE] Requested compact pruning at \\(newStorageMode.pruneMB) MiB.")
        if case .running = state {
            await stop()
            guard state == .stopped else {
                throw RPCClientError.serializationError("Knots did not shut down cleanly; pruning restart aborted.")
            }
            try start()
        }
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
