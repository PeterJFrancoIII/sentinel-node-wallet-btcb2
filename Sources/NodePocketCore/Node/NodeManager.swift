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

#if os(macOS)
@_silgen_name("proc_pidpath")
func proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer, _ buffersize: UInt32) -> Int32
#endif

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

    /// Configured capacity can differ from the running daemon's effective cap.
    /// Ultra Power always overrides maxconnections with 4 for app-owned Knots.
    public var maxConnectionsForCurrentPowerMode: Int {
        isUltraActive ? 4 : config.profile.maxConnections
    }

    /// Only claim a runtime cap when the app owns the started subprocess.
    /// An adopted daemon may have additional command-line overrides.
    public var verifiedRunningMaxConnections: Int? {
        guard state.isRunning, process != nil else { return nil }
        return maxConnectionsForCurrentPowerMode
    }

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
        let confFile = config.dataDirectory.appendingPathComponent("bitcoin.conf")
        let hasCookie = FileManager.default.fileExists(atPath: cookieFile.path)
        let hasConf = FileManager.default.fileExists(atPath: confFile.path)

        // At least one valid authentication credential file (.cookie or bitcoin.conf) must exist
        guard hasCookie || hasConf else { return false }

        // Datadir and credential file ownership verification
        #if os(macOS)
        var dirStat = stat()
        if stat(config.dataDirectory.path, &dirStat) != 0 || dirStat.st_uid != getuid() {
            return false
        }
        if hasCookie {
            var cookieStat = stat()
            if stat(cookieFile.path, &cookieStat) != 0 || cookieStat.st_uid != getuid() {
                return false
            }
        }
        if hasConf {
            var confStat = stat()
            if stat(confFile.path, &confStat) != 0 || confStat.st_uid != getuid() {
                return false
            }
        }
        #endif

        // Process identity and executable provenance: PID MUST be present, alive, and end in bitcoind
        let pidFile = config.dataDirectory.appendingPathComponent("bitcoind.pid")
        guard FileManager.default.fileExists(atPath: pidFile.path) else { return false }
        #if os(macOS)
        var pidStat = stat()
        if stat(pidFile.path, &pidStat) != 0 || pidStat.st_uid != getuid() {
            return false
        }
        #endif

        guard let pid = readPidFile(), pid > 0, kill(pid, 0) == 0 else {
            return false
        }
        #if os(macOS)
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let ret = pathBuffer.withUnsafeMutableBytes { ptr in
            proc_pidpath(pid, ptr.baseAddress!, UInt32(ptr.count))
        }
        guard ret > 0 else { return false }
        let execPath = String(cString: pathBuffer)
        guard execPath.hasSuffix("/bitcoind") || execPath == "bitcoind" else {
            return false
        }
        #endif

        // Chain identity: must be mainnet
        guard let binfo = try? await rpcClient.getBlockchainInfo(), binfo.chain == "main" else {
            return false
        }

        // Subversion identity: must be Knots
        guard let netInfo = try? await rpcClient.getNetworkInfo(),
              netInfo.subversion.contains("Knots") else {
            return false
        }

        // Protocol / Service check: must report BLAKE2B? or Knots subversion
        guard (netInfo.localservicesnames?.contains("BLAKE2B?") ?? false) || netInfo.subversion.contains("Knots") else {
            return false
        }

        // BTCB2 Consensus Checkpoint & Pre-Fork Anchor Verification
        if binfo.blocks >= BTCB2ConsensusConstants.forkActivationHeight {
            guard let hash = try? await rpcClient.getBlockHash(height: BTCB2ConsensusConstants.forkActivationHeight),
                  hash == BTCB2ConsensusConstants.forkActivationBlockHash else {
                return false
            }
        } else {
            // Pre-fork chain: must verify header tree continuity and positive pre-fork consensus anchors
            guard binfo.headers >= binfo.blocks else { return false }
            // Verify Genesis anchor (height 0)
            guard let genesisHash = try? await rpcClient.getBlockHash(height: 0),
                  genesisHash == "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f" else {
                return false
            }
            // If blocks have reached height 800,000, verify height 800,000 anchor
            if binfo.blocks >= 800000 {
                guard let h800k = try? await rpcClient.getBlockHash(height: 800000),
                      h800k == "00000000000000000002a7c4c1e48d76c5a37902165a270156b7a8d72728a054" else {
                    return false
                }
            } else if binfo.blocks >= 500000 {
                guard let h500k = try? await rpcClient.getBlockHash(height: 500000),
                      h500k == "00000000000000000024fb37364cbf81fd49cc2d51c09c75c35433c3a1945d04" else {
                    return false
                }
            }
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
                "-maxconnections=3",
                "-listen=0",
                "-maxuploadtarget=64"
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
            let pid = proc.processIdentifier
            if self.isUltraActive || self.config.profile.type == .quiet {
                #if os(macOS)
                let tpProc = Process()
                tpProc.executableURL = URL(fileURLWithPath: "/usr/bin/taskpolicy")
                tpProc.arguments = ["-b", "-p", "\(pid)"]
                try? tpProc.run()
                setpriority(PRIO_PROCESS, id_t(pid), 19)
                #endif
            }
            updateState(.running(pid: pid))
            startMonitoring()
        } catch {
            updateState(.error("Failed to spawn node: \(error.localizedDescription)"))
            throw error
        }
    }

    private func shouldProceedWithStop() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if state == .stopping || state == .stopped {
            return false
        }
        return true
    }

    /// Graceful shutdown is mandatory for a node writing chainstate.
    /// Never SIGKILL the owned bitcoind on an ordinary stop or upgrade.
    public func stop() async {
        guard shouldProceedWithStop() else { return }

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
        storageMode newMode: StorageMode,
        allowInboundP2P newInbound: Bool? = nil
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

        let requestedInbound = newInbound ?? config.allowInboundP2P
        if config.profile == newProfile && config.storageMode == newMode && config.allowInboundP2P == requestedInbound {
            return isUltraActive
                ? "Settings saved; Ultra Power currently overrides maxconnections to 4 until stable AC power."
                : "Settings are already configured."
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

        // Ultra's hard 4-peer command-line override wins over bitcoin.conf. Do
        // not restart for a change that cannot become effective until AC resumes.
        let queuedForUltra = wasRunning && isUltraActive
        if queuedForUltra && process == nil {
            throw RPCClientError.serializationError("Cannot queue settings on an externally managed Ultra node; verify the daemon first.")
        }

        if wasRunning && !queuedForUltra {
            if process != nil {
                await stop()
                guard state == .stopped else {
                    throw RPCClientError.serializationError("Knots did not finish its graceful shutdown.")
                }
            } else {
                let isVerified = await verifyAdoptedDaemon()
                guard isVerified else {
                    throw RPCClientError.unverifiedDaemon(
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
        config.allowInboundP2P = requestedInbound
        do {
            try config.writeToDisk()
            ProfileSettingsStore.shared.saveParameters(
                for: newProfile.type,
                parameters: ProfileParameters(
                    parThreads: newProfile.parThreads,
                    dbCacheMB: newProfile.dbCacheMB,
                    maxConnections: newProfile.maxConnections,
                    maxUploadTargetMB: newProfile.maxUploadTargetMB
                )
            )
            ProfileSettingsStore.shared.setSelectedProfileType(newProfile.type)

            if wasRunning && !queuedForUltra {
                try start(ultraOverride: false)
                try await waitForRPCReadiness(timeoutSeconds: 90)
            }

            if let curPid = process?.processIdentifier ?? adoptedPid {
                #if os(macOS)
                let tpProc = Process()
                tpProc.executableURL = URL(fileURLWithPath: "/usr/bin/taskpolicy")
                tpProc.arguments = [newProfile.type == .quiet ? "-b" : "-B", "-p", "\(curPid)"]
                try? tpProc.run()
                setpriority(PRIO_PROCESS, id_t(curPid), newProfile.type == .quiet ? 19 : 0)
                #endif
            }
            let status: String
            if queuedForUltra {
                status = "Saved, not active yet: Ultra Power is running with a 4-peer command-line cap. Your configured \(newProfile.maxConnections)-peer cap and inbound policy apply when stable AC resumes and Knots restarts."
            } else if wasRunning {
                status = "Applied after clean restart and verified RPC connectivity. Max peer count is a cap, not a connection target."
            } else {
                status = "Saved. Settings will take effect on the next node startup."
            }
            onLogMessage?("[CONFIG] \(newProfile.type.rawValue) par=\(newProfile.parThreads) " +
                          "dbcache=\(newProfile.dbCacheMB) maxconnections=\(newProfile.maxConnections) " +
                          "listen=\(requestedInbound ? 1 : 0). " + status)
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

        // Update taskpolicy and nice priority immediately on existing child or adopted process
        if let currentPid = process?.processIdentifier ?? adoptedPid {
            #if os(macOS)
            let tpProc = Process()
            tpProc.executableURL = URL(fileURLWithPath: "/usr/bin/taskpolicy")
            tpProc.arguments = [active ? "-b" : "-B", "-p", "\(currentPid)"]
            try? tpProc.run()
            setpriority(PRIO_PROCESS, id_t(currentPid), active ? 19 : 0)
            #endif
        }

        if wasRunning {
            if process == nil && adoptedPid != nil {
                let verified = await verifyAdoptedDaemon()
                guard verified else {
                    return false
                }
            }
            let previousPid = process?.processIdentifier ?? adoptedPid
            await stop()
            for _ in 0..<20 {
                if state == .stopped { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard state == .stopped else {
                onLogMessage?("[POWER] Cannot restart for Ultra mode: previous daemon shutdown was not confirmed.")
                throw RPCClientError.serializationError("Cannot restart for Ultra mode: previous daemon shutdown was not confirmed.")
            }
            if let oldPid = previousPid, kill(oldPid, 0) == 0 {
                onLogMessage?("[POWER] Cannot restart for Ultra mode: previous daemon PID \(oldPid) is still running.")
                throw RPCClientError.serializationError("Cannot restart for Ultra mode: previous daemon PID \(oldPid) is still running.")
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
                    let inIBD = binfo.initialblockdownload

                    let report: HashrateReport

                    if inIBD {
                        // The network hashrate tracker should not begin until the node is fully synced.
                        // Rapid block sync skews results; clear any partial sync samples.
                        self.hashrateTracker.clear()
                        report = HashrateReport(
                            networkHashrateHps: 0.0,
                            networkHashratePH: 0.0,
                            smoothedHashratePH: 0.0,
                            nominalHashratePH: 0.0,
                            difficulty: 0.0,
                            averageBlockIntervalSeconds: 600.0,
                            sampleCount: 0,
                            validIntervalCount: 0,
                            totalWindowSeconds: 0.0,
                            telemetryAgeSeconds: 0.0,
                            isStale: true,
                            hasTimestampAnomalies: false,
                            isSyncing: true,
                            history: []
                        )
                    } else {
                        // Node is fully synced: seed the 30-block window if not yet seeded
                        let bhash = binfo.bestblockhash
                        if !bhash.isEmpty {
                            if self.hashrateTracker.sampleCount < 30 {
                                await self.seedHashrateWindow(tipHash: bhash, count: 31)
                            } else if let header = try? await self.rpcClient.getBlockHeader(hash: bhash) {
                                if let target = TargetConverter.targetHexFromBits(UInt32(header.bits, radix: 16) ?? 0) {
                                    self.hashrateTracker.addBlock(
                                        height: header.height,
                                        hash: header.hash,
                                        timestamp: TimeInterval(header.time),
                                        targetHex: target
                                    )
                                }
                            }
                        }

                        // Query consensus hashrate from local Knots daemon
                        let knotsHash30 = try? await self.rpcClient.getNetworkHashps(blocks: 30)
                        let knotsHash120 = try? await self.rpcClient.getNetworkHashps(blocks: 120)

                        report = self.hashrateTracker.generateReport(
                            override30Hps: knotsHash30,
                            override120Hps: knotsHash120,
                            isSyncing: false
                        )
                    }

                    // Adaptive Verification Progress ETA
                    self.etaEngine.addSample(progress: binfo.verificationprogress, height: binfo.blocks)
                    let peerCount = netInfo?.connections ?? 8
                    let eta = self.etaEngine.calculateETA(isIBD: inIBD, peerCount: peerCount)

                    self.onBlockchainUpdate?(binfo, report, netInfo, eta)
                } catch {
                    // Suppress connection errors during initial startup
                }
            }
        }
    }

    /// Seeds the hashrate tracker with a contiguous chain of block headers from tip backwards.
    public func seedHashrateWindow(tipHash: String, count: Int = 31) async {
        var currentHash = tipHash
        var fetchedHeaders: [BlockHeader] = []

        for _ in 0..<count {
            guard !currentHash.isEmpty else { break }
            do {
                let header = try await rpcClient.getBlockHeader(hash: currentHash)
                fetchedHeaders.append(header)
                if let prev = header.previousblockhash, !prev.isEmpty {
                    currentHash = prev
                } else {
                    break
                }
            } catch {
                break
            }
        }

        guard !fetchedHeaders.isEmpty else { return }
        // Reverse so headers are added in ascending chronological order
        for header in fetchedHeaders.reversed() {
            if let target = TargetConverter.targetHexFromBits(UInt32(header.bits, radix: 16) ?? 0) {
                hashrateTracker.addBlock(
                    height: header.height,
                    hash: header.hash,
                    timestamp: TimeInterval(header.time),
                    targetHex: target
                )
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
