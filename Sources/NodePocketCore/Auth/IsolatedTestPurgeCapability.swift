import Foundation

/// A typed, unforgeable capability token strictly required to execute account purge in automated test fixtures.
/// Completely prohibits execution against production or user datadirs in both Debug and Release builds.
public struct IsolatedTestPurgeCapability: Sendable {
    public let fixtureId: UUID
    public let fixtureDirectory: URL
    public let fixtureNonce: String
    public let isMockDeviceOwnerAuthorized: Bool
    public let disposableKeychainNamespace: String

    public static let fixtureMarkerFileName = "nodepocket_isolated_test_fixture.lock"

    /// WO-54: App-facing createForTestFixture is permanently disabled in shipping core.
    /// External callers from ordinary app code cannot construct a valid test capability.
    public static func createForTestFixture(
        directory: URL,
        mockDeviceOwner: Bool = false
    ) throws -> IsolatedTestPurgeCapability {
        throw OperatorAccountPurgeError.releaseModeDisabled
    }

    /// Internal test-only factory method available strictly to internal/test targets.
    /// Strictly rejects non-temporary directories, production datadir paths, symlinks, missing markers,
    /// or non-disposable / production Keychain namespaces.
    package static func createInternalTestCapability(
        directory: URL,
        disposableKeychainNamespace: String,
        mockDeviceOwner: Bool = false
    ) throws -> IsolatedTestPurgeCapability {
        let stdDir = directory.standardizedFileURL
        let resolvedDir = stdDir.resolvingSymlinksInPath()

        // 1. Must be contained within the system temporary directory
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.resolvingSymlinksInPath()
        let resolvedComponents = resolvedDir.pathComponents
        let tempComponents = tempDir.pathComponents

        guard resolvedComponents.starts(with: tempComponents) && resolvedComponents.count > tempComponents.count else {
            throw OperatorAccountPurgeError.storageError(
                "Security violation: Test purge fixture directory must reside inside system temporary directory: \(resolvedDir.path)"
            )
        }

        // 2. Reject any production / user application support directories
        let prohibitedSubstrings = ["Application Support", "Bitcoin", "NodePocket", "Ethereum Mining Corp"]
        for sub in prohibitedSubstrings {
            if resolvedDir.path.localizedCaseInsensitiveContains(sub) {
                throw OperatorAccountPurgeError.storageError(
                    "Security violation: Test purge capability rejected prohibited datadir path: \(resolvedDir.path)"
                )
            }
        }

        // 3. Reject ancestor or directory symlinks
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: stdDir.path)) != nil {
            throw OperatorAccountPurgeError.symlinkNotPermitted("Test fixture directory cannot be a symbolic link: \(stdDir.path)")
        }

        // 4. Must contain the unique cryptographic fixture marker file
        let markerURL = resolvedDir.appendingPathComponent(fixtureMarkerFileName)
        guard FileManager.default.fileExists(atPath: markerURL.path),
              let markerData = try? Data(contentsOf: markerURL),
              let markerNonce = String(data: markerData, encoding: .utf8),
              !markerNonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OperatorAccountPurgeError.storageError(
                "Security violation: Test fixture missing required valid marker lock file: \(markerURL.path)"
            )
        }

        // 5. WO-54: Enforce disposable Keychain namespace (must not be production Keychain namespace)
        let trimmedNamespace = disposableKeychainNamespace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNamespace != "app.nodepocket.btcb2.wallet" &&
              trimmedNamespace != "app.nodepocket.btcb2.auth" &&
              trimmedNamespace.hasPrefix("app.nodepocket.test.") else {
            throw OperatorAccountPurgeError.storageError(
                "Security violation: Test purge capability requires a disposable test Keychain namespace starting with 'app.nodepocket.test.', got '\(disposableKeychainNamespace)'"
            )
        }

        let id = UUID()
        return IsolatedTestPurgeCapability(
            fixtureId: id,
            fixtureDirectory: resolvedDir,
            fixtureNonce: markerNonce.trimmingCharacters(in: .whitespacesAndNewlines),
            isMockDeviceOwnerAuthorized: mockDeviceOwner,
            disposableKeychainNamespace: trimmedNamespace
        )
    }

    package init(
        fixtureId: UUID,
        fixtureDirectory: URL,
        fixtureNonce: String,
        isMockDeviceOwnerAuthorized: Bool,
        disposableKeychainNamespace: String
    ) {
        self.fixtureId = fixtureId
        self.fixtureDirectory = fixtureDirectory
        self.fixtureNonce = fixtureNonce
        self.isMockDeviceOwnerAuthorized = isMockDeviceOwnerAuthorized
        self.disposableKeychainNamespace = disposableKeychainNamespace
    }

    /// Verifies the capability against the coordinator's actual runtime datadir and disposable Keychain namespace.
    public func validate(forDataDirectory dataDirectory: URL, keychainNamespace: String? = nil) -> Bool {
        let resolvedDataDir = dataDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedDataDir == fixtureDirectory else {
            return false
        }
        let markerURL = fixtureDirectory.appendingPathComponent(Self.fixtureMarkerFileName)
        guard FileManager.default.fileExists(atPath: markerURL.path),
              let data = try? Data(contentsOf: markerURL),
              let nonce = String(data: data, encoding: .utf8),
              nonce.trimmingCharacters(in: .whitespacesAndNewlines) == self.fixtureNonce else {
            return false
        }
        if let ns = keychainNamespace {
            guard ns == self.disposableKeychainNamespace else {
                return false
            }
        }
        return true
    }
}
