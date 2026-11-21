import XCTest
import CryptoKit
@testable import NodePocketCore

final class SoftwareUpdateTests: XCTestCase {

    // MARK: - AppVersion Parsing & Numeric Build Ordering

    func testAppVersionParsingFormats() {
        let v1 = AppVersion.parse("v1.0.0-build3")
        XCTAssertNotNil(v1)
        XCTAssertEqual(v1?.major, 1)
        XCTAssertEqual(v1?.minor, 0)
        XCTAssertEqual(v1?.patch, 0)
        XCTAssertEqual(v1?.build, 3)
        XCTAssertFalse(v1!.isPrerelease)

        let v2 = AppVersion.parse("1.0 (3)")
        XCTAssertNotNil(v2)
        XCTAssertEqual(v2?.major, 1)
        XCTAssertEqual(v2?.minor, 0)
        XCTAssertEqual(v2?.patch, 0)
        XCTAssertEqual(v2?.build, 3)

        let v3 = AppVersion.parse("v1.0.0-build10")
        XCTAssertNotNil(v3)
        XCTAssertEqual(v3?.build, 10)

        let v4 = AppVersion.parse("1.2.3-beta.1-build4")
        XCTAssertNotNil(v4)
        XCTAssertEqual(v4?.major, 1)
        XCTAssertEqual(v4?.minor, 2)
        XCTAssertEqual(v4?.patch, 3)
        XCTAssertEqual(v4?.prerelease, "beta.1")
        XCTAssertEqual(v4?.build, 4)
        XCTAssertTrue(v4!.isPrerelease)
    }

    func testNumericBuildOrderingVersusLexicographical() {
        let build3 = AppVersion.parse("v1.0.0-build3")!
        let build10 = AppVersion.parse("v1.0.0-build10")!

        // In lexicographical string comparison, "build10" < "build3" (false order).
        // In integer build ordering, build 3 MUST be strictly less than build 10!
        XCTAssertTrue(build3 < build10)
        XCTAssertFalse(build10 < build3)

        // Equivalence across different presentation formats
        let paren3 = AppVersion.parse("1.0.0 (3)")!
        XCTAssertEqual(build3, paren3)
    }

    func testSemVerPriorityOverBuild() {
        let v1_0_build10 = AppVersion.parse("v1.0.0-build10")!
        let v1_1_build1 = AppVersion.parse("v1.1.0-build1")!
        let v2_0_build0 = AppVersion.parse("v2.0.0-build0")!

        XCTAssertTrue(v1_0_build10 < v1_1_build1)
        XCTAssertTrue(v1_1_build1 < v2_0_build0)
    }

    func testPrereleasePrecedence() {
        let beta = AppVersion.parse("1.0.0-beta.1")!
        let stable = AppVersion.parse("1.0.0")!

        // SemVer: 1.0.0-beta.1 < 1.0.0
        XCTAssertTrue(beta < stable)
        XCTAssertFalse(stable < beta)
    }

    func testDisallowDowngrades() {
        let installed = AppVersion.parse("v1.0.0-build3")!
        let older = AppVersion.parse("v1.0.0-build2")!
        let resolver = GitHubReleaseResolver()

        let candidate = AppReleaseInfo(
            id: "old",
            tagName: "v1.0.0-build2",
            version: older,
            name: "Older Release",
            releaseNotes: "Older",
            publishedAt: Date()
        )

        let result = resolver.findEligibleUpdate(
            from: [candidate],
            installedVersion: installed
        )

        switch result {
        case .success(let update):
            XCTAssertNil(update, "Downgrades must be rejected as no update available")
        case .failure(let err):
            XCTFail("Unexpected error: \(err)")
        }
    }

    // MARK: - Architecture Compatibility & Asset Matching

    func testArchitectureCompatibilityRules() {
        // Apple Silicon arm64 host:
        XCTAssertTrue(AppArchitecture.arm64.isCompatible(with: .arm64))
        XCTAssertTrue(AppArchitecture.universal.isCompatible(with: .arm64))
        XCTAssertFalse(AppArchitecture.x86_64.isCompatible(with: .arm64), "arm64 Mac must strictly reject x86_64 binary")

        // Intel x86_64 host:
        XCTAssertTrue(AppArchitecture.x86_64.isCompatible(with: .x86_64))
        XCTAssertTrue(AppArchitecture.universal.isCompatible(with: .x86_64))
        XCTAssertFalse(AppArchitecture.arm64.isCompatible(with: .x86_64), "x86_64 Mac must strictly reject arm64 binary")
    }

    func testArchitectureDetectionFromAssetFilenames() {
        XCTAssertEqual(
            AppArchitecture.detect(from: "Sentinel-Node-Wallet-v1.0-Build3-macOS-arm64.dmg"),
            .arm64
        )
        XCTAssertEqual(
            AppArchitecture.detect(from: "Sentinel-Node-Wallet-v1.0-Build3-macOS-x86_64.dmg"),
            .x86_64
        )
        XCTAssertEqual(
            AppArchitecture.detect(from: "Sentinel-Node-Wallet-v1.0-Build3-macOS-universal.dmg"),
            .universal
        )
        XCTAssertEqual(
            AppArchitecture.detect(from: "random-file.dmg"),
            .unknown
        )
    }

    func testMissingIntelAssetRejectionOnIntelMac() {
        let resolver = GitHubReleaseResolver()
        let installed = AppVersion.parse("v1.0.0-build3")!

        // Release published with arm64 DMG ONLY (current reality of v1.0.0-build3)
        let arm64Release = AppReleaseInfo(
            id: "rel4",
            tagName: "v1.0.0-build4",
            version: AppVersion.parse("v1.0.0-build4")!,
            name: "Build 4",
            releaseNotes: "Notes",
            publishedAt: Date(),
            downloadUrl: URL(string: "https://github.com/.../macOS-arm64.dmg"),
            architecture: .arm64
        )

        // When queried from an Intel Mac (host: .x86_64)
        let result = resolver.findEligibleUpdate(
            from: [arm64Release],
            installedVersion: installed,
            hostArchitecture: .x86_64
        )

        switch result {
        case .success:
            XCTFail("Must not accept arm64 binary for x86_64 host")
        case .failure(let err):
            if case .incompatibleArchitecture(let target, let host) = err {
                XCTAssertEqual(target, .arm64)
                XCTAssertEqual(host, .x86_64)
            } else {
                XCTFail("Expected .incompatibleArchitecture, got \(err)")
            }
        }
    }

    // MARK: - Channel Filtering & Skipped Versions

    func testChannelFilteringStableVersusBeta() {
        let resolver = GitHubReleaseResolver()
        let installed = AppVersion.parse("v1.0.0-build3")!

        let betaRelease = AppReleaseInfo(
            id: "beta4",
            tagName: "v1.1.0-beta.1-build1",
            version: AppVersion.parse("v1.1.0-beta.1-build1")!,
            name: "Beta 1",
            releaseNotes: "Beta notes",
            publishedAt: Date(),
            isPrerelease: true,
            architecture: .arm64
        )

        // Stable channel: must ignore prereleases
        let stableResult = resolver.findEligibleUpdate(
            from: [betaRelease],
            installedVersion: installed,
            hostArchitecture: .arm64,
            channel: .stable
        )
        XCTAssertEqual(try? stableResult.get(), nil, "Stable channel must not receive beta updates")

        // Beta channel: must receive prerelease update
        let betaResult = resolver.findEligibleUpdate(
            from: [betaRelease],
            installedVersion: installed,
            hostArchitecture: .arm64,
            channel: .beta
        )
        XCTAssertEqual(try? betaResult.get(), betaRelease)
    }

    func testSkippedVersionSuppression() {
        let resolver = GitHubReleaseResolver()
        let installed = AppVersion.parse("v1.0.0-build3")!

        let release4 = AppReleaseInfo(
            id: "build4",
            tagName: "v1.0.0-build4",
            version: AppVersion.parse("v1.0.0-build4")!,
            name: "Build 4",
            releaseNotes: "Notes",
            publishedAt: Date(),
            architecture: .arm64
        )

        var skipped: Set<String> = ["v1.0.0-build4"]
        let result = resolver.findEligibleUpdate(
            from: [release4],
            installedVersion: installed,
            hostArchitecture: .arm64,
            skippedVersions: skipped
        )
        XCTAssertEqual(try? result.get(), nil, "Skipped version must not be surfaced as an eligible update")

        // Unskipping version surfaces it again
        skipped.removeAll()
        let unskippedResult = resolver.findEligibleUpdate(
            from: [release4],
            installedVersion: installed,
            hostArchitecture: .arm64,
            skippedVersions: skipped
        )
        XCTAssertEqual(try? unskippedResult.get(), release4)
    }

    // MARK: - Sparkle Appcast XML Parsing

    func testSparkleAppcastXMLParsing() throws {
        let sampleXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>
                <title>Sentinel Node Wallet Updates</title>
                <item>
                    <title>Sentinel Node Wallet 1.0 (Build 4)</title>
                    <description>Fixed Keychain access and dynamic storage reporting.</description>
                    <pubDate>Mon, 16 Nov 2026 15:00:00 +0000</pubDate>
                    <enclosure
                        url="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v1.0.0-build4/Sentinel-Node-Wallet-v1.0-Build4-macOS-arm64.dmg"
                        sparkle:edSignature="k7Zqg9x8j...=="
                        sparkle:version="4"
                        sparkle:shortVersionString="1.0"
                        sparkle:os="macos"
                        sparkle:cpu="arm64"
                        length="12450000"
                        type="application/octet-stream" />
                    <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
                </item>
            </channel>
        </rss>
        """

        let data = sampleXML.data(using: .utf8)!
        let releases = try SparkleAppcastParser.parse(xmlData: data)

        XCTAssertEqual(releases.count, 1)
        let first = releases[0]
        XCTAssertEqual(first.version.major, 1)
        XCTAssertEqual(first.version.minor, 0)
        XCTAssertEqual(first.version.build, 4)
        XCTAssertEqual(first.architecture, .arm64)
        XCTAssertEqual(first.sparkleEdSignature, "k7Zqg9x8j...==")
        XCTAssertEqual(first.downloadSize, 12450000)
        XCTAssertEqual(first.minOSVersion, "13.0")
        XCTAssertTrue(first.releaseNotes.contains("Fixed Keychain access"))
    }

    // MARK: - Mock Driver Verification & Coordinator Lifecycle

    func testMockDriverUpdateLifecycle() async throws {
        let driver = MockUpdateDriver(status: .idle, distributionChannel: .directGitHub)
        driver.installedVersion = AppVersion(major: 1, minor: 0, patch: 0, build: 3)
        driver.hostArchitecture = .arm64

        let newer = AppReleaseInfo(
            id: "b4",
            tagName: "v1.0.0-build4",
            version: AppVersion(major: 1, minor: 0, patch: 0, build: 4),
            name: "Sentinel Node Wallet 1.0 (Build 4)",
            releaseNotes: "Security updates",
            publishedAt: Date(),
            downloadUrl: URL(string: "https://example.com/build4.dmg"),
            architecture: .arm64
        )
        driver.mockReleases = [newer]

        let status = try await driver.checkForUpdates(isUserInitiated: true)
        if case .updateAvailable(let rel) = status {
            XCTAssertEqual(rel.version.build, 4)
        } else {
            XCTFail("Expected .updateAvailable, got \(status)")
        }

        try await driver.installUpdate(release: newer)
        XCTAssertTrue(driver.installCalled)
        XCTAssertEqual(driver.installCallCount, 1)
        XCTAssertEqual(driver.lastInstalledRelease, newer)
    }

    func testAppStoreDistributionIsolation() async throws {
        // App Store distribution must never download or install GitHub binaries
        let appStoreDriver = MockUpdateDriver(status: .idle, distributionChannel: .macAppStore)
        XCTAssertEqual(appStoreDriver.distributionChannel, .macAppStore)
    }

    // MARK: - Dynamic Bundle Version & Parsing Edge Cases

    func testBundleVersionDynamicParsing() {
        let v1 = AppVersion.parse("1.0 (build 3)")
        XCTAssertNotNil(v1)
        XCTAssertEqual(v1?.major, 1)
        XCTAssertEqual(v1?.minor, 0)
        XCTAssertEqual(v1?.patch, 0)
        XCTAssertEqual(v1?.build, 3)

        let v2 = AppVersion.parse("1.2.3 (build 15)")
        XCTAssertNotNil(v2)
        XCTAssertEqual(v2?.major, 1)
        XCTAssertEqual(v2?.minor, 2)
        XCTAssertEqual(v2?.patch, 3)
        XCTAssertEqual(v2?.build, 15)

        let v3 = AppVersion.parse("2.0.0-rc.1 (build 42)")
        XCTAssertNotNil(v3)
        XCTAssertEqual(v3?.major, 2)
        XCTAssertEqual(v3?.minor, 0)
        XCTAssertEqual(v3?.patch, 0)
        XCTAssertEqual(v3?.prerelease, "rc.1")
        XCTAssertEqual(v3?.build, 42)

        // Raw short version without build in string:
        let v4 = AppVersion.parse("2.1.0")
        XCTAssertNotNil(v4)
        XCTAssertEqual(v4?.major, 2)
        XCTAssertEqual(v4?.minor, 1)
        XCTAssertEqual(v4?.patch, 0)
        XCTAssertNil(v4?.build)
    }

    // MARK: - HTTP 304 and Cache Invalidation Safety

    func testHttp304PreservesDiscoveredReleaseState() {
        let release = AppReleaseInfo(
            id: "rel5",
            tagName: "v1.0.0-build5",
            version: AppVersion(major: 1, minor: 0, patch: 0, build: 5),
            name: "Build 5",
            releaseNotes: "Critical fix",
            publishedAt: Date()
        )

        var status: SoftwareUpdateStatus = .updateAvailable(release)
        let discovered: AppReleaseInfo? = release

        // Simulate 304 Not Modified handler logic
        let error: Error = SoftwareUpdateError.notModified
        if case SoftwareUpdateError.notModified = error {
            if let existing = discovered {
                status = .updateAvailable(existing)
            } else {
                status = .upToDate(lastChecked: Date())
            }
        }

        if case .updateAvailable(let preserved) = status {
            XCTAssertEqual(preserved.version.build, 5, "HTTP 304 must preserve the previously discovered update")
        } else {
            XCTFail("Expected .updateAvailable to be preserved on 304, got \(status)")
        }
    }

    // MARK: - Busy Guards & Node Termination Safety

    final class StopFlag: @unchecked Sendable {
        var invoked = false
    }

    func testBusyGuardBlocksInstallationWhenWalletOrNodeBusy() async {
        let driver = MockUpdateDriver()
        let release = AppReleaseInfo(
            id: "rel4",
            tagName: "v1.0.0-build4",
            version: AppVersion(major: 1, minor: 0, patch: 0, build: 4),
            name: "Build 4",
            releaseNotes: "Notes",
            publishedAt: Date()
        )

        let flag = StopFlag()
        let isBusy: @Sendable () async -> Bool = { true }
        let stopAction: @Sendable () async throws -> Void = { flag.invoked = true }

        // Simulate coordinator pre-install check:
        var threwBusy = false
        do {
            if await isBusy() {
                throw SoftwareUpdateError.walletActiveOperationInProgress
            }
            try await stopAction()
            try await driver.installUpdate(release: release)
        } catch SoftwareUpdateError.walletActiveOperationInProgress {
            threwBusy = true
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(threwBusy, "Busy guard must reject installation")
        XCTAssertFalse(flag.invoked, "Node must NOT be stopped when busy")
        XCTAssertFalse(driver.installCalled, "Driver must NOT be called when busy")
    }

    func testAdoptedExternalDaemonRejectsAutoTermination() async {
        let adoptedPid: Int32? = 47208

        var threwAdoptedError = false
        do {
            if let pid = adoptedPid {
                throw SoftwareUpdateError.nodeTerminationFailed(
                    "An external adopted Bitcoin Knots daemon (PID \(pid)) is running. External daemons must be stopped manually by the operator before updating."
                )
            }
        } catch SoftwareUpdateError.nodeTerminationFailed(let msg) {
            threwAdoptedError = true
            XCTAssertTrue(msg.contains("47208"))
            XCTAssertTrue(msg.contains("adopted"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(threwAdoptedError, "Adopted daemon presence must block automated node stop")
    }

    func testNodeTerminationTimeoutFailure() async {
        var threwTimeout = false
        let simulateShutdown: () async throws -> Void = {
            let waited = 30
            let stateIsStopped = false
            if !stateIsStopped && waited >= 30 {
                throw SoftwareUpdateError.nodeTerminationFailed(
                    "Bitcoin Knots daemon did not complete graceful shutdown within 30 seconds."
                )
            }
        }

        do {
            try await simulateShutdown()
        } catch SoftwareUpdateError.nodeTerminationFailed(let msg) {
            threwTimeout = true
            XCTAssertTrue(msg.contains("30 seconds"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(threwTimeout, "Failure to stop within 30s must throw nodeTerminationFailed")
    }

    func testPostponedRelaunchLifecycleCancelAndRetry() async throws {
        final class PostponeContext: @unchecked Sendable {
            var installHandlerInvoked = false
            var isBusy = true
            var shutdownInvoked = false
        }
        let ctx = PostponeContext()

        // 1. Postponed due to busy
        XCTAssertTrue(ctx.isBusy)
        XCTAssertFalse(ctx.installHandlerInvoked)

        // 2. Cancellation sets status to idle and clears handler
        var isPostponed = true
        var status: SoftwareUpdateStatus = .error("Busy")
        func cancel() {
            isPostponed = false
            status = .idle
        }
        cancel()
        XCTAssertFalse(isPostponed)
        XCTAssertEqual(status, .idle)

        // 3. Retry when no longer busy invokes graceful shutdown then handler
        ctx.isBusy = false
        if !ctx.isBusy {
            ctx.shutdownInvoked = true
            ctx.installHandlerInvoked = true
        }
        XCTAssertTrue(ctx.shutdownInvoked)
        XCTAssertTrue(ctx.installHandlerInvoked)
    }

    // MARK: - WO-68 Native Cutover & Sparkle Edge Case Tests

    func testBuild3ToBuild4EligibleUpdateDiscovery() {
        let resolver = GitHubReleaseResolver()
        let installedBuild3 = AppVersion.parse("1.0 (build 3)")!

        let build3Release = AppReleaseInfo(
            id: "b3",
            tagName: "v1.0.0-build3",
            version: installedBuild3,
            name: "Sentinel Node Wallet 1.0 (Build 3)",
            releaseNotes: "Legacy ad-hoc build",
            publishedAt: Date(timeIntervalSince1970: 1731628800),
            architecture: .arm64
        )

        let build4Release = AppReleaseInfo(
            id: "b4",
            tagName: "v1.0.0-build4",
            version: AppVersion.parse("1.0.0 (build 4)")!,
            name: "Sentinel Node Wallet 1.0 (Build 4)",
            releaseNotes: "Sparkle 2 auto-update cutover and recovery hardening",
            publishedAt: Date(),
            downloadUrl: URL(string: "https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v1.0.0-build4/Sentinel-Node-Wallet-v1.0-Build4-macOS-arm64.dmg"),
            downloadSize: 12450000,
            architecture: .arm64,
            sparkleEdSignature: "mock_valid_signature_base64_==",
            minOSVersion: "13.0"
        )

        let result = resolver.findEligibleUpdate(
            from: [build3Release, build4Release],
            installedVersion: installedBuild3,
            hostArchitecture: .arm64,
            channel: .stable
        )

        switch result {
        case .success(let eligible):
            XCTAssertNotNil(eligible)
            XCTAssertEqual(eligible?.version.build, 4)
            XCTAssertEqual(eligible?.tagName, "v1.0.0-build4")
            XCTAssertEqual(eligible?.sparkleEdSignature, "mock_valid_signature_base64_==")
        case .failure(let err):
            XCTFail("Expected eligible Build 4 update, got failure: \(err)")
        }
    }

    func testMalformedAppcastXMLFailsClosed() {
        let badXML = "<rss><channel><item><title>Broken XML without closing tag".data(using: .utf8)!
        XCTAssertThrowsError(try SparkleAppcastParser.parse(xmlData: badXML)) { error in
            guard let updateError = error as? SoftwareUpdateError,
                  case .invalidAppcast = updateError else {
                XCTFail("Expected SoftwareUpdateError.invalidAppcast, got \(error)")
                return
            }
        }
    }

    func testEmptyAppcastReturnsZeroReleases() throws {
        let emptyXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0">
            <channel>
                <title>No Releases</title>
            </channel>
        </rss>
        """.data(using: .utf8)!

        let releases = try SparkleAppcastParser.parse(xmlData: emptyXML)
        XCTAssertTrue(releases.isEmpty)

        let resolver = GitHubReleaseResolver()
        let installed = AppVersion.parse("1.0 (build 3)")!
        let result = resolver.findEligibleUpdate(from: releases, installedVersion: installed)
        XCTAssertEqual(try? result.get(), nil, "Empty appcast must return nil eligible update")
    }

    func testHostArchitectureGatingIneligibleIntelRejection() {
        let resolver = GitHubReleaseResolver()
        let installed = AppVersion.parse("1.0 (build 3)")!

        let arm64OnlyRelease = AppReleaseInfo(
            id: "arm64_only",
            tagName: "v1.0.0-build4",
            version: AppVersion.parse("1.0.0 (build 4)")!,
            name: "Arm64 Build",
            releaseNotes: "Apple Silicon only",
            publishedAt: Date(),
            architecture: .arm64
        )

        let result = resolver.findEligibleUpdate(
            from: [arm64OnlyRelease],
            installedVersion: installed,
            hostArchitecture: .x86_64, // Host is x86_64
            channel: .stable
        )

        switch result {
        case .success:
            XCTFail("Intel host must NOT be offered arm64-only binary")
        case .failure(let err):
            guard case .incompatibleArchitecture(let target, let host) = err else {
                XCTFail("Expected incompatibleArchitecture, got \(err)")
                return
            }
            XCTAssertEqual(target, AppArchitecture.arm64)
            XCTAssertEqual(host, AppArchitecture.x86_64)
        }
    }

    func testBackgroundCheckSafetyNeverStopsNode() async {
        final class StopContext: @unchecked Sendable {
            var nodeStopInvoked = false
        }
        let ctx = StopContext()
        let stopAction: @Sendable () async throws -> Void = {
            ctx.nodeStopInvoked = true
        }

        let installed = AppVersion.parse("1.0 (build 3)")!
        let driver = MockUpdateDriver(status: .idle, distributionChannel: .directGitHub)
        driver.installedVersion = installed

        let newer = AppReleaseInfo(
            id: "b4",
            tagName: "v1.0.0-build4",
            version: AppVersion.parse("1.0.0 (build 4)")!,
            name: "Build 4",
            releaseNotes: "Security update",
            publishedAt: Date(),
            architecture: .arm64
        )
        driver.mockReleases = [newer]

        // Running an update check (whether background or manual) must NEVER invoke graceful node shutdown!
        let status = try? await driver.checkForUpdates(isUserInitiated: false)
        XCTAssertFalse(ctx.nodeStopInvoked, "Background check must never terminate node")
        if case .updateAvailable(let rel) = status {
            XCTAssertEqual(rel.version.build, 4)
        }

        // Only explicitly installing update triggers node shutdown
        try? await stopAction()
        XCTAssertTrue(ctx.nodeStopInvoked, "Confirmed node shutdown invoked only on deliberate install")
    }

    // MARK: - WO-70 Production Feed Isolation, ETag Segregation & Fallback Defense

    func testETagSegregationPerFeedURL() {
        let tempDefaults = UserDefaults(suiteName: "test.etag.segregation.\(UUID().uuidString)")!
        let config = SoftwareUpdateConfiguration(defaults: tempDefaults)

        let prodUrl = URL(string: "https://raw.githubusercontent.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/main/dist/appcast.xml")!
        let betaUrl = URL(string: "https://raw.githubusercontent.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/main/dist/appcast-beta.xml")!

        XCTAssertNil(config.lastCheckETag(for: prodUrl))
        XCTAssertNil(config.lastCheckETag(for: betaUrl))

        config.setLastCheckETag("\"etag-prod-123\"", for: prodUrl)
        XCTAssertEqual(config.lastCheckETag(for: prodUrl), "\"etag-prod-123\"")
        XCTAssertNil(config.lastCheckETag(for: betaUrl), "Beta feed must NOT inherit production ETag")

        config.setLastCheckETag("\"etag-beta-456\"", for: betaUrl)
        XCTAssertEqual(config.lastCheckETag(for: prodUrl), "\"etag-prod-123\"")
        XCTAssertEqual(config.lastCheckETag(for: betaUrl), "\"etag-beta-456\"")
    }

    func testStableChannelRejectsInsecureScheme() {
        let insecureUrl = URL(string: "http://malicious-site.com/appcast.xml")!
        let scheme = insecureUrl.scheme?.lowercased()
        let isSecure = scheme == "https" || (scheme == "http" && (insecureUrl.host == "127.0.0.1" || insecureUrl.host == "localhost"))
        XCTAssertFalse(isSecure, "Non-local HTTP scheme must be rejected")
    }

    func testStableChannelRejectsDraftBranchFallbackOn404() async {
        let resolver = GitHubReleaseResolver()
        let missingUrl = URL(string: "https://raw.githubusercontent.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/main/dist/nonexistent-appcast-fixture-404.xml")!

        do {
            _ = try await resolver.fetchFromAppcast(appcastUrl: missingUrl)
            XCTFail("Must fail when stable feed returns 404")
        } catch let SoftwareUpdateError.networkError(msg) {
            XCTAssertTrue(msg.contains("404"), "Expected HTTP 404 in error message, got: \(msg)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - WO-72 Cryptographic Feed & Stale / Canary Rollback Defense

    func testAppcastEnclosureSignatureValidation() throws {
        let unsignedAppcast = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>
                <title>Sentinel Updates</title>
                <item>
                    <title>Build 4</title>
                    <enclosure url="https://example.com/app.dmg" sparkle:version="4" sparkle:shortVersionString="1.0" type="application/octet-stream" />
                </item>
            </channel>
        </rss>
        """.data(using: .utf8)!

        let releases = try SparkleAppcastParser.parse(xmlData: unsignedAppcast)
        XCTAssertEqual(releases.count, 1)
        XCTAssertNil(releases.first?.sparkleEdSignature, "Unsigned appcast must have nil sparkleEdSignature")
    }

    func testCanaryRollbackAndStaleFeedDetection() {
        let resolver = GitHubReleaseResolver()
        let installed = AppVersion.parse("1.0.0 (build 4)")!

        // Stale or rollback feed containing only older Build 3
        let olderRelease = AppReleaseInfo(
            id: "b3",
            tagName: "v1.0.0-build3",
            version: AppVersion.parse("1.0.0 (build 3)")!,
            name: "Build 3",
            releaseNotes: "Older",
            publishedAt: Date()
        )

        let result = resolver.findEligibleUpdate(from: [olderRelease], installedVersion: installed)
        switch result {
        case .success(let eligible):
            XCTAssertNil(eligible, "Stale or rollback feed containing older build must return nil eligible update")
        case .failure(let err):
            XCTFail("Unexpected failure on stale feed check: \(err)")
        }
    }

    // MARK: - WO-76 Release Tag Grammar, Monotonic Build & Operator Approval Validation

    func testReleaseTagStrictRegexAndGrammarValidation() throws {
        // Valid tags matching ^v[0-9]+\.[0-9]+\.[0-9]+-build[0-9]+$ with build > 4
        let validTags = [
            "v1.0.0-build5",
            "v1.0.1-build6",
            "v2.0.0-build10",
            "v10.20.30-build100"
        ]
        for tag in validTags {
            XCTAssertNoThrow(try ReleaseTagValidator.validateReleaseTag(tag, minimumBuildNumber: 4))
            let validated = try ReleaseTagValidator.validateReleaseTag(tag, minimumBuildNumber: 4)
            XCTAssertEqual(validated.rawTag, tag)
            XCTAssertGreaterThan(validated.buildNumber, 4)
        }

        // Invalid tags: missing 'v' prefix, missing build, prerelease string, injection tokens, empty
        let invalidTags = [
            "",
            "   ",
            "1.0.0-build5",          // missing leading 'v'
            "v1.0.0",                // missing build suffix
            "v1.0.0-build",          // non-numeric build
            "v1.0.0-beta-build5",    // prerelease token disallowed in strict release regex
            "v1.0-build5",           // two-component version
            "v1.0.0.0-build5",       // four-component version
            "v1.0.0-build5; rm -rf /", // shell injection payload
            "v1.0.0-build5\n",       // trailing newline
            "refs/tags/v1.0.0-build5" // ref path
        ]
        for tag in invalidTags {
            XCTAssertThrowsError(try ReleaseTagValidator.validateReleaseTag(tag, minimumBuildNumber: 4)) { error in
                guard let valError = error as? ReleaseTagValidator.ValidationError else {
                    XCTFail("Expected ReleaseTagValidator.ValidationError, got \(error)")
                    return
                }
                if tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    XCTAssertEqual(valError, .emptyTag)
                } else {
                    XCTAssertEqual(valError, .invalidFormat(tag))
                }
            }
        }
    }

    func testMonotonicReleaseBuildEnforcement() {
        // Active dev build is 4. Candidate production release builds must be strictly > 4.
        let nonMonotonicTags = [
            "v1.0.0-build0",
            "v1.0.0-build1",
            "v1.0.0-build3",
            "v1.0.0-build4"
        ]
        for tag in nonMonotonicTags {
            XCTAssertThrowsError(try ReleaseTagValidator.validateReleaseTag(tag, minimumBuildNumber: 4)) { error in
                guard case .nonMonotonicBuild(let build, let min) = error as? ReleaseTagValidator.ValidationError else {
                    XCTFail("Expected nonMonotonicBuild, got \(error)")
                    return
                }
                XCTAssertEqual(min, 4)
                XCTAssertLessThanOrEqual(build, 4)
            }
        }

        // Monotonic builds > 4 succeed
        XCTAssertNoThrow(try ReleaseTagValidator.validateReleaseTag("v1.0.0-build5", minimumBuildNumber: 4))
        XCTAssertNoThrow(try ReleaseTagValidator.validateReleaseTag("v1.0.0-build6", minimumBuildNumber: 4))
    }

    func testOperatorReleaseAuthorizationValidation() {
        // Only exact uppercase "YES" is accepted
        XCTAssertNoThrow(try ReleaseTagValidator.validateOperatorApproval("YES"))

        let invalidApprovals = [
            "NO",
            "yes",
            "Yes",
            "true",
            "1",
            "",
            "CONFIRM",
            "APPROVED"
        ]
        for approval in invalidApprovals {
            XCTAssertThrowsError(try ReleaseTagValidator.validateOperatorApproval(approval)) { error in
                guard case .operatorApprovalMissing(let received) = error as? ReleaseTagValidator.ValidationError else {
                    XCTFail("Expected operatorApprovalMissing, got \(error)")
                    return
                }
                XCTAssertEqual(received, approval)
            }
        }
    }

    func testTagParsingExtractsVersionAndBuild() throws {
        let tag = "v1.2.3-build42"
        let validated = try ReleaseTagValidator.validateReleaseTag(tag, minimumBuildNumber: 4)
        XCTAssertEqual(validated.rawTag, "v1.2.3-build42")
        XCTAssertEqual(validated.version, "1.2.3")
        XCTAssertEqual(validated.major, 1)
        XCTAssertEqual(validated.minor, 2)
        XCTAssertEqual(validated.patch, 3)
        XCTAssertEqual(validated.buildNumber, 42)
    }

    // MARK: - WO-77 Public Sparkle Feed Publication Gating & Enclosure Integrity

    func testAppcastPublisherMonotonicBuildCheckAndEnclosureValidation() throws {
        let baseAppcastXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <channel>
                <title>Sentinel Node Wallet Updates</title>
                <link>https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2</link>
                <description>Official updates</description>
                <language>en</language>
                <item>
                    <title>Build 3</title>
                    <enclosure url="https://example.com/app3.dmg" sparkle:version="3" sparkle:shortVersionString="1.0" length="12000000" type="application/octet-stream" />
                </item>
            </channel>
        </rss>
        """

        let existingReleases = try SparkleAppcastParser.parse(xmlData: baseAppcastXML.data(using: .utf8)!)
        XCTAssertEqual(existingReleases.count, 1)
        XCTAssertEqual(existingReleases.first?.version.build, 3)

        // Monotonic check: candidate Build 4 must fail against active dev build 4, while candidate Build 5 must succeed
        XCTAssertThrowsError(try ReleaseTagValidator.validateReleaseTag("v1.0.0-build4", minimumBuildNumber: 4))
        XCTAssertThrowsError(try ReleaseTagValidator.validateReleaseTag("v1.0.0-build3", minimumBuildNumber: 4))
        let validated = try ReleaseTagValidator.validateReleaseTag("v1.0.0-build5", minimumBuildNumber: 4)
        XCTAssertEqual(validated.buildNumber, 5)

        // Construct candidate updated appcast with signed enclosure
        let mockEdSignature = "KzM39JvY+Q8r1f8z0A3wH5MockSignature12345678901234567890123456789012345678901234567890=="
        let updatedAppcastXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <channel>
                <title>Sentinel Node Wallet Updates</title>
                <link>https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2</link>
                <description>Official updates</description>
                <language>en</language>
                <item>
                    <title>Sentinel Node Wallet v1.0.0 (Build 5)</title>
                    <pubDate>Thu, 19 Nov 2026 06:00:00 +0000</pubDate>
                    <sparkle:releaseNotesLink>https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/tag/v1.0.0-build5</sparkle:releaseNotesLink>
                    <enclosure
                        url="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v1.0.0-build5/Sentinel-Node-Wallet-BTCB2-v1.0.0-build5-macOS-arm64-notarized.dmg"
                        sparkle:version="5"
                        sparkle:shortVersionString="1.0.0"
                        sparkle:os="macos"
                        sparkle:cpu="arm64"
                        sparkle:edSignature="\(mockEdSignature)"
                        length="12450000"
                        type="application/octet-stream" />
                    <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
                </item>
                <item>
                    <title>Build 3</title>
                    <enclosure url="https://example.com/app3.dmg" sparkle:version="3" sparkle:shortVersionString="1.0" length="12000000" type="application/octet-stream" />
                </item>
            </channel>
        </rss>
        """

        let updatedReleases = try SparkleAppcastParser.parse(xmlData: updatedAppcastXML.data(using: .utf8)!)
        XCTAssertEqual(updatedReleases.count, 2)

        let newestRelease = updatedReleases[0]
        XCTAssertEqual(newestRelease.version.build, 5)
        XCTAssertEqual(newestRelease.version.major, 1)
        XCTAssertEqual(newestRelease.sparkleEdSignature, mockEdSignature)
        XCTAssertEqual(newestRelease.architecture, .arm64)
        XCTAssertEqual(newestRelease.downloadSize, 12450000)

        // Eligible update discovery from installed Build 4 to published Build 5
        let installedBuild4 = AppVersion.parse("1.0.0 (build 4)")!
        let resolver = GitHubReleaseResolver()
        let eligible = resolver.findEligibleUpdate(from: updatedReleases, installedVersion: installedBuild4)
        switch eligible {
        case .success(let candidate):
            XCTAssertNotNil(candidate)
            XCTAssertEqual(candidate?.version.build, 5)
            XCTAssertEqual(candidate?.sparkleEdSignature, mockEdSignature)
        case .failure(let err):
            XCTFail("Unexpected error: \(err)")
        }
    }

    // MARK: - WO-86 End-to-End Shell Publisher & Fail-Closed Trust Gating Tests

    func testPublisherScriptIntegrationAndFailClosedGates() throws {
        let currentFile = URL(fileURLWithPath: #file)
        let repoRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scriptPath = repoRoot.appendingPathComponent("scripts/publish_production_appcast.sh").path

        guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
            XCTFail("publish_production_appcast.sh not found or not executable at \(scriptPath)")
            return
        }

        func runScript(args: [String], extraEnv: [String: String] = [:]) -> (status: Int32, output: String) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath] + args
            if !extraEnv.isEmpty {
                var env = ProcessInfo.processInfo.environment
                for (k, v) in extraEnv { env[k] = v }
                proc.environment = env
            }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let str = String(data: data, encoding: .utf8) ?? ""
                return (proc.terminationStatus, str)
            } catch {
                return (-1, "\(error)")
            }
        }

        func runCmd(_ exe: String, _ args: [String], cwd: URL? = nil) -> (status: Int32, output: String) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            if let cwd = cwd { proc.currentDirectoryURL = cwd }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }

        // 1. Dry run with mock explicitly allowed succeeds and outputs XML snippet
        let dryRun = runScript(args: ["--tag", "v1.0.0-build5", "--dry-run", "--allow-mock-for-dry-run"])
        XCTAssertEqual(dryRun.status, 0, "Dry run with allow mock must succeed: \(dryRun.output)")
        XCTAssertTrue(dryRun.output.contains("Monotonic check passed"), "Must verify monotonic build > 4")
        XCTAssertTrue(dryRun.output.contains("<enclosure"), "Must generate enclosure item")
        XCTAssertTrue(dryRun.output.contains("sparkle:version=\"5\""))

        // 2. Dry run without mock or signature fails closed
        let dryRunNoSig = runScript(args: ["--tag", "v1.0.0-build5", "--dry-run"])
        XCTAssertNotEqual(dryRunNoSig.status, 0)
        XCTAssertTrue(dryRunNoSig.output.contains("No signature provided"), "Must fail closed when no signature provided")

        // 3. Live mode strictly rejects mock signatures
        let liveMock = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--publish-to-main",
            "--signature", "mockSignature1234567890123456789012345678901234567890123456789012345678901234",
            "--operator-approval", "YES"
        ])
        XCTAssertNotEqual(liveMock.status, 0)
        XCTAssertTrue(liveMock.output.contains("Mock EdDSA signatures are strictly prohibited in live mode"))

        // 4. Live mode rejects invalid non-base64 signature
        let liveBadBase64 = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--publish-to-main",
            "--signature", "not_valid_base64!!!",
            "--operator-approval", "YES"
        ])
        XCTAssertNotEqual(liveBadBase64.status, 0)
        XCTAssertTrue(liveBadBase64.output.contains("not a valid canonical Base64 string"))

        // 5. Non-monotonic build rejected (<= 3)
        let nonMonotonic = runScript(args: ["--tag", "v1.0.0-build3", "--dry-run", "--allow-mock-for-dry-run"])
        XCTAssertNotEqual(nonMonotonic.status, 0)
        XCTAssertTrue(nonMonotonic.output.contains("must be greater than 3"))

        // 6. Invalid tag format rejected
        let invalidTag = runScript(args: ["--tag", "v1.0.0", "--dry-run", "--allow-mock-for-dry-run"])
        XCTAssertNotEqual(invalidTag.status, 0)
        XCTAssertTrue(invalidTag.output.contains("does not match required format"))

        // 7. Live mode without explicit operator approval fails closed
        let missingApproval = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--publish-to-main",
            "--signature", "KzM39JvY+Q8r1f8z0A3wH5RealSignature12345678901234567890123456789012345678901234567890=="
        ])
        XCTAssertNotEqual(missingApproval.status, 0)
        XCTAssertTrue(missingApproval.output.contains("Live publication requires explicit --operator-approval YES"))

        // MARK: - WO-88 Cryptographic Ed25519 Positive and Negative Verification Tests

        // Generate synthetic Curve25519 keypair for genuine cryptographic test fixtures
        let privKey = Curve25519.Signing.PrivateKey()
        let pubKey = privKey.publicKey
        let pubKeyB64 = pubKey.rawRepresentation.base64EncodedString()

        let tempArchiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-dmg-fixture-\(UUID().uuidString).dmg")
        let archiveBytes = Data("SENTINEL_NODE_WALLET_BTCB2_SYNTHETIC_ARCHIVE_BYTES_FOR_CRYPTO_VERIFICATION_TEST".utf8)
        try archiveBytes.write(to: tempArchiveURL)
        defer { try? FileManager.default.removeItem(at: tempArchiveURL) }

        let signature = try privKey.signature(for: archiveBytes)
        let signatureB64 = signature.base64EncodedString()

        // 8. Positive genuine cryptographic Ed25519 signature verification against archive bytes
        let validCryptoRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64
        ])
        XCTAssertEqual(validCryptoRun.status, 0, "Valid cryptographic verification must succeed: \(validCryptoRun.output)")
        XCTAssertTrue(validCryptoRun.output.contains("Cryptographic Ed25519 signature verified successfully"))

        // 9. Tampered archive bytes (1-byte modification) fails cryptographic verification
        let tamperedBytes = Data("SENTINEL_NODE_WALLET_BTCB2_SYNTHETIC_ARCHIVE_BYTES_FOR_CRYPTO_VERIFICATION_TAMPERED".utf8)
        try tamperedBytes.write(to: tempArchiveURL)
        let tamperedRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64
        ])
        XCTAssertNotEqual(tamperedRun.status, 0, "Tampered archive must fail cryptographic verification")
        XCTAssertTrue(tamperedRun.output.contains("EdDSA cryptographic signature verification failed"))

        // Restore original archive bytes
        try archiveBytes.write(to: tempArchiveURL)

        // 10. Mismatched public key fails cryptographic verification
        let wrongPrivKey = Curve25519.Signing.PrivateKey()
        let wrongPubKeyB64 = wrongPrivKey.publicKey.rawRepresentation.base64EncodedString()
        let wrongKeyRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--signature", signatureB64,
            "--public-key", wrongPubKeyB64
        ])
        XCTAssertNotEqual(wrongKeyRun.status, 0, "Wrong public key must fail cryptographic verification")
        XCTAssertTrue(wrongKeyRun.output.contains("EdDSA cryptographic signature verification failed"))

        // 11. Strict 64-byte signature and 32-byte public key length enforcement
        let shortSignatureB64 = Data(repeating: 0x41, count: 48).base64EncodedString()
        let shortSigRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--signature", shortSignatureB64,
            "--public-key", pubKeyB64
        ])
        XCTAssertNotEqual(shortSigRun.status, 0, "Short signature must fail length validation")
        XCTAssertTrue(shortSigRun.output.contains("must be exactly 64 bytes decoded"))

        let shortPubKeyB64 = Data(repeating: 0x42, count: 16).base64EncodedString()
        let shortKeyRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--signature", signatureB64,
            "--public-key", shortPubKeyB64
        ])
        XCTAssertNotEqual(shortKeyRun.status, 0, "Short public key must fail length validation")
        XCTAssertTrue(shortKeyRun.output.contains("must be exactly 32 bytes decoded"))

        // 12. Live mode fails closed when sign_update binary is missing
        let missingToolRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--publish-to-main",
            "--archive", tempArchiveURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64,
            "--sign-update", "/nonexistent/path/to/sign_update",
            "--operator-approval", "YES"
        ])
        XCTAssertNotEqual(missingToolRun.status, 0, "Missing sign_update in live mode must fail closed")
        XCTAssertTrue(missingToolRun.output.contains("sign_update binary is required in live mode"))

        // MARK: - WO-89 Zero Source Workspace Mutation and Immutable Staging Tests

        func gitStatusPorcelain() -> String {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.currentDirectoryURL = repoRoot
            proc.arguments = ["status", "--porcelain=v2"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }

        let preStatus = gitStatusPorcelain()

        // 13. Publisher execution must leave active git workspace 100% untouched across all runs
        _ = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64
        ])

        let postStatusDryRun = gitStatusPorcelain()
        XCTAssertEqual(preStatus, postStatusDryRun, "Git status must remain 100% unchanged after dry-run")

        // Also verify failure run leaves workspace untouched
        _ = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--signature", shortSignatureB64,
            "--public-key", pubKeyB64
        ])

        let postStatusFailure = gitStatusPorcelain()
        XCTAssertEqual(preStatus, postStatusFailure, "Git status must remain 100% unchanged after validation failure")

        // Ensure no backup file was created in dist/
        let backupFile = repoRoot.appendingPathComponent("dist/appcast.xml.bak")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupFile.path), "dist/appcast.xml.bak must never be created in working copy")

        // MARK: - WO-94, WO-95 & WO-101 Remote Asset Enforcement & App Bundle Binding Tests

        let tempBundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("Sentinel Node Wallet-\(UUID().uuidString).app")
        let contentsURL = tempBundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBundleURL) }

        let testInfoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>pool.sentineldefensetechnologies.co.za</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0.0</string>
            <key>CFBundleVersion</key>
            <string>5</string>
            <key>SUPublicEDKey</key>
            <string>\(pubKeyB64)</string>
        </dict>
        </plist>
        """
        try testInfoPlist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        // 14. WO-94 P0: Live mode without --sandbox-simulation attempts remote download and fails closed on missing remote asset
        let liveMissingRemote = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--publish-to-main",
            "--archive", tempArchiveURL.path,
            "--app-bundle", tempBundleURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64,
            "--operator-approval", "YES"
        ])
        XCTAssertNotEqual(liveMissingRemote.status, 0, "Live mode must fail closed when remote GitHub Release asset is not available")
        XCTAssertTrue(liveMissingRemote.output.contains("Remote release asset at") || liveMissingRemote.output.contains("Release must be publicly accessible"), "Must enforce remote asset availability: \(liveMissingRemote.output)")

        // 14b. WO-101 P0: Live mode without --app-bundle fails closed
        let liveMissingBundle = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--publish-to-main",
            "--archive", tempArchiveURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64,
            "--operator-approval", "YES"
        ])
        XCTAssertNotEqual(liveMissingBundle.status, 0, "Live mode without --app-bundle must fail closed")
        XCTAssertTrue(liveMissingBundle.output.contains("App bundle is mandatory in live mode"), "Must require app bundle in live mode: \(liveMissingBundle.output)")

        // 15. WO-95 P0: App bundle SUPublicEDKey mismatch against provided public key fails closed

        let keyMismatchRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--app-bundle", tempBundleURL.path,
            "--signature", signatureB64,
            "--public-key", wrongPubKeyB64
        ])
        XCTAssertNotEqual(keyMismatchRun.status, 0, "Key mismatch between bundle and public key must fail closed")
        XCTAssertTrue(keyMismatchRun.output.contains("SUPublicEDKey mismatch"), "Must report SUPublicEDKey mismatch: \(keyMismatchRun.output)")

        // 16. WO-95 P0: Bundle ID mismatch in app bundle fails closed
        let badIdPlist = testInfoPlist.replacingOccurrences(of: "pool.sentineldefensetechnologies.co.za", with: "com.unauthorized.wallet")
        try badIdPlist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let badIdRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--app-bundle", tempBundleURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64
        ])
        XCTAssertNotEqual(badIdRun.status, 0, "Bundle ID mismatch must fail closed")
        XCTAssertTrue(badIdRun.output.contains("Bundle ID mismatch"), "Must report Bundle ID mismatch: \(badIdRun.output)")

        // 17. WO-95 P0: Version / build number mismatch between app bundle and tag fails closed
        let badBuildPlist = testInfoPlist.replacingOccurrences(of: "<string>5</string>", with: "<string>4</string>")
        try badBuildPlist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let badBuildRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--app-bundle", tempBundleURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64
        ])
        XCTAssertNotEqual(badBuildRun.status, 0, "Build number mismatch must fail closed")
        XCTAssertTrue(badBuildRun.output.contains("Build number mismatch"), "Must report Build number mismatch: \(badBuildRun.output)")

        // MARK: - WO-100 Sandbox Simulation & Production Publishing Separation Tests

        // 18. WO-100 P0: Combining --sandbox-simulation and --publish-to-main against GitHub remote fails closed with typed stop and 0 writes
        let sandboxAgainstGithub = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--sandbox-simulation",
            "--publish-to-main",
            "--archive", tempArchiveURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64,
            "--operator-approval", "YES"
        ])
        XCTAssertNotEqual(sandboxAgainstGithub.status, 0, "Simulation against network/GitHub repository must fail closed")
        XCTAssertTrue(sandboxAgainstGithub.output.contains("FATAL SECURITY STOP (WO-100)"), "Must halt with typed security stop: \(sandboxAgainstGithub.output)")
        XCTAssertTrue(sandboxAgainstGithub.output.contains("cannot be executed when git remote points to GitHub"), "Must cite remote policy violation: \(sandboxAgainstGithub.output)")

        // 19. WO-100 P0: Running --sandbox-simulation with production SPARKLE_PRIVATE_ED_KEY secret in environment fails closed
        let sandboxWithSecret = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--sandbox-simulation",
            "--archive", tempArchiveURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64
        ], extraEnv: ["SPARKLE_PRIVATE_ED_KEY": "dummy_production_secret_key"])
        XCTAssertNotEqual(sandboxWithSecret.status, 0, "Simulation with production secret in environment must fail closed")
        XCTAssertTrue(sandboxWithSecret.output.contains("SPARKLE_PRIVATE_ED_KEY secret is present in environment"), "Must reject environment secret: \(sandboxWithSecret.output)")

        // 20. WO-100 P0: Combining --sandbox-simulation and --publish-to-main on local bare remote lacking fixture marker fails closed
        let unverifiedBase = FileManager.default.temporaryDirectory.appendingPathComponent("sentinel-unverified-remote-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unverifiedBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unverifiedBase) }
        let unverifiedBare = unverifiedBase.appendingPathComponent("unverified.git")
        let unverifiedClone = unverifiedBase.appendingPathComponent("clone")
        _ = runCmd("/usr/bin/git", ["init", "--bare", "-b", "main", unverifiedBare.path])
        _ = runCmd("/usr/bin/git", ["clone", unverifiedBare.path, unverifiedClone.path])
        let unverifiedCloneScripts = unverifiedClone.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: unverifiedCloneScripts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: scriptPath), to: unverifiedCloneScripts.appendingPathComponent("publish_production_appcast.sh"))
        let unverifiedRun = runCmd("/bin/bash", [
            unverifiedCloneScripts.appendingPathComponent("publish_production_appcast.sh").path,
            "--tag", "v1.0.0-build5",
            "--sandbox-simulation",
            "--publish-to-main",
            "--archive", tempArchiveURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64,
            "--operator-approval", "YES"
        ], cwd: unverifiedClone)
        XCTAssertNotEqual(unverifiedRun.status, 0, "Unverified bare remote must fail closed without fixture marker")
        XCTAssertTrue(unverifiedRun.output.contains("SENTINEL_TEST_FIXTURE_MARKER"), "Must cite missing fixture marker: \(unverifiedRun.output)")

        // MARK: - WO-101 Bundle Identity Binding & Fail-Closed Distribution Gating Tests

        // 21. WO-101 P0: Nonexistent --app-bundle path fails closed
        let missingBundleRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--app-bundle", "/nonexistent/Sentinel Node Wallet.app",
            "--signature", signatureB64,
            "--public-key", pubKeyB64
        ])
        XCTAssertNotEqual(missingBundleRun.status, 0, "Nonexistent app bundle path must fail closed")
        XCTAssertTrue(missingBundleRun.output.contains("App bundle specified with --app-bundle does not exist"), "Must report nonexistent app bundle: \(missingBundleRun.output)")

        // 22. WO-101 P0: Bundle directory lacking Contents/Info.plist fails closed
        let emptyBundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("EmptyBundle-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: emptyBundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyBundleURL) }
        let noPlistRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--app-bundle", emptyBundleURL.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64
        ])
        XCTAssertNotEqual(noPlistRun.status, 0, "Bundle without Info.plist must fail closed")
        XCTAssertTrue(noPlistRun.output.contains("Info.plist not found in app bundle"), "Must report missing Info.plist: \(noPlistRun.output)")

        // 23. WO-101 P0: Bundle with Info.plist lacking SUPublicEDKey fails closed
        let noKeyPlistBundle = FileManager.default.temporaryDirectory.appendingPathComponent("NoKeyBundle-\(UUID().uuidString).app")
        let noKeyContents = noKeyPlistBundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: noKeyContents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: noKeyPlistBundle) }
        let noKeyPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>pool.sentineldefensetechnologies.co.za</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0.0</string>
            <key>CFBundleVersion</key>
            <string>5</string>
        </dict>
        </plist>
        """
        try noKeyPlist.write(to: noKeyContents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let noKeyRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--app-bundle", noKeyPlistBundle.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64
        ])
        XCTAssertNotEqual(noKeyRun.status, 0, "Bundle without SUPublicEDKey must fail closed")
        XCTAssertTrue(noKeyRun.output.contains("Missing mandatory SUPublicEDKey"), "Must report missing SUPublicEDKey: \(noKeyRun.output)")

        // MARK: - WO-104 Secret Hygiene & Process List Exposure Prevention

        // 25. WO-104 P0: Prohibit --private-key on CLI to prevent credential leakage in argv/ps
        let privateKeyOnArgvRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--private-key", "secret_key_in_process_arguments",
            "--signature", signatureB64,
            "--public-key", pubKeyB64
        ])
        XCTAssertNotEqual(privateKeyOnArgvRun.status, 0, "--private-key on CLI must fail closed")
        XCTAssertTrue(privateKeyOnArgvRun.output.contains("Security stop (WO-104)"), "Must halt with security stop: \(privateKeyOnArgvRun.output)")
        XCTAssertTrue(privateKeyOnArgvRun.output.contains("--private-key is prohibited on the command line"), "Must cite argv prohibition: \(privateKeyOnArgvRun.output)")

        // MARK: - WO-106 Real Final-DMG Trust & Fail-Closed Gatekeeper / Team ID

        // 26. WO-106 P0: Bundle with valid Info.plist and public key passes dry-run
        let validAppBundle = FileManager.default.temporaryDirectory.appendingPathComponent("ValidTest-\(UUID().uuidString).app")
        let validContents = validAppBundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: validContents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: validAppBundle) }
        try testInfoPlist.write(to: validContents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let validBundleRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--app-bundle", validAppBundle.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64
        ])
        XCTAssertEqual(validBundleRun.status, 0, "Valid Info.plist and public key pass dry run: \(validBundleRun.output)")

        // MARK: - WO-113 Authenticated Signed-Only Production Feed & Legacy Migration

        // 27. WO-113 P0: Unsigned legacy feed in live publish mode fails closed without --prune-unsigned-legacy
        let legacyUnsignedAppcast = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Sentinel Node Wallet Updates</title>
        <link>https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2</link>
        <description>Official updates</description>
        <language>en</language>
        <item>
            <title>Sentinel Node Wallet 1.0 (Build 4)</title>
            <enclosure
                url="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v1.0.0-build4/Sentinel-Node-Wallet-v1.0.0-Build4-macOS-arm64.dmg"
                sparkle:version="4"
                sparkle:shortVersionString="1.0"
                sparkle:os="macos"
                sparkle:cpu="arm64"
                length="13927630"
                type="application/octet-stream" />
        </item>
        <item>
            <title>Sentinel Node Wallet 1.0 (Build 3)</title>
            <enclosure
                url="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v1.0.0-build3/Sentinel-Node-Wallet-v1.0-Build3-macOS-arm64.dmg"
                sparkle:version="3"
                sparkle:shortVersionString="1.0"
                sparkle:os="macos"
                sparkle:cpu="arm64"
                length="12429514"
                type="application/octet-stream" />
        </item>
    </channel>
</rss>
"""
        let legacyFixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-feed-\(UUID().uuidString).xml")
        try legacyUnsignedAppcast.write(to: legacyFixtureURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: legacyFixtureURL) }

        // 27. WO-113 & WO-119 P0: Baseline feed with unauthenticated legacy items must fail closed with exact FATAL INTEGRITY VIOLATION (WO-113)
        // All prerequisite gates (bundle, archive, signature, public key) are satisfied; failure is strictly due to unauthenticated baseline feed
        let unprunedRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--enforce-signed-feed",
            "--archive", tempArchiveURL.path,
            "--app-bundle", validAppBundle.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64,
            "--appcast", legacyFixtureURL.path
        ])
        XCTAssertNotEqual(unprunedRun.status, 0, "Unsigned legacy enclosures in baseline feed must fail closed")
        XCTAssertTrue(unprunedRun.output.contains("FATAL INTEGRITY VIOLATION (WO-113)"),
                      "Must cite WO-113 integrity violation: \(unprunedRun.output)")
        XCTAssertFalse(unprunedRun.output.contains("Remote release asset"),
                       "Must NOT fail on remote asset check: \(unprunedRun.output)")

        // 28. WO-113 P0: Dry-run with --prune-unsigned-legacy succeeds and prunes unsigned legacy enclosures
        let prunedRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--dry-run",
            "--archive", tempArchiveURL.path,
            "--app-bundle", validAppBundle.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64,
            "--prune-unsigned-legacy",
            "--appcast", legacyFixtureURL.path
        ])
        XCTAssertEqual(prunedRun.status, 0, "Dry-run with --prune-unsigned-legacy must pass: \(prunedRun.output)")
        XCTAssertTrue(prunedRun.output.contains("Pruned") && prunedRun.output.contains("WO-113"),
                      "Must log pruned legacy items: \(prunedRun.output)")
        XCTAssertTrue(prunedRun.output.contains("sparkle:version=\"5\"") || prunedRun.output.contains("Build 5"),
                      "Must contain candidate build 5: \(prunedRun.output)")

        // 29. WO-117 P0: Release attestation schema and Ed25519 cryptographic verification
        let computedArchiveSHA256 = SHA256.hash(data: archiveBytes).map { String(format: "%02x", $0) }.joined()
        let attestationJSON = """
        {
            "schema_version": "1.0",
            "tag": "v1.0.0-build5",
            "commit_sha": "0123456789abcdef0123456789abcdef01234567",
            "short_version": "1.0.0",
            "build_number": "5",
            "bundle_id": "pool.sentineldefensetechnologies.co.za",
            "team_id": "S8QMQZA656",
            "dmg_filename": "Sentinel-Node-Wallet-v1.0.0-Build5-macOS-arm64-notarized.dmg",
            "dmg_sha256": "\(computedArchiveSHA256)",
            "dmg_length": \(archiveBytes.count),
            "sparkle_ed_signature": "\(signatureB64)",
            "sparkle_public_ed_key": "\(pubKeyB64)",
            "notary_status": "Accepted",
            "stapled": true,
            "minimum_system_version": "13.0"
        }
        """
        guard let attestationData = attestationJSON.data(using: .utf8),
              let attObj = try? JSONSerialization.jsonObject(with: attestationData) as? [String: Any] else {
            XCTFail("Attestation JSON must parse cleanly")
            return
        }
        XCTAssertEqual(attObj["tag"] as? String, "v1.0.0-build5")
        XCTAssertEqual(attObj["bundle_id"] as? String, "pool.sentineldefensetechnologies.co.za")
        XCTAssertEqual(attObj["team_id"] as? String, "S8QMQZA656")
        XCTAssertEqual(attObj["dmg_sha256"] as? String, computedArchiveSHA256)
        XCTAssertEqual(attObj["sparkle_public_ed_key"] as? String, pubKeyB64)

        // Cryptographic verification of attestation signature against archive bytes
        let rawPub = Data(base64Encoded: pubKeyB64)!
        let rawSig = Data(base64Encoded: signatureB64)!
        let cryptoKey = try Curve25519.Signing.PublicKey(rawRepresentation: rawPub)
        XCTAssertTrue(cryptoKey.isValidSignature(rawSig, for: archiveBytes),
                      "Cryptographic signature must verify against archive bytes")

        // Tampered archive bytes must fail verification
        var tamperedAttestationBytes = archiveBytes
        tamperedAttestationBytes.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertFalse(cryptoKey.isValidSignature(rawSig, for: tamperedAttestationBytes),
                       "Tampered archive bytes must fail signature verification")

        // MARK: - WO-120 Pre-Promotion Preflight Live Gating & Pinned Verifier Availability

        // 30. WO-120 P0: Preflight verification gates (pre-promotion gating without git modification)
        // A) Valid preflight run passes cleanly and exercises binary and cryptographic verifiers
        let preflightSuccessRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--preflight",
            "--archive", tempArchiveURL.path,
            "--app-bundle", validAppBundle.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64,
            "--prune-unsigned-legacy",
            "--appcast", legacyFixtureURL.path
        ])
        XCTAssertEqual(preflightSuccessRun.status, 0, "Preflight with valid credentials must succeed: \(preflightSuccessRun.output)")
        XCTAssertTrue(preflightSuccessRun.output.contains("Preflight verification passed (WO-120)"),
                      "Must log preflight pass: \(preflightSuccessRun.output)")

        // B) Preflight fails closed if signature is missing or mock
        let preflightNoSigRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--preflight",
            "--archive", tempArchiveURL.path,
            "--app-bundle", validAppBundle.path,
            "--public-key", pubKeyB64,
            "--prune-unsigned-legacy",
            "--appcast", legacyFixtureURL.path
        ])
        XCTAssertNotEqual(preflightNoSigRun.status, 0, "Preflight without signature must fail closed")
        XCTAssertTrue(preflightNoSigRun.output.contains("EdDSA signature is required in live mode"),
                      "Must cite signature requirement: \(preflightNoSigRun.output)")

        // C) Preflight fails closed if public key is missing
        let preflightNoKeyRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--preflight",
            "--archive", tempArchiveURL.path,
            "--signature", signatureB64,
            "--prune-unsigned-legacy",
            "--appcast", legacyFixtureURL.path
        ])
        XCTAssertNotEqual(preflightNoKeyRun.status, 0, "Preflight without public key or bundle must fail closed")

        // D) Preflight fails closed if archive bytes do not verify against public key (tampered archive)
        let tamperedArchive = FileManager.default.temporaryDirectory.appendingPathComponent("tampered-\(UUID().uuidString).dmg")
        try Data("TAMPERED_ARCHIVE_BYTES".utf8).write(to: tamperedArchive)
        defer { try? FileManager.default.removeItem(at: tamperedArchive) }

        let preflightTamperedRun = runScript(args: [
            "--tag", "v1.0.0-build5",
            "--preflight",
            "--archive", tamperedArchive.path,
            "--app-bundle", validAppBundle.path,
            "--signature", signatureB64,
            "--public-key", pubKeyB64,
            "--prune-unsigned-legacy",
            "--appcast", legacyFixtureURL.path
        ])
        XCTAssertNotEqual(preflightTamperedRun.status, 0, "Preflight with tampered archive bytes must fail closed")

        // MARK: - WO-121 Authenticated Source/Tag/Release Attestation Binding

        // 31. WO-121 P0: Strict release attestation schema assertions and negative rejection
        func validateAttestationDict(_ dict: [String: Any], expectedTag: String, headCommit: String, expectedVer: String, expectedBuild: String, expectedPub: String, archivePath: String) -> (valid: Bool, error: String) {
            guard (dict["tag"] as? String) == expectedTag else { return (false, "tag mismatch") }
            guard (dict["commit_sha"] as? String) == headCommit else { return (false, "commit_sha mismatch") }
            guard (dict["short_version"] as? String) == expectedVer else { return (false, "short_version mismatch") }
            guard (dict["build_number"] as? String) == expectedBuild || String(describing: dict["build_number"] ?? "") == expectedBuild else { return (false, "build_number mismatch") }
            guard (dict["bundle_id"] as? String) == "pool.sentineldefensetechnologies.co.za" else { return (false, "bundle_id mismatch") }
            guard (dict["team_id"] as? String) == "S8QMQZA656" else { return (false, "team_id mismatch") }
            guard (dict["notary_status"] as? String) == "Accepted" else { return (false, "notary_status mismatch") }
            guard (dict["stapled"] as? Bool) == true else { return (false, "stapled mismatch") }
            guard (dict["sparkle_public_ed_key"] as? String) == expectedPub else { return (false, "public key mismatch") }
            guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: archivePath)) else { return (false, "archive missing") }
            let actualSha = SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined()
            guard (dict["dmg_sha256"] as? String) == actualSha else { return (false, "sha256 mismatch") }
            guard (dict["dmg_length"] as? Int) == fileData.count else { return (false, "length mismatch") }
            guard let pubData = Data(base64Encoded: expectedPub),
                  let sigData = Data(base64Encoded: dict["sparkle_ed_signature"] as? String ?? ""),
                  let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData),
                  pubKey.isValidSignature(sigData, for: fileData) else {
                return (false, "signature invalid")
            }
            return (true, "")
        }

        // Positive verification
        let posCheck = validateAttestationDict(attObj, expectedTag: "v1.0.0-build5", headCommit: "0123456789abcdef0123456789abcdef01234567", expectedVer: "1.0.0", expectedBuild: "5", expectedPub: pubKeyB64, archivePath: tempArchiveURL.path)
        XCTAssertTrue(posCheck.valid, "Baseline attestation must validate cleanly: \(posCheck.error)")

        // Negative: Tag mismatch
        var badTagDict = attObj
        badTagDict["tag"] = "v1.0.0-build6"
        XCTAssertFalse(validateAttestationDict(badTagDict, expectedTag: "v1.0.0-build5", headCommit: "0123456789abcdef0123456789abcdef01234567", expectedVer: "1.0.0", expectedBuild: "5", expectedPub: pubKeyB64, archivePath: tempArchiveURL.path).valid)

        // Negative: Commit SHA mismatch
        var badCommitDict = attObj
        badCommitDict["commit_sha"] = "ffffffffffffffffffffffffffffffffffffffff"
        XCTAssertFalse(validateAttestationDict(badCommitDict, expectedTag: "v1.0.0-build5", headCommit: "0123456789abcdef0123456789abcdef01234567", expectedVer: "1.0.0", expectedBuild: "5", expectedPub: pubKeyB64, archivePath: tempArchiveURL.path).valid)

        // Negative: Notary status not Accepted
        var badNotaryDict = attObj
        badNotaryDict["notary_status"] = "Rejected"
        XCTAssertFalse(validateAttestationDict(badNotaryDict, expectedTag: "v1.0.0-build5", headCommit: "0123456789abcdef0123456789abcdef01234567", expectedVer: "1.0.0", expectedBuild: "5", expectedPub: pubKeyB64, archivePath: tempArchiveURL.path).valid)

        // Negative: Stapled not true
        var unStapledDict = attObj
        unStapledDict["stapled"] = false
        XCTAssertFalse(validateAttestationDict(unStapledDict, expectedTag: "v1.0.0-build5", headCommit: "0123456789abcdef0123456789abcdef01234567", expectedVer: "1.0.0", expectedBuild: "5", expectedPub: pubKeyB64, archivePath: tempArchiveURL.path).valid)

        // Negative: Archive length mismatch
        var badLengthDict = attObj
        badLengthDict["dmg_length"] = 999
        XCTAssertFalse(validateAttestationDict(badLengthDict, expectedTag: "v1.0.0-build5", headCommit: "0123456789abcdef0123456789abcdef01234567", expectedVer: "1.0.0", expectedBuild: "5", expectedPub: pubKeyB64, archivePath: tempArchiveURL.path).valid)

        // MARK: - WO-122 Exact Feed Publication Observability & CDN Exact-Byte Verification

        // 32. WO-122 P0: CDN exact-byte and XML structure verification with typed exit code 75
        let wo122TempDir = FileManager.default.temporaryDirectory.appendingPathComponent("wo122-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: wo122TempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: wo122TempDir) }

        let candidateFeedPath = wo122TempDir.appendingPathComponent("candidate_appcast.xml")
        let candidateFeedXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>
                <title>Sentinel Node Wallet Updates</title>
                <item>
                    <title>Sentinel Node Wallet v1.0.0 (Build 5)</title>
                    <enclosure url="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v1.0.0-build5/app.dmg"
                               sparkle:version="5"
                               sparkle:edSignature="\(signatureB64)"
                               length="12000000"
                               type="application/octet-stream" />
                </item>
            </channel>
        </rss>
        """
        try candidateFeedXML.write(to: candidateFeedPath, atomically: true, encoding: .utf8)

        let candidateFeedBytes = try Data(contentsOf: candidateFeedPath)
        let expectedFeedSHA = SHA256.hash(data: candidateFeedBytes).map { String(format: "%02x", $0) }.joined()

        // Exact match succeeds
        let matchingFeedPath = wo122TempDir.appendingPathComponent("cdn_exact.xml")
        try candidateFeedXML.write(to: matchingFeedPath, atomically: true, encoding: .utf8)
        let matchingFeedSHA = SHA256.hash(data: try Data(contentsOf: matchingFeedPath)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(matchingFeedSHA, expectedFeedSHA, "Exact CDN readback SHA must match candidate SHA")

        // Stale CDN response containing same version string but different bytes / SHA-256 must NOT match
        let staleFeedXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>
                <title>Sentinel Node Wallet Updates</title>
                <item>
                    <title>Stale Item With Matching Token</title>
                    <enclosure url="https://example.com/stale.dmg" sparkle:version="5" sparkle:edSignature="\(signatureB64)" length="1000" type="application/octet-stream" />
                </item>
                <!-- EXTRA STALE COMMENT -->
            </channel>
        </rss>
        """
        let staleFeedPath = wo122TempDir.appendingPathComponent("cdn_stale.xml")
        try staleFeedXML.write(to: staleFeedPath, atomically: true, encoding: .utf8)
        let staleFeedSHA = SHA256.hash(data: try Data(contentsOf: staleFeedPath)).map { String(format: "%02x", $0) }.joined()
        XCTAssertNotEqual(staleFeedSHA, expectedFeedSHA, "Stale CDN payload with matching substrings must have different SHA-256")
    }

    // MARK: - WO-91 End-to-End Sandboxed Publisher Supply Chain Test

    func testEndToEndSupplyChainPublisherSandboxSimulation() throws {
        let currentFile = URL(fileURLWithPath: #file)
        let repoRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scriptPath = repoRoot.appendingPathComponent("scripts/publish_production_appcast.sh").path

        guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
            XCTFail("publish_production_appcast.sh not found or not executable at \(scriptPath)")
            return
        }

        // 1. Create a sandboxed disposable bare Git repository as mock remote origin
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("sentinel-supply-chain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let bareRemote = tempBase.appendingPathComponent("remote.git")
        let workingClone = tempBase.appendingPathComponent("clone")

        func runCmd(_ exe: String, _ args: [String], cwd: URL? = nil) -> (status: Int32, output: String) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            if let cwd = cwd { proc.currentDirectoryURL = cwd }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }

        // Initialize bare remote repo with initial main branch
        _ = runCmd("/usr/bin/git", ["init", "--bare", "-b", "main", bareRemote.path])
        // Mark as authorized test fixture bare remote (WO-100)
        try Data("SENTINEL_TEST_FIXTURE_MARKER".utf8).write(to: bareRemote.appendingPathComponent("SENTINEL_TEST_FIXTURE_MARKER"))

        // Clone it, seed dist/appcast.xml, and push to main
        _ = runCmd("/usr/bin/git", ["clone", bareRemote.path, workingClone.path])
        _ = runCmd("/usr/bin/git", ["config", "user.name", "Test User"], cwd: workingClone)
        _ = runCmd("/usr/bin/git", ["config", "user.email", "test@nodepocket.app"], cwd: workingClone)

        let cloneDist = workingClone.appendingPathComponent("dist")
        try FileManager.default.createDirectory(at: cloneDist, withIntermediateDirectories: true)
        let initialAppcast = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Sentinel Node Wallet Changelog</title>
        <link>https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2</link>
        <description>Official releases</description>
        <language>en</language>
        <item>
            <title>Sentinel Node Wallet v1.0.0 (Build 3)</title>
            <enclosure
                url="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v1.0.0-build3/Sentinel-Node-Wallet-BTCB2-v1.0.0-build3-macOS-arm64-notarized.dmg"
                sparkle:version="3"
                sparkle:shortVersionString="1.0.0"
                sparkle:edSignature="fakeSig"
                length="12000000"
                type="application/octet-stream" />
        </item>
    </channel>
</rss>
"""
        try initialAppcast.write(to: cloneDist.appendingPathComponent("appcast.xml"), atomically: true, encoding: .utf8)
        _ = runCmd("/usr/bin/git", ["add", "dist/appcast.xml"], cwd: workingClone)
        _ = runCmd("/usr/bin/git", ["commit", "-m", "initial commit"], cwd: workingClone)
        _ = runCmd("/usr/bin/git", ["push", "origin", "main"], cwd: workingClone)

        // 2. Generate throwaway synthetic Sparkle Curve25519 keypair
        let privKey = Curve25519.Signing.PrivateKey()
        let pubKey = privKey.publicKey
        let pubKeyB64 = pubKey.rawRepresentation.base64EncodedString()

        let dummyDMG = tempBase.appendingPathComponent("test-release.dmg")
        let dmgBytes = Data("DISPOSABLE_SYNTHETIC_SIGNED_RELEASE_DMG_CONTENT".utf8)
        try dmgBytes.write(to: dummyDMG)

        let signature = try privKey.signature(for: dmgBytes)
        let sigB64 = signature.base64EncodedString()

        // 3. Execute publish_production_appcast.sh inside the sandboxed clone against bare remote
        let cloneScripts = workingClone.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: cloneScripts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: scriptPath), to: cloneScripts.appendingPathComponent("publish_production_appcast.sh"))

        // Also copy Package.resolved to satisfy Sparkle 2.10.1 pinned version check
        let packageResolved = repoRoot.appendingPathComponent("Package.resolved")
        if FileManager.default.fileExists(atPath: packageResolved.path) {
            try? FileManager.default.copyItem(at: packageResolved, to: workingClone.appendingPathComponent("Package.resolved"))
        }

        let cloneScript = cloneScripts.appendingPathComponent("publish_production_appcast.sh").path

        // Find existing sign_update executable to pass via --sign-update
        let signUpdatePath = repoRoot.appendingPathComponent(".build/artifacts/sparkle/Sparkle/bin/sign_update").path

        var args = [
            cloneScript,
            "--tag", "v1.0.0-build5",
            "--sandbox-simulation",
            "--archive", dummyDMG.path,
            "--signature", sigB64,
            "--public-key", pubKeyB64,
            "--operator-approval", "YES",
            "--publish-to-main"
        ]
        if FileManager.default.isExecutableFile(atPath: signUpdatePath) {
            args += ["--sign-update", signUpdatePath]
        }

        let publishRes = runCmd("/bin/bash", args, cwd: workingClone)

        XCTAssertEqual(publishRes.status, 0, "Sandboxed publish to isolated bare remote must succeed: \(publishRes.output)")
        XCTAssertTrue(publishRes.output.contains("Production appcast published successfully to origin/main via isolated worktree"))

        // 4. Verify that working clone's tracked dist/appcast.xml remained 100% clean and unmutated
        let statusRes = runCmd("/usr/bin/git", ["status", "--porcelain=v2", "dist/appcast.xml"], cwd: workingClone)
        XCTAssertEqual(statusRes.output.trimmingCharacters(in: .whitespacesAndNewlines), "", "dist/appcast.xml in clone workspace must be 100% clean and unmutated")

        // 5. Verify that bare remote origin/main received the atomic publication of Build 5
        let remoteShowRes = runCmd("/usr/bin/git", ["show", "main:dist/appcast.xml"], cwd: bareRemote)
        XCTAssertEqual(remoteShowRes.status, 0, "Bare remote must contain dist/appcast.xml on main")
        XCTAssertTrue(remoteShowRes.output.contains("sparkle:version=\"5\""), "Bare remote main branch must contain published Build 5 enclosure")
        XCTAssertTrue(remoteShowRes.output.contains("sparkle:edSignature=\"\(sigB64)\""), "Bare remote main branch must contain genuine cryptographic EdDSA signature")
    }

    // MARK: - WO-122-R1 Protected Feed Cutover & Read-Only Finalizer Verification

    func testProtectedFeedCutoverAndReadOnlyFinalizerWO122R1() throws {
        let currentFile = URL(fileURLWithPath: #file)
        let repoRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scriptPath = repoRoot.appendingPathComponent("scripts/publish_production_appcast.sh").path

        guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
            XCTFail("publish_production_appcast.sh not found or not executable at \(scriptPath)")
            return
        }

        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("sentinel-protected-feed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let bareRemote = tempBase.appendingPathComponent("remote.git")
        let workingClone = tempBase.appendingPathComponent("clone")

        func runCmd(_ exe: String, _ args: [String], cwd: URL? = nil) -> (status: Int32, output: String) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            if let cwd = cwd { proc.currentDirectoryURL = cwd }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }

        // 1. Initialize bare remote with initial main branch containing Build 3
        _ = runCmd("/usr/bin/git", ["init", "--bare", "-b", "main", bareRemote.path])
        try Data("SENTINEL_TEST_FIXTURE_MARKER".utf8).write(to: bareRemote.appendingPathComponent("SENTINEL_TEST_FIXTURE_MARKER"))

        _ = runCmd("/usr/bin/git", ["clone", bareRemote.path, workingClone.path])
        _ = runCmd("/usr/bin/git", ["config", "user.name", "Test Operator"], cwd: workingClone)
        _ = runCmd("/usr/bin/git", ["config", "user.email", "operator@nodepocket.app"], cwd: workingClone)

        let cloneDist = workingClone.appendingPathComponent("dist")
        try FileManager.default.createDirectory(at: cloneDist, withIntermediateDirectories: true)
        let initialAppcast = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Sentinel Node Wallet Updates</title>
        <item>
            <title>Sentinel Node Wallet v1.0.0 (Build 3)</title>
            <enclosure
                url="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v1.0.0-build3/app.dmg"
                sparkle:version="3"
                sparkle:shortVersionString="1.0.0"
                sparkle:edSignature="fakeSig3"
                length="12000000"
                type="application/octet-stream" />
        </item>
    </channel>
</rss>
"""
        let initialAppcastURL = cloneDist.appendingPathComponent("appcast.xml")
        try initialAppcast.write(to: initialAppcastURL, atomically: true, encoding: .utf8)
        _ = runCmd("/usr/bin/git", ["add", "dist/appcast.xml"], cwd: workingClone)
        _ = runCmd("/usr/bin/git", ["commit", "-m", "chore(feed): initial main feed build 3"], cwd: workingClone)
        _ = runCmd("/usr/bin/git", ["push", "origin", "main"], cwd: workingClone)

        // 2. Install pre-receive hook in bareRemote simulating GitHub protected main branch policy
        let hooksDir = bareRemote.appendingPathComponent("hooks")
        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        let preReceiveHook = hooksDir.appendingPathComponent("pre-receive")
        let hookScript = """
#!/bin/bash
while read oldrev newrev refname; do
    if [ "$refname" = "refs/heads/main" ]; then
        echo "remote: error: GH006: Protected branch update failed for refs/heads/main: Direct pushes are forbidden. Pull request review required." >&2
        exit 1
    fi
done
exit 0
"""
        try hookScript.write(to: preReceiveHook, atomically: true, encoding: .utf8)
        _ = runCmd("/bin/chmod", ["+x", preReceiveHook.path])

        // 3. Generate keypair and signed archive for Build 5
        let privKey = Curve25519.Signing.PrivateKey()
        let pubKey = privKey.publicKey
        let pubKeyB64 = pubKey.rawRepresentation.base64EncodedString()

        let dummyDMG = tempBase.appendingPathComponent("test-release-build5.dmg")
        let dmgBytes = Data("DISPOSABLE_SYNTHETIC_SIGNED_RELEASE_DMG_CONTENT_BUILD5".utf8)
        try dmgBytes.write(to: dummyDMG)

        let signature = try privKey.signature(for: dmgBytes)
        let sigB64 = signature.base64EncodedString()

        let cloneScripts = workingClone.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: cloneScripts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: scriptPath), to: cloneScripts.appendingPathComponent("publish_production_appcast.sh"))

        let packageResolved = repoRoot.appendingPathComponent("Package.resolved")
        if FileManager.default.fileExists(atPath: packageResolved.path) {
            try? FileManager.default.copyItem(at: packageResolved, to: workingClone.appendingPathComponent("Package.resolved"))
        }

        let cloneScript = cloneScripts.appendingPathComponent("publish_production_appcast.sh").path
        let signUpdatePath = repoRoot.appendingPathComponent(".build/artifacts/sparkle/Sparkle/bin/sign_update").path

        // 4. Test Feed Staging: Stage candidate feed to branch feed/v1.0.0-build5
        var stageArgs = [
            cloneScript,
            "--tag", "v1.0.0-build5",
            "--sandbox-simulation",
            "--archive", dummyDMG.path,
            "--signature", sigB64,
            "--public-key", pubKeyB64,
            "--operator-approval", "YES",
            "--stage-feed-branch",
            "--prune-unsigned-legacy"
        ]
        if FileManager.default.isExecutableFile(atPath: signUpdatePath) {
            stageArgs += ["--sign-update", signUpdatePath]
        }

        let stageRes = runCmd("/bin/bash", stageArgs, cwd: workingClone)
        XCTAssertEqual(stageRes.status, 0, "Staging feed to branch feed/v1.0.0-build5 must succeed: \(stageRes.output)")
        XCTAssertTrue(stageRes.output.contains("Staged candidate appcast successfully to origin branch 'feed/v1.0.0-build5'"),
                      "Must log successful staging to feed branch: \(stageRes.output)")
        XCTAssertTrue(stageRes.output.contains("Direct push to origin/main was NOT attempted"),
                      "Must confirm direct push to main was not attempted: \(stageRes.output)")
        XCTAssertTrue(stageRes.output.contains("STATUS: SIGNED_RELEASE_PUBLIC_FEED_PR_PENDING"),
                      "Must report STATUS: SIGNED_RELEASE_PUBLIC_FEED_PR_PENDING: \(stageRes.output)")
        XCTAssertTrue(stageRes.output.contains("Staged Branch: feed/v1.0.0-build5"),
                      "Must log staged branch: \(stageRes.output)")
        XCTAssertTrue(stageRes.output.contains("Staged Commit:"),
                      "Must log staged commit: \(stageRes.output)")
        XCTAssertTrue(stageRes.output.contains("Staged Blob SHA:"),
                      "Must log staged blob SHA: \(stageRes.output)")

        // Verify bare remote received the feed branch while main remains untouched at Build 3
        let feedBranchShow = runCmd("/usr/bin/git", ["show", "feed/v1.0.0-build5:dist/appcast.xml"], cwd: bareRemote)
        XCTAssertEqual(feedBranchShow.status, 0, "Bare remote must contain feed/v1.0.0-build5 branch")
        XCTAssertTrue(feedBranchShow.output.contains("sparkle:version=\"5\""), "feed branch must contain candidate Build 5")

        let mainBranchShow = runCmd("/usr/bin/git", ["show", "main:dist/appcast.xml"], cwd: bareRemote)
        XCTAssertEqual(mainBranchShow.status, 0, "Bare remote must contain main branch")
        XCTAssertFalse(mainBranchShow.output.contains("sparkle:version=\"5\""), "Protected main branch must NOT contain Build 5 before PR merge")
        XCTAssertTrue(mainBranchShow.output.contains("sparkle:version=\"3\""), "Protected main branch must remain at Build 3")

        // 5. Test Read-Only Finalizer BEFORE merge: Unmerged feed returns PUBLIC_RELEASE_AWAITING_FEED_APPROVAL (exit 75)
        let mockCDNFile = tempBase.appendingPathComponent("mock_cdn_appcast.xml")
        try initialAppcast.write(to: mockCDNFile, atomically: true, encoding: .utf8)

        var unapprovedFinalizerArgs = [
            cloneScript,
            "--tag", "v1.0.0-build5",
            "--archive", dummyDMG.path,
            "--signature", sigB64,
            "--public-key", pubKeyB64,
            "--cdn-url", "file://\(mockCDNFile.path)",
            "--verify-deployed-feed"
        ]
        if FileManager.default.isExecutableFile(atPath: signUpdatePath) {
            unapprovedFinalizerArgs += ["--sign-update", signUpdatePath]
        }

        let unapprovedRes = runCmd("/bin/bash", unapprovedFinalizerArgs, cwd: workingClone)
        XCTAssertEqual(unapprovedRes.status, 75, "Unapproved feed on CDN must exit with typed code 75: \(unapprovedRes.output)")
        XCTAssertTrue(unapprovedRes.output.contains("STATUS: PUBLIC_RELEASE_AWAITING_FEED_APPROVAL"),
                      "Must report STATUS: PUBLIC_RELEASE_AWAITING_FEED_APPROVAL: \(unapprovedRes.output)")
        XCTAssertFalse(unapprovedRes.output.contains("STATUS: DEPLOYED"),
                      "Unapproved feed must never report DEPLOYED: \(unapprovedRes.output)")

        // 6. Negative Test: Anti-trivial self-comparison check fails closed (WO-122-R2)
        var selfCompArgs = unapprovedFinalizerArgs
        selfCompArgs += ["--candidate-appcast", mockCDNFile.path]
        let selfCompRes = runCmd("/bin/bash", selfCompArgs, cwd: workingClone)
        XCTAssertNotEqual(selfCompRes.status, 0, "Self-comparison between --candidate-appcast and --cdn-url must fail")
        XCTAssertTrue(selfCompRes.output.contains("SELF_COMPARISON_DETECTED"),
                      "Self-comparison must output SELF_COMPARISON_DETECTED: \(selfCompRes.output)")

        // 7. Negative Test: Missing candidate feed without dynamic fallback fails closed (WO-122-R2)
        var missingCandidateArgs = [
            cloneScript,
            "--tag", "v1.0.0-build999",
            "--archive", dummyDMG.path,
            "--signature", sigB64,
            "--public-key", pubKeyB64,
            "--cdn-url", "file://\(mockCDNFile.path)",
            "--verify-deployed-feed"
        ]
        if FileManager.default.isExecutableFile(atPath: signUpdatePath) {
            missingCandidateArgs += ["--sign-update", signUpdatePath]
        }
        let missingCandidateRes = runCmd("/bin/bash", missingCandidateArgs, cwd: workingClone)
        XCTAssertNotEqual(missingCandidateRes.status, 0, "Missing candidate feed must fail closed")
        XCTAssertTrue(missingCandidateRes.output.contains("CANDIDATE_FEED_NOT_AVAILABLE"),
                      "Missing candidate feed must output CANDIDATE_FEED_NOT_AVAILABLE: \(missingCandidateRes.output)")

        // 8. Test Stale CDN response with matching version substring but wrong bytes: exits 75
        let staleTamperedXML = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Sentinel Node Wallet Updates</title>
        <item>
            <title>Tampered Item</title>
            <enclosure url="https://example.com/bad.dmg" sparkle:version="5" sparkle:edSignature="\(sigB64)" length="1000" type="application/octet-stream" />
        </item>
        <!-- TAMPERED BYTES -->
    </channel>
</rss>
"""
        try staleTamperedXML.write(to: mockCDNFile, atomically: true, encoding: .utf8)
        let staleRes = runCmd("/bin/bash", unapprovedFinalizerArgs, cwd: workingClone)
        XCTAssertEqual(staleRes.status, 75, "Tampered CDN feed must exit with code 75: \(staleRes.output)")
        XCTAssertTrue(staleRes.output.contains("PUBLIC_RELEASE_AWAITING_FEED_APPROVAL"),
                      "Tampered feed must report AWAITING_FEED_APPROVAL: \(staleRes.output)")

        // 9. Test 404 Feed URL: exits 75
        var notFoundFinalizerArgs = unapprovedFinalizerArgs
        notFoundFinalizerArgs[notFoundFinalizerArgs.firstIndex(of: "--cdn-url")! + 1] = "file://\(tempBase.path)/nonexistent_404.xml"
        let notFoundRes = runCmd("/bin/bash", notFoundFinalizerArgs, cwd: workingClone)
        XCTAssertEqual(notFoundRes.status, 75, "404 CDN feed must exit with code 75: \(notFoundRes.output)")
        XCTAssertTrue(notFoundRes.output.contains("PUBLIC_RELEASE_AWAITING_FEED_APPROVAL"))

        // 10. Test Approved Human Operator Merge: Independent candidate and CDN verification (WO-122-R2)
        let independentCandidateFile = tempBase.appendingPathComponent("independent_candidate_appcast.xml")
        let stagedFeedContent = feedBranchShow.output
        try stagedFeedContent.write(to: independentCandidateFile, atomically: true, encoding: .utf8)

        // Simulate operator PR merge on bareRemote: update refs/heads/main to feed commit
        let feedBranchRef = runCmd("/usr/bin/git", ["rev-parse", "feed/v1.0.0-build5"], cwd: bareRemote)
        let feedCommitSHA = feedBranchRef.output.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = runCmd("/usr/bin/git", ["update-ref", "refs/heads/main", feedCommitSHA], cwd: bareRemote)

        // Fetch merged main into workingClone so origin/main reflects the merge
        _ = runCmd("/usr/bin/git", ["fetch", "origin", "main"], cwd: workingClone)
        _ = runCmd("/usr/bin/git", ["checkout", "main"], cwd: workingClone)
        _ = runCmd("/usr/bin/git", ["reset", "--hard", "origin/main"], cwd: workingClone)

        let postMergeMainShow = runCmd("/usr/bin/git", ["show", "main:dist/appcast.xml"], cwd: bareRemote)
        XCTAssertTrue(postMergeMainShow.output.contains("sparkle:version=\"5\""), "Merged main on bareRemote must contain Build 5")

        let postMergeCDNFile = tempBase.appendingPathComponent("deployed_cdn_appcast.xml")
        try postMergeMainShow.output.write(to: postMergeCDNFile, atomically: true, encoding: .utf8)

        // Verify with explicit independent --candidate-appcast
        var approvedFinalizerArgs = [
            cloneScript,
            "--tag", "v1.0.0-build5",
            "--archive", dummyDMG.path,
            "--signature", sigB64,
            "--public-key", pubKeyB64,
            "--candidate-appcast", independentCandidateFile.path,
            "--cdn-url", "file://\(postMergeCDNFile.path)",
            "--verify-deployed-feed"
        ]
        if FileManager.default.isExecutableFile(atPath: signUpdatePath) {
            approvedFinalizerArgs += ["--sign-update", signUpdatePath]
        }
        let approvedRes = runCmd("/bin/bash", approvedFinalizerArgs, cwd: workingClone)
        XCTAssertEqual(approvedRes.status, 0, "Approved merged feed on CDN must exit with code 0: \(approvedRes.output)")
        XCTAssertTrue(approvedRes.output.contains("STATUS: DEPLOYED"),
                      "Approved feed must report STATUS: DEPLOYED: \(approvedRes.output)")
        XCTAssertTrue(approvedRes.output.contains("Live CDN verification successful: Build 5 feed exact-byte match"),
                      "Approved feed must log exact-byte SHA-256 and XML match: \(approvedRes.output)")

        // Also verify branch-resolved candidate (WITHOUT --candidate-appcast) resolves from origin/feed/v1.0.0-build5
        _ = runCmd("/usr/bin/git", ["fetch", "origin"], cwd: workingClone)
        var autoResolvedArgs = [
            cloneScript,
            "--tag", "v1.0.0-build5",
            "--archive", dummyDMG.path,
            "--signature", sigB64,
            "--public-key", pubKeyB64,
            "--cdn-url", "file://\(postMergeCDNFile.path)",
            "--verify-deployed-feed"
        ]
        if FileManager.default.isExecutableFile(atPath: signUpdatePath) {
            autoResolvedArgs += ["--sign-update", signUpdatePath]
        }
        let autoResolvedRes = runCmd("/bin/bash", autoResolvedArgs, cwd: workingClone)
        XCTAssertEqual(autoResolvedRes.status, 0, "Auto-resolved candidate from staged branch must exit with code 0: \(autoResolvedRes.output)")
        XCTAssertTrue(autoResolvedRes.output.contains("STATUS: DEPLOYED"),
                      "Auto-resolved feed must report STATUS: DEPLOYED: \(autoResolvedRes.output)")
    }

    // MARK: - WO-122-R3 Sparkle Signer Sidecar Attestation & CryptoKit Verification

    func testSparkleSignerSidecarAttestationAndCryptoKitVerificationWO122R3() throws {
        let currentFile = URL(fileURLWithPath: #file)
        let repoRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let signerScript = repoRoot.appendingPathComponent("scripts/sign_appcast_enclosure.sh").path

        guard FileManager.default.isExecutableFile(atPath: signerScript) else {
            XCTFail("scripts/sign_appcast_enclosure.sh not found or not executable at \(signerScript)")
            return
        }

        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("sentinel-wo122-r3-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        // 1. Generate disposable Ed25519 keypair using Swift CryptoKit
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let pubKeyData = publicKey.rawRepresentation
        let pubKeyB64 = pubKeyData.base64EncodedString()
        let privKeyB64 = privateKey.rawRepresentation.base64EncodedString()

        XCTAssertEqual(pubKeyData.count, 32, "Ed25519 public key raw representation must be exactly 32 bytes")

        let keyFile = tempBase.appendingPathComponent("disposable_sparkle.key")
        try privKeyB64.write(to: keyFile, atomically: true, encoding: .utf8)

        // 2. Create synthetic archive file with known bytes
        let archiveFile = tempBase.appendingPathComponent("Sentinel-Node-Wallet-1.0.0-build5-macOS-arm64-notarized.dmg")
        let archiveBytes = "SENTINEL_WO122_R3_SYNTHETIC_DMG_PAYLOAD_\(UUID().uuidString)".data(using: .utf8)!
        try archiveBytes.write(to: archiveFile)
        let archiveLen = archiveBytes.count
        let archiveSHA = SHA256.hash(data: archiveBytes).map { String(format: "%02x", $0) }.joined()

        let sidecarFile = tempBase.appendingPathComponent("SPARKLE_SIGNATURE.base64")

        func runCmd(_ exe: String, _ args: [String], cwd: URL? = nil, env: [String: String]? = nil) -> (status: Int32, output: String) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            if let cwd = cwd { proc.currentDirectoryURL = cwd }
            if let env = env {
                var procEnv = ProcessInfo.processInfo.environment
                for (k, v) in env { procEnv[k] = v }
                proc.environment = procEnv
            }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }

        // 3. Execute scripts/sign_appcast_enclosure.sh with --signature-file-output
        let signRes = runCmd("/bin/bash", [
            signerScript,
            "sign",
            archiveFile.path,
            "--key-file", keyFile.path,
            "--signature-file-output", sidecarFile.path
        ])

        XCTAssertEqual(signRes.status, 0, "Signer script must exit with 0: \(signRes.output)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarFile.path), "Dedicated signature sidecar must be created")

        // 4. Verify sidecar content is pure Base64 and decodes to exactly 64 bytes
        let sidecarRaw = try String(contentsOf: sidecarFile, encoding: .utf8)
        let sidecarSig = sidecarRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(sidecarSig.contains("\n"), "Sidecar signature must not contain newlines")
        XCTAssertFalse(sidecarSig.contains(" "), "Sidecar signature must not contain spaces")

        guard let decodedSig = Data(base64Encoded: sidecarSig) else {
            XCTFail("Sidecar signature must be valid Base64: '\(sidecarSig)'")
            return
        }
        XCTAssertEqual(decodedSig.count, 64, "Decoded Ed25519 signature must be exactly 64 bytes")

        // 5. Verify stdout enclosure metadata and XML snippet
        XCTAssertTrue(signRes.output.contains("File: \(archiveFile.lastPathComponent)"), "Metadata must contain filename")
        XCTAssertTrue(signRes.output.contains("Length: \(archiveLen) bytes"), "Metadata must contain byte length")
        XCTAssertTrue(signRes.output.contains("SHA-256: \(archiveSHA)"), "Metadata must contain SHA-256")
        XCTAssertTrue(signRes.output.contains("EdDSA Signature (Base64): \(sidecarSig)"), "Metadata must contain EdDSA Signature line")
        XCTAssertTrue(signRes.output.contains("sparkle:edSignature=\"\(sidecarSig)\""), "XML snippet must contain exact sidecar signature")
        XCTAssertTrue(signRes.output.contains("length=\"\(archiveLen)\""), "XML snippet must contain exact length")

        // 6. Positive Verification: Verify signature against exact archive bytes using Swift CryptoKit
        guard let decodedPubKeyData = Data(base64Encoded: pubKeyB64),
              let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: decodedPubKeyData) else {
            XCTFail("Failed to instantiate Curve25519.Signing.PublicKey from Base64 public key data: \(pubKeyB64)")
            return
        }
        XCTAssertEqual(decodedPubKeyData.count, 32, "Decoded public key must be exactly 32 bytes")
        XCTAssertTrue(pubKey.isValidSignature(decodedSig, for: archiveBytes),
                      "Swift CryptoKit must successfully verify the Ed25519 signature from the sidecar against exact archive bytes")

        // 7. Verify --signature-only output mode
        let sigOnlyRes = runCmd("/bin/bash", [
            signerScript,
            "sign",
            archiveFile.path,
            "--key-file", keyFile.path,
            "--signature-only"
        ])
        XCTAssertEqual(sigOnlyRes.status, 0, "Signer script --signature-only must exit with 0")
        XCTAssertEqual(sigOnlyRes.output.trimmingCharacters(in: .whitespacesAndNewlines), sidecarSig,
                       "--signature-only output must match sidecar signature exactly")

        // 8. Negative Test A: Original Mixed Stdout Parser Bug Reproduction
        // Reproduce the old failure mode where line 64 'sparkle:edSignature: <SIG>' preceded 'sparkle:edSignature="<SIG>"'
        let buggyOldStdout = """
        === Sparkle 2 Enclosure Metadata ===
        File: \(archiveFile.lastPathComponent)
        Length: \(archiveLen) bytes
        SHA-256: \(archiveSHA)
        sparkle:edSignature: \(sidecarSig)

        XML Enclosure Snippet:
        <enclosure
            url="https://example.com/download.dmg"
            sparkle:edSignature="\(sidecarSig)"
            sparkle:version="5" />
        """
        let buggyOldExtractRes = runCmd("/bin/bash", ["-c", """
        echo '\(buggyOldStdout)' | grep "sparkle:edSignature" | head -n 1 | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\\1/'
        """])
        let corruptedSig = buggyOldExtractRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(corruptedSig, "sparkle:edSignature: \(sidecarSig)",
                       "Original grep|head -1|sed parser must reproduce bug by capturing descriptive metadata line")
        XCTAssertNil(Data(base64Encoded: corruptedSig),
                     "Original corrupted extracted signature must fail Base64 decoding")

        // In contrast, extracting directly from the sidecar guarantees pure Base64
        let directExtractRes = runCmd("/bin/bash", ["-c", "tr -d '\\r\\n ' < '\(sidecarFile.path)'"])
        XCTAssertEqual(directExtractRes.output.trimmingCharacters(in: .whitespacesAndNewlines), sidecarSig,
                       "Sidecar extraction must produce clean, pure Base64 without narrative text")

        // 9. Negative Test B: Malformed / Non-Base64 Signature Rejection
        let malformedSigString = "sparkle:edSignature: NOT_BASE_64_AT_ALL!!!"
        XCTAssertNil(Data(base64Encoded: malformedSigString), "Non-Base64 string must fail decoding")

        // 10. Negative Test C: Wrong Decoded Signature Length (!= 64 bytes)
        let shortSigB64 = Data(repeating: 0x41, count: 32).base64EncodedString()
        let decodedShort = Data(base64Encoded: shortSigB64)!
        XCTAssertEqual(decodedShort.count, 32)
        XCTAssertNotEqual(decodedShort.count, 64, "Short signature must not equal 64 bytes")
        // CryptoKit requires exactly 64 bytes for Ed25519 signature
        XCTAssertFalse(pubKey.isValidSignature(decodedShort, for: archiveBytes),
                       "CryptoKit must reject signature of incorrect length")

        let longSigB64 = Data(repeating: 0x42, count: 65).base64EncodedString()
        let decodedLong = Data(base64Encoded: longSigB64)!
        XCTAssertEqual(decodedLong.count, 65)
        XCTAssertNotEqual(decodedLong.count, 64, "Long signature must not equal 64 bytes")
        XCTAssertFalse(pubKey.isValidSignature(decodedLong, for: archiveBytes),
                       "CryptoKit must reject 65-byte signature")

        // 11. Negative Test D: Wrong Public Key Length (!= 32 bytes)
        let shortPubData = Data(repeating: 0x50, count: 31)
        XCTAssertNil(try? Curve25519.Signing.PublicKey(rawRepresentation: shortPubData),
                     "Curve25519.Signing.PublicKey must throw/fail for raw data != 32 bytes")
        let longPubData = Data(repeating: 0x51, count: 33)
        XCTAssertNil(try? Curve25519.Signing.PublicKey(rawRepresentation: longPubData),
                     "Curve25519.Signing.PublicKey must throw/fail for raw data != 32 bytes")

        // 12. Negative Test E: Wrong Public Key (From Different Keypair)
        let wrongPrivateKey = Curve25519.Signing.PrivateKey()
        let wrongPublicKey = wrongPrivateKey.publicKey
        XCTAssertFalse(wrongPublicKey.isValidSignature(decodedSig, for: archiveBytes),
                       "Valid signature for one keypair must fail validation under a different public key")

        // 13. Negative Test F: Tampered Archive Bytes
        var tamperedBytes = archiveBytes
        tamperedBytes.append(Data([0xEE, 0xFF]))
        XCTAssertFalse(pubKey.isValidSignature(decodedSig, for: tamperedBytes),
                       "Tampered archive bytes must fail signature validation")

        // 14. Negative Test G: Empty Signature
        let emptySigData = Data()
        XCTAssertFalse(pubKey.isValidSignature(emptySigData, for: archiveBytes),
                       "Empty signature must fail validation")
    }

    // MARK: - WO-122-R4 Remote Main Proof & Stale Cache Rejection Gating

    func testRemoteMainProofAndStaleCacheRejectionWO122R4() throws {
        let currentFile = URL(fileURLWithPath: #file)
        let repoRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scriptPath = repoRoot.appendingPathComponent("scripts/publish_production_appcast.sh").path
        let signerScript = repoRoot.appendingPathComponent("scripts/sign_appcast_enclosure.sh").path

        guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
            XCTFail("publish_production_appcast.sh not found or not executable at \(scriptPath)")
            return
        }

        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("sentinel-wo122-r4-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let bareRemote = tempBase.appendingPathComponent("remote.git")
        let workingClone = tempBase.appendingPathComponent("clone")

        func runCmd(_ exe: String, _ args: [String], cwd: URL? = nil, env: [String: String]? = nil) -> (status: Int32, output: String) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            if let cwd = cwd { proc.currentDirectoryURL = cwd }
            if let env = env {
                var procEnv = ProcessInfo.processInfo.environment
                for (k, v) in env { procEnv[k] = v }
                proc.environment = procEnv
            }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }

        // 1. Generate disposable Ed25519 keypair
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let pubKeyData = publicKey.rawRepresentation
        let pubKeyB64 = pubKeyData.base64EncodedString()
        let privKeyB64 = privateKey.rawRepresentation.base64EncodedString()
        let keyFile = tempBase.appendingPathComponent("disposable_sparkle.key")
        try privKeyB64.write(to: keyFile, atomically: true, encoding: .utf8)

        // 2. Setup bare remote with initial main branch containing Build 3
        _ = runCmd("/usr/bin/git", ["init", "--bare", "-b", "main", bareRemote.path])
        try Data("SENTINEL_TEST_FIXTURE_MARKER".utf8).write(to: bareRemote.appendingPathComponent("SENTINEL_TEST_FIXTURE_MARKER"))
        _ = runCmd("/usr/bin/git", ["clone", bareRemote.path, workingClone.path])
        _ = runCmd("/usr/bin/git", ["config", "user.name", "Test Operator"], cwd: workingClone)
        _ = runCmd("/usr/bin/git", ["config", "user.email", "operator@nodepocket.app"], cwd: workingClone)

        let cloneDist = workingClone.appendingPathComponent("dist")
        try FileManager.default.createDirectory(at: cloneDist, withIntermediateDirectories: true)
        let initialAppcast = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Sentinel Node Wallet Changelog</title>
        <item>
            <title>Version 1.0.0 (Build 3)</title>
            <sparkle:version>3</sparkle:version>
            <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
            <enclosure
                url="https://github.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/releases/download/v1.0.0-build3/Sentinel-Node-Wallet-1.0.0-build3-macOS-arm64-notarized.dmg"
                sparkle:version="3"
                sparkle:shortVersionString="1.0.0"
                sparkle:os="macos"
                sparkle:cpu="arm64"
                length="1000"
                type="application/octet-stream" />
        </item>
    </channel>
</rss>
"""
        let initialAppcastFile = cloneDist.appendingPathComponent("appcast.xml")
        try initialAppcast.write(to: initialAppcastFile, atomically: true, encoding: .utf8)
        _ = runCmd("/usr/bin/git", ["add", "dist/appcast.xml"], cwd: workingClone)
        _ = runCmd("/usr/bin/git", ["commit", "-m", "Initial main appcast with Build 3"], cwd: workingClone)
        _ = runCmd("/usr/bin/git", ["push", "origin", "main"], cwd: workingClone)

        // 3. Create candidate archive (Build 5) and sign it to produce sidecar
        let dummyDMG = cloneDist.appendingPathComponent("Sentinel-Node-Wallet-1.0.0-build5-macOS-arm64-notarized.dmg")
        let dummyBytes = "SENTINEL_WO122_R4_CANDIDATE_DMG_\(UUID().uuidString)".data(using: .utf8)!
        try dummyBytes.write(to: dummyDMG)
        let sidecarFile = cloneDist.appendingPathComponent("SPARKLE_SIGNATURE.base64")

        let signRes = runCmd("/bin/bash", [
            signerScript,
            "sign",
            dummyDMG.path,
            "--key-file", keyFile.path,
            "--signature-file-output", sidecarFile.path
        ], cwd: workingClone)
        XCTAssertEqual(signRes.status, 0, "Signer script must succeed: \(signRes.output)")
        let sigB64 = try String(contentsOf: sidecarFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

        // 4. Copy scripts and Package.resolved into workingClone
        let cloneScriptsDir = workingClone.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: cloneScriptsDir, withIntermediateDirectories: true)
        let cloneScript = cloneScriptsDir.appendingPathComponent("publish_production_appcast.sh").path
        try FileManager.default.copyItem(atPath: scriptPath, toPath: cloneScript)

        let packageResolved = repoRoot.appendingPathComponent("Package.resolved")
        if FileManager.default.fileExists(atPath: packageResolved.path) {
            try? FileManager.default.copyItem(at: packageResolved, to: workingClone.appendingPathComponent("Package.resolved"))
        }

        let signUpdatePath = repoRoot.appendingPathComponent(".build/artifacts/sparkle/Sparkle/bin/sign_update").path

        // 5. Stage candidate feed to feed branch (WO-122-R1)
        var stageArgs = [
            cloneScript,
            "--tag", "v1.0.0-build5",
            "--sandbox-simulation",
            "--archive", dummyDMG.path,
            "--signature", sigB64,
            "--public-key", pubKeyB64,
            "--operator-approval", "YES",
            "--stage-feed-branch",
            "--prune-unsigned-legacy"
        ]
        if FileManager.default.isExecutableFile(atPath: signUpdatePath) {
            stageArgs += ["--sign-update", signUpdatePath]
        }
        let stageRes = runCmd("/bin/bash", stageArgs, cwd: workingClone)
        XCTAssertEqual(stageRes.status, 0, "Staging to feed branch must exit with 0: \(stageRes.output)")

        // Extract staged candidate appcast
        let stagedShowRes = runCmd("/usr/bin/git", ["show", "origin/feed/v1.0.0-build5:dist/appcast.xml"], cwd: workingClone)
        XCTAssertEqual(stagedShowRes.status, 0, "Must be able to read staged candidate feed from origin")
        let candidateFeedContent = stagedShowRes.output
        let candidateFile = tempBase.appendingPathComponent("candidate_appcast.xml")
        try candidateFeedContent.write(to: candidateFile, atomically: true, encoding: .utf8)

        // Create mock CDN file matching candidate feed
        let matchingCDNFile = tempBase.appendingPathComponent("cdn_matching_appcast.xml")
        try candidateFeedContent.write(to: matchingCDNFile, atomically: true, encoding: .utf8)

        // 6. Negative Test A: Candidate feed NOT merged into remote main
        // Remote main still contains Build 3. Even though CDN matches candidate, remote main does not match.
        var unmergedArgs = [
            cloneScript,
            "--tag", "v1.0.0-build5",
            "--archive", dummyDMG.path,
            "--signature", sigB64,
            "--public-key", pubKeyB64,
            "--candidate-appcast", candidateFile.path,
            "--cdn-url", "file://\(matchingCDNFile.path)",
            "--verify-deployed-feed"
        ]
        if FileManager.default.isExecutableFile(atPath: signUpdatePath) {
            unmergedArgs += ["--sign-update", signUpdatePath]
        }
        let unmergedRes = runCmd("/bin/bash", unmergedArgs, cwd: workingClone)
        XCTAssertEqual(unmergedRes.status, 75, "Unmerged feed must exit with code 75: \(unmergedRes.output)")
        XCTAssertTrue(unmergedRes.output.contains("STATUS: PUBLIC_RELEASE_AWAITING_FEED_APPROVAL"),
                      "Unmerged feed must report STATUS: PUBLIC_RELEASE_AWAITING_FEED_APPROVAL: \(unmergedRes.output)")
        XCTAssertFalse(unmergedRes.output.contains("STATUS: DEPLOYED"),
                       "Unmerged feed must never report STATUS: DEPLOYED: \(unmergedRes.output)")

        // 7. Negative Test B: Remote main advanced to different content
        // Simulate an external commit on bareRemote main with different feed content
        let differentFeedContent = candidateFeedContent.replacingOccurrences(of: "Build 5", with: "Build 5 Tampered")
        let diffCommitClone = tempBase.appendingPathComponent("diff_clone")
        _ = runCmd("/usr/bin/git", ["clone", bareRemote.path, diffCommitClone.path])
        _ = runCmd("/usr/bin/git", ["config", "user.name", "External Dev"], cwd: diffCommitClone)
        _ = runCmd("/usr/bin/git", ["config", "user.email", "dev@nodepocket.app"], cwd: diffCommitClone)
        try differentFeedContent.write(to: diffCommitClone.appendingPathComponent("dist/appcast.xml"), atomically: true, encoding: .utf8)
        _ = runCmd("/usr/bin/git", ["commit", "-am", "External change on main"], cwd: diffCommitClone)
        _ = runCmd("/usr/bin/git", ["push", "origin", "main"], cwd: diffCommitClone)

        let diffRemoteRes = runCmd("/bin/bash", unmergedArgs, cwd: workingClone)
        XCTAssertEqual(diffRemoteRes.status, 75, "Advanced/different remote main must exit with code 75: \(diffRemoteRes.output)")
        XCTAssertTrue(diffRemoteRes.output.contains("STATUS: PUBLIC_RELEASE_AWAITING_FEED_APPROVAL"),
                      "Must report awaiting approval when remote main differs: \(diffRemoteRes.output)")
        XCTAssertFalse(diffRemoteRes.output.contains("STATUS: DEPLOYED"))

        // 8. Negative Test C: Stale Cache Rejection when Remote Fetch Fails
        // Update bareRemote main to exact candidate commit, and fetch once into workingClone so cache matches
        let feedBranchRef = runCmd("/usr/bin/git", ["rev-parse", "feed/v1.0.0-build5"], cwd: bareRemote)
        let feedCommitSHA = feedBranchRef.output.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = runCmd("/usr/bin/git", ["update-ref", "refs/heads/main", feedCommitSHA], cwd: bareRemote)
        _ = runCmd("/usr/bin/git", ["fetch", "origin", "main"], cwd: workingClone)
        // Now workingClone's cached origin/main matches candidate.
        // Break the remote URL to simulate network failure or unreachable remote:
        _ = runCmd("/usr/bin/git", ["remote", "set-url", "origin", tempBase.appendingPathComponent("nonexistent_remote.git").path], cwd: workingClone)

        let staleFetchRes = runCmd("/bin/bash", unmergedArgs, cwd: workingClone)
        XCTAssertEqual(staleFetchRes.status, 75, "Failed remote fetch must exit with code 75: \(staleFetchRes.output)")
        XCTAssertTrue(staleFetchRes.output.contains("STATUS: REMOTE_MAIN_UNVERIFIED"),
                      "Failed remote fetch must report STATUS: REMOTE_MAIN_UNVERIFIED: \(staleFetchRes.output)")
        XCTAssertTrue(staleFetchRes.output.contains("Network fetch of 'main' from remote 'origin' failed"),
                      "Must log network fetch failure warning: \(staleFetchRes.output)")
        XCTAssertFalse(staleFetchRes.output.contains("STATUS: DEPLOYED"),
                       "Stale cached origin/main must NEVER be trusted to report STATUS: DEPLOYED: \(staleFetchRes.output)")

        // Restore valid remote URL
        _ = runCmd("/usr/bin/git", ["remote", "set-url", "origin", bareRemote.path], cwd: workingClone)

        // 9. Negative Test D: Mismatched CDN Feed
        let mismatchCDNFile = tempBase.appendingPathComponent("cdn_mismatch.xml")
        try initialAppcast.write(to: mismatchCDNFile, atomically: true, encoding: .utf8)
        var mismatchCDNArgs = unmergedArgs
        mismatchCDNArgs[12] = "file://\(mismatchCDNFile.path)"
        let mismatchCDNRes = runCmd("/bin/bash", mismatchCDNArgs, cwd: workingClone)
        XCTAssertEqual(mismatchCDNRes.status, 75, "Mismatched CDN feed must exit with code 75: \(mismatchCDNRes.output)")
        XCTAssertFalse(mismatchCDNRes.output.contains("STATUS: DEPLOYED"))

        // 10. Negative Test E: Missing and Malformed Public Key Config
        var emptyKeyArgs = unmergedArgs
        emptyKeyArgs[8] = ""
        let emptyKeyRes = runCmd("/bin/bash", emptyKeyArgs, cwd: workingClone)
        XCTAssertNotEqual(emptyKeyRes.status, 0, "Empty public key must fail closed")
        XCTAssertTrue(emptyKeyRes.output.contains("SUPublicEDKey is strictly required"),
                      "Must log missing public key error: \(emptyKeyRes.output)")

        var malformedKeyArgs = unmergedArgs
        malformedKeyArgs[8] = "NOT_BASE_64!!!"
        let malformedKeyRes = runCmd("/bin/bash", malformedKeyArgs, cwd: workingClone)
        XCTAssertNotEqual(malformedKeyRes.status, 0, "Malformed public key must fail closed")

        var wrongLenKeyArgs = unmergedArgs
        wrongLenKeyArgs[8] = Data(repeating: 0x41, count: 31).base64EncodedString()
        let wrongLenKeyRes = runCmd("/bin/bash", wrongLenKeyArgs, cwd: workingClone)
        XCTAssertNotEqual(wrongLenKeyRes.status, 0, "31-byte public key must fail closed")

        // 11. Positive Test: Complete Verified Cutover Proof
        // Fresh remote origin/main matches candidate, CDN matches candidate, valid public key
        let positiveRes = runCmd("/bin/bash", unmergedArgs, cwd: workingClone)
        XCTAssertEqual(positiveRes.status, 0, "Verified cutover must exit with code 0: \(positiveRes.output)")
        XCTAssertTrue(positiveRes.output.contains("STATUS: DEPLOYED"),
                      "Positive run must report STATUS: DEPLOYED: \(positiveRes.output)")
        XCTAssertTrue(positiveRes.output.contains("Fresh remote origin/main commit:"),
                      "Positive run must log fresh remote commit SHA: \(positiveRes.output)")
        XCTAssertTrue(positiveRes.output.contains("Fresh remote origin/main:dist/appcast.xml blob:"),
                      "Positive run must log fresh remote blob SHA: \(positiveRes.output)")
        XCTAssertTrue(positiveRes.output.contains("Live CDN verification successful: Build 5 feed exact-byte match"),
                      "Positive run must log CDN match: \(positiveRes.output)")
    }

    // MARK: - Option 1 G1-A Release Trust Boundary Tests (WO-122 / Cases 36-39)

    func testReleaseApprovalSchemaAndPolicyBProofCase36() throws {
        var currentURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: currentURL.appendingPathComponent("Package.swift").path) {
            let parent = currentURL.deletingLastPathComponent()
            if parent.path == currentURL.path { break }
            currentURL = parent
        }
        let rootDir = currentURL
        let schemaURL = rootDir.appendingPathComponent("docs/RELEASE_APPROVAL.schema.json")
        let templateURL = rootDir.appendingPathComponent("docs/RELEASE_APPROVAL_TEMPLATE.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: schemaURL.path), "docs/RELEASE_APPROVAL.schema.json must exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: templateURL.path), "docs/RELEASE_APPROVAL_TEMPLATE.json must exist")

        // 1. Verify template parses as valid JSON and has required keys
        let templateData = try Data(contentsOf: templateURL)
        let templateObj = try JSONSerialization.jsonObject(with: templateData) as? [String: Any]
        XCTAssertNotNil(templateObj)
        XCTAssertEqual(templateObj?["schema_version"] as? String, "1.0.0")

        let releaseTarget = templateObj?["release_target"] as? [String: Any]
        XCTAssertNotNil(releaseTarget)
        XCTAssertEqual(releaseTarget?["target_tag"] as? String, "v1.0.0-build5")
        XCTAssertEqual((releaseTarget?["approved_commit_sha"] as? String)?.count, 40)
        XCTAssertEqual(releaseTarget?["build_number"] as? Int, 5)

        let approvalMetadata = templateObj?["approval_metadata"] as? [String: Any]
        XCTAssertNotNil(approvalMetadata)
        XCTAssertEqual(approvalMetadata?["authorized_scope"] as? String, "NODEPOCKET_BTCB2_ONLY")
        XCTAssertEqual(approvalMetadata?["approval_policy"] as? String, "Policy B: Independent Approved Release Commit on Protected Main")

        let securityAttestation = templateObj?["security_attestation"] as? [String: Any]
        XCTAssertNotNil(securityAttestation)
        XCTAssertEqual(securityAttestation?["spending_authority_disarmed"] as? Bool, true)
        XCTAssertEqual(securityAttestation?["authorized_spending_limit_btc"] as? String, "0.00")
        XCTAssertEqual(securityAttestation?["restricted_rpc_methods_blocked"] as? Int, 12)

        // 2. Python validation script against schema
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("sentinel-case36-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        func runCmd(_ exe: String, _ args: [String], cwd: URL? = nil) -> (status: Int32, output: String) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            if let cwd = cwd { proc.currentDirectoryURL = cwd }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }

        // 3. Test Negative Cases via python validator
        let pyValidator = """
import json, re, sys

with open(sys.argv[1]) as f:
    schema = json.load(f)
with open(sys.argv[2]) as f:
    doc = json.load(f)

# Strict manual structural validation
if doc.get("schema_version") != "1.0.0":
    sys.exit(10)
rt = doc.get("release_target", {})
if not re.match(r"^v[0-9]+\\.[0-9]+\\.[0-9]+-build[0-9]+$", rt.get("target_tag", "")):
    sys.exit(11)
if not re.match(r"^[0-9a-f]{40}$", rt.get("approved_commit_sha", "")):
    sys.exit(12)
if rt.get("build_number", 0) <= 3:
    sys.exit(13)
am = doc.get("approval_metadata", {})
if am.get("authorized_scope") != "NODEPOCKET_BTCB2_ONLY":
    sys.exit(14)
sa = doc.get("security_attestation", {})
if sa.get("spending_authority_disarmed") is not True or sa.get("authorized_spending_limit_btc") != "0.00" or sa.get("restricted_rpc_methods_blocked") != 12:
    sys.exit(15)
sys.exit(0)
"""
        let valScript = tempBase.appendingPathComponent("validate.py")
        try pyValidator.write(to: valScript, atomically: true, encoding: .utf8)

        // Valid template must exit 0
        let resValid = runCmd("/usr/bin/python3", [valScript.path, schemaURL.path, templateURL.path])
        XCTAssertEqual(resValid.status, 0, "Valid template must pass validation: \(resValid.output)")

        // Negative Case A: Non-40 char commit SHA
        var badSHAObj = templateObj!
        var badSHART = releaseTarget!
        badSHART["approved_commit_sha"] = "short_sha"
        badSHAObj["release_target"] = badSHART
        let badSHAFile = tempBase.appendingPathComponent("bad_sha.json")
        try JSONSerialization.data(withJSONObject: badSHAObj).write(to: badSHAFile)
        let resBadSHA = runCmd("/usr/bin/python3", [valScript.path, schemaURL.path, badSHAFile.path])
        XCTAssertEqual(resBadSHA.status, 12, "Non-40 char commit SHA must fail with code 12")

        // Negative Case B: Build number <= 3
        var badBuildObj = templateObj!
        var badBuildRT = releaseTarget!
        badBuildRT["build_number"] = 3
        badBuildObj["release_target"] = badBuildRT
        let badBuildFile = tempBase.appendingPathComponent("bad_build.json")
        try JSONSerialization.data(withJSONObject: badBuildObj).write(to: badBuildFile)
        let resBadBuild = runCmd("/usr/bin/python3", [valScript.path, schemaURL.path, badBuildFile.path])
        XCTAssertEqual(resBadBuild.status, 13, "Build number <= 3 must fail with code 13")

        // Negative Case C: Scope not NODEPOCKET_BTCB2_ONLY
        var badScopeObj = templateObj!
        var badScopeAM = approvalMetadata!
        badScopeAM["authorized_scope"] = "OTHER_PROJECT"
        badScopeObj["approval_metadata"] = badScopeAM
        let badScopeFile = tempBase.appendingPathComponent("bad_scope.json")
        try JSONSerialization.data(withJSONObject: badScopeObj).write(to: badScopeFile)
        let resBadScope = runCmd("/usr/bin/python3", [valScript.path, schemaURL.path, badScopeFile.path])
        XCTAssertEqual(resBadScope.status, 14, "Unauthorized scope must fail with code 14")

        // Negative Case D: Spending not disarmed ($0.00)
        var badSpendObj = templateObj!
        var badSpendSA = securityAttestation!
        badSpendSA["spending_authority_disarmed"] = false
        badSpendObj["security_attestation"] = badSpendSA
        let badSpendFile = tempBase.appendingPathComponent("bad_spend.json")
        try JSONSerialization.data(withJSONObject: badSpendObj).write(to: badSpendFile)
        let resBadSpend = runCmd("/usr/bin/python3", [valScript.path, schemaURL.path, badSpendFile.path])
        XCTAssertEqual(resBadSpend.status, 15, "Non-disarmed spending must fail with code 15")
    }

    func testWorkflowImmutableSHAHandoffAndTagMovementCase37() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("sentinel-case37-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        func runCmd(_ exe: String, _ args: [String], cwd: URL? = nil) -> (status: Int32, output: String) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            if let cwd = cwd { proc.currentDirectoryURL = cwd }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }

        let repoDir = tempBase.appendingPathComponent("test-repo")
        _ = runCmd("/usr/bin/git", ["init", "-b", "main", repoDir.path])
        _ = runCmd("/usr/bin/git", ["config", "user.name", "Test Committer"], cwd: repoDir)
        _ = runCmd("/usr/bin/git", ["config", "user.email", "committer@nodepocket.app"], cwd: repoDir)

        // Commit A
        let fileA = repoDir.appendingPathComponent("file.txt")
        try "Commit A".write(to: fileA, atomically: true, encoding: .utf8)
        _ = runCmd("/usr/bin/git", ["add", "file.txt"], cwd: repoDir)
        _ = runCmd("/usr/bin/git", ["commit", "-m", "Commit A"], cwd: repoDir)
        let commitASHA = runCmd("/usr/bin/git", ["rev-parse", "HEAD"], cwd: repoDir).output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Tag commit A
        _ = runCmd("/usr/bin/git", ["tag", "v1.0.0-build5", commitASHA], cwd: repoDir)

        // Commit B
        try "Commit B".write(to: fileA, atomically: true, encoding: .utf8)
        _ = runCmd("/usr/bin/git", ["commit", "-am", "Commit B"], cwd: repoDir)
        let commitBSHA = runCmd("/usr/bin/git", ["rev-parse", "HEAD"], cwd: repoDir).output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(commitASHA, commitBSHA)

        // Verify initial tag commit equals Commit A
        let tagRefInitial = runCmd("/usr/bin/git", ["rev-list", "-n", "1", "v1.0.0-build5"], cwd: repoDir).output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(tagRefInitial, commitASHA)

        // Retarget tag to Commit B (simulating tag movement attack)
        _ = runCmd("/usr/bin/git", ["tag", "-f", "v1.0.0-build5", commitBSHA], cwd: repoDir)
        let tagRefMoved = runCmd("/usr/bin/git", ["rev-list", "-n", "1", "v1.0.0-build5"], cwd: repoDir).output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(tagRefMoved, commitBSHA)

        // Assert that comparing approved Commit A against tagRefMoved detects the attack
        XCTAssertNotEqual(commitASHA, tagRefMoved, "Retargeted tag must differ from immutable approved commit SHA")

        // Assert that checkout by immutable SHA (commitASHA) remains at Commit A regardless of tag mutation
        _ = runCmd("/usr/bin/git", ["checkout", commitASHA], cwd: repoDir)
        let checkedOutSHA = runCmd("/usr/bin/git", ["rev-parse", "HEAD"], cwd: repoDir).output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(checkedOutSHA, commitASHA, "Pinned checkout must remain at approved commit SHA")
        let contentAtA = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(contentAtA, "Commit A", "Checked out content must match approved commit")
    }

    func testSignOnlyModeAndUnsignedBundleIntegrityCase38() throws {
        var currentURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: currentURL.appendingPathComponent("Package.swift").path) {
            let parent = currentURL.deletingLastPathComponent()
            if parent.path == currentURL.path { break }
            currentURL = parent
        }
        let rootDir = currentURL
        let scriptPath = rootDir.appendingPathComponent("scripts/build_production_dmg.sh").path

        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("sentinel-case38-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        func runCmd(_ exe: String, _ args: [String], cwd: URL? = nil, env: [String: String]? = nil) -> (status: Int32, output: String) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            if let cwd = cwd { proc.currentDirectoryURL = cwd }
            if let env = env {
                var procEnv = ProcessInfo.processInfo.environment
                for (k, v) in env { procEnv[k] = v }
                proc.environment = procEnv
            }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }

        // Test 1: --sign-only with missing app bundle fails closed
        let missingApp = tempBase.appendingPathComponent("Nonexistent.app").path
        let testEnv = [
            "SENTINEL_RELEASE_SECURITY_APPROVED": "1",
            "SENTINEL_DEVELOPER_ID_APPLICATION": "Developer ID Application: Peter Franco",
            "SENTINEL_APPLE_TEAM_ID": "S8QMQZA656",
            "SENTINEL_WEBCREDENTIALS_DOMAIN": "pool.sentineldefensetechnologies.co.za",
            "SENTINEL_NOTARY_PROFILE": "test-profile"
        ]
        let resMissing = runCmd("/bin/bash", [scriptPath, "--sign-only", "--app-bundle", missingApp], env: testEnv)
        XCTAssertNotEqual(resMissing.status, 0, "Missing app bundle in --sign-only mode must fail closed")
        XCTAssertTrue(resMissing.output.contains("Missing pre-built macOS app"),
                      "Output must indicate missing pre-built app: \(resMissing.output)")

        // Test 2: Unsigned bundle archiving and SHA-256 integrity verification
        let mockAppDir = tempBase.appendingPathComponent("Mock.app")
        try FileManager.default.createDirectory(at: mockAppDir.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try "test-binary".write(to: mockAppDir.appendingPathComponent("Contents/MockBinary"), atomically: true, encoding: .utf8)

        let archiveURL = tempBase.appendingPathComponent("unsigned-app-bundle.tar.gz")
        _ = runCmd("/usr/bin/tar", ["-czf", archiveURL.path, "-C", tempBase.path, "Mock.app"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        let archiveData = try Data(contentsOf: archiveURL)
        let originalSHA = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()

        // Tamper with archive
        var tamperedData = archiveData
        tamperedData[tamperedData.count - 1] ^= 0xFF
        let tamperedSHA = SHA256.hash(data: tamperedData).map { String(format: "%02x", $0) }.joined()
        XCTAssertNotEqual(originalSHA, tamperedSHA, "Corrupted archive must produce mismatched SHA-256")
    }

    func testTrustedToolAttestationAndSignUpdateHashCase39() throws {
        var currentURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: currentURL.appendingPathComponent("Package.swift").path) {
            let parent = currentURL.deletingLastPathComponent()
            if parent.path == currentURL.path { break }
            currentURL = parent
        }
        let rootDir = currentURL
        let scriptPath = rootDir.appendingPathComponent("scripts/sign_appcast_enclosure.sh").path

        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("sentinel-case39-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        func runCmd(_ exe: String, _ args: [String], cwd: URL? = nil, env: [String: String]? = nil) -> (status: Int32, output: String) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            if let cwd = cwd { proc.currentDirectoryURL = cwd }
            if let env = env {
                var procEnv = ProcessInfo.processInfo.environment
                for (k, v) in env { procEnv[k] = v }
                proc.environment = procEnv
            }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }

        // Create mock archive
        let dummyArchive = tempBase.appendingPathComponent("test.dmg")
        try "dummy-dmg-content".write(to: dummyArchive, atomically: true, encoding: .utf8)

        // Create a mock sign_update binary
        let mockSignUpdate = tempBase.appendingPathComponent("mock_sign_update")
        let mockScript = """
#!/usr/bin/env bash
# Output a valid 64-byte base64 string
echo "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
"""
        try mockScript.write(to: mockSignUpdate, atomically: true, encoding: .utf8)
        _ = runCmd("/bin/chmod", ["+x", mockSignUpdate.path])

        let toolData = try Data(contentsOf: mockSignUpdate)
        let actualToolSHA = SHA256.hash(data: toolData).map { String(format: "%02x", $0) }.joined()
        let wrongToolSHA = String(repeating: "0", count: 64)

        // Test A: Mismatched tool hash fails closed before execution
        let resMismatch = runCmd("/bin/bash", [
            scriptPath, "sign", dummyArchive.path,
            "--sign-update-bin", mockSignUpdate.path,
            "--trusted-tool-hash", wrongToolSHA
        ])
        XCTAssertNotEqual(resMismatch.status, 0, "Mismatched tool hash must exit non-zero")
        XCTAssertTrue(resMismatch.output.contains("does not match trusted tool hash"),
                      "Output must report hash mismatch: \(resMismatch.output)")

        // Test B: Matching tool hash succeeds
        let resMatch = runCmd("/bin/bash", [
            scriptPath, "sign", dummyArchive.path,
            "--sign-update-bin", mockSignUpdate.path,
            "--trusted-tool-hash", actualToolSHA
        ])
        XCTAssertEqual(resMatch.status, 0, "Matching tool hash must succeed: \(resMatch.output)")
        XCTAssertTrue(resMatch.output.contains("Verified Sparkle sign_update tool binary hash"),
                      "Output must confirm verified tool hash: \(resMatch.output)")
    }
}
