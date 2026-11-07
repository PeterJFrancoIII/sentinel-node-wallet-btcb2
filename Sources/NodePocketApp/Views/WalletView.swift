import SwiftUI
import NodePocketCore

public struct WalletView: View {
    @EnvironmentObject var state: AppState

    // Wallet Lifecycle Sheets
    @State private var showCreateModal = false
    @State private var walletNameInput = "main_wallet"
    @State private var passphraseInput = ""
    @State private var passphraseConfirmInput = ""
    @State private var storeInKeychain = true
    @State private var showWalletPassphrase = false
    @State private var isCreatingWallet = false

    // Send Form Fields
    @State private var sendAddressInput = ""
    @State private var sendAmountInput = ""
    @State private var selectedFeePreset: FeePresetType = .normal
    @State private var customSatPerVBInput = "2"
    @State private var activePreview: FundedTxPreview?
    @State private var showPreviewSheet = false
    @State private var sendPassphraseInput = ""
    @State private var isBroadcasting = false
    @State private var sendErrorMessage: String?

    // Address Book / Allowlist Sheet
    @State private var showAddressBookSheet = false
    @State private var newRecipientName = ""
    @State private var newRecipientAddress = ""
    @State private var addressBookError: String?

    // Open / Restore Wallet Fields
    @State private var showOpenRestoreModal = false
    @State private var availableOnDiskWallets: [String] = []
    @State private var availableLoadedWallets: [String] = []
    @State private var selectedWalletToOpen: String = ""
    @State private var restoreFileURL: URL?
    @State private var restoreWalletName = "restored_wallet"
    @State private var isPerformingWalletAction = false
    @State private var hasConfirmedOfflinePassphrase = false

    // Transaction Filter
    @State private var selectedTxFilter: String = "all"

    private var isNodeReadyForWallet: Bool {
        if case .running = state.nodeState { return true }
        return false
    }

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
                        Text("Encrypted Descriptor Wallet • Native SegWit Bech32 • Integer Satoshi Math")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    chainIdentityBadge
                }

                if state.walletSnapshot == nil {
                    HStack(spacing: 12) {
                        Image(systemName: "wallet.pass")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Encrypted Wallet Loaded")
                                .font(.headline)
                            Text("Create a new encrypted descriptor wallet or open an existing wallet database to begin using BTCB2.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Create New Wallet") {
                            showCreateModal = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open / Restore") {
                            showOpenRestoreModal = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.08)))
                }

                // Balance Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Verified Spendable Balance")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(String(format: "%.8f BTCB2", state.walletSnapshot?.trustedBalance ?? 0.0))
                                .font(.system(size: 34, weight: .bold, design: .monospaced))

                            Text("\(SatoshiMath.formatSats(state.walletSnapshot?.trustedBalanceSats ?? 0)) sats")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if state.walletSnapshot?.isEncrypted == true {
                            Label("Encrypted & Locked", systemImage: "lock.shield.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.green.opacity(0.12)))
                        }
                    }

                    Divider()

                    HStack(spacing: 24) {
                        balanceDetail(
                            label: "Pending (0-Conf)",
                            amount: state.walletSnapshot?.pendingBalance ?? 0.0,
                            sats: state.walletSnapshot?.pendingBalanceSats ?? 0
                        )
                        balanceDetail(
                            label: "Immature (Mining Rewards)",
                            amount: state.walletSnapshot?.immatureBalance ?? 0.0,
                            sats: state.walletSnapshot?.immatureBalanceSats ?? 0
                        )
                    }

                    // Immature Coinbase Rewards Countdown & Epoch Breakdown
                    if (state.walletSnapshot?.immatureBalance ?? 0.0) > 0 || !state.coinbaseRewards.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "hourglass.circle.fill")
                                    .foregroundColor(.orange)
                                Text("Coinbase Rewards Maturity Countdown")
                                    .font(.subheadline)
                                    .bold()
                                Spacer()
                                Text("BIP-110 Consensus Schedule")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if state.coinbaseRewards.isEmpty {
                                Text("Mining rewards detected. Maturity schedule: 100 blocks (< 973,440), 6,480 blocks (~45 days for 973,440-979,918), 25,920 blocks (~180 days for >= 979,919 until Sep 2027 MTP expiry).")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(state.coinbaseRewards.prefix(3)) { reward in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Block #\(reward.originHeight) Reward (\(String(format: "%.4f", reward.amountBTC)) BTCB2)")
                                                .font(.caption)
                                                .bold()
                                            Text("Matures at height #\(reward.maturityHeight) • \(reward.remainingBlocks) blocks remaining")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(reward.estimatedTimeRemaining)
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundColor(reward.isMature ? .green : .orange)
                                            if reward.isLowConfidence {
                                                Text("Est. (~10m/blk)")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.windowBackgroundColor)))
                                }
                            }
                        }
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

                // Send Composer Section (Minimalist, Gated, V7-Compliant)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: isSendAllowed ? "paperplane.fill" : "lock.fill")
                            .foregroundColor(isSendAllowed ? .green : .orange)
                        Text("Send BTCB2 Transaction")
                            .font(.headline)
                        Spacer()

                        // Allowlist Badge & Manager Button
                        Button(action: { showAddressBookSheet = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: state.addressBook.isAllowlistEnabled ? "shield.checkmark.fill" : "shield.slash")
                                    .foregroundColor(state.addressBook.isAllowlistEnabled ? .green : .orange)
                                Text(state.addressBook.isAllowlistEnabled ? "Allowlist Active" : "Allowlist Off")
                                    .font(.caption2)
                                    .bold()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(NSColor.windowBackgroundColor)))
                        }
                        .buttonStyle(.plain)

                        Text(isSendAllowed ? "BIP-110 Armed" : "IBD Incomplete")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill((isSendAllowed ? Color.green : Color.orange).opacity(0.15)))
                            .foregroundColor(isSendAllowed ? .green : .orange)
                    }

                    if !isSendAllowed {
                        Text("Sending on Mainnet is strictly locked until Initial Block Download passes BIP-110 hard-fork height \(BTCB2ConsensusConstants.forkActivationHeight).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Recipient Selector / Input
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Recipient Address:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if !state.addressBook.recipients.isEmpty {
                                Menu("Select Trusted Recipient") {
                                    ForEach(state.addressBook.recipients) { r in
                                        Button("\(r.name) (\(r.address.prefix(12))...)") {
                                            sendAddressInput = r.address
                                        }
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .font(.caption)
                            }
                        }

                        TextField("bc1... (Native SegWit Bech32 only)", text: $sendAddressInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Amount Input
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Amount (BTCB2):")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("0.00000000", text: $sendAmountInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)

                            let parsedBTC = Double(sendAmountInput) ?? 0.0
                            let parsedSats = SatoshiMath.toSats(btc: parsedBTC)
                            Text("≈ \(SatoshiMath.formatSats(parsedSats)) satoshis")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Fee Selection (Cheapest / Normal / Fast / Custom)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Network Fee Target (Local BTCB2 Knots Quotes):")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            feeOptionButton(title: "Cheapest", subtitle: "24 blks (~4h)", preset: .cheapest)
                            feeOptionButton(title: "Normal", subtitle: "6 blks (~1h)", preset: .normal)
                            feeOptionButton(title: "Fast", subtitle: "2 blks (~20m)", preset: .fast)
                            feeOptionButton(title: "Custom", subtitle: "sat/vB", preset: .custom)
                        }

                        if selectedFeePreset == .custom {
                            HStack {
                                Text("Custom Fee Rate:")
                                    .font(.caption)
                                TextField("sat/vB", text: $customSatPerVBInput)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("sat/vB")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }

                    // Review & Preview Button
                    HStack {
                        Spacer()
                        Button(action: { generateSendPreview() }) {
                            Label("Review Transaction Preview", systemImage: "magnifyingglass.circle.fill")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(!isSendAllowed || sendAddressInput.isEmpty || (Double(sendAmountInput) ?? 0) <= 0)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Recent Transactions List with Verified Explorer Link
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.purple)
                        Text("Recent Transactions")
                            .font(.headline)

                        Spacer()

                        Picker("Filter", selection: $selectedTxFilter) {
                            Text("All").tag("all")
                            Text("Received").tag("receive")
                            Text("Sent").tag("send")
                            Text("Mining").tag("generate")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)

                        Button(action: {
                            state.refreshWallet()
                            state.refreshCoinbaseRewards()
                            state.refreshFeeQuotes()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Verified BTCB2 Explorer: mempool.guide (ordinary mempool.space tracks legacy SHA-256d chain)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    let filtered = filteredTransactions
                    if filtered.isEmpty {
                        Text("No transactions found matching current filter.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(filtered.prefix(12)) { tx in
                                transactionRow(tx)
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))

                // Management Actions Row
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
                        showOpenRestoreModal = true
                    }) {
                        Label("Open / Restore", systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(action: {
                        state.refreshWallet()
                        state.refreshCoinbaseRewards()
                        state.refreshFeeQuotes()
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
        .onAppear {
            state.refreshFeeQuotes()
            state.refreshCoinbaseRewards()
        }
        .sheet(isPresented: $showPreviewSheet) {
            sendPreviewSheet
        }
        .sheet(isPresented: $showAddressBookSheet) {
            addressBookSheet
        }
        .sheet(isPresented: $showCreateModal) {
            createWalletSheet
        }
        .sheet(isPresented: $showOpenRestoreModal) {
            openOrRestoreWalletSheet
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

    private func balanceDetail(label: String, amount: Double, sats: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.8f BTCB2", amount))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            Text("\(SatoshiMath.formatSats(sats)) sats")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func feeOptionButton(title: String, subtitle: String, preset: FeePresetType) -> some View {
        let isSelected = selectedFeePreset == preset
        let quote = state.feeQuotes[preset]
        let rate = quote?.satPerVB ?? (preset == .cheapest ? 1 : (preset == .normal ? 2 : 5))

        return Button(action: { selectedFeePreset = preset }) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.caption)
                    .bold()
                Text("\(rate) sat/vB")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.2) : Color(NSColor.windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var filteredTransactions: [TransactionRecord] {
        if selectedTxFilter == "all" {
            return state.transactions
        }
        return state.transactions.filter { $0.category == selectedTxFilter }
    }

    private func transactionRow(_ tx: TransactionRecord) -> some View {
        HStack {
            Image(systemName: categoryIcon(tx.category))
                .foregroundColor(categoryColor(tx.category))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(categoryTitle(tx.category))
                        .font(.caption)
                        .bold()

                    // Clickable Explorer link (mempool.guide)
                    if !tx.txid.isEmpty {
                        Button(action: {
                            if let url = URL(string: "https://mempool.guide/tx/\(tx.txid)") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 2) {
                                Text(tx.txid.prefix(12) + "..." + tx.txid.suffix(6))
                                    .font(.system(size: 10, design: .monospaced))
                                    .underline()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let height = tx.blockheight {
                    Text("Block #\(height) • \(tx.confirmations) confirmations")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%@%.8f BTCB2", tx.amount >= 0 ? "+" : "", tx.amount))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(tx.amount >= 0 ? .green : .primary)
                Text("\(SatoshiMath.formatSats(SatoshiMath.toSats(btc: tx.amount))) sats")
                    .font(.system(size: 10, design: .monospaced))
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
        case "generate", "immature": return "hammer.fill"
        default: return "circle.fill"
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "receive": return .green
        case "send": return .orange
        case "generate", "immature": return .purple
        default: return .blue
        }
    }

    private func categoryTitle(_ category: String) -> String {
        switch category {
        case "receive": return "Received"
        case "send": return "Sent"
        case "generate": return "Mined Reward"
        case "immature": return "Immature Reward"
        default: return category.capitalized
        }
    }

    private func generateSendPreview() {
        let btc = Double(sendAmountInput) ?? 0.0
        let sats = SatoshiMath.toSats(btc: btc)

        let quote: FeeQuote
        if selectedFeePreset == .custom {
            let customRate = max(1, Int(customSatPerVBInput) ?? 1)
            quote = FeeQuote(type: .custom, satPerVB: customRate, targetBlocks: 0, estimatedMinutes: 0)
        } else {
            quote = state.feeQuotes[selectedFeePreset] ?? FeeQuote(type: selectedFeePreset, satPerVB: 2, targetBlocks: selectedFeePreset.targetBlocks, estimatedMinutes: 60)
        }

        Task {
            do {
                let preview = try await state.prepareSendPreview(to: sendAddressInput, amountSats: sats, feeQuote: quote)
                await MainActor.run {
                    self.activePreview = preview
                    self.showPreviewSheet = true
                    self.sendErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.state.alertMessage = error.localizedDescription
                    self.state.showAlert = true
                }
            }
        }
    }

    // MARK: - Subviews & Modal Sheets

    private var sendPreviewSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Authorize BTCB2 Transaction")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    showPreviewSheet = false
                    activePreview = nil
                    sendPassphraseInput = ""
                }
                .buttonStyle(.plain)
            }

            Divider()

            if let preview = activePreview {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Destination Address (Full & Unmasked):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(preview.destinationAddress)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))

                        if let name = preview.recipientName {
                            Text("Trusted Recipient: \(name)")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Amount:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.8f BTCB2", SatoshiMath.toBTC(sats: preview.amountSats)))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                            Text("\(SatoshiMath.formatSats(preview.amountSats)) sats")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Network Fee (\(preview.satPerVB) sat/vB):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.8f BTCB2", SatoshiMath.toBTC(sats: preview.feeSats)))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                            Text("\(SatoshiMath.formatSats(preview.feeSats)) sats (\(preview.estimatedVSize) vB)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Debit from Wallet:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.8f BTCB2", SatoshiMath.toBTC(sats: preview.totalDebitSats)))
                            .font(.system(size: 20, weight: .heavy, design: .monospaced))
                            .foregroundColor(.primary)
                        Text("\(SatoshiMath.formatSats(preview.totalDebitSats)) sats")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let err = sendErrorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    HStack(spacing: 8) {
                        SecureField("Wallet passphrase (if not using saved credential)", text: $sendPassphraseInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Use Saved Passphrase") {
                            Task {
                                do {
                                    let keychain = KeychainHelper.shared
                                    let name = state.walletSnapshot?.name ?? ""
                                    guard !name.isEmpty else { return }
                                    let authorized = try await keychain.authenticateUserPresence(
                                        reason: "Fill saved BTCB2 wallet passphrase for " + name
                                    )
                                    guard authorized else { return }
                                    sendPassphraseInput = try await keychain.retrievePassphraseInteractively(account: name)
                                } catch {
                                    sendErrorMessage = "Keychain fill denied: \(error.localizedDescription)"
                                }
                            }
                        }
                        .disabled(state.walletSnapshot?.name == nil)
                    }

                    HStack {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Authorization window expires in 60s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }

                Spacer()

                HStack(spacing: 14) {
                    Button("Abort") {
                        showPreviewSheet = false
                        activePreview = nil
                        sendPassphraseInput = ""
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        isBroadcasting = true
                        Task {
                            do {
                                let txid = try await state.executeAuthorizedSend(preview: preview, explicitPassphrase: sendPassphraseInput.isEmpty ? nil : sendPassphraseInput)
                                await MainActor.run {
                                    self.isBroadcasting = false
                                    self.showPreviewSheet = false
                                    self.activePreview = nil
                                    self.sendPassphraseInput = ""
                                    self.sendAddressInput = ""
                                    self.sendAmountInput = ""
                                    self.state.alertMessage = "Transaction successfully broadcasted!\n\nTXID: \(txid)\n\nTrack on mempool.guide."
                                    self.state.showAlert = true
                                }
                            } catch {
                                await MainActor.run {
                                    self.isBroadcasting = false
                                    self.sendErrorMessage = error.localizedDescription
                                }
                            }
                        }
                    }) {
                        if isBroadcasting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Authenticate & Broadcast Spend", systemImage: "touchid")
                                .bold()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isBroadcasting)
                }
            }
        }
        .padding(24)
        .frame(width: 540, height: 460)
    }

    private var addressBookSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "person.crop.rectangle.stack.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Trusted Recipients Allowlist")
                    .font(.headline)
                Spacer()
                Button("Done") { showAddressBookSheet = false }
                    .buttonStyle(.plain)
            }

            // Allowlist Toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Strict Outgoing Allowlist Enforcement")
                        .font(.subheadline)
                        .bold()
                    Text("When active, the wallet strictly blocks transactions to any address not on this trusted list.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.addressBook.isAllowlistEnabled },
                    set: { enabled in
                        Task {
                            if (try? await KeychainHelper.shared.authenticateUserPresence(reason: "Authorize Allowlist security setting change")) == true {
                                await MainActor.run {
                                    state.setAllowlistEnabled(enabled)
                                }
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))

            Divider()

            // Add Recipient Form
            VStack(alignment: .leading, spacing: 8) {
                Text("Add New Trusted Recipient")
                    .font(.subheadline)
                    .bold()

                HStack(spacing: 10) {
                    TextField("Name / Label", text: $newRecipientName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)

                    TextField("Native SegWit Address (bc1...)", text: $newRecipientAddress)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        Task {
                            do {
                                if (try? await KeychainHelper.shared.authenticateUserPresence(reason: "Authorize adding trusted recipient '\(newRecipientName)'")) == true {
                                    _ = try state.addTrustedRecipient(name: newRecipientName, address: newRecipientAddress)
                                    await MainActor.run {
                                        self.newRecipientName = ""
                                        self.newRecipientAddress = ""
                                        self.addressBookError = nil
                                    }
                                }
                            } catch {
                                await MainActor.run {
                                    self.addressBookError = error.localizedDescription
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newRecipientAddress.isEmpty)
                }

                if let err = addressBookError {
                    Text(err)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            // List of Recipients
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Recipients (\(state.addressBook.recipients.count)):")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if state.addressBook.recipients.isEmpty {
                    Text("No trusted recipients saved yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    List {
                        ForEach(state.addressBook.recipients) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name)
                                        .font(.subheadline)
                                        .bold()
                                    Text(r.address)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(action: {
                                    try? state.removeTrustedRecipient(id: r.id)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.inset)
                    .frame(height: 160)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 500)
    }

    private var createWalletSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Encrypted Descriptor Wallet")
                .font(.headline)
            Text("The encryption passphrase unlocks this wallet. It is NOT a recovery seed; you must also back up the encrypted wallet database.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Wallet Name", text: $walletNameInput)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Group {
                    if showWalletPassphrase {
                        TextField("Encryption Passphrase", text: $passphraseInput)
                    } else {
                        SecureField("Encryption Passphrase", text: $passphraseInput)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    showWalletPassphrase.toggle()
                } label: {
                    Image(systemName: showWalletPassphrase ? "eye.slash" : "eye")
                }
                .help(showWalletPassphrase ? "Hide passphrase" : "Show passphrase")
                .buttonStyle(.borderless)
            }

            SecureField("Confirm Passphrase", text: $passphraseConfirmInput)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("Generate Strong Passphrase") {
                    do {
                        let generated = try WalletPassphraseGenerator.generate()
                        passphraseInput = generated
                        passphraseConfirmInput = generated
                        showWalletPassphrase = false
                    } catch {
                        state.alertMessage = error.localizedDescription
                        state.showAlert = true
                    }
                }

                Button("Use Saved Passphrase") {
                    Task {
                        do {
                            let keychain = KeychainHelper.shared
                            let authorized = try await keychain.authenticateUserPresence(
                                reason: "Fill the saved encryption passphrase for wallet " + walletNameInput
                            )
                            guard authorized else { return }
                            let saved = try await keychain.retrievePassphraseInteractively(account: walletNameInput)
                            passphraseInput = saved
                            passphraseConfirmInput = saved
                        } catch {
                            state.alertMessage = "Cannot fill saved passphrase: \(error.localizedDescription)"
                            state.showAlert = true
                        }
                    }
                }
                .disabled(walletNameInput.isEmpty)
            }
            .font(.caption)

            Toggle("Save in macOS Keychain (requires Mac user authentication)", isOn: $storeInKeychain)
                .font(.caption)

            if !storeInKeychain {
                Toggle("I have securely saved my passphrase and understand the node cannot unlock this wallet without it", isOn: $hasConfirmedOfflinePassphrase)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Text("This saves the wallet name and passphrase to app-protected macOS Keychain, NOT necessarily to Apple's Passwords app. ThisDeviceOnly protection does not sync to a new Mac. Keep a separate encrypted wallet backup.")
                .font(.caption2)
                .foregroundColor(.secondary)

            if !isNodeReadyForWallet {
                Label("Start the BTCB2 node before creating a wallet.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack {
                Button("Cancel") {
                    passphraseInput = ""
                    passphraseConfirmInput = ""
                    showWalletPassphrase = false
                    hasConfirmedOfflinePassphrase = false
                    showCreateModal = false
                }
                .buttonStyle(.bordered)

                Button("Open / Restore Existing Wallet…") {
                    showCreateModal = false
                    showOpenRestoreModal = true
                }
                .disabled(isCreatingWallet || !isNodeReadyForWallet)
                .buttonStyle(.bordered)

                Spacer()

                Button("Create Encrypted Wallet") {
                    guard !isCreatingWallet else { return }
                    let name = walletNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    let passphrase = passphraseInput
                    let save = storeInKeychain
                    guard WalletManager.isValidWalletName(name),
                          !passphrase.isEmpty,
                          passphrase == passphraseConfirmInput else {
                        state.alertMessage = "Enter a unique wallet name and matching encryption passphrases."
                        state.showAlert = true
                        return
                    }

                    isCreatingWallet = true
                    Task { @MainActor in
                        defer { isCreatingWallet = false }
                        do {
                            try await state.createEncryptedWallet(
                                name: name, passphrase: passphrase, storeInKeychain: save
                            )
                            showCreateModal = false
                            passphraseInput = ""
                            passphraseConfirmInput = ""
                            showWalletPassphrase = false
                            hasConfirmedOfflinePassphrase = false
                            state.alertMessage = "Encrypted descriptor wallet created and verified. Back up the wallet database before receiving substantial funds. Its passphrase alone cannot restore the wallet."
                            state.showAlert = true
                        } catch {
                            state.alertMessage = "Wallet creation was not confirmed: \(error.localizedDescription)\n\nIf Keychain storage is unavailable on this build, you may uncheck 'Save in macOS Keychain' to proceed without Keychain storage after securely recording your passphrase."
                            state.showAlert = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(
                    isCreatingWallet || !isNodeReadyForWallet ||
                    passphraseInput.isEmpty || passphraseInput != passphraseConfirmInput ||
                    (!storeInKeychain && !hasConfirmedOfflinePassphrase)
                )
            }
            if isCreatingWallet {
                ProgressView("Creating and verifying encrypted wallet…")
                    .controlSize(.small)
            }
        }
        .padding(24)
        .frame(width: 520, height: 490)
    }

    private var openOrRestoreWalletSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open or Restore Wallet")
                        .font(.title2)
                        .bold()
                    Text("Load an existing wallet from this Mac or restore from an encrypted backup file.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    showOpenRestoreModal = false
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Option 1: Open Local Wallet on this Mac
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text("Open Existing Wallet on this Mac")
                                .font(.headline)
                        }

                        let allWallets = Array(Set(availableOnDiskWallets + availableLoadedWallets)).sorted()
                        if allWallets.isEmpty {
                            Text("No wallet directories discovered in the node datadir.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Discovered Wallets:", selection: $selectedWalletToOpen) {
                                ForEach(allWallets, id: \.self) { w in
                                    let isLoaded = availableLoadedWallets.contains(w)
                                    Text("\(w) \(isLoaded ? "(Currently Loaded)" : "(On Disk)")").tag(w)
                                }
                            }
                            .pickerStyle(.menu)

                            HStack {
                                Spacer()
                                Button("Open Selected Wallet") {
                                    guard !selectedWalletToOpen.isEmpty else { return }
                                    isPerformingWalletAction = true
                                    Task { @MainActor in
                                        defer { isPerformingWalletAction = false }
                                        do {
                                            try await state.loadExistingWallet(name: selectedWalletToOpen)
                                            showOpenRestoreModal = false
                                            state.alertMessage = "Wallet '\(selectedWalletToOpen)' loaded successfully."
                                            state.showAlert = true
                                        } catch {
                                            state.alertMessage = "Failed to load wallet: \(error.localizedDescription)"
                                            state.showAlert = true
                                        }
                                    }
                                }
                                .disabled(selectedWalletToOpen.isEmpty || isPerformingWalletAction || !isNodeReadyForWallet)
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))

                    // Option 2: Restore from Backup File (.dat)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundColor(.green)
                            Text("Restore from Backup File (.dat)")
                                .font(.headline)
                        }

                        Text("Select a previously exported encrypted Knots wallet database (.dat). The wallet will be safely staged and verified.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button("Choose Backup File…") {
                                let panel = NSOpenPanel()
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                panel.allowedContentTypes = [.data]
                                if panel.runModal() == .OK, let url = panel.url {
                                    restoreFileURL = url
                                    let base = url.deletingPathExtension().lastPathComponent
                                    if WalletManager.isValidWalletName(base) {
                                        restoreWalletName = base
                                    }
                                }
                            }
                            .buttonStyle(.bordered)

                            if let url = restoreFileURL {
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .bold()
                            } else {
                                Text("No file chosen")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        TextField("Target Wallet Name", text: $restoreWalletName)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Spacer()
                            Button("Restore Wallet") {
                                guard let fileURL = restoreFileURL else { return }
                                let targetName = restoreWalletName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard WalletManager.isValidWalletName(targetName) else {
                                    state.alertMessage = "Enter a valid alphanumeric wallet name."
                                    state.showAlert = true
                                    return
                                }
                                isPerformingWalletAction = true
                                Task { @MainActor in
                                    defer { isPerformingWalletAction = false }
                                    do {
                                        let name = try await state.restoreWallet(name: targetName, backupFile: fileURL)
                                        showOpenRestoreModal = false
                                        state.alertMessage = "Successfully restored wallet '\(name)' from \(fileURL.lastPathComponent)."
                                        state.showAlert = true
                                    } catch {
                                        state.alertMessage = "Restore failed: \(error.localizedDescription)"
                                        state.showAlert = true
                                    }
                                }
                            }
                            .disabled(restoreFileURL == nil || restoreWalletName.isEmpty || isPerformingWalletAction || !isNodeReadyForWallet)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))

                    // Option 3: Explanation regarding QR Codes and Recovery
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.orange)
                            Text("Why Address QR Codes Cannot Restore a Wallet")
                                .font(.headline)
                        }
                        Text("A QR code of a receiving address or transaction only contains a public address or payment URI. It does NOT contain private keys or descriptors. To restore spendable funds, an encrypted wallet database backup (.dat) is required. Never paste private keys into untrusted external tools.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
                }
            }

            if isPerformingWalletAction {
                ProgressView("Processing wallet operation…")
                    .controlSize(.small)
            }
        }
        .padding(24)
        .frame(width: 540, height: 520)
        .task {
            await refreshDiscoveredWallets()
        }
    }

    private func refreshDiscoveredWallets() async {
        let (loaded, onDisk) = await state.fetchAvailableWallets()
        await MainActor.run {
            self.availableLoadedWallets = loaded
            self.availableOnDiskWallets = onDisk
            if selectedWalletToOpen.isEmpty {
                selectedWalletToOpen = loaded.first ?? onDisk.first ?? ""
            }
        }
    }
}
