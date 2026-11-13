import SwiftUI
import AppKit
import NodePocketCore

public struct AdvancedSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss

    @State private var storageSelection: Int = 0 // 0 = Compact, 1 = Archival
    @State private var selectedPrunePreset: Int = StorageMode.defaultPruneMB
    @State private var customPruneInput: String = "\(StorageMode.defaultPruneMB)"
    @State private var externalArchivalPath: String = ""
    @State private var selectedProfile: SyncProfileType = .balanced
    @State private var dbCacheInput: String = "512"
    @State private var parInput: String = "2"
    @State private var maxConnectionsInput: String = "24"
    @State private var enableInboundP2P: Bool = false

    // Clean Uninstall & Data Wipe States
    @State private var showWipeConfirmation: Bool = false
    @State private var isWipingData: Bool = false
    @State private var wipeCompleted: Bool = false
    @State private var wipeErrorMessage: String? = nil
    @State private var uninstallResult: AppState.UninstallResult? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advanced Node & Storage Settings")
                        .font(.title2)
                        .bold()
                    Text("Configure storage modes, pruning limits, and sync intensity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Storage Mode Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Storage Mode & Blockchain Retention")
                            .font(.headline)

                        Picker("Storage Mode", selection: $storageSelection) {
                            Text("Compact Pruned (Default)").tag(0)
                            Text("Full History / Archival").tag(1)
                        }
                        .pickerStyle(.segmented)

                        if storageSelection == 0 {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Select Block Retention Limit (Minimum 550 MiB):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 8) {
                                    prunePresetButton(550, label: "550 MiB (Minimum)")
                                    prunePresetButton(1024, label: "1 GiB")
                                    prunePresetButton(2048, label: "2 GiB (Recommended)")
                                    prunePresetButton(4096, label: "4 GiB")
                                }

                                HStack {
                                    Text("Custom Retention Limit (MiB ≥ 550):")
                                        .font(.caption)
                                    Spacer()
                                    TextField("MiB", text: $customPruneInput)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 90)
                                }

                                rollingHistorySelectionPreview

                                Text("ℹ️ Note: Pruning limits apply to historical raw block files. A compact pruned node performs 100% cryptographic validation of all blocks and consensus rules.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Archival Mode Requirements")
                                        .font(.subheadline)
                                        .bold()
                                }

                                Text("Full-History / Archival mode requires retaining ~800+ GB of historical blocks. Because internal Mac storage is constrained, archival mode must be hosted on an external drive with ≥ 1 TB free space.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack {
                                    TextField("External Drive Target Path", text: $externalArchivalPath)
                                        .textFieldStyle(.roundedBorder)

                                    Button("Choose Drive...") {
                                        let openPanel = NSOpenPanel()
                                        openPanel.title = "Select External Volume for Archival Storage"
                                        openPanel.canChooseFiles = false
                                        openPanel.canChooseDirectories = true
                                        openPanel.canCreateDirectories = true
                                        if openPanel.runModal() == .OK, let url = openPanel.url {
                                            externalArchivalPath = url.path
                                        }
                                    }
                                }

                                Text("⚠️ Warning: Enabling archival mode requires a full re-index and redownloading all historical blocks from genesis. Your current pruned wallet and chain data will be preserved as a safe rollback.")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                        }
                    }

                    Divider()

                    // Sync Profile Presets
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sync Profile (Intensity)")
                            .font(.headline)

                        Picker("Profile", selection: $selectedProfile) {
                            ForEach(SyncProfileType.userSelectableCases, id: \.self) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedProfile) { newProfile in
                            let params = ProfileSettingsStore.shared.getParameters(for: newProfile)
                            dbCacheInput = "\(params.dbCacheMB)"
                            parInput = "\(params.parThreads)"
                            maxConnectionsInput = "\(params.maxConnections)"
                        }

                        Text(selectedProfile.description)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if state.isUltraActive {
                            HStack {
                                Image(systemName: "bolt.shield.fill")
                                    .foregroundColor(.orange)
                                Text("Ultra Power Saving is automatically active because your Mac is running on battery or actively charging. Your selected profile (\(selectedProfile.rawValue)) will resume when on stable AC power.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                        }
                    }

                    Divider()

                    Text("Current: \(state.selectedProfileType.rawValue) · \(state.appliedSettingsStatus)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Resource Limits
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Fine-Tuned Resource Limits (\(selectedProfile.rawValue))")
                                .font(.headline)
                            Spacer()
                            Button("Restore Defaults") {
                                ProfileSettingsStore.shared.restoreDefaults(for: selectedProfile)
                                let def = ProfileParameters.defaultParameters(for: selectedProfile)
                                dbCacheInput = "\(def.dbCacheMB)"
                                parInput = "\(def.parThreads)"
                                maxConnectionsInput = "\(def.maxConnections)"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("restore-profile-defaults")
                        }

                        HStack {
                            Text("Database Cache (MB):")
                            Spacer()
                            TextField("MB", text: $dbCacheInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }

                        HStack {
                            Text("Script Verification Threads (par):")
                            Spacer()
                            TextField("Threads", text: $parInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }

                        HStack {
                            Text("Max Peer Connections:")
                            Spacer()
                            TextField("Peers", text: $maxConnectionsInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }

                        Text(state.nodeManager.isUltraActive
                             ? "Ultra Power is active: the running Knots node is capped at 4 peers. A new value is saved and becomes effective after Ultra ends on stable AC."
                             : "Maximum peers is an upper bound, not the number Knots will dial. Applying a new cap restarts the managed node safely; without inbound reachability, outbound peers remain limited by network policy.")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Toggle("Enable Inbound P2P (does not configure your firewall or router)", isOn: $enableInboundP2P)
                            .font(.caption)
                        Text("Inbound connections require an open P2P port on your firewall/router. RPC remains loopback-only.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Isolation Assurance
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                            Text("Strict Loopback & Isolation Parameters")
                                .font(.headline)
                        }
                        Text("• RPC Host: 127.0.0.1 (Strict loopback; public ingress disabled)\n• Data Directory: ~/Library/Application Support/NodePocketBTCB2\n• File Permissions: 0700 dir / 0600 config\n• Bundle ID: app.nodepocket.btcb2")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Full Application & Data Uninstallation
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "trash.circle.fill")
                                .foregroundColor(.red)
                            Text("Full Application & Data Uninstallation")
                                .font(.headline)
                        }
                        Text("Completely remove Sentinel Node Wallet from this Mac, including all 18 GB of synchronized blockchain data, chainstate databases, wallet databases, and the application bundle itself.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button(role: .destructive, action: {
                                showWipeConfirmation = true
                            }) {
                                HStack(spacing: 6) {
                                    if isWipingData {
                                        ProgressView().controlSize(.small)
                                        Text("Uninstalling…")
                                    } else {
                                        Image(systemName: "trash.fill")
                                        Text("Fully Uninstall Application & All Files…")
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(isWipingData)

                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: state.nodeManager.config.dataDirectory.path)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                if state.isApplyingNodeSettings {
                    ProgressView().controlSize(.small)
                }
                Button("Apply Settings") {
                    applySettings()
                }
                .disabled(state.isApplyingNodeSettings)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 540, height: 600)
        .onAppear {
            loadCurrentSettings()
        }
        .alert("Fully Uninstall Application & All Files?", isPresented: $showWipeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Uninstall Everything", role: .destructive) {
                Task {
                    isWipingData = true
                    defer { isWipingData = false }
                    do {
                        let res = try await state.fullyUninstallApplicationAndAllFiles()
                        uninstallResult = res
                        wipeCompleted = true
                    } catch {
                        wipeErrorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("This will permanently remove Sentinel Node Wallet from your Mac:\n\n• All synchronized blockchain blocks and chainstate (~18 GB)\n• All wallet databases, auth records, and configuration\n• The application bundle itself\n\nThis action cannot be undone. Are you sure you want to proceed?")
        }
        .alert("Uninstallation Complete", isPresented: $wipeCompleted) {
            Button("Exit App Now") {
                NSApp.terminate(nil)
            }
        } message: {
            Text(uninstallResult?.details ?? "All blockchain data, wallets, and configuration files have been completely removed from your Mac.\n\nThe application will now exit.")
        }
        .alert("Failed to Uninstall", isPresented: Binding(
            get: { wipeErrorMessage != nil },
            set: { if !$0 { wipeErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { wipeErrorMessage = nil }
        } message: {
            Text(wipeErrorMessage ?? "An unknown error occurred while uninstalling the application.")
        }
    }

    /// Instant recomputation from latest verified node measurements.
    /// Editing the size NEVER changes running Knots settings until Apply.
    private var rollingHistorySelectionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Rolling historical ledger coverage")
                .font(.subheadline)
                .bold()
            if let coverage = state.rollingHistoryCoverage {
                Text("Currently retained: \(coverage.actualDisplay) • \(coverage.retainedBlockCount) blocks")
                    .font(.caption)
                Text("At selected \(customPruneInput) MiB: \(coverage.projectedDisplay(forPruneMiB: Int(customPruneInput) ?? 0))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if coverage.initialBlockDownload {
                    Text("Syncing historical blocks: projection calibrates near the live tip.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(state.rollingHistoryStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("A live forecast appears after Knots reports enough retained-history data.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text("Approximate block history, not wallet insurance. Changing the target does not restore already-pruned blocks. Months and years use average calendar lengths.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func prunePresetButton(_ mb: Int, label: String) -> some View {
        Button(action: {
            selectedPrunePreset = mb
            customPruneInput = "\(mb)"
        }) {
            Text(label)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(selectedPrunePreset == mb ? .blue : .primary)
    }

    private func loadCurrentSettings() {
        let currentStorage = state.storageMode
        if currentStorage.isPruned {
            storageSelection = 0
            selectedPrunePreset = currentStorage.pruneMB
            customPruneInput = "\(currentStorage.pruneMB)"
        } else {
            storageSelection = 1
            if case .archival(let url) = currentStorage {
                externalArchivalPath = url.path
            }
        }

        let currentProfile = state.nodeManager.config.profile
        selectedProfile = currentProfile.type
        let params = ProfileSettingsStore.shared.getParameters(for: currentProfile.type)
        dbCacheInput = "\(params.dbCacheMB)"
        parInput = "\(params.parThreads)"
        maxConnectionsInput = "\(params.maxConnections)"
        enableInboundP2P = state.nodeManager.config.allowInboundP2P
    }

    private func applySettings() {
        let mode: StorageMode
        if storageSelection == 0 {
            guard let prune = Int(customPruneInput), prune >= 550 else {
                state.alertMessage = "Enter a valid pruning limit of at least 550 MiB."
                state.showAlert = true
                return
            }
            mode = .compact(pruneMB: prune)
        } else {
            guard !externalArchivalPath.isEmpty else {
                state.alertMessage = "Choose a high-capacity external disk for archival rebuilding."
                state.showAlert = true
                return
            }
            mode = .archival(externalDataDir: URL(fileURLWithPath: externalArchivalPath))
        }

        guard let cache = Int(dbCacheInput), (128...4096).contains(cache),
              let par = Int(parInput), (1...8).contains(par),
              let peers = Int(maxConnectionsInput), (1...64).contains(peers) else {
            state.alertMessage = "Resource limits must be: cache 128–4096 MiB, verification threads 1–8, and peers 1–64."
            state.showAlert = true
            return
        }

        let customParams = ProfileParameters(
            parThreads: par,
            dbCacheMB: cache,
            maxConnections: peers,
            maxUploadTargetMB: SyncProfile.preset(for: selectedProfile).maxUploadTargetMB
        )
        ProfileSettingsStore.shared.saveParameters(for: selectedProfile, parameters: customParams)
        ProfileSettingsStore.shared.setSelectedProfileType(selectedProfile)

        var profile = ProfileSettingsStore.shared.getProfile(for: selectedProfile, pruneMB: mode.pruneMB)
        profile.dbCacheMB = cache
        profile.parThreads = par
        profile.maxConnections = peers
        profile.pruneMB = mode.pruneMB

        Task {
            do {
                try await state.applyNodeSettings(profile: profile, storageMode: mode, allowInboundP2P: enableInboundP2P)
                dismiss()
            } catch {
                state.alertMessage = "Settings were NOT applied: \(error.localizedDescription)"
                state.showAlert = true
            }
        }
    }

}
