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
            onLogMessage?("[INFO] bitcoind binary not found on local PATH. Ready for standalone integration or mock RPC.")
            updateState(.stopped)
            return
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

    public func stop() async {
        updateState(.stopping)
        monitorTask?.cancel()
        monitorTask = nil

        // Attempt RPC stop first
        do {
            _ = try await rpcClient.stopNode()
            onLogMessage?("[NODE] Sent RPC stop signal to bitcoind.")
        } catch {
            onLogMessage?("[NODE] RPC stop call returned: \(error.localizedDescription); proceeding with process termination.")
        }

        if let proc = process, proc.isRunning {
            proc.terminate()
            for _ in 0..<10 {
                if !proc.isRunning { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }

        self.process = nil
        self.stdoutPipe = nil
        self.stderrPipe = nil
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
        self.config.storageMode = newStorageMode
        try config.writeToDisk()
        onLogMessage?("[STORAGE] Switched storage mode to \(newStorageMode.isPruned ? "Compact Pruned (\(newStorageMode.pruneMB) MiB)" : "Full History / Archival").")

        if case .running = state {
            onLogMessage?("[STORAGE] Restarting node daemon to apply updated storage mode...")
            await stop()
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

    public func findBitcoindBinary() -> URL? {
        var candidates: [String] = []

        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/bitcoind").path)

        if let execURL = Bundle.main.executableURL {
            candidates.append(execURL.deletingLastPathComponent().appendingPathComponent("bitcoind").path)
        }

        candidates.append("/Users/computer/Developer/NodePocketBTCB2/.cache/bitcoin-29.4.3.knots20260508/bin/bitcoind")
        candidates.append("/opt/homebrew/bin/bitcoind")
        candidates.append("/usr/local/bin/bitcoind")

        let fm = FileManager.default
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func caseMatchesError(_ state: NodeState) -> Bool {
        if case .error = state { return true }
        return false
    }
}
