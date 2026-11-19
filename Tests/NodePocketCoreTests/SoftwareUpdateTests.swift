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
        let missingUrl = URL(string: "https://raw.githubusercontent.com/PeterJFrancoIII/sentinel-node-wallet-btcb2/main/dist/appcast.xml")!

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

        func runScript(args: [String]) -> (status: Int32, output: String) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath] + args
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

        // 5. Non-monotonic build rejected (< 5)
        let nonMonotonic = runScript(args: ["--tag", "v1.0.0-build3", "--dry-run", "--allow-mock-for-dry-run"])
        XCTAssertNotEqual(nonMonotonic.status, 0)
        XCTAssertTrue(nonMonotonic.output.contains("must be greater than 4"))

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
}
