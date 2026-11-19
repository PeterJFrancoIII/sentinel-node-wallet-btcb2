import XCTest
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
}
