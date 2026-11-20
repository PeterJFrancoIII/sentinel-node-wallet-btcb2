import XCTest
import Darwin
@testable import NodePocketCore

final class StorageBreakdownSnapshotTests: XCTestCase {
    func testFormattingAndCalculations() {
        let snapshot = StorageBreakdownSnapshot(
            blocksBytes: 550 * 1024 * 1024,
            chainstateBytes: 18 * 1024 * 1024 * 1024,
            indexesBytes: 4096,
            walletsBytes: 65536,
            totalDataDirBytes: 19 * 1024 * 1024 * 1024,
            rpcSizeOnDisk: 550 * 1024 * 1024
        )

        XCTAssertFalse(snapshot.formattedBlocksSize.isEmpty)
        XCTAssertFalse(snapshot.formattedChainstateSize.isEmpty)
        XCTAssertFalse(snapshot.formattedTotalSize.isEmpty)
        XCTAssertEqual(snapshot.blocksBytes, 550 * 1024 * 1024)
        XCTAssertEqual(snapshot.chainstateBytes, 18 * 1024 * 1024 * 1024)
        XCTAssertEqual(snapshot.rpcSizeOnDisk, 550 * 1024 * 1024)
    }

    func testMeasureNonExistentDirectoryReturnsZero() {
        let nonExistent = URL(fileURLWithPath: "/tmp/non_existent_dir_\(UUID().uuidString)")
        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: nonExistent)

        XCTAssertEqual(snapshot.blocksBytes, 0)
        XCTAssertEqual(snapshot.chainstateBytes, 0)
        XCTAssertEqual(snapshot.totalDataDirBytes, 0)
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.totalQuality, .unavailable)
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
        XCTAssertEqual(snapshot.blocksQuality, .measuredAllocated)
        XCTAssertEqual(snapshot.chainstateQuality, .measuredAllocated)
        XCTAssertEqual(snapshot.totalQuality, .measuredAllocated)
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
        XCTAssertEqual(syncSnap.totalQuality, asyncSnap.totalQuality)
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
        XCTAssertEqual(snapshot.totalQuality, .unavailable)
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

    func testDivergentRPCAndFilesystemAllocationParity() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DivergentRPCTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let blocksDir = tempDir.appendingPathComponent("blocks")
        let chainstateDir = tempDir.appendingPathComponent("chainstate")
        try FileManager.default.createDirectory(at: blocksDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chainstateDir, withIntermediateDirectories: true)

        // Physical files: 200 KB in blocks, 300 KB in chainstate
        try Data(repeating: 0x11, count: 200 * 1024).write(to: blocksDir.appendingPathComponent("blk00000.dat"))
        try Data(repeating: 0x22, count: 300 * 1024).write(to: chainstateDir.appendingPathComponent("000001.ldb"))

        // Deliberately divergent RPC value: 50 GB
        let divergentRPC: Int64 = 50 * 1024 * 1024 * 1024
        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: tempDir, rpcSizeOnDisk: divergentRPC)

        XCTAssertTrue(snapshot.isAvailable)
        // blocksBytes MUST reflect physical filesystem allocation (~200 KB), NEVER the 50 GB RPC figure!
        XCTAssertLessThan(snapshot.blocksBytes, 1024 * 1024, "blocksBytes must be physical filesystem allocation")
        // totalDataDirBytes MUST reflect physical filesystem allocation (~500 KB), NEVER 50 GB + chainstate!
        XCTAssertLessThan(snapshot.totalDataDirBytes, 1024 * 1024, "totalDataDirBytes must be pure physical filesystem total")
        // rpcSizeOnDisk must be cleanly retained as a separate optional field
        XCTAssertEqual(snapshot.rpcSizeOnDisk, divergentRPC)
        XCTAssertEqual(snapshot.formattedRpcSizeOnDisk, ByteCountFormatter.string(fromByteCount: divergentRPC, countStyle: .file))
        XCTAssertEqual(snapshot.blocksQuality, .measuredAllocated)
        XCTAssertEqual(snapshot.totalQuality, .measuredAllocated)
    }

    func testPerComponentQualityWithMissingOptionalDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OptionalDirTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create required blocks and chainstate (no optional indexes, no optional wallets)
        let blocksDir = tempDir.appendingPathComponent("blocks")
        try FileManager.default.createDirectory(at: blocksDir, withIntermediateDirectories: true)
        try Data(repeating: 0x22, count: 100 * 1024).write(to: blocksDir.appendingPathComponent("blk00000.dat"))

        let chainstateDir = tempDir.appendingPathComponent("chainstate")
        try FileManager.default.createDirectory(at: chainstateDir, withIntermediateDirectories: true)
        try Data(repeating: 0x33, count: 200 * 1024).write(to: chainstateDir.appendingPathComponent("000001.ldb"))

        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: tempDir)

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.blocksQuality, .measuredAllocated)
        XCTAssertGreaterThan(snapshot.blocksBytes, 0)
        XCTAssertEqual(snapshot.chainstateQuality, .measuredAllocated)
        XCTAssertGreaterThan(snapshot.chainstateBytes, 0)
        // Absent optional directories must report 0 bytes with .measuredAllocated, NOT fail or downgrade the snapshot
        XCTAssertEqual(snapshot.indexesQuality, .measuredAllocated)
        XCTAssertEqual(snapshot.indexesBytes, 0)
        XCTAssertEqual(snapshot.walletsQuality, .measuredAllocated)
        XCTAssertEqual(snapshot.walletsBytes, 0)
        XCTAssertEqual(snapshot.totalQuality, .measuredAllocated)
    }

    func testAbsentRequiredDirectoryInEstablishedNodeReturnsUnavailable() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AbsentRequiredTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Established node with chainstate and bitcoin.conf, but missing required blocks/
        let chainstateDir = tempDir.appendingPathComponent("chainstate")
        try FileManager.default.createDirectory(at: chainstateDir, withIntermediateDirectories: true)
        try Data(repeating: 0x33, count: 100 * 1024).write(to: chainstateDir.appendingPathComponent("000001.ldb"))
        try "test=1".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("bitcoin.conf"))

        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: tempDir)

        XCTAssertTrue(snapshot.isAvailable, "Snapshot is available but partial")
        XCTAssertEqual(snapshot.blocksQuality, .unavailable, "Missing required blocks/ directory in established node must be .unavailable")
        XCTAssertEqual(snapshot.blocksBytes, 0)
        XCTAssertEqual(snapshot.chainstateQuality, .measuredAllocated)
        XCTAssertGreaterThan(snapshot.chainstateBytes, 0)
        XCTAssertEqual(snapshot.indexesQuality, .measuredAllocated, "Absent optional indexes/ remains .measuredAllocated")
        XCTAssertEqual(snapshot.walletsQuality, .measuredAllocated, "Absent optional wallets/ remains .measuredAllocated")
        XCTAssertEqual(snapshot.totalQuality, .partial, "Aggregate quality must be .partial when a required directory is missing")
    }

    func testHiddenFilesIncludedInAllocation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("HiddenFilesTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let blocksDir = tempDir.appendingPathComponent("blocks")
        try FileManager.default.createDirectory(at: blocksDir, withIntermediateDirectories: true)

        // Write a visible 100 KB file and a hidden 200 KB file
        try Data(repeating: 0x44, count: 100 * 1024).write(to: blocksDir.appendingPathComponent("blk00000.dat"))
        try Data(repeating: 0x55, count: 200 * 1024).write(to: blocksDir.appendingPathComponent(".hidden_block_data"))

        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: tempDir)

        // Both visible and hidden disk-consuming files must be counted in allocation
        XCTAssertGreaterThanOrEqual(snapshot.blocksBytes, 300 * 1024, "Hidden files must be counted in allocation")
        XCTAssertGreaterThanOrEqual(snapshot.totalDataDirBytes, 300 * 1024, "Hidden files must be counted in total datadir")
    }

    func testMixedSuccessQualityWithUnreadableComponent() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MixedSuccessTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Valid chainstate directory
        let chainstateDir = tempDir.appendingPathComponent("chainstate")
        try FileManager.default.createDirectory(at: chainstateDir, withIntermediateDirectories: true)
        try Data(repeating: 0x66, count: 250 * 1024).write(to: chainstateDir.appendingPathComponent("000001.ldb"))

        // Inaccessible indexes directory (chmod 000)
        let indexesDir = tempDir.appendingPathComponent("indexes")
        try FileManager.default.createDirectory(at: indexesDir, withIntermediateDirectories: true)
        try Data(repeating: 0x77, count: 50 * 1024).write(to: indexesDir.appendingPathComponent("index.dat"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: indexesDir.path)
        defer {
            // Restore permissions to allow cleanup
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: indexesDir.path)
        }

        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: tempDir)

        XCTAssertTrue(snapshot.isAvailable, "Snapshot overall must remain available")
        // Valid chainstate MUST NOT be suppressed by unreadable indexes
        XCTAssertEqual(snapshot.chainstateQuality, .measuredAllocated)
        XCTAssertGreaterThan(snapshot.chainstateBytes, 0)
        XCTAssertFalse(snapshot.formattedChainstateSize.contains("Unavailable"))
        // Unreadable indexes must report Unavailable
        XCTAssertEqual(snapshot.indexesQuality, .unavailable)
        XCTAssertEqual(snapshot.formattedIndexesSize, "Unavailable")
        // Total quality must reflect partial traversal
        XCTAssertEqual(snapshot.totalQuality, .partial)
        XCTAssertTrue(snapshot.formattedTotalSize.contains("(partial)"))
    }

    func testSparseFileAllocationParity() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SparseTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let blocksDir = tempDir.appendingPathComponent("blocks")
        try FileManager.default.createDirectory(at: blocksDir, withIntermediateDirectories: true)

        let sparseFileURL = blocksDir.appendingPathComponent("sparse_block.dat")
        let fd = open(sparseFileURL.path, O_CREAT | O_RDWR | O_TRUNC, 0o644)
        guard fd >= 0 else { throw NSError(domain: "Test", code: 1) }
        let data = Data(repeating: 0x41, count: 10 * 1024 * 1024)
        _ = data.withUnsafeBytes { ptr in
            write(fd, ptr.baseAddress, ptr.count)
        }
        var hole = fpunchhole_t(fp_flags: 0, reserved: 0, fp_offset: 0, fp_length: 9 * 1024 * 1024)
        let punchRes = fcntl(fd, F_PUNCHHOLE, &hole)
        close(fd)
        XCTAssertEqual(punchRes, 0, "F_PUNCHHOLE must succeed on APFS")

        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: tempDir)

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.blocksQuality, .measuredAllocated)
        // Physical APFS allocation after punching a 9 MB hole in 10 MB is ~1 MB, far less than 5 MB
        XCTAssertLessThan(snapshot.blocksBytes, 5 * 1024 * 1024, "Sparse file must measure physical allocation, not 10 MB logical size")
    }

    func testMeasurementQualityFormattingDistinctions() {
        // 1. Measured Allocated
        let allocatedSnap = StorageBreakdownSnapshot(
            blocksBytes: 1024 * 1024,
            chainstateBytes: 2 * 1024 * 1024,
            indexesBytes: 0,
            walletsBytes: 0,
            totalDataDirBytes: 3 * 1024 * 1024,
            blocksQuality: .measuredAllocated,
            chainstateQuality: .measuredAllocated,
            indexesQuality: .measuredAllocated,
            walletsQuality: .measuredAllocated,
            totalQuality: .measuredAllocated
        )
        XCTAssertFalse(allocatedSnap.formattedChainstateSize.contains("(logical)"))
        XCTAssertFalse(allocatedSnap.formattedChainstateSize.contains("(partial)"))

        // 2. Fallback Logical Estimate
        let logicalSnap = StorageBreakdownSnapshot(
            blocksBytes: 1024 * 1024,
            chainstateBytes: 2 * 1024 * 1024,
            indexesBytes: 0,
            walletsBytes: 0,
            totalDataDirBytes: 3 * 1024 * 1024,
            blocksQuality: .fallbackLogicalEstimate,
            chainstateQuality: .fallbackLogicalEstimate,
            indexesQuality: .fallbackLogicalEstimate,
            walletsQuality: .fallbackLogicalEstimate,
            totalQuality: .fallbackLogicalEstimate
        )
        XCTAssertTrue(logicalSnap.formattedChainstateSize.contains("(logical)"))
        XCTAssertTrue(logicalSnap.formattedChainstateSize.hasPrefix("~"))

        // 3. Partial Failure
        let partialSnap = StorageBreakdownSnapshot(
            blocksBytes: 1024 * 1024,
            chainstateBytes: 2 * 1024 * 1024,
            indexesBytes: 0,
            walletsBytes: 0,
            totalDataDirBytes: 3 * 1024 * 1024,
            blocksQuality: .partial,
            chainstateQuality: .partial,
            indexesQuality: .partial,
            walletsQuality: .partial,
            totalQuality: .partial
        )
        XCTAssertTrue(partialSnap.formattedChainstateSize.contains("(partial)"))

        // 4. Unavailable
        let unavailableSnap = StorageBreakdownSnapshot(
            blocksBytes: 0,
            chainstateBytes: 0,
            indexesBytes: 0,
            walletsBytes: 0,
            totalDataDirBytes: 0,
            isAvailable: false,
            failureReason: "Permission Denied",
            blocksQuality: .unavailable,
            chainstateQuality: .unavailable,
            indexesQuality: .unavailable,
            walletsQuality: .unavailable,
            totalQuality: .unavailable
        )
        XCTAssertEqual(unavailableSnap.formattedChainstateSize, "Unavailable")
        XCTAssertEqual(unavailableSnap.formattedTotalSize, "Unavailable (Permission Denied)")
    }

    func testEmptyObservedDirectoryReturnsAllocatedZero() throws {
        let emptyDir = FileManager.default.temporaryDirectory.appendingPathComponent("EmptyDir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let snapshot = StorageBreakdownSnapshot.measure(dataDirectory: emptyDir)
        XCTAssertTrue(snapshot.isAvailable, "Observed empty directory must be available")
        XCTAssertEqual(snapshot.blocksBytes, 0)
        XCTAssertEqual(snapshot.chainstateBytes, 0)
        XCTAssertEqual(snapshot.totalDataDirBytes, 0)
        XCTAssertEqual(snapshot.blocksQuality, .measuredAllocated)
        XCTAssertEqual(snapshot.chainstateQuality, .measuredAllocated)
        XCTAssertEqual(snapshot.totalQuality, .measuredAllocated, "Observed empty directory quality is measuredAllocated")
    }
}
