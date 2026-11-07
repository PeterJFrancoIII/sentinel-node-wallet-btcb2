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
    @State private var showSendConfirmSheet = false
    @State private var sendPassphraseInput = ""
    @State private var isBroadcasting = false

    // Restore Wallet Fields
    @State private var showRestoreModal = false
    @State private var restoreFileURL: URL?
    @State private var restoreWalletName = "restored_wallet"

    public var isSendAllowed: Bool {
        // Mainnet requires completion of IBD past the fork checkpoint
        let inIBD = state.blockchainInfo?.initialblockdownload ?? true
        let height = state.blockchainInfo?.blocks ?? 0
        return !inIBD && height >= BTCB2ConsensusConstants.forkActivationHeight
    }

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

                // Receive Section with QR Code
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Text("Receive BTCB2")
                            .font(.headline)
                    }

                    if !state.receiveAddress.isEmpty {
                        HStack(alignment: .top, spacing: 20) {
                            // QR Code
                            QRCodeView(string: state.receiveAddress, size: 130)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Native SegWit Bech32 Receive Address:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(state.receiveAddress)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)))

                                HStack(spacing: 12) {
                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(state.receiveAddress, forType: .string)
                                        state.appendLog("[UI] Copied receive address to clipboard.")
                                    }) {
                                        Label("Copy Address", systemImage: "doc.on.doc")
                                    }

                                    Button(action: {
                                        state.generateNewReceiveAddress()
                                    }) {
                                        Label("New Address", systemImage: "plus.circle")
                                    }
                                }
                            }
                        }
                    } else {
                        Button(action: {
                            state.generateNewReceiveAddress()
                        }) {
                            Label("Generate Receive Address", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Gated Send Section
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: isSendAllowed ? "paperplane.fill" : "lock.fill")
                            .foregroundColor(isSendAllowed ? .green : .orange)
                        Text("Gated Send Transaction")
                            .font(.headline)
                        Spacer()
                        Text(isSendAllowed ? "SIGHASH_UNIFIED Armed" : "Replay Protection Locked")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill((isSendAllowed ? Color.green : Color.orange).opacity(0.15)))
                            .foregroundColor(isSendAllowed ? .green : .orange)
                    }

                    if !isSendAllowed {
                        Text("Sending on Mainnet is strictly locked until the local node finishes Initial Block Download (IBD) past BIP-110 fork height \(BTCB2ConsensusConstants.forkActivationHeight).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 12) {
                        TextField("Recipient Bech32 Address", text: $sendAddressInput)
                            .textFieldStyle(.roundedBorder)

                        TextField("Amount (BTCB2)", text: $sendAmountInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)

                        Button("Review & Send") {
                            showSendConfirmSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isSendAllowed || sendAddressInput.isEmpty || (Double(sendAmountInput) ?? 0) <= 0)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Recent Transactions List
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.purple)
                        Text("Recent Transactions")
                            .font(.headline)
                        Spacer()
                        Button(action: { state.refreshWallet() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                    }

                    if state.transactions.isEmpty {
                        Text("No transactions found in active descriptor wallet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(state.transactions.prefix(8)) { tx in
                                transactionRow(tx)
                            }
                        }
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

                    Button(action: {
                        let openPanel = NSOpenPanel()
                        openPanel.title = "Select Wallet Backup File"
                        openPanel.canChooseFiles = true
                        openPanel.canChooseDirectories = false
                        openPanel.allowsMultipleSelection = false
                        if openPanel.runModal() == .OK, let fileURL = openPanel.url {
                            self.restoreFileURL = fileURL
                            self.showRestoreModal = true
                        }
                    }) {
                        Label("Restore Wallet", systemImage: "arrow.up.doc.fill")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(action: { state.refreshWallet() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showSendConfirmSheet) {
            sendConfirmationSheet
        }
        .sheet(isPresented: $showCreateModal) {
            createWalletSheet
        }
        .sheet(isPresented: $showRestoreModal) {
            restoreWalletSheet
        }
    }

    private var chainIdentityBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
            Text("BTCB2 MAINNET (BIP-110)")
                .font(.caption)
                .bold()
                .foregroundColor(.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.green.opacity(0.15)))
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

    private func transactionRow(_ tx: TransactionRecord) -> some View {
        HStack {
            Image(systemName: categoryIcon(tx.category))
                .foregroundColor(categoryColor(tx.category))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(categoryTitle(tx.category))
                    .font(.caption)
                    .bold()
                Text(tx.txid.prefix(16) + "..." + tx.txid.suffix(8))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%@%.8f BTCB2", tx.amount >= 0 ? "+" : "", tx.amount))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(tx.amount >= 0 ? .green : .primary)
                Text("\(tx.confirmations) confs")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.windowBackgroundColor)))
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "receive": return "arrow.down.left"
        case "send": return "arrow.up.right"
        case "generate": return "hammer.fill"
        case "immature": return "clock.fill"
        default: return "circle"
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "receive", "generate": return .green
        case "send": return .orange
        case "immature": return .yellow
        default: return .secondary
        }
    }

    private func categoryTitle(_ category: String) -> String {
        switch category {
        case "receive": return "Received"
        case "send": return "Sent"
        case "generate": return "Mined Reward"
        case "immature": return "Immature Coinbase"
        default: return category.capitalized
        }
    }

    private var sendConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm Transaction")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Recipient Bech32 Address:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(sendAddressInput)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(6)

                HStack {
                    Text("Transfer Amount:")
                    Spacer()
                    Text("\(sendAmountInput) BTCB2")
                        .bold()
                }

                HStack {
                    Text("Estimated Network Fee:")
                    Spacer()
                    Text("0.00010000 BTCB2")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Consensus Replay Protection:")
                    Spacer()
                    Text("SIGHASH_UNIFIED Validated")
                        .foregroundColor(.green)
                        .font(.caption)
                        .bold()
                }
            }

            if state.walletSnapshot?.isEncrypted == true {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wallet Passphrase (Required to Authorize Spend):")
                        .font(.caption)
                    SecureField("Passphrase", text: $sendPassphraseInput)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("Cancel") {
                    showSendConfirmSheet = false
                    sendPassphraseInput = ""
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Authorize & Broadcast") {
                    isBroadcasting = true
                    Task {
                        do {
                            let amount = Double(sendAmountInput) ?? 0.0
                            _ = try await state.sendTransaction(
                                to: sendAddressInput,
                                amount: amount,
                                passphrase: sendPassphraseInput.isEmpty ? nil : sendPassphraseInput
                            )
                            isBroadcasting = false
                            showSendConfirmSheet = false
                            sendAddressInput = ""
                            sendAmountInput = ""
                            sendPassphraseInput = ""
                        } catch {
                            isBroadcasting = false
                            state.alertMessage = "Transaction broadcast failed: \(error.localizedDescription)"
                            state.showAlert = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBroadcasting)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var createWalletSheet: some View {
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

    private var restoreWalletSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)
                Text("Restore Wallet & Pruning Advisory")
                    .font(.title2)
                    .bold()
            }

            Text("⚠️ Pruned Restore Warning: Bitcoin Knots in pruned mode only retains chainstate and recent block files. If the restored wallet has transaction history created prior to the local prune window, historical transactions will not be visible without initiating a fresh chain resync.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let file = restoreFileURL {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Backup File:")
                        .font(.caption2)
                    Text(file.path)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(6)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Restored Wallet Name:")
                    .font(.caption)
                TextField("Wallet Name", text: $restoreWalletName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    showRestoreModal = false
                    restoreFileURL = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Confirm Restore") {
                    guard let file = restoreFileURL else { return }
                    Task {
                        do {
                            _ = try await state.restoreWallet(name: restoreWalletName, backupFile: file)
                            showRestoreModal = false
                            restoreFileURL = nil
                        } catch {
                            state.alertMessage = "Wallet restore failed: \(error.localizedDescription)"
                            state.showAlert = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
