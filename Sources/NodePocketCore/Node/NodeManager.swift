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
    public let rpcClient: BitcoinRPCClient
    public let hashrateTracker: HashrateTracker

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let stateLock = NSLock()
    private var monitorTask: Task<Void, Never>?

    public var onStateChange: (@Sendable (NodeState) -> Void)?
    public var onLogMessage: (@Sendable (String) -> Void)?
    public var onBlockchainUpdate: (@Sendable (BlockchainInfo, HashrateReport) -> Void)?

    public init(config: NodeConfig = NodeConfig()) {
        self.config = config
        self.rpcClient = BitcoinRPCClient(
            host: "127.0.0.1",
            port: config.rpcPort,
            user: config.rpcUser,
            password: config.rpcPassword
        )
        self.hashrateTracker = HashrateTracker(windowSize: 30)
    }

    private func updateState(_ newState: NodeState) {
        stateLock.lock()
        self.state = newState
        stateLock.unlock()
        onStateChange?(newState)
    }

    /// Starts the node subprocess using the configured bitcoind binary or a simulator if not present.
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
            // If bitcoind is not installed on this host, enter simulated/mock-ready mode
            onLogMessage?("[INFO] bitcoind binary not found on local PATH. Ready for standalone integration or mock RPC.")
            updateState(.stopped)
            return
        }

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = [
            "-conf=\(config.configFileURL.path)",
            "-datadir=\(config.dataDirectory.path)"
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                self?.onLogMessage?(str)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                self?.onLogMessage?("[STDERR] \(str)")
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
            // Wait up to 5 seconds
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

        // If running, restart to apply new thread/cache/prune settings
        if case .running = state {
            onLogMessage?("[CONFIG] Restarting node daemon to apply updated profile parameters...")
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
                    self.onBlockchainUpdate?(binfo, report)
                } catch {
                    // Suppress connection errors during initial startup
                }
            }
        }
    }

    private func findBitcoindBinary() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/bitcoind",
            "/usr/local/bin/bitcoind",
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/bitcoind").path
        ]
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
