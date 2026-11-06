import SwiftUI
import NodePocketCore

public struct WalletView: View {
    @EnvironmentObject var state: AppState
    @State private var showCreateModal = false
    @State private var walletNameInput = "main_wallet"
    @State private var passphraseInput = ""
    @State private var storeInKeychain = true

    // Gated Send Fields
    @State private var sendAddressInput = ""
    @State private var sendAmountInput = ""
    @State private var showSendConfirmModal = false

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with Chain Identity Verification
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wallet Manager")
                            .font(.system(size: 26, weight: .bold))
                        Text("Encrypted Descriptor Wallet • Native SegWit Bech32")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    chainIdentityBadge
                }

                // Balance Card
                VStack(alignment: .leading, spacing: 14) {
                    Text("Verified Spendable Balance")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(String(format: "%.8f BTCB2", state.walletSnapshot?.trustedBalance ?? 0.0))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))

                    Divider()

                    HStack(spacing: 24) {
                        balanceDetail(label: "Pending (0-Conf)", amount: state.walletSnapshot?.pendingBalance ?? 0.0)
                        balanceDetail(label: "Immature (Mining/Subsidy)", amount: state.walletSnapshot?.immatureBalance ?? 0.0)
                        Spacer()
                        if state.walletSnapshot?.isEncrypted == true {
                            Label("Encrypted & Locked", systemImage: "lock.shield.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    if (state.walletSnapshot?.immatureBalance ?? 0.0) > 0 {
                        Text("ℹ️ Note: Post-fork coinbase transactions require 6,480 to 25,920 block confirmations before becoming spendable.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Receive Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Receive BTCB2")
                        .font(.headline)

                    if !state.receiveAddress.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Receive Address (Bech32):")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                Text(state.receiveAddress)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(state.receiveAddress, forType: .string)
                                    state.appendLog("[UI] Copied receive address to clipboard.")
                                }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)))
                        }
                    }

                    Button(action: {
                        state.generateNewReceiveAddress()
                    }) {
                        Label("Generate Receive Address", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Gated Send Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.orange)
                        Text("Gated Send Transaction")
                            .font(.headline)
                        Spacer()
                        Text("Replay Protection Locked")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }

                    Text("Sending is strictly locked until the local node is 100% synchronized to the BIP-110 tip and SIGHASH_UNIFIED replay-safe signatures are verified.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        TextField("Recipient Bech32 Address", text: $sendAddressInput)
                            .textFieldStyle(.roundedBorder)
                        TextField("Amount (BTCB2)", text: $sendAmountInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)

                        Button("Send") {
                            showSendConfirmModal = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(true) // Locked until live tip verification
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Management Actions
                HStack(spacing: 12) {
                    Button(action: { showCreateModal = true }) {
                        Label("Create Encrypted Wallet", systemImage: "plus.app.fill")
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        let savePanel = NSSavePanel()
                        savePanel.title = "Backup Wallet Database"
                        savePanel.nameFieldStringValue = "wallet_backup_\(Int(Date().timeIntervalSince1970)).dat"
                        if savePanel.runModal() == .OK, let url = savePanel.url {
                            Task {
                                do {
                                    try await state.walletManager.exportBackup(to: url)
                                    state.appendLog("[WALLET] Successfully exported backup to \(url.path)")
                                } catch {
                                    state.alertMessage = "Backup failed: \(error.localizedDescription)"
                                    state.showAlert = true
                                }
                            }
                        }
                    }) {
                        Label("Backup Wallet", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.bordered)

                    Button(action: { state.refreshWallet() }) {
                        Label("Refresh Balances", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showCreateModal) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create Encrypted Descriptor Wallet")
                    .font(.title2)
                    .bold()

                TextField("Wallet Name", text: $walletNameInput)
                    .textFieldStyle(.roundedBorder)

                SecureField("Passphrase", text: $passphraseInput)
                    .textFieldStyle(.roundedBorder)

                Toggle("Save Passphrase to macOS Keychain (Touch ID/Local Auth)", isOn: $storeInKeychain)

                HStack {
                    Button("Cancel") { showCreateModal = false }
                        .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Create Wallet") {
                        Task {
                            do {
                                try await state.walletManager.createEncryptedDescriptorWallet(
                                    name: walletNameInput,
                                    passphrase: passphraseInput,
                                    storeInKeychain: storeInKeychain
                                )
                                showCreateModal = false
                                state.refreshWallet()
                            } catch {
                                state.alertMessage = "Wallet creation failed: \(error.localizedDescription)"
                                state.showAlert = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 440)
        }
    }

    private var chainIdentityBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: state.selectedNetwork == .regtest ? "hammer.fill" : "checkmark.shield.fill")
                .foregroundColor(state.selectedNetwork == .regtest ? .purple : .green)
            Text(state.selectedNetwork == .regtest ? "REGTEST TESTBED (Development Only)" : "BTCB2 MAINNET (BIP-110 Live Validation)")
                .font(.caption)
                .bold()
                .foregroundColor(state.selectedNetwork == .regtest ? .purple : .green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill((state.selectedNetwork == .regtest ? Color.purple : Color.green).opacity(0.15)))
    }

    private func balanceDetail(label: String, amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.8f", amount))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
    }
}
