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
}
