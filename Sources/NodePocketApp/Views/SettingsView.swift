import SwiftUI
import NodePocketCore

public struct SettingsView: View {
    @EnvironmentObject var state: AppState

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Node & Security Settings")
                        .font(.title2)
                        .bold()
                    Text("Configuration parameters and strict isolation properties.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Network & Consensus")
                        .font(.headline)

                    HStack {
                        Text("Active Chain:")
                        Spacer()
                        Text(state.nodeManager.config.network.chainName)
                            .bold()
                    }

                    HStack {
                        Text("RPC Port (Localhost 127.0.0.1):")
                        Spacer()
                        Text("\(state.nodeManager.config.rpcPort)")
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Text("P2P Port:")
                        Spacer()
                        Text("\(state.nodeManager.config.p2pPort)")
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Text("Data Directory:")
                        Spacer()
                        Text(state.nodeManager.config.dataDirectory.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text("Strict Security & Isolation Matrix")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        securityRow(title: "Public Ingress Disabled", detail: "rpcbind=127.0.0.1 strictly bound; external network requests rejected")
                        securityRow(title: "Standalone Filesystem", detail: "Configured at ~/Library/Application Support/NodePocketBTCB2 with 0700 permissions")
                        securityRow(title: "Credential Isolation", detail: "High-entropy random RPC password stored locally; never synced to git or remote stores")
                        securityRow(title: "Cross-Project Zero Coupling", detail: "No dependencies, shared volumes, or RPC links to Sentinel, EMC, or BM-S3")
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            }
            .padding(24)
        }
    }

    private func securityRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .bold()
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
