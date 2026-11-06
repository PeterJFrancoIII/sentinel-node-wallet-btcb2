import SwiftUI
import NodePocketCore

public struct AdvancedSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss

    @State private var selectedProfile: SyncProfileType = .quiet
    @State private var pruneInput: String = "2048"
    @State private var dbCacheInput: String = "256"
    @State private var parInput: String = "1"
    @State private var maxConnectionsInput: String = "8"
    @State private var enableInboundP2P: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Advanced Node & Resource Settings")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Profile Preset Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sync Profile Preset")
                            .font(.headline)

                        Picker("Profile", selection: $selectedProfile) {
                            ForEach(SyncProfileType.allCases, id: \.self) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedProfile) { newProfile in
                            let preset = SyncProfile.preset(for: newProfile)
                            pruneInput = "\(preset.pruneMB)"
                            dbCacheInput = "\(preset.dbCacheMB)"
                            parInput = "\(preset.parThreads)"
                            maxConnectionsInput = "\(preset.maxConnections)"
                        }

                        Text(selectedProfile.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Resource Inputs
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Custom Resource Limits")
                            .font(.headline)

                        HStack {
                            Text("Prune Blockfile Limit (MiB):")
                            Spacer()
                            TextField("MiB", text: $pruneInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }

                        HStack {
                            Text("Database Cache (MB):")
                            Spacer()
                            TextField("MB", text: $dbCacheInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }

                        HStack {
                            Text("Script Verification Threads (par):")
                            Spacer()
                            TextField("Threads", text: $parInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }

                        HStack {
                            Text("Max Peer Connections:")
                            Spacer()
                            TextField("Peers", text: $maxConnectionsInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }

                        Toggle("Enable Inbound P2P (Default OFF for portable security)", isOn: $enableInboundP2P)
                    }

                    Divider()

                    // Isolation Assurance
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                            Text("Strict Isolation & Loopback Parameters")
                                .font(.headline)
                        }
                        Text("• RPC Host: 127.0.0.1 (Strict loopback; remote RPC permanently disabled)\n• Datadir: ~/Library/Application Support/NodePocketBTCB2\n• File Permissions: 0700 dir / 0600 config\n• Bundle ID: app.nodepocket.btcb2")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Apply & Restart Node") {
                    let prune = Int(pruneInput) ?? 2048
                    let dbcache = Int(dbCacheInput) ?? 256
                    let par = Int(parInput) ?? 1
                    let conns = Int(maxConnectionsInput) ?? 8

                    let customProfile = SyncProfile(
                        type: selectedProfile,
                        parThreads: par,
                        dbCacheMB: dbcache,
                        maxConnections: conns,
                        maxUploadTargetMB: 500,
                        pruneMB: prune
                    )

                    Task {
                        try? await state.nodeManager.switchProfile(customProfile)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520, height: 500)
        .onAppear {
            let current = state.nodeManager.config.profile
            selectedProfile = current.type
            pruneInput = "\(current.pruneMB)"
            dbCacheInput = "\(current.dbCacheMB)"
            parInput = "\(current.parThreads)"
            maxConnectionsInput = "\(current.maxConnections)"
        }
    }
}
