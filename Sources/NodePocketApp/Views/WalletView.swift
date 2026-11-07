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

    // Multi-Wallet Inventory and Deletion
    @State private var showDeleteConfirmationSheet: Bool = false
    @State private var walletToDelete: WalletSummary? = nil
    @State private var typedDeleteName: String = ""
    @State private var deleteBackupPath: String = ""
    @State private var isCreatingBackupBeforeDelete: Bool = false
    @State private var deleteErrorMessage: String? = nil
    @State private var showArchivedSection: Bool = false

    // Transaction Filter
    @State private var selectedTxFilter: String = "all"

    // V13 Local Login & 2FA State
    @State private var loginUsername: String = ""
    @State private var loginPassword: String = ""
    @State private var appleSavedPasswordCoordinator: AppleSavedPasswordCoordinator? = nil
    @State private var loginTotpCode: String = ""
    @State private var loginRecoveryCode: String = ""
    @State private var showRecoveryLogin: Bool = false
    @State private var enrollUsername: String = ""
    @State private var enrollPassword: String = ""
    @State private var showEnrollmentPassword: Bool = false
    @State private var hasStoredRecoveryCodesOffline: Bool = false
    @State private var enrollTotpCode: String = ""
    @State private var isAuthActionInProgress: Bool = false
    @State private var authLocalError: String? = nil

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
            if !state.isWalletTabUnlocked {
                walletAuthLockedView
            } else {
                walletMainContentView
            }
        }
        .onAppear {
            state.refreshAuthState()
            if loginUsername.isEmpty { loginUsername = state.enrolledUsername ?? "" }
            state.refreshFeeQuotes()
            state.refreshCoinbaseRewards()
            state.refreshWalletInventory()
        }
        .onChange(of: state.nodeState) { _ in
            state.refreshWalletInventory()
        }
        .onChange(of: state.enrolledUsername) { newName in
            if loginUsername.isEmpty { loginUsername = newName ?? "" }
        }
        .onChange(of: state.isWalletTabUnlocked) { unlocked in
            if !unlocked {
                loginPassword = ""
                loginTotpCode = ""
                loginRecoveryCode = ""
            }
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
        .sheet(isPresented: $showDeleteConfirmationSheet) {
            deleteWalletSheet
        }
    }

    private var walletMainContentView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with Chain Identity Verification and Lock button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wallet Manager")
                        .font(.system(size: 26, weight: .bold))
                    Text("Encrypted Descriptor Wallet • Native SegWit Bech32 • Integer Satoshi Math")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .foregroundColor(.green)
                        Text(state.enrolledUsername ?? "Operator")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.1)))

                    Button(action: {
                        state.lockWallet()
                    }) {
                        Label("Lock", systemImage: "lock.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    chainIdentityBadge
                }
            }

            // Migration transparency banner
            if state.isMigrationPending {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Legacy Authenticator Migration Pending")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.yellow)
                        Text("Legacy authenticator migration pending — protected Keychain unavailable. Credential will automatically migrate upon verified login.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.12)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
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

                // All Discovered Wallets Inventory Section
                walletInventorySection

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
                        let targetWallet = state.walletSnapshot?.name ?? "wallet"
                        savePanel.nameFieldStringValue = "\(targetWallet)_backup_\(Int(Date().timeIntervalSince1970)).dat"
                        if savePanel.runModal() == .OK, let url = savePanel.url {
                            Task {
                                do {
                                    try await state.exportBackup(to: url)
                                    state.alertMessage = "Wallet backup successfully saved to:\n\(url.path)"
                                    state.showAlert = true
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

    private var walletAuthLockedView: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                chainIdentityBadge
            }

            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.blue)

                Text("Wallet Manager Locked")
                    .font(.system(size: 24, weight: .bold))

                Text("Operator username, strong password and 2-factor authentication (TOTP) are required to access wallets, balances, and keys.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            .padding(.top, 20)

            // Apple Passwords Honesty Callout
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal")
                    .font(.title3)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Passwords Support Status")
                        .font(.caption)
                        .bold()
                    Text("System-mediated Apple Passwords saving requires verified Developer ID associated-domain webcredentials AASA. Local manual login with standard authenticator app (RFC 6238) is active.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            .frame(maxWidth: 480)

            if state.isMigrationPending {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Legacy Authenticator Migration Pending")
                            .font(.caption)
                            .bold()
                            .foregroundColor(.yellow)
                        Text("Legacy authenticator migration pending — protected Keychain unavailable. Device-owner authentication required to authorize unmigrated login.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.12)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
                .frame(maxWidth: 480)
            }

            if !state.isAuthEnrolled {
                enrollmentCard
            } else {
                loginCard
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    private var enrollmentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("First-Time Operator Setup")
                .font(.headline)
            Text("Create a unique local username and strong password (min 10 chars, uppercase, lowercase, number, special character).")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Username").font(.caption).bold()
                TextField("operator", text: $enrollUsername)
                    .textContentType(.username)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("user-enroll-name")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Password").font(.caption).bold()
                Group {
                    if showEnrollmentPassword {
                        if #available(macOS 14.0, *) {
                            TextField("Strong Password", text: $enrollPassword)
                                .textContentType(.newPassword)
                        } else {
                            TextField("Strong Password", text: $enrollPassword)
                        }
                    } else {
                        if #available(macOS 14.0, *) {
                            SecureField("Strong Password", text: $enrollPassword)
                                .textContentType(.newPassword)
                        } else {
                            SecureField("Strong Password", text: $enrollPassword)
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("user-enroll-password")

                HStack(spacing: 12) {
                    Button("Generate Strong Password") {
                        do {
                            enrollPassword = try WalletAuthCoordinator.generateStrongOperatorPassword()
                            authLocalError = nil
                        } catch {
                            authLocalError = "Secure password generation failed: \(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.bordered)
                    Toggle("Show", isOn: $showEnrollmentPassword)
                        .toggleStyle(.checkbox)
                }
                Text("Apple Passwords may suggest a strong password when this app is signed and linked to an approved website. Automatic password saving is not available in this development build.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let data = state.generatedEnrollmentData {
                VStack(alignment: .leading, spacing: 8) {
                    Text("2-Factor Authenticator Setup (RFC 6238)").font(.caption).bold()
                    Text("Scan or enter this key in your authenticator app (Apple Passwords, Google Authenticator, etc.):")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button("Add Verification Code to Apple Passwords") {
                        // The user must approve the OS-controlled credential choice.
                        // Opening the URL does not itself certify a successful save.
                        var components = URLComponents(string: data.otpauthURI)
                        components?.scheme = "apple-otpauth"
                        guard let url = components?.url, NSWorkspace.shared.open(url) else {
                            authLocalError = "Could not open Apple Passwords verification-code setup. You can use another authenticator."
                            return
                        }
                        authLocalError = nil
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("user-enroll-apple-totp")
                    Text("Apple Passwords will ask which saved login should receive the code. Enter a current code below to verify setup. Keeping both factors in one vault reduces their independence.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack {
                        Text(data.secretBase32)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copy Key") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(data.secretBase32, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Emergency Recovery Codes (Save these offline!)").font(.caption2).bold()
                        Text(data.recoveryCodes.joined(separator: "  •  "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))

                    Toggle("I saved my recovery codes somewhere separate from this Mac", isOn: $hasStoredRecoveryCodesOffline)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .accessibilityIdentifier("user-enroll-recovery-confirmed")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enter 6-Digit Authenticator Code to Confirm").font(.caption).bold()
                        TextField("000000", text: $enrollTotpCode)
                            .textContentType(.oneTimeCode)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .accessibilityIdentifier("user-enroll-totp")
                    }
                }
            } else {
                Button("Generate 2FA Key & Emergency Codes") {
                    state.prepareEnrollment(username: enrollUsername)
                }
                .buttonStyle(.bordered)
                .disabled(enrollUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let err = authLocalError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button(action: {
                Task {
                    isAuthActionInProgress = true
                    authLocalError = nil
                    defer { isAuthActionInProgress = false }
                    do {
                        try await state.enrollUser(password: enrollPassword, totpCode: enrollTotpCode)
                        enrollPassword = ""
                        enrollTotpCode = ""
                        showEnrollmentPassword = false
                        hasStoredRecoveryCodesOffline = false
                    } catch {
                        authLocalError = error.localizedDescription
                    }
                }
            }) {
                if isAuthActionInProgress {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Complete Enrollment & Unlock")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.generatedEnrollmentData == nil || enrollTotpCode.count != 6 || !hasStoredRecoveryCodesOffline || isAuthActionInProgress)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
        .frame(maxWidth: 480)
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Operator Sign-In")
                .font(.headline)

            if !showRecoveryLogin {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Username").font(.caption).bold()
                    TextField("Username", text: $loginUsername)
                        .textContentType(.username)
                        .autocorrectionDisabled(true)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("user-login-name")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password").font(.caption).bold()
                    Group {
                        if #available(macOS 14.0, *) {
                            SecureField("Password", text: $loginPassword)
                                .textContentType(.password)
                        } else {
                            SecureField("Password", text: $loginPassword)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("user-login-password")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("6-Digit 2FA Verification Code").font(.caption).bold()
                    TextField("000000", text: $loginTotpCode)
                        .textContentType(.oneTimeCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .accessibilityIdentifier("user-login-totp")
                }

                Button("Fill from Apple Passwords…") {
                    // macOS controls user consent and any Touch ID or Mac-password prompt.
                    // A signed webcredentials associated domain is required before access.
                    let picker = AppleSavedPasswordCoordinator()
                    picker.onCredential = { username, password in
                        loginUsername = username
                        loginPassword = password
                        authLocalError = nil
                        appleSavedPasswordCoordinator = nil
                    }
                    picker.onFailure = { message in
                        authLocalError = message
                        appleSavedPasswordCoordinator = nil
                    }
                    appleSavedPasswordCoordinator = picker
                    picker.requestSavedLogin()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("user-login-apple-passwords")
                .disabled(isAuthActionInProgress)

                Text("macOS handles saved-login approval through Touch ID or the Mac password. Apple Passwords access requires a signed webcredentials association. Enter a 6-digit verification code to finish signing in.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let err = authLocalError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Button(action: {
                        Task {
                            isAuthActionInProgress = true
                            authLocalError = nil
                            defer { isAuthActionInProgress = false }
                            do {
                                try await state.loginUser(username: loginUsername, password: loginPassword, totpCode: loginTotpCode)
                                loginPassword = ""
                                loginTotpCode = ""
                            } catch {
                                authLocalError = error.localizedDescription
                            }
                        }
                    }) {
                        if isAuthActionInProgress {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Unlock Wallet Manager")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("user-login-submit")
                    .disabled(loginUsername.isEmpty || loginPassword.isEmpty || loginTotpCode.count != 6 || isAuthActionInProgress)

                    Spacer()

                    Button("Lost 2FA? Use Recovery Code") {
                        showRecoveryLogin = true
                        authLocalError = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Username").font(.caption).bold()
                    TextField("Username", text: $loginUsername)
                        .textContentType(.username)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Emergency One-Time Recovery Code").font(.caption).bold()
                    TextField("8-character code", text: $loginRecoveryCode)
                        .textFieldStyle(.roundedBorder)
                }

                if let err = authLocalError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Button(action: {
                        Task {
                            isAuthActionInProgress = true
                            authLocalError = nil
                            defer { isAuthActionInProgress = false }
                            do {
                                try await state.loginWithRecoveryCode(username: loginUsername, code: loginRecoveryCode)
                            } catch {
                                authLocalError = error.localizedDescription
                            }
                        }
                    }) {
                        if isAuthActionInProgress {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Unlock with Recovery Code")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loginUsername.isEmpty || loginRecoveryCode.isEmpty || isAuthActionInProgress)

                    Spacer()

                    Button("Back to Standard Login") {
                        showRecoveryLogin = false
                        authLocalError = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
        .frame(maxWidth: 480)
    }

    private var walletInventorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundColor(.blue)
                Text("All Created Wallets (\(state.walletSummaries.count))")
                    .font(.headline)
                Spacer()
                if state.isRefreshingInventory {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Refresh") {
                    state.refreshWalletInventory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("+ Create") {
                    showCreateModal = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Open/Restore") {
                    showOpenRestoreModal = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if state.walletSummaries.isEmpty {
                Text("No local wallets discovered in datadir. Click '+ Create' to initialize an encrypted descriptor wallet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                let activeWallets = state.walletSummaries.filter { !$0.isArchived }
                let archivedWallets = state.walletSummaries.filter { $0.isArchived }

                ForEach(activeWallets) { summary in
                    walletRow(summary: summary)
                }

                if !archivedWallets.isEmpty {
                    DisclosureGroup(
                        isExpanded: $showArchivedSection,
                        content: {
                            VStack(spacing: 8) {
                                ForEach(archivedWallets) { summary in
                                    walletRow(summary: summary)
                                }
                            }
                            .padding(.top, 6)
                        },
                        label: {
                            HStack {
                                Image(systemName: "archivebox")
                                Text("Archived Wallets (\(archivedWallets.count))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
    }

    private func walletRow(summary: WalletSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.name)
                        .font(.headline)

                    if state.walletSnapshot?.name == summary.name {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.2)))
                            .foregroundColor(.blue)
                    }

                    if summary.isLoaded {
                        Text("Loaded")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                            .foregroundColor(.green)
                    } else {
                        Text("Unloaded")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.gray.opacity(0.2)))
                            .foregroundColor(.secondary)
                    }

                    if summary.isArchived {
                        Text("Archived")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundColor(.orange)
                    }

                    if summary.isEncrypted {
                        Image(systemName: summary.isLocked ? "lock.fill" : "lock.open.fill")
                            .font(.caption2)
                            .foregroundColor(summary.isLocked ? .green : .orange)
                    }
                }

                HStack(spacing: 8) {
                    if let status = summary.statusMessage {
                        Text(status)
                            .font(.caption2)
                            .foregroundColor(summary.isStale ? .secondary : .primary)
                    }
                    Text("Total: \(summary.totalBTCB2) BTCB2 (\(SatoshiMath.formatSats(summary.totalSats)) sats)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Spendable: \(summary.spendableBTCB2) • Pending: \(summary.pendingBTCB2) • Immature: \(summary.immatureBTCB2)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Row Action Buttons
            HStack(spacing: 8) {
                if summary.isLoaded && state.walletSnapshot?.name != summary.name {
                    Button("Select") {
                        state.selectWallet(name: summary.name)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if !summary.isLoaded {
                    Button("Load") {
                        state.selectWallet(name: summary.name)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !summary.isArchived {
                    Button("Archive") {
                        state.archiveWallet(name: summary.name)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Unload wallet from memory and collapse into Archived list. No files are deleted.")
                } else {
                    Button("Unarchive") {
                        state.unarchiveWallet(name: summary.name)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(action: {
                    walletToDelete = summary
                    typedDeleteName = ""
                    deleteBackupPath = ""
                    deleteErrorMessage = nil
                    showDeleteConfirmationSheet = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(summary.canDeleteSafely ? .red : .gray)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .disabled(!summary.canDeleteSafely)
                .help(summary.canDeleteSafely
                      ? "Safely move verified empty wallet to macOS Trash (reversible)"
                      : "Cannot delete wallet with non-zero or unverified balance to prevent loss of funds. Use Archive instead.")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.windowBackgroundColor)))
    }

    private var deleteWalletSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "trash.circle.fill")
                    .font(.title)
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete Wallet from this Mac")
                        .font(.headline)
                    Text("Reversible macOS Trash Deletion for '\(walletToDelete?.name ?? "")'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    showDeleteConfirmationSheet = false
                }
                .buttonStyle(.bordered)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Preflight Safety Verification")
                    .font(.subheadline)
                    .bold()
                Text("• Balance must be verified 0 sats across spendable, pending, and immature balances.\n• Wallet will be unloaded from Knots and moved to your macOS Trash (reversible).\n• Important: If this wallet generated addresses in the past, someone could send funds to them in the future. A mandatory backup must be saved first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))

            // Backup step
            VStack(alignment: .leading, spacing: 6) {
                Text("Step 1: Mandatory Backup Verification")
                    .font(.subheadline)
                    .bold()
                if deleteBackupPath.isEmpty {
                    Button("Create Verified Backup to Downloads") {
                        Task {
                            guard let name = walletToDelete?.name else { return }
                            isCreatingBackupBeforeDelete = true
                            deleteErrorMessage = nil
                            defer { isCreatingBackupBeforeDelete = false }
                            do {
                                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                                let backupFile = downloads.appendingPathComponent("Sentinel_Backup_\(name)_\(Int(Date().timeIntervalSince1970)).dat")
                                try await state.nodeManager.rpcClient.backupWallet(destinationPath: backupFile.path, walletName: name)
                                if FileManager.default.fileExists(atPath: backupFile.path) {
                                    deleteBackupPath = backupFile.path
                                }
                            } catch {
                                deleteErrorMessage = "Backup failed: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreatingBackupBeforeDelete)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Backup verified: \(deleteBackupPath)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }

            // Typed name step
            VStack(alignment: .leading, spacing: 6) {
                Text("Step 2: Confirm by Typing Wallet Name")
                    .font(.subheadline)
                    .bold()
                Text("Type '\(walletToDelete?.name ?? "")' exactly to confirm:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Wallet Name", text: $typedDeleteName)
                    .textFieldStyle(.roundedBorder)
            }

            if let err = deleteErrorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    showDeleteConfirmationSheet = false
                }
                .buttonStyle(.bordered)

                Button("Move to macOS Trash") {
                    guard let name = walletToDelete?.name else { return }
                    state.deleteWallet(
                        name: name,
                        typedConfirmation: typedDeleteName,
                        verifiedBackupPath: deleteBackupPath
                    )
                    showDeleteConfirmationSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(typedDeleteName != (walletToDelete?.name ?? "") || deleteBackupPath.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
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
