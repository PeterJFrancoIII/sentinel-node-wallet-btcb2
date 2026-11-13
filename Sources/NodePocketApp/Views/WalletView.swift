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
    @State private var sendAmountUSDInput = ""
    @State private var sendAmountPercentInput = ""
    @State private var isSyncingAmountInputs = false
    @State private var isMaxSelected = false
    @State private var amountCorrectionNotice: String? = nil
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
    @State private var deleteBackupReceipt: VerifiedBackupReceipt? = nil
    @State private var isCreatingBackupBeforeDelete: Bool = false
    @State private var deleteErrorMessage: String? = nil
    @State private var showArchivedSection: Bool = false

    // Wallet Renaming State
    @State private var showRenameSheet: Bool = false
    @State private var walletToRename: WalletSummary? = nil
    @State private var newWalletNameInput: String = ""
    @State private var renameErrorMessage: String? = nil
    @State private var isRenamingWallet: Bool = false

    // RBF Fee Bump State
    @State private var showBumpFeeSheet: Bool = false
    @State private var txToBump: TransactionRecord? = nil
    @State private var bumpFeeRateInput: String = "5"
    @State private var bumpFeeErrorMessage: String? = nil
    @State private var isBumpingFee: Bool = false

    // Transaction Filter
    @State private var selectedTxFilter: String = "all"

    // V13 Local Login & 2FA State
    @State private var loginUsername: String = ""
    @State private var loginPassword: String = ""
    @State private var appleSavedPasswordCoordinator: AppleSavedPasswordCoordinator? = nil
    @State private var isApplePasswordSaved: Bool = false
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
    @State private var showEnrollmentCard: Bool = false

    // Price Service & Override Sheet
    @State private var showPriceOverrideSheet: Bool = false
    @State private var customPriceInput: String = ""

    // Receive Address Management State
    @State private var showNewAddressSheet: Bool = false
    @State private var newAddressLabelInput: String = ""
    @State private var showSavedAddressesList: Bool = false
    @State private var showArchivedReceiveAddresses: Bool = false
    @State private var addressToDelete: String? = nil
    @State private var showDeleteAddressAlert: Bool = false

    // Node RPC Live Status in Create Sheet
    @State private var isCheckingRPC: Bool = false
    @State private var isRPCOnline: Bool = false
    @State private var rpcStatusMessage: String? = nil

    // Knots Node Startup Prompt
    @State private var showNodePromptSheet: Bool = false
    @State private var hasBypassedNodePrompt: Bool = false

    private var isNodeReadyForWallet: Bool {
        if case .running = state.nodeState { return true }
        return false
    }

    public var isSendAllowed: Bool {
        isNodeReadyForWallet && state.walletSnapshot != nil
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
            if loginUsername.isEmpty { loginUsername = state.enrolledUsername ?? state.enrolledUsernames.first ?? "" }
            state.refreshFeeQuotes()
            state.refreshCoinbaseRewards()
            state.refreshWalletInventory()
            Task { await state.refreshPrice() }
            if state.isWalletTabUnlocked && !isNodeReadyForWallet && !hasBypassedNodePrompt {
                showNodePromptSheet = true
            }
        }
        .onChange(of: state.nodeState) { newState in
            state.refreshWalletInventory()
            if case .running = newState {
                state.refreshWallet()
                state.refreshFeeQuotes()
                state.refreshCoinbaseRewards()
                showNodePromptSheet = false
            }
        }
        .onChange(of: state.enrolledUsername) { newName in
            if loginUsername.isEmpty { loginUsername = newName ?? "" }
        }
        .onChange(of: loginUsername) { _ in
            loginPassword = ""
            loginTotpCode = ""
            isApplePasswordSaved = false
        }
        .onChange(of: state.isWalletTabUnlocked) { unlocked in
            if !unlocked {
                loginPassword = ""
                loginTotpCode = ""
                loginRecoveryCode = ""
                isApplePasswordSaved = false
                hasBypassedNodePrompt = false
                showNodePromptSheet = false
            } else {
                state.refreshWalletInventory()
                Task { await state.refreshPrice() }
                if !isNodeReadyForWallet && !hasBypassedNodePrompt {
                    showNodePromptSheet = true
                }
            }
        }
        .onChange(of: selectedFeePreset) { _ in
            recheckAndClampSendAmount()
        }
        .onChange(of: customSatPerVBInput) { _ in
            recheckAndClampSendAmount()
        }
        .onChange(of: state.walletSnapshot?.trustedBalance) { _ in
            recheckAndClampSendAmount()
        }
        .sheet(isPresented: $showNodePromptSheet) {
            nodeStartupPromptSheet
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
        .sheet(isPresented: $showPriceOverrideSheet) {
            priceOverrideSheet
        }
        .sheet(isPresented: $showNewAddressSheet) {
            newAddressSheet
        }
        .sheet(isPresented: $showRenameSheet) {
            renameWalletSheet
        }
        .sheet(isPresented: $showBumpFeeSheet) {
            bumpFeeSheet
        }
        .alert("Permanently Delete Receive Address?", isPresented: $showDeleteAddressAlert) {
            Button("Cancel", role: .cancel) {
                addressToDelete = nil
            }
            Button("Delete Permanently", role: .destructive) {
                if let addr = addressToDelete {
                    state.deleteReceiveAddress(addr)
                    addressToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(addressToDelete ?? "")'?\n\nThis address will be permanently removed from your active and archived address lists in Sentinel Node Wallet.")
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

            // Knots Node offline / standby banner
            if !isNodeReadyForWallet {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bitcoin Knots Node Offline")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.orange)
                        Text("Wallets and transaction history require an active Knots Node to synchronize and display blockchain data.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        if !state.isStartingUp {
                            state.startNode()
                        }
                    }) {
                        HStack(spacing: 4) {
                            if state.isStartingUp {
                                ProgressView().controlSize(.small)
                                Text("Starting…")
                            } else {
                                Image(systemName: "play.fill")
                                Text("Turn On Node")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            } else if let binfo = state.blockchainInfo, binfo.initialblockdownload || binfo.verificationprogress < 0.9999 {
                // Live Node Syncing Banner
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Knots Node Synchronizing: Block \(binfo.blocks) / \(binfo.headers) (\(String(format: "%.2f%%", binfo.verificationprogress * 100)))")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Wallet balances and transaction history are updating in real-time as blocks are processed.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.25), lineWidth: 1)
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

                // Live BTCB2 Exchange Pricing (Neoxa & NonKYC)
                priceBannerView

                // All Discovered Wallets Inventory Section
                walletInventorySection

                // Balance & Receive Section
                balanceAndReceiveSection

                // Send Composer Section (Active Wallet, V7-Compliant)
                sendComposerSection

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
                            Text("Pending (0-Conf)").tag("pending")
                            Text("Confirmed").tag("confirmed")
                            Text("Received").tag("receive")
                            Text("Sent").tag("send")
                            Text("Mining").tag("generate")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 480)

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
                                let didStartAccessing = url.startAccessingSecurityScopedResource()
                                defer {
                                    if didStartAccessing {
                                        url.stopAccessingSecurityScopedResource()
                                    }
                                }
                                do {
                                    let result = try await state.exportBackup(to: url)
                                    if result.isDurabilityConfirmed {
                                        state.alertMessage = "Wallet backup successfully saved to:\n\(url.path)\n\nPersistence: Fully verified on storage volume."
                                    } else {
                                        state.alertMessage = "Wallet backup published to:\n\(url.path)\n\n⚠️ Durability Unconfirmed: \(result.durabilityWarning ?? "Underlying volume does not support directory persistence sync.")\n\nPlease keep an additional verified copy."
                                    }
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

            // Apple Passwords & macOS Keychain Status Callout
            HStack(spacing: 10) {
                Image(systemName: "touchid")
                    .font(.title3)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Biometric Security & Keychain Active")
                        .font(.caption)
                        .bold()
                    Text("Operator login credentials and 2FA secrets are secured in macOS Keychain. Touch ID or Mac password authentication is required to autofill.")
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

            if !state.isAuthEnrolled || showEnrollmentCard {
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
            HStack {
                Text(state.isAuthEnrolled ? "Add Additional Operator Account" : "First-Time Operator Setup")
                    .font(.headline)
                Spacer()
                if state.isAuthEnrolled {
                    Button("Cancel / Return to Sign-In") {
                        showEnrollmentCard = false
                        authLocalError = nil
                        enrollUsername = ""
                        enrollPassword = ""
                        enrollTotpCode = ""
                        state.cancelEnrollment()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .font(.caption)
                }
            }

            Text(state.isAuthEnrolled
                ? "Enroll an additional local operator account with an independent username, strong password, and 2FA credentials."
                : "Create a unique local username and strong password (min 10 chars, uppercase, lowercase, number, special character)."
            )
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
                Text("Operator login credentials and 2FA secrets are securely protected in the macOS Keychain and Apple Passwords, and will be automatically pulled when unlocking the Wallet Manager.")
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
                        let enrolledName = enrollUsername
                        let passToSave = enrollPassword
                        try await state.enrollUser(password: enrollPassword, totpCode: enrollTotpCode)
                        try? WalletAuthCoordinator.saveOperatorPasswordToKeychain(username: enrolledName, password: passToSave)
                        enrollUsername = ""
                        enrollPassword = ""
                        enrollTotpCode = ""
                        showEnrollmentPassword = false
                        hasStoredRecoveryCodesOffline = false
                        showEnrollmentCard = false
                    } catch {
                        authLocalError = error.localizedDescription
                    }
                }
            }) {
                if isAuthActionInProgress {
                    ProgressView().controlSize(.small)
                } else {
                    Text(state.isAuthEnrolled ? "Complete Operator Enrollment" : "Complete Enrollment & Unlock")
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
            HStack {
                Text("Operator Sign-In")
                    .font(.headline)
                Spacer()
                Button("+ Add Operator Account") {
                    showEnrollmentCard = true
                    authLocalError = nil
                    enrollUsername = ""
                    enrollPassword = ""
                    enrollTotpCode = ""
                    state.cancelEnrollment()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Apple Password Manager Biometric Auto-Populate Prompt Banner
            HStack(spacing: 12) {
                Image(systemName: "touchid")
                    .font(.title2)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Autofill with Touch ID or Password?")
                        .font(.subheadline)
                        .bold()
                    Text("Scan your fingerprint or enter your Mac password to autofill Operator Login credentials.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    requestAutofillWithBiometrics(for: loginUsername, andLogin: false)
                }) {
                    Label("Autofill with Touch ID", systemImage: "touchid")
                        .bold()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
                .disabled(isAuthActionInProgress)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )

            if !showRecoveryLogin {
                if state.enrolledUsernames.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Select Operator Account").font(.caption).bold()
                        Picker("Account", selection: $loginUsername) {
                            ForEach(state.enrolledUsernames, id: \.self) { u in
                                Text(u).tag(u)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Username").font(.caption).bold()
                        TextField("Username", text: $loginUsername)
                            .textContentType(.username)
                            .autocorrectionDisabled(true)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("user-login-name")
                    }
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

                Button(action: {
                    requestAutofillWithBiometrics(for: loginUsername, andLogin: false)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "touchid")
                        Text("Autofill with Touch ID or Password…")
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("user-login-apple-passwords")
                .disabled(isAuthActionInProgress)

                if isApplePasswordSaved || !loginPassword.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Credentials authenticated and loaded from Keychain")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                Text("Saved logins and 2FA credentials in macOS Keychain are protected by biometric authentication. Touch ID or your Mac password is required to autofill.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let err = authLocalError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack(spacing: 10) {
                    Button(action: {
                        Task {
                            isAuthActionInProgress = true
                            authLocalError = nil
                            defer { isAuthActionInProgress = false }
                            do {
                                let userToSave = loginUsername
                                let passToSave = loginPassword
                                try await state.loginUser(username: loginUsername, password: loginPassword, totpCode: loginTotpCode)
                                try? WalletAuthCoordinator.saveOperatorPasswordToKeychain(username: userToSave, password: passToSave)
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

                    Button(action: {
                        requestAutofillWithBiometrics(for: loginUsername, andLogin: true)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "touchid")
                            Text("1-Click Touch ID Sign-In")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAuthActionInProgress)

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

    // MARK: - Apple Passwords & macOS Keychain Biometric Autofill

    private func requestAutofillWithBiometrics(for username: String? = nil, andLogin: Bool = false) {
        let target = (username?.isEmpty ?? true)
            ? (state.enrolledUsername ?? state.enrolledUsernames.first ?? "")
            : (username ?? "")
        guard !target.isEmpty else {
            authLocalError = "Please select or enter an operator username first."
            return
        }

        if loginUsername.isEmpty {
            loginUsername = target
        }

        isAuthActionInProgress = true
        authLocalError = nil

        Task { @MainActor in
            defer { isAuthActionInProgress = false }
            do {
                // Prompt user for fingerprint (Touch ID) or Mac password
                let creds = try await state.retrieveOperatorCredentialsWithBiometrics(username: target)
                var credentialsFound = false

                if let pass = creds.password, !pass.isEmpty {
                    loginPassword = pass
                    isApplePasswordSaved = true
                    credentialsFound = true
                }
                if let code = creds.totpCode, !code.isEmpty {
                    loginTotpCode = code
                    credentialsFound = true
                }

                // If not found in Keychain, try system Apple Passwords coordinator
                if !credentialsFound || loginPassword.isEmpty {
                    let picker = AppleSavedPasswordCoordinator()
                    picker.onCredential = { user, pass in
                        loginUsername = user
                        loginPassword = pass
                        isApplePasswordSaved = true
                        authLocalError = nil
                        appleSavedPasswordCoordinator = nil
                        try? WalletAuthCoordinator.saveOperatorPasswordToKeychain(username: user, password: pass)
                        Task { @MainActor in
                            if let refreshed = try? await state.retrieveOperatorCredentialsWithBiometrics(username: user),
                               let c = refreshed.totpCode {
                                loginTotpCode = c
                            }
                            if andLogin && !loginPassword.isEmpty && loginTotpCode.count == 6 {
                                do {
                                    try await state.loginUser(username: loginUsername, password: loginPassword, totpCode: loginTotpCode)
                                    loginPassword = ""
                                    loginTotpCode = ""
                                } catch {
                                    authLocalError = error.localizedDescription
                                }
                            }
                        }
                    }
                    picker.onFailure = { err in
                        if loginPassword.isEmpty {
                            authLocalError = err
                        }
                        appleSavedPasswordCoordinator = nil
                    }
                    appleSavedPasswordCoordinator = picker
                    picker.requestSavedLogin(isInteractive: true)
                    return
                }

                if andLogin {
                    if !loginUsername.isEmpty && !loginPassword.isEmpty && loginTotpCode.count == 6 {
                        let userToLogin = loginUsername
                        let passToLogin = loginPassword
                        let codeToLogin = loginTotpCode
                        try await state.loginUser(username: userToLogin, password: passToLogin, totpCode: codeToLogin)
                        loginPassword = ""
                        loginTotpCode = ""
                    }
                }
            } catch {
                if case WalletAuthError.deviceOwnerAuthCanceled = error {
                    authLocalError = "Autofill canceled: Fingerprint (Touch ID) or Mac password required."
                } else {
                    authLocalError = error.localizedDescription
                }
            }
        }
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
                    if state.priceState.effectivePrice > 0 {
                        Text("• ≈ \(state.priceState.formatFiat(satoshis: summary.totalSats))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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

                Button("Rename") {
                    walletToRename = summary
                    newWalletNameInput = summary.name
                    renameErrorMessage = nil
                    showRenameSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Rename wallet directory and database")

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
                    deleteBackupReceipt = nil
                    deleteErrorMessage = nil
                    showDeleteConfirmationSheet = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(summary.canDeleteSafely ? .red : .gray)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .disabled(true)
                .help("Deletion is temporarily unavailable: an independently verified encrypted-wallet recovery is required. Use Archive to remove a wallet from active memory without deleting files.")
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
                                let result = try await state.exportBackup(to: backupFile, walletName: name)
                                if FileManager.default.fileExists(atPath: result.destinationURL.path) {
                                    deleteBackupPath = result.destinationURL.path
                                    deleteBackupReceipt = result.receipt(for: name)
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
                        verifiedBackupPath: deleteBackupPath,
                        verifiedReceipt: deleteBackupReceipt
                    )
                    showDeleteConfirmationSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(typedDeleteName != (walletToDelete?.name ?? "") || deleteBackupPath.isEmpty || deleteBackupReceipt == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var renameWalletSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .font(.title)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rename Wallet")
                        .font(.headline)
                    Text("Rename '\(walletToRename?.name ?? "")' on disk and in Bitcoin Knots")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    showRenameSheet = false
                }
                .buttonStyle(.bordered)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("New Wallet Name:")
                    .font(.subheadline)
                    .bold()

                TextField("New Name (e.g. SavingsWallet)", text: $newWalletNameInput)
                    .textFieldStyle(.roundedBorder)

                Text("Wallet names must be 1–64 alphanumeric characters, hyphens, or underscores. The on-disk wallet folder and database will be safely moved, receive address mappings updated, and the wallet reloaded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let err = renameErrorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    showRenameSheet = false
                }
                .buttonStyle(.bordered)

                Button("Rename Wallet") {
                    guard let oldName = walletToRename?.name else { return }
                    let newName = newWalletNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !newName.isEmpty && newName != oldName else { return }

                    isRenamingWallet = true
                    renameErrorMessage = nil

                    Task {
                        defer { isRenamingWallet = false }
                        let ok = await state.renameWallet(oldName: oldName, newName: newName)
                        if ok {
                            showRenameSheet = false
                        } else {
                            renameErrorMessage = state.alertMessage ?? "Failed to rename wallet."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRenamingWallet || newWalletNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newWalletNameInput.trimmingCharacters(in: .whitespacesAndNewlines) == walletToRename?.name)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var bumpFeeSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bolt.circle.fill")
                    .font(.title)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bump Transaction Fee (RBF)")
                        .font(.headline)
                    Text("Accelerate unconfirmed transaction via BIP-125 Replace-By-Fee")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    showBumpFeeSheet = false
                }
                .buttonStyle(.bordered)
            }

            Divider()

            if let tx = txToBump {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Transaction ID:")
                            .font(.caption)
                            .bold()
                        Text(tx.txid)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack {
                        Text("Amount:")
                            .font(.caption)
                            .bold()
                        Text(String(format: "%.8f BTCB2", tx.amount))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Text("(\(SatoshiMath.formatSats(SatoshiMath.toSats(btc: tx.amount))) sats)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Status:")
                            .font(.caption)
                            .bold()
                        Text("Pending (0 Confirmations)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("New Fee Rate Target (sat/vB):")
                    .font(.subheadline)
                    .bold()

                HStack(spacing: 8) {
                    TextField("Rate", text: $bumpFeeRateInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)

                    Text("sat/vB")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Cheapest (\(state.feeQuotes[.cheapest]?.satPerVB ?? 1))") {
                        bumpFeeRateInput = "\(max(2, state.feeQuotes[.cheapest]?.satPerVB ?? 1))"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Normal (\(state.feeQuotes[.normal]?.satPerVB ?? 2))") {
                        bumpFeeRateInput = "\(max(3, state.feeQuotes[.normal]?.satPerVB ?? 2))"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Fast (\(state.feeQuotes[.fast]?.satPerVB ?? 5))") {
                        bumpFeeRateInput = "\(max(5, state.feeQuotes[.fast]?.satPerVB ?? 5))"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("BIP-125 requires the replacement transaction to pay a higher absolute fee and a higher fee rate than the original transaction.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let err = bumpFeeErrorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    showBumpFeeSheet = false
                }
                .buttonStyle(.bordered)

                Button("Submit Fee Bump") {
                    guard let txid = txToBump?.txid, let newRate = Int(bumpFeeRateInput), newRate > 0 else {
                        bumpFeeErrorMessage = "Please enter a valid positive integer sat/vB fee rate."
                        return
                    }

                    isBumpingFee = true
                    bumpFeeErrorMessage = nil

                    Task {
                        defer { isBumpingFee = false }
                        let ok = await state.bumpTransactionFee(txid: txid, newFeeRate: newRate)
                        if ok {
                            showBumpFeeSheet = false
                        } else {
                            bumpFeeErrorMessage = state.alertMessage ?? "Fee bump rejected by Bitcoin Knots node."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isSendAllowed || isBumpingFee || (Int(bumpFeeRateInput) ?? 0) <= 0)
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
            HStack(spacing: 6) {
                Text("\(SatoshiMath.formatSats(sats)) sats")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                if state.priceState.effectivePrice > 0 {
                    Text("• ≈ \(state.priceState.formatFiat(satoshis: sats))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func feeOptionButton(title: String, subtitle: String, preset: FeePresetType) -> some View {
        let isSelected = selectedFeePreset == preset
        let quote = state.feeQuotes[preset]
        let rate = quote?.satPerVB ?? (preset == .cheapest ? 1 : (preset == .normal ? 2 : 5))
        let medianCostSats = quote?.medianTxFeeSats ?? Int64(rate * 140)

        return Button(action: {
            selectedFeePreset = preset
            recheckAndClampSendAmount()
        }) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.caption)
                    .bold()
                Text("\(rate) sat/vB")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("~\(medianCostSats) sats")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .blue : .secondary)
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
        switch selectedTxFilter {
        case "pending":
            return state.transactions.filter { $0.confirmations == 0 }
        case "confirmed":
            return state.transactions.filter { $0.confirmations > 0 }
        case "receive", "send", "generate":
            return state.transactions.filter { $0.category == selectedTxFilter }
        default:
            return state.transactions
        }
    }

    private func transactionRow(_ tx: TransactionRecord) -> some View {
        let maturity = CoinbaseMaturityCalculator.maturityInfo(for: tx)

        return HStack(alignment: .top) {
            Image(systemName: categoryIcon(tx.category))
                .foregroundColor(categoryColor(tx.category))
                .frame(width: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
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

                    // Confirmations Badge
                    HStack(spacing: 3) {
                        Image(systemName: tx.confirmations > 0 ? "checkmark.circle.fill" : "clock.fill")
                            .font(.system(size: 9))
                        Text(tx.confirmations > 0 ? "\(tx.confirmations) Conf\(tx.confirmations == 1 ? "" : "s")" : "0 Conf (Pending)")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill((tx.confirmations > 0 ? Color.blue : Color.orange).opacity(0.15)))
                    .foregroundColor(tx.confirmations > 0 ? .blue : .orange)

                    // Spendable / Locked Status Badge
                    if maturity.isSpendable {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 9))
                            Text("Available for Spend")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                        .foregroundColor(.green)
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text("Locked Up")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundColor(.orange)
                    }

                    if tx.confirmations == 0 {
                        Button(action: {
                            txToBump = tx
                            bumpFeeRateInput = "\(max(5, Int(state.feeQuotes[.fast]?.satPerVB ?? 5)))"
                            bumpFeeErrorMessage = nil
                            showBumpFeeSheet = true
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                Text("Bump Fee (RBF)")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSendAllowed)
                    }
                }

                if maturity.isCoinbase {
                    if maturity.isSpendable {
                        Text("Mined Coinbase Reward • Fully Matured at block #\(tx.blockheight ?? 0) (\(tx.confirmations) of \(maturity.requiredConfirmations) confs) • \(maturity.lockupDescription)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "hourglass")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("BIP-110 Lockup: \(maturity.remainingBlocks) blocks remaining • \(maturity.remainingTimeFormatted) remaining until unlock (\(maturity.lockupDescription)) • \(tx.confirmations)/\(maturity.requiredConfirmations) confs")
                                .font(.caption2)
                                .bold()
                                .foregroundColor(.orange)
                        }
                    }
                } else if tx.confirmations > 0 {
                    if let height = tx.blockheight {
                        Text("Block #\(height) • Confirmed and available for spend (\(tx.confirmations) confirmations)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(tx.confirmations) confirmations • Confirmed and available for spend")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Unconfirmed in mempool • Awaiting block inclusion (~10m) before spendable")
                        .font(.caption2)
                        .foregroundColor(.orange)
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
                if state.priceState.effectivePrice > 0 {
                    Text("≈ \(state.priceState.formatFiat(btc: abs(tx.amount)))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)))
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

    private func currentFeeQuote() -> FeeQuote {
        if selectedFeePreset == .custom {
            let customRate = max(1, Int(customSatPerVBInput) ?? 1)
            return FeeQuote(type: .custom, satPerVB: customRate, targetBlocks: 0, estimatedMinutes: 0)
        } else {
            return state.feeQuotes[selectedFeePreset] ?? FeeQuote(
                type: selectedFeePreset,
                satPerVB: selectedFeePreset == .cheapest ? 1 : (selectedFeePreset == .normal ? 2 : 5),
                targetBlocks: selectedFeePreset.targetBlocks,
                estimatedMinutes: selectedFeePreset == .cheapest ? 240 : (selectedFeePreset == .normal ? 60 : 20)
            )
        }
    }

    private func estimatedFeeCalculation(quote: FeeQuote) -> (feeSats: Int64, feeBTC: Double, vSize: Int) {
        let estVSize = 141
        let feeSats = max(Int64(quote.satPerVB * estVSize), quote.medianTxFeeSats)
        let feeBTC = Double(feeSats) / 100_000_000.0
        return (feeSats, feeBTC, estVSize)
    }

    private func updateAmountFromBTC(_ newBTC: String) {
        guard !isSyncingAmountInputs else { return }
        isSyncingAmountInputs = true
        defer { isSyncingAmountInputs = false }

        let trimmed = newBTC.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            sendAmountInput = ""
            sendAmountUSDInput = ""
            sendAmountPercentInput = ""
            isMaxSelected = false
            amountCorrectionNotice = nil
            return
        }

        let avail = state.walletSnapshot?.trustedBalance ?? 0.0
        let quote = currentFeeQuote()
        let feeCalc = estimatedFeeCalculation(quote: quote)
        let maxSpendable = max(0.0, avail - feeCalc.feeBTC)

        if avail <= feeCalc.feeBTC {
            sendAmountInput = "0.00000000"
            sendAmountUSDInput = "0.00"
            sendAmountPercentInput = "0.0"
            isMaxSelected = false
            amountCorrectionNotice = "Spendable balance (\(String(format: "%.8f", avail)) BTCB2) is insufficient to cover the network fee (\(String(format: "%.8f", feeCalc.feeBTC)) BTCB2)."
            return
        }

        // Allow trailing decimal point during active typing (e.g. "0.")
        if trimmed == "." || trimmed == "0." || (trimmed.hasSuffix(".") && trimmed.filter({ $0 == "." }).count == 1) {
            sendAmountInput = trimmed
            return
        }

        guard let btc = Double(trimmed) else {
            amountCorrectionNotice = "Invalid numerical input."
            return
        }

        if btc > maxSpendable {
            // Error-correct user attempt to enter an amount they don't have and prevent entering it
            sendAmountInput = String(format: "%.8f", maxSpendable)
            let price = state.priceState.effectivePrice
            if price > 0 {
                sendAmountUSDInput = String(format: "%.2f", maxSpendable * price)
            } else {
                sendAmountUSDInput = ""
            }
            if avail > 0 {
                sendAmountPercentInput = String(format: "%.1f", min(100.0, (maxSpendable / avail) * 100.0))
            }
            isMaxSelected = true
            amountCorrectionNotice = "Auto-corrected to maximum spendable \(String(format: "%.8f", maxSpendable)) BTCB2 (reserved \(String(format: "%.8f", feeCalc.feeBTC)) BTCB2 for fee)."
        } else {
            sendAmountInput = trimmed
            let price = state.priceState.effectivePrice
            if price > 0 && btc > 0 {
                sendAmountUSDInput = String(format: "%.2f", btc * price)
            } else {
                sendAmountUSDInput = ""
            }
            if avail > 0 && btc > 0 {
                let pct = min(100.0, (btc / avail) * 100.0)
                sendAmountPercentInput = String(format: "%.1f", pct)
            } else {
                sendAmountPercentInput = ""
            }
            isMaxSelected = (abs(btc - maxSpendable) < 1e-8)
            amountCorrectionNotice = nil
        }
    }

    private func updateAmountFromUSD(_ newUSD: String) {
        guard !isSyncingAmountInputs else { return }
        isSyncingAmountInputs = true
        defer { isSyncingAmountInputs = false }

        let trimmed = newUSD.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            sendAmountInput = ""
            sendAmountUSDInput = ""
            sendAmountPercentInput = ""
            isMaxSelected = false
            amountCorrectionNotice = nil
            return
        }

        let avail = state.walletSnapshot?.trustedBalance ?? 0.0
        let quote = currentFeeQuote()
        let feeCalc = estimatedFeeCalculation(quote: quote)
        let maxSpendable = max(0.0, avail - feeCalc.feeBTC)
        let price = state.priceState.effectivePrice

        if avail <= feeCalc.feeBTC {
            sendAmountInput = "0.00000000"
            sendAmountUSDInput = "0.00"
            sendAmountPercentInput = "0.0"
            isMaxSelected = false
            amountCorrectionNotice = "Spendable balance is insufficient to cover the network fee."
            return
        }

        if trimmed == "." || trimmed == "0." || (trimmed.hasSuffix(".") && trimmed.filter({ $0 == "." }).count == 1) {
            sendAmountUSDInput = trimmed
            return
        }

        guard let usd = Double(trimmed), price > 0 else {
            if price <= 0 {
                sendAmountUSDInput = trimmed
                amountCorrectionNotice = "Live market price unavailable for USD auto-calculation."
            }
            return
        }

        let maxUSD = maxSpendable * price
        if usd > maxUSD {
            sendAmountUSDInput = String(format: "%.2f", maxUSD)
            sendAmountInput = String(format: "%.8f", maxSpendable)
            if avail > 0 {
                sendAmountPercentInput = String(format: "%.1f", min(100.0, (maxSpendable / avail) * 100.0))
            }
            isMaxSelected = true
            amountCorrectionNotice = "Auto-corrected to maximum spendable $\(String(format: "%.2f", maxUSD)) (\(String(format: "%.8f", maxSpendable)) BTCB2) to preserve network fee."
        } else {
            sendAmountUSDInput = trimmed
            let btc = usd / price
            sendAmountInput = String(format: "%.8f", btc)
            if avail > 0 {
                let pct = min(100.0, (btc / avail) * 100.0)
                sendAmountPercentInput = String(format: "%.1f", pct)
            }
            isMaxSelected = (abs(btc - maxSpendable) < 1e-8)
            amountCorrectionNotice = nil
        }
    }

    private func updateAmountFromPercent(_ newPct: String) {
        guard !isSyncingAmountInputs else { return }
        isSyncingAmountInputs = true
        defer { isSyncingAmountInputs = false }

        let trimmed = newPct.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            sendAmountInput = ""
            sendAmountUSDInput = ""
            sendAmountPercentInput = ""
            isMaxSelected = false
            amountCorrectionNotice = nil
            return
        }

        let avail = state.walletSnapshot?.trustedBalance ?? 0.0
        let quote = currentFeeQuote()
        let feeCalc = estimatedFeeCalculation(quote: quote)
        let maxSpendable = max(0.0, avail - feeCalc.feeBTC)

        if avail <= feeCalc.feeBTC {
            sendAmountInput = "0.00000000"
            sendAmountUSDInput = "0.00"
            sendAmountPercentInput = "0.0"
            isMaxSelected = false
            amountCorrectionNotice = "Spendable balance is insufficient to cover the network fee."
            return
        }

        if trimmed == "." || trimmed == "0." || (trimmed.hasSuffix(".") && trimmed.filter({ $0 == "." }).count == 1) {
            sendAmountPercentInput = trimmed
            return
        }

        guard let pct = Double(trimmed) else { return }

        let maxPct = avail > 0 ? min(100.0, (maxSpendable / avail) * 100.0) : 0.0
        if pct > maxPct {
            sendAmountPercentInput = String(format: "%.1f", maxPct)
            sendAmountInput = String(format: "%.8f", maxSpendable)
            let price = state.priceState.effectivePrice
            if price > 0 {
                sendAmountUSDInput = String(format: "%.2f", maxSpendable * price)
            } else {
                sendAmountUSDInput = ""
            }
            isMaxSelected = true
            amountCorrectionNotice = "Auto-corrected to maximum spendable \(String(format: "%.1f", maxPct))% (\(String(format: "%.8f", maxSpendable)) BTCB2) to preserve network fee."
        } else {
            sendAmountPercentInput = trimmed
            let btc = max(0.0, min(maxSpendable, (pct / 100.0) * avail))
            sendAmountInput = String(format: "%.8f", btc)
            let price = state.priceState.effectivePrice
            if price > 0 {
                sendAmountUSDInput = String(format: "%.2f", btc * price)
            } else {
                sendAmountUSDInput = ""
            }
            isMaxSelected = (abs(btc - maxSpendable) < 1e-8)
            amountCorrectionNotice = nil
        }
    }

    private func applyMaxAmount() {
        guard !isSyncingAmountInputs else { return }
        isSyncingAmountInputs = true
        isMaxSelected = true
        defer { isSyncingAmountInputs = false }

        let avail = state.walletSnapshot?.trustedBalance ?? 0.0
        let quote = currentFeeQuote()
        let feeCalc = estimatedFeeCalculation(quote: quote)
        let maxSpendable = max(0.0, avail - feeCalc.feeBTC)

        guard avail > feeCalc.feeBTC else {
            sendAmountInput = "0.00000000"
            sendAmountUSDInput = "0.00"
            sendAmountPercentInput = "0.0"
            amountCorrectionNotice = "Spendable balance (\(String(format: "%.8f", avail)) BTCB2) is insufficient to cover the network fee (\(String(format: "%.8f", feeCalc.feeBTC)) BTCB2)."
            return
        }

        sendAmountInput = String(format: "%.8f", maxSpendable)
        let price = state.priceState.effectivePrice
        if price > 0 {
            sendAmountUSDInput = String(format: "%.2f", maxSpendable * price)
        } else {
            sendAmountUSDInput = ""
        }
        sendAmountPercentInput = String(format: "%.1f", min(100.0, (maxSpendable / avail) * 100.0))
        amountCorrectionNotice = nil
    }

    private func recheckAndClampSendAmount() {
        if isMaxSelected {
            applyMaxAmount()
            return
        }

        guard let currentBTC = Double(sendAmountInput), currentBTC > 0 else { return }
        let avail = state.walletSnapshot?.trustedBalance ?? 0.0
        let quote = currentFeeQuote()
        let feeCalc = estimatedFeeCalculation(quote: quote)
        let maxSpendable = max(0.0, avail - feeCalc.feeBTC)

        if currentBTC > maxSpendable {
            guard !isSyncingAmountInputs else { return }
            isSyncingAmountInputs = true
            isMaxSelected = true
            defer { isSyncingAmountInputs = false }

            sendAmountInput = String(format: "%.8f", maxSpendable)
            let price = state.priceState.effectivePrice
            if price > 0 {
                sendAmountUSDInput = String(format: "%.2f", maxSpendable * price)
            } else {
                sendAmountUSDInput = ""
            }
            if avail > 0 {
                sendAmountPercentInput = String(format: "%.1f", min(100.0, (maxSpendable / avail) * 100.0))
            }
            amountCorrectionNotice = "Auto-adjusted to \(String(format: "%.8f", maxSpendable)) BTCB2 to accommodate updated \(quote.satPerVB) sat/vB fee rate."
        }
    }

    private func generateSendPreview() {
        let btc = Double(sendAmountInput) ?? 0.0
        let sats = SatoshiMath.toSats(btc: btc)
        let quote = currentFeeQuote()

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


    // MARK: - Extracted Main Wallet Sections

    @ViewBuilder private var balanceAndReceiveSection: some View {
                VStack(alignment: .leading, spacing: 14) {
                    // Pending incoming transfer alert
                    if (state.walletSnapshot?.pendingBalance ?? 0.0) > 0 {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.badge.exclamationmark.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Incoming Transfer Pending (0 Confirmations)")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.orange)
                                    Text("ACTIVELY BEING RECEIVED")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                                        .foregroundColor(.orange)
                                }
                                Text("+\(String(format: "%.8f", state.walletSnapshot?.pendingBalance ?? 0.0)) BTCB2 (\(SatoshiMath.formatSats(state.walletSnapshot?.pendingBalanceSats ?? 0)) sats) is unconfirmed in the mempool. This pending transfer is NOT yet spendable until confirmed in a block.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Verified Spendable Balance")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(String(format: "%.8f BTCB2", state.walletSnapshot?.trustedBalance ?? 0.0))
                                .font(.system(size: 34, weight: .bold, design: .monospaced))

                            HStack(spacing: 8) {
                                Text("\(SatoshiMath.formatSats(state.walletSnapshot?.trustedBalanceSats ?? 0)) sats")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)

                                if state.priceState.effectivePrice > 0 {
                                    Text("• ≈ \(state.priceState.formatFiat(satoshis: state.walletSnapshot?.trustedBalanceSats ?? 0))")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primary)
                                }
                            }
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

                // Receive Section: Canonical Creation Address & Temporary Rotated Addresses
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        Text("Receive BTCB2")
                            .font(.title3)
                            .bold()

                        if let currentName = state.walletSnapshot?.name {
                            Text("• \(currentName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Count badges
                        if !state.activeReceiveAddresses.isEmpty {
                            Text("\(state.activeReceiveAddresses.count) Temporary Active")
                                .font(.caption2)
                                .bold()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.blue.opacity(0.15)))
                                .foregroundColor(.blue)
                        }

                        if !state.archivedReceiveAddresses.isEmpty {
                            Button(action: { showArchivedReceiveAddresses.toggle() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "archivebox")
                                    Text("Archived (\(state.archivedReceiveAddresses.count))")
                                }
                                .font(.caption2)
                                .bold()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: {
                            newAddressLabelInput = ""
                            showNewAddressSheet = true
                        }) {
                            Label("New Temporary Address", systemImage: "plus.circle")
                                .font(.caption)
                        }
                    }

                    // 1. CANONICAL WALLET ADDRESS CARD (Permanent & Locked to Creation)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.purple)
                            Text("Canonical Wallet Address")
                                .font(.headline)

                            Text("PERMANENT • LOCKED TO CREATION")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.purple.opacity(0.15)))
                                .foregroundColor(.purple)

                            Spacer()

                            if !state.canonicalReceiveAddress.isEmpty {
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(state.canonicalReceiveAddress, forType: .string)
                                    state.appendLog("[UI] Copied canonical receive address to clipboard.")
                                }) {
                                    Label("Copy Canonical Address", systemImage: "doc.on.doc")
                                }
                            }
                        }

                        Text("Permanent immutable receive address bound to the creation of '\(state.walletSnapshot?.name ?? "this wallet")'. This address never changes and cannot be deleted or archived. Recommended for MiningRigRentals mining pool payouts, exchange whitelisting, and recurring deposits.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !state.canonicalReceiveAddress.isEmpty {
                            HStack(alignment: .top, spacing: 16) {
                                QRCodeView(string: state.canonicalReceiveAddress, size: 105)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Locked Creation Bech32 (Native SegWit):")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    Text(state.canonicalReceiveAddress)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)))

                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundColor(.purple)
                                            .font(.caption)
                                        Text("Immutable creation address for \(state.walletSnapshot?.name ?? "wallet")")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        } else {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("Loading canonical creation address...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.windowBackgroundColor).opacity(0.6)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                    )

                    // 2. TEMPORARY RECEIVE ADDRESS CARD (Rotatable & Regenerable)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .foregroundColor(.blue)
                            Text("Temporary Receive Address")
                                .font(.headline)

                            Text("ROTATABLE • REGENERABLE")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.15)))
                                .foregroundColor(.blue)

                            Spacer()

                            Button(action: {
                                newAddressLabelInput = ""
                                showNewAddressSheet = true
                            }) {
                                Label("New Address", systemImage: "plus.circle")
                            }
                        }

                        Text("Dynamic receive address for one-off payments and enhanced privacy rotation. Can be regenerated multiple times, archived from view, or permanently deleted.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !state.receiveAddress.isEmpty {
                            HStack(alignment: .top, spacing: 16) {
                                QRCodeView(string: state.receiveAddress, size: 105)

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Active Temporary Bech32 Address:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)

                                        if let record = state.activeReceiveAddresses.first(where: { $0.address == state.receiveAddress }),
                                           !record.label.isEmpty {
                                            Text("• \(record.label)")
                                                .font(.caption2)
                                                .bold()
                                                .foregroundColor(.blue)
                                        }
                                    }

                                    Text(state.receiveAddress)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)))

                                    HStack(spacing: 12) {
                                        Button(action: {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(state.receiveAddress, forType: .string)
                                            state.appendLog("[UI] Copied temporary receive address to clipboard.")
                                        }) {
                                            Label("Copy Address", systemImage: "doc.on.doc")
                                        }

                                        Button(action: {
                                            state.archiveReceiveAddress(state.receiveAddress)
                                        }) {
                                            Label("Archive", systemImage: "archivebox")
                                        }
                                        .help("Removes address from active view while safely preserving it and its funds in the wallet database.")

                                        Button(role: .destructive, action: {
                                            addressToDelete = state.receiveAddress
                                            showDeleteAddressAlert = true
                                        }) {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .help("Permanently deletes address record from Sentinel Node Wallet.")
                                    }
                                }
                            }

                            // Saved Temporary Addresses List
                            if state.activeReceiveAddresses.count > 1 {
                                DisclosureGroup(
                                    isExpanded: $showSavedAddressesList,
                                    content: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(state.activeReceiveAddresses) { record in
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        HStack {
                                                            Text(record.address)
                                                                .font(.system(size: 11, design: .monospaced))
                                                                .lineLimit(1)
                                                            if record.address == state.receiveAddress {
                                                                Text("ACTIVE")
                                                                    .font(.system(size: 9, weight: .bold))
                                                                    .padding(.horizontal, 4)
                                                                    .padding(.vertical, 1)
                                                                    .background(Capsule().fill(Color.blue))
                                                                    .foregroundColor(.white)
                                                        }
                                                    }
                                                    HStack(spacing: 8) {
                                                        if !record.label.isEmpty {
                                                            Text(record.label)
                                                                .font(.caption2)
                                                                .bold()
                                                                .foregroundColor(.secondary)
                                                        }
                                                        Text(record.createdAt, style: .date)
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }

                                                Spacer()

                                                if record.address != state.receiveAddress {
                                                    Button("Select") {
                                                        state.selectReceiveAddress(record.address)
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.small)
                                                }

                                                Button(action: {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(record.address, forType: .string)
                                                    state.appendLog("[UI] Copied address to clipboard.")
                                                }) {
                                                    Image(systemName: "doc.on.doc")
                                                }
                                                .buttonStyle(.plain)
                                                .help("Copy Address")

                                                Button(action: {
                                                    state.archiveReceiveAddress(record.address)
                                                }) {
                                                    Image(systemName: "archivebox")
                                                }
                                                .buttonStyle(.plain)
                                                .help("Archive Address")

                                                Button(action: {
                                                    addressToDelete = record.address
                                                    showDeleteAddressAlert = true
                                                }) {
                                                    Image(systemName: "trash")
                                                        .foregroundColor(.red)
                                                }
                                                .buttonStyle(.plain)
                                                .help("Delete Address")
                                            }
                                            .padding(6)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.windowBackgroundColor).opacity(0.5)))
                                        }
                                    }
                                    .padding(.top, 6)
                                },
                                label: {
                                    Text("Saved Temporary Addresses for \(state.walletSnapshot?.name ?? "Wallet") (\(state.activeReceiveAddresses.count))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            )
                        }
                    } else if !state.archivedReceiveAddresses.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("All temporary receive addresses for '\(state.walletSnapshot?.name ?? "this wallet")' are currently archived.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            Text("Archived addresses remain fully valid and funds sent to them are safely preserved. You can unarchive an address below or generate a new temporary address.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 12) {
                                Button(action: {
                                    newAddressLabelInput = ""
                                    showNewAddressSheet = true
                                }) {
                                    Label("Generate New Address", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)

                                Button(action: {
                                    showArchivedReceiveAddresses = true
                                }) {
                                    Label("View Archived (\(state.archivedReceiveAddresses.count))", systemImage: "archivebox")
                                }
                            }
                        }
                    } else {
                        Button(action: {
                            state.generateNewReceiveAddress()
                        }) {
                            Label("Generate Temporary Receive Address", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    // Archived Addresses Section
                    if showArchivedReceiveAddresses && !state.archivedReceiveAddresses.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Divider()
                            HStack {
                                Image(systemName: "archivebox.fill")
                                    .foregroundColor(.secondary)
                                Text("Archived Receive Addresses (\(state.archivedReceiveAddresses.count))")
                                    .font(.subheadline)
                                    .bold()
                                Spacer()
                                Button("Hide") {
                                    showArchivedReceiveAddresses = false
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                            }

                            Text("Archived addresses are removed from your active view, but their presence and all associated funds remain safely in your Bitcoin Knots wallet database. You can retrieve/unarchive them at any time.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(state.archivedReceiveAddresses) { record in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.address)
                                            .font(.system(size: 11, design: .monospaced))
                                            .lineLimit(1)
                                        HStack(spacing: 8) {
                                            if !record.label.isEmpty {
                                                Text(record.label)
                                                    .font(.caption2)
                                                    .bold()
                                            }
                                            if let archDate = record.archivedAt {
                                                Text("Archived: \(archDate, style: .date)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()

                                    Button("Unarchive") {
                                        state.unarchiveReceiveAddress(record.address)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(record.address, forType: .string)
                                        state.appendLog("[UI] Copied archived address to clipboard.")
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy Address")

                                    Button(action: {
                                        addressToDelete = record.address
                                        showDeleteAddressAlert = true
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete Permanently")
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.windowBackgroundColor).opacity(0.4)))
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.windowBackgroundColor).opacity(0.6)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
    }

    private var isSendDisabledDueToFunds: Bool {
        let availBTC = state.walletSnapshot?.trustedBalance ?? 0.0
        let availSats = SatoshiMath.toSats(btc: availBTC)
        let recipientBTC = Double(sendAmountInput) ?? 0.0
        let recipientSats = SatoshiMath.toSats(btc: recipientBTC)
        let quote = currentFeeQuote()
        let feeCalc = estimatedFeeCalculation(quote: quote)
        let totalDebitSats = recipientSats + feeCalc.feeSats
        return recipientSats > 0 && totalDebitSats > availSats
    }

    private var transactionCostBreakdownCard: some View {
                    // Real-Time Transaction Cost Breakdown & Wallet Debit Card
                    let availBTC = state.walletSnapshot?.trustedBalance ?? 0.0
                    let availSats = SatoshiMath.toSats(btc: availBTC)
                    let recipientBTC = Double(sendAmountInput) ?? 0.0
                    let recipientSats = SatoshiMath.toSats(btc: recipientBTC)

                    let currentQuote = currentFeeQuote()
                    let feeCalc = estimatedFeeCalculation(quote: currentQuote)
                    let feeBTC = feeCalc.feeBTC
                    let feeSats = feeCalc.feeSats

                    let totalDebitBTC = recipientBTC > 0 ? (recipientBTC + feeBTC) : 0.0
                    let totalDebitSats = recipientSats > 0 ? (recipientSats + feeSats) : 0
                    let remainingBTC = max(0.0, availBTC - totalDebitBTC)
                    let remainingSats = max(0, availSats - totalDebitSats)
                    let isInsufficientFunds = recipientSats > 0 && totalDebitSats > availSats
                    let deficitSats = max(0, totalDebitSats - availSats)
                    let deficitBTC = Double(deficitSats) / 100_000_000.0

                    return VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "creditcard.and.123")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("Transaction Cost Breakdown (Debit from Wallet)")
                                .font(.caption)
                                .bold()
                            if isMaxSelected {
                                Text("MAX MODE")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                            Text("Spendable: \(String(format: "%.8f", availBTC)) BTCB2")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        VStack(spacing: 6) {
                            // 1. Recipient Receives
                            HStack {
                                Text("Recipient Receives:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "%.8f BTCB2", recipientBTC))
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.primary)
                                    HStack(spacing: 4) {
                                        Text("\(SatoshiMath.formatSats(recipientSats)) sats")
                                        if state.priceState.effectivePrice > 0 {
                                            Text("• ≈ \(state.priceState.formatFiat(satoshis: recipientSats))")
                                        }
                                    }
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                }
                            }

                            // 2. Network Fee
                            HStack {
                                HStack(spacing: 3) {
                                    Text("+ Network Mining Fee:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text("(\(currentQuote.satPerVB) sat/vB • ~\(feeCalc.vSize) vB)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "+%.8f BTCB2", feeBTC))
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.orange)
                                    HStack(spacing: 4) {
                                        Text("+\(SatoshiMath.formatSats(feeSats)) sats")
                                        if state.priceState.effectivePrice > 0 {
                                            Text("• ≈ \(state.priceState.formatFiat(satoshis: feeSats))")
                                        }
                                    }
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.orange)
                                }
                            }

                            Divider()

                            // 3. Total Debit from Wallet
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Total Cost to Send (Debit from Wallet):")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.primary)
                                    Text("Amount to Recipient + Network Fee")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "%.8f BTCB2", totalDebitBTC))
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(isInsufficientFunds ? .red : .primary)
                                    HStack(spacing: 4) {
                                        Text("\(SatoshiMath.formatSats(totalDebitSats)) sats")
                                        if state.priceState.effectivePrice > 0 {
                                            Text("• ≈ \(state.priceState.formatFiat(satoshis: totalDebitSats))")
                                        }
                                    }
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(isInsufficientFunds ? .red : .secondary)
                                }
                            }

                            // 4. Remaining Balance
                            HStack {
                                Text("Remaining Spendable Balance:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.8f BTCB2 (%@ sats)", remainingBTC, SatoshiMath.formatSats(remainingSats)))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(remainingSats == 0 && recipientBTC > 0 ? .secondary : .green)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))

                        if isInsufficientFunds {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.callout)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Insufficient Funds for Amount + Fee")
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(.red)
                                    Text("Total debit of \(String(format: "%.8f", totalDebitBTC)) BTCB2 exceeds spendable balance by \(String(format: "%.8f", deficitBTC)) BTCB2.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Adjust to MAX") {
                                    applyMaxAmount()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .controlSize(.small)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3), lineWidth: 1))
                        }
                    }


    }

    @ViewBuilder private var sendComposerSection: some View {
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

                        Text(isSendAllowed ? "Active Wallet" : "Node Inactive")
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill((isSendAllowed ? Color.green : Color.orange).opacity(0.15)))
                            .foregroundColor(isSendAllowed ? .green : .orange)
                    }

                    Text("Active BTCB2 Wallet: Transactions are validated against native BTCB2 consensus, previewed with live fee rates, and signed upon operator authorization.")
                        .font(.caption)
                        .foregroundColor(.secondary)

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

                    // Amount Input Section (BTCB2 / USD / Percentage 3-Way Auto-Calculation + Max)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Amount to Send (Recipient Receives):")
                                .font(.caption)
                                .bold()
                            Spacer()
                            Text("Spendable Available: \(String(format: "%.8f", state.walletSnapshot?.trustedBalance ?? 0.0)) BTCB2")
                                .font(.caption2)
                                .bold()
                                .foregroundColor(.green)
                        }

                        if let notice = amountCorrectionNotice {
                            HStack(spacing: 6) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text(notice)
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.blue)
                                Spacer()
                                Button(action: { amountCorrectionNotice = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                        }

                        HStack(alignment: .bottom, spacing: 12) {
                            // BTCB2 Field
                            VStack(alignment: .leading, spacing: 3) {
                                Text("BTCB2")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.secondary)
                                TextField("0.00000000", text: Binding(
                                    get: { sendAmountInput },
                                    set: { updateAmountFromBTC($0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                            }

                            // USD Field
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text("USD ($)")
                                        .font(.caption2)
                                        .bold()
                                        .foregroundColor(.secondary)
                                    if state.priceState.effectivePrice > 0 {
                                        Text("($\(String(format: "%.0f", state.priceState.effectivePrice)))")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                TextField("0.00", text: Binding(
                                    get: { sendAmountUSDInput },
                                    set: { updateAmountFromUSD($0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            }

                            // Percent Field
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Share (%)")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.secondary)
                                TextField("0.0%", text: Binding(
                                    get: { sendAmountPercentInput },
                                    set: { updateAmountFromPercent($0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 75)
                            }

                            // Quick Presets & MAX Button
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Presets")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.secondary)
                                HStack(spacing: 4) {
                                    Button("25%") { updateAmountFromPercent("25.0") }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    Button("50%") { updateAmountFromPercent("50.0") }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    Button("75%") { updateAmountFromPercent("75.0") }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    if isMaxSelected {
                                        Button("MAX") { applyMaxAmount() }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.blue)
                                            .controlSize(.small)
                                            .help("Fills all available spendable funds minus the estimated network fee required for transmission")
                                    } else {
                                        Button("MAX") { applyMaxAmount() }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .help("Fills all available spendable funds minus the estimated network fee required for transmission")
                                    }
                                }
                            }
                        }

                        HStack {
                            let parsedBTC = Double(sendAmountInput) ?? 0.0
                            let parsedSats = SatoshiMath.toSats(btc: parsedBTC)
                            Text("≈ \(SatoshiMath.formatSats(parsedSats)) satoshis")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)

                            Spacer()

                            let quote = currentFeeQuote()
                            let feeCalc = estimatedFeeCalculation(quote: quote)
                            Text("Estimated Fee Reserved on Max: ~\(String(format: "%.8f", feeCalc.feeBTC)) BTCB2 (\(quote.satPerVB) sat/vB)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if (state.walletSnapshot?.pendingBalance ?? 0.0) > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption2)
                                Text("Pending incoming transfer of +\(String(format: "%.8f", state.walletSnapshot?.pendingBalance ?? 0.0)) BTCB2 is actively being received and cannot be spent yet.")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    // Fee Selection (Cheapest / Normal / Fast / Custom)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Network Fee Target (Live Mempool-Derived Quotes):")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            feeOptionButton(title: "Cheapest", subtitle: "24 blks (~4h)", preset: .cheapest)
                            feeOptionButton(title: "Normal", subtitle: "6 blks (~1h)", preset: .normal)
                            feeOptionButton(title: "Fast", subtitle: "2 blks (~20m)", preset: .fast)
                            feeOptionButton(title: "Custom", subtitle: "sat/vB", preset: .custom)
                        }

                        if let normalQuote = state.feeQuotes[.normal] {
                            HStack(spacing: 6) {
                                Image(systemName: "chart.bar.xaxis")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text("Live Mempool: Median fee rate is \(normalQuote.satPerVB) sat/vB (median cost ~\(normalQuote.medianTxFeeSats) sats for ~\(normalQuote.estimatedMinutes)m confirmation).")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 2)
                        }

                        if selectedFeePreset == .custom {
                            HStack {
                                Text("Custom Fee Rate:")
                                    .font(.caption)
                                TextField("sat/vB", text: Binding(
                                    get: { customSatPerVBInput },
                                    set: { val in
                                        customSatPerVBInput = val
                                        recheckAndClampSendAmount()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                Text("sat/vB")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }

                    transactionCostBreakdownCard

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
                        .disabled(!isSendAllowed || sendAddressInput.isEmpty || (Double(sendAmountInput) ?? 0) <= 0 || isSendDisabledDueToFunds)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
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
                        guard let preview = activePreview else { return }
                        isBroadcasting = true
                        sendErrorMessage = nil
                        Task {
                            defer { isBroadcasting = false }
                            do {
                                let txid = try await state.executeAuthorizedSend(
                                    preview: preview,
                                    explicitPassphrase: sendPassphraseInput.isEmpty ? nil : sendPassphraseInput
                                )
                                await MainActor.run {
                                    self.showPreviewSheet = false
                                    self.activePreview = nil
                                    self.sendPassphraseInput = ""
                                    self.sendAddressInput = ""
                                    self.sendAmountInput = ""
                                    self.state.alertMessage = "Transaction successfully broadcasted!\n\nTXID:\n\(txid)\n\nWallet has been safely re-locked."
                                    self.state.showAlert = true
                                }
                            } catch {
                                await MainActor.run {
                                    self.sendErrorMessage = error.localizedDescription
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            if isBroadcasting {
                                ProgressView().controlSize(.small)
                            }
                            Label(isBroadcasting ? "Signing & Broadcasting..." : "Authorize & Sign Transaction", systemImage: "paperplane.fill")
                                .bold()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isBroadcasting || activePreview?.isExpired == true)
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

            // Live Node RPC Readiness Banner
            HStack(spacing: 8) {
                if isCheckingRPC {
                    ProgressView()
                        .controlSize(.small)
                    Text("Testing Bitcoin Knots RPC connectivity (127.0.0.1)…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if isRPCOnline {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Node RPC Online (127.0.0.1)")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundColor(.red)
                    Text(rpcStatusMessage ?? "Node RPC Offline. Start the BTCB2 node before creating a wallet.")
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Retry") {
                        Task { await checkRPCReadiness() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(6)

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
                            let result = try await state.createEncryptedWallet(
                                name: name, passphrase: passphrase, storeInKeychain: save
                            )
                            showCreateModal = false
                            passphraseInput = ""
                            passphraseConfirmInput = ""
                            showWalletPassphrase = false
                            hasConfirmedOfflinePassphrase = false
                            if let warning = result.keychainWarning {
                                state.alertMessage = "Encrypted descriptor wallet '\(result.walletName)' was created and verified!\n\nNotice: \(warning)\n\nEnsure you have saved your passphrase and backed up your wallet database."
                            } else {
                                state.alertMessage = "Encrypted descriptor wallet '\(result.walletName)' created and verified. Back up the wallet database before receiving substantial funds. Its passphrase alone cannot restore the wallet."
                            }
                            state.showAlert = true
                        } catch let creationErr as WalletCreationError {
                            state.alertMessage = "Wallet creation failed: \(creationErr.localizedDescription)"
                            state.showAlert = true
                        } catch {
                            state.alertMessage = "Wallet creation failed: \(error.localizedDescription)"
                            state.showAlert = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(
                    isCreatingWallet || isCheckingRPC || !isRPCOnline ||
                    walletNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
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
        .frame(width: 520, height: 530)
        .task {
            await checkRPCReadiness()
        }
    }

    private func checkRPCReadiness() async {
        isCheckingRPC = true
        let (ready, status) = await state.checkRPCReadiness()
        isRPCOnline = ready
        rpcStatusMessage = status
        isCheckingRPC = false
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

    // MARK: - BTCB2 Exchange Pricing UI

    private var priceBannerView: some View {
        HStack(spacing: 12) {
            // Price display with status circle
            HStack(spacing: 6) {
                Circle()
                    .fill(state.priceState.isOverridden ? Color.orange : (state.priceState.isStale ? Color.yellow : Color.green))
                    .frame(width: 8, height: 8)

                Text("BTCB2 Price:")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)

                if state.priceState.effectivePrice > 0 {
                    Text(String(format: "$%.2f %@", state.priceState.effectivePrice, state.priceState.effectiveCurrency))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                } else {
                    Text("Connecting…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("(\(state.priceState.effectiveSource))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Exchange comparison
            HStack(spacing: 8) {
                if let n = state.priceState.neoxaQuote {
                    Text("Neoxa: $\(String(format: "%.2f", n.price))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let nk = state.priceState.nonKycQuote {
                    Text("NonKYC: $\(String(format: "%.2f", nk.price))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Refresh button
            Button(action: {
                Task { await state.refreshPrice() }
            }) {
                if state.isFetchingPrice {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Refresh live prices from Neoxa and NonKYC")

            // Price Override button
            Button(action: {
                customPriceInput = state.priceState.customPrice != nil ? String(format: "%.2f", state.priceState.customPrice!) : ""
                showPriceOverrideSheet = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                    Text(state.priceState.isOverridden ? "Override: Active" : "Override Price")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }

    private var priceOverrideSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("BTCB2 Exchange Price & Manual Override")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showPriceOverrideSheet = false
                }
                .buttonStyle(.bordered)
            }

            Text("The wallet connects to Neoxa and NonKYC exchange APIs to determine the current highest market price in USD/USDC/USDT. If APIs are missing, unreachable, or stale, you can set a custom price override.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Market quotes status
            VStack(alignment: .leading, spacing: 8) {
                Text("Live Market Feeds").font(.caption).bold()

                HStack {
                    Text("Neoxa (BTCB2_USDC):")
                        .font(.caption)
                    Spacer()
                    if let q = state.priceState.neoxaQuote {
                        Text(String(format: "$%.2f USDC", q.price))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    } else {
                        Text("No response / unavailable")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("NonKYC (BTCB2_USDT):")
                        .font(.caption)
                    Spacer()
                    if let q = state.priceState.nonKycQuote {
                        Text(String(format: "$%.2f USDT", q.price))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    } else {
                        Text("No response / unavailable")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                HStack {
                    Text("Highest Market Price:")
                        .font(.caption).bold()
                    Spacer()
                    if state.priceState.highestMarketPrice > 0 {
                        Text(String(format: "$%.2f %@ (Source: %@)", state.priceState.highestMarketPrice, state.priceState.highestMarketCurrency, state.priceState.highestMarketSource))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    } else {
                        Text("None available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))

            // Manual override section
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Price Override").font(.caption).bold()
                Text("Enter a custom price in USD per 1 BTCB2 to calculate fiat equivalents throughout the wallet:")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("e.g. 286.50", text: $customPriceInput)
                        .textFieldStyle(.roundedBorder)

                    Button("Apply Override") {
                        if let val = Double(customPriceInput), val > 0 {
                            state.setPriceOverride(price: val)
                            showPriceOverrideSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(Double(customPriceInput) == nil || Double(customPriceInput)! <= 0)

                    if state.priceState.isOverridden {
                        Button("Reset to Live Market") {
                            state.clearPriceOverride()
                            customPriceInput = ""
                            showPriceOverrideSheet = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))

            Spacer()
        }
        .padding(20)
        .frame(width: 480, height: 380)
    }

    private var newAddressSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                Text("Generate New Receive Address")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    showNewAddressSheet = false
                }
                .buttonStyle(.plain)
            }

            Text("Generate a new Native SegWit Bech32 (bc1...) receive address attached to '\(state.walletSnapshot?.name ?? "active wallet")'.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Address Label (Optional):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. Mining Pool Payout, Cold Storage, etc.", text: $newAddressLabelInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showNewAddressSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Generate Address") {
                    let label = newAddressLabelInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.generateNewReceiveAddress(label: label)
                    showNewAddressSheet = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var nodeStartupPromptSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button("Close") {
                    hasBypassedNodePrompt = true
                    showNodePromptSheet = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Image(systemName: "server.rack")
                .font(.system(size: 46))
                .foregroundColor(.orange)

            VStack(spacing: 6) {
                Text("Turn On Bitcoin Knots Node?")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("The Bitcoin Knots Node is currently offline. Wallets, balances, and transaction history require the Knots Node to synchronize and display blockchain data.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.isStartingUp {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(state.startupStatus.isEmpty ? "Starting Knots Node…" : state.startupStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Enabling the node connects to the Bitcoin Knots daemon and begins synchronizing blocks and UTXOs in the background.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
            }

            HStack(spacing: 16) {
                Button("Bypass") {
                    hasBypassedNodePrompt = true
                    showNodePromptSheet = false
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(state.isStartingUp)

                Button(action: {
                    state.startNode()
                }) {
                    HStack(spacing: 6) {
                        if state.isStartingUp {
                            ProgressView()
                                .controlSize(.small)
                            Text("Starting…")
                        } else {
                            Image(systemName: "play.fill")
                            Text("Enable Knots Node")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(state.isStartingUp)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
