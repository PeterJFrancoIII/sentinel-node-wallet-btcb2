import XCTest
@testable import NodePocketCore

final class StorageBreakdownSnapshotTests: XCTestCase {
    func testFormattingAndCalculations() {
        let snapshot = StorageBreakdownSnapshot(
            blocksBytes: 550 * 1024 * 1024,
            chainstateBytes: 18 * 1024 * 1024 * 1024,
            indexesBytes: 4096,
            walletsBytes: 65536,
            totalDataDirBytes: 19 * 1024 * 1024 * 1024
        )

        XCTAssertFalse(snapshot.formattedBlocksSize.isEmpty)
        XCTAssertFalse(snapshot.formattedChainstateSize.isEmpty)
        XCTAssertFalse(snapshot.formattedTotalSize.isEmpty)
        XCTAssertEqual(snapshot.blocksBytes, 550 * 1024 * 1024)
        XCTAssertEqual(snapshot.chainstateBytes, 18 * 1024 * 1024 * 1024)
    }

    func testMeasureNonExistentDirectoryReturnsZero() {
        let nonExistent = URL(fileURLWithPath: "/tmp/non_existent_dir_\(UUID().uuidString)")
        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: nonExistent)

        XCTAssertEqual(snapshot.blocksBytes, 0)
        XCTAssertEqual(snapshot.chainstateBytes, 0)
        XCTAssertEqual(snapshot.totalDataDirBytes, 0)
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertTrue(snapshot.formattedTotalSize.contains("Unavailable"))
    }

    func testMeasureMockDataDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("StorageTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let blocksDir = tempDir.appendingPathComponent("blocks")
        let chainstateDir = tempDir.appendingPathComponent("chainstate")
        try FileManager.default.createDirectory(at: blocksDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chainstateDir, withIntermediateDirectories: true)

        let sampleData = Data(repeating: 0x42, count: 1024 * 1024) // 1 MB
        try sampleData.write(to: blocksDir.appendingPathComponent("blk00000.dat"))
        try sampleData.write(to: chainstateDir.appendingPathComponent("000001.ldb"))

        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: tempDir)

        XCTAssertGreaterThanOrEqual(snapshot.blocksBytes, 1024 * 1024)
        XCTAssertGreaterThanOrEqual(snapshot.chainstateBytes, 1024 * 1024)
        XCTAssertGreaterThanOrEqual(snapshot.totalDataDirBytes, 2 * 1024 * 1024)
    }

    func testMeasureAsyncMatchesSynchronousResult() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("StorageAsyncTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let blocksDir = tempDir.appendingPathComponent("blocks")
        try FileManager.default.createDirectory(at: blocksDir, withIntermediateDirectories: true)
        let sampleData = Data(repeating: 0x55, count: 512 * 1024) // 512 KB
        try sampleData.write(to: blocksDir.appendingPathComponent("blk00000.dat"))

        let syncSnap = StorageBreakdownSnapshot.measure(dataDirectory: tempDir)
        let asyncSnap = await StorageBreakdownSnapshot.measureAsync(dataDirectory: tempDir)

        XCTAssertEqual(syncSnap.blocksBytes, asyncSnap.blocksBytes)
        XCTAssertEqual(syncSnap.chainstateBytes, asyncSnap.chainstateBytes)
        XCTAssertEqual(syncSnap.totalDataDirBytes, asyncSnap.totalDataDirBytes)
    }

    func testSymlinksAreStrictlySkippedAndDoNotLeakExternalBytes() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("StorageSymlinkTest_\(UUID().uuidString)")
        let externalDir = FileManager.default.temporaryDirectory.appendingPathComponent("StorageExternalTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: externalDir)
        }

        // Write a 5 MB file in external directory
        let externalFile = externalDir.appendingPathComponent("huge_external.dat")
        let fiveMB = Data(repeating: 0xAA, count: 5 * 1024 * 1024)
        try fiveMB.write(to: externalFile)

        // Inside datadir/blocks, write a small 100 KB file AND a symlink pointing to the external 5 MB file
        let blocksDir = tempDir.appendingPathComponent("blocks")
        try FileManager.default.createDirectory(at: blocksDir, withIntermediateDirectories: true)
        let smallFile = blocksDir.appendingPathComponent("blk00000.dat")
        try Data(repeating: 0xBB, count: 100 * 1024).write(to: smallFile)

        let symlinkFile = blocksDir.appendingPathComponent("symlink_to_external.dat")
        try FileManager.default.createSymbolicLink(at: symlinkFile, withDestinationURL: externalFile)

        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: tempDir)

        // Blocks size must account ONLY for the small 100 KB file, NEVER traversing the 5 MB symlink!
        XCTAssertLessThan(snapshot.blocksBytes, 1024 * 1024, "Symlink destination must be skipped")
        XCTAssertLessThan(snapshot.totalDataDirBytes, 1024 * 1024, "Total datadir must not count external symlink target")
    }

    func testSymlinkRootFailsClosedToZeroBytes() throws {
        let realDir = FileManager.default.temporaryDirectory.appendingPathComponent("StorageRealDir_\(UUID().uuidString)")
        let symlinkDir = FileManager.default.temporaryDirectory.appendingPathComponent("StorageSymlinkDir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: realDir)
            try? FileManager.default.removeItem(at: symlinkDir)
        }

        let blocksDir = realDir.appendingPathComponent("blocks")
        try FileManager.default.createDirectory(at: blocksDir, withIntermediateDirectories: true)
        try Data(repeating: 0xCC, count: 500 * 1024).write(to: blocksDir.appendingPathComponent("blk00000.dat"))

        // Create a symlink pointing to realDir
        try FileManager.default.createSymbolicLink(at: symlinkDir, withDestinationURL: realDir)

        // Measuring the symlink directory directly must return 0 and unavailable status
        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: symlinkDir)
        XCTAssertEqual(snapshot.blocksBytes, 0, "Symlink root must return 0 bytes")
        XCTAssertEqual(snapshot.totalDataDirBytes, 0, "Symlink root must fail-closed")
        XCTAssertFalse(snapshot.isAvailable, "Symlink root must be marked unavailable")
        XCTAssertTrue(snapshot.formattedTotalSize.contains("Unavailable"), "Must format as Unavailable, never 0 bytes")
    }

    func testDirectorySymlinkDescendantsAreSkipped() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DirSymlinkTest_\(UUID().uuidString)")
        let externalDir = FileManager.default.temporaryDirectory.appendingPathComponent("ExternalDir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: externalDir)
        }

        // Put 10 MB in the external directory
        let externalData = Data(repeating: 0xEE, count: 10 * 1024 * 1024)
        try externalData.write(to: externalDir.appendingPathComponent("external_block.dat"))

        // Create blocks directory with a 200 KB valid file
        let blocksDir = tempDir.appendingPathComponent("blocks")
        try FileManager.default.createDirectory(at: blocksDir, withIntermediateDirectories: true)
        try Data(repeating: 0xFF, count: 200 * 1024).write(to: blocksDir.appendingPathComponent("blk00000.dat"))

        // Create a directory symlink inside blocks/ pointing to the 10 MB external directory
        let dirSymlink = blocksDir.appendingPathComponent("symlinked_dir")
        try FileManager.default.createSymbolicLink(at: dirSymlink, withDestinationURL: externalDir)

        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: tempDir)
        XCTAssertTrue(snapshot.isAvailable)
        // Must measure ONLY the 200 KB local file, completely skipping descending into the 10 MB symlinked directory
        XCTAssertLessThan(snapshot.blocksBytes, 1024 * 1024, "Directory symlink descendants must be skipped")
        XCTAssertLessThan(snapshot.totalDataDirBytes, 1024 * 1024, "Total datadir must not count external directory symlink")
    }

    func testDatadirSymlinkRemovalPreservesExternalVolumeTarget() throws {
        let externalTarget = FileManager.default.temporaryDirectory.appendingPathComponent("ExternalVolumeSimulation_\(UUID().uuidString)")
        let datadirSymlink = FileManager.default.temporaryDirectory.appendingPathComponent("NodePocketSymlink_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: externalTarget, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: externalTarget)
            try? FileManager.default.removeItem(at: datadirSymlink)
        }

        // Put a precious file on the external target
        let preciousFile = externalTarget.appendingPathComponent("precious_wallet.dat")
        try Data("precious data".utf8).write(to: preciousFile)

        // Create symlink
        try FileManager.default.createSymbolicLink(at: datadirSymlink, withDestinationURL: externalTarget)

        // Simulate AppState uninstall symlink defense
        let fm = FileManager.default
        let isSymlink = (try? datadirSymlink.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        XCTAssertTrue(isSymlink, "Must detect that datadir is a symlink")

        if isSymlink {
            try fm.removeItem(at: datadirSymlink)
        }

        // Verify that datadirSymlink was removed, BUT the externalTarget and its contents REMAIN INTACT!
        XCTAssertFalse(fm.fileExists(atPath: datadirSymlink.path), "Symlink pointer must be removed")
        XCTAssertTrue(fm.fileExists(atPath: externalTarget.path), "External target directory MUST be preserved")
        XCTAssertTrue(fm.fileExists(atPath: preciousFile.path), "Files in external target directory MUST be intact")
    }
}
