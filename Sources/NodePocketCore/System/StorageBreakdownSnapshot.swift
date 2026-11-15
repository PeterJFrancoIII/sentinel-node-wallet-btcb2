import Foundation

public enum StorageMeasurementQuality: String, Sendable, Equatable {
    case measuredAllocated = "Allocated"
    case fallbackLogicalEstimate = "Logical Estimate"
    case partial = "Partial"
    case unavailable = "Unavailable"
}

public struct StorageBreakdownSnapshot: Sendable, Equatable {
    public let blocksBytes: Int64
    public let chainstateBytes: Int64
    public let indexesBytes: Int64
    public let walletsBytes: Int64
    public let totalDataDirBytes: Int64
    public let rpcSizeOnDisk: Int64?
    public let isAvailable: Bool
    public let failureReason: String?
    public let blocksQuality: StorageMeasurementQuality
    public let chainstateQuality: StorageMeasurementQuality
    public let indexesQuality: StorageMeasurementQuality
    public let walletsQuality: StorageMeasurementQuality
    public let totalQuality: StorageMeasurementQuality
    public let measuredAt: Date

    /// Aggregate measurement quality for backward compatibility.
    public var measurementQuality: StorageMeasurementQuality {
        totalQuality
    }

    public init(
        blocksBytes: Int64,
        chainstateBytes: Int64,
        indexesBytes: Int64,
        walletsBytes: Int64,
        totalDataDirBytes: Int64,
        rpcSizeOnDisk: Int64? = nil,
        isAvailable: Bool = true,
        failureReason: String? = nil,
        blocksQuality: StorageMeasurementQuality = .measuredAllocated,
        chainstateQuality: StorageMeasurementQuality = .measuredAllocated,
        indexesQuality: StorageMeasurementQuality = .measuredAllocated,
        walletsQuality: StorageMeasurementQuality = .measuredAllocated,
        totalQuality: StorageMeasurementQuality = .measuredAllocated,
        measuredAt: Date = Date()
    ) {
        self.blocksBytes = blocksBytes
        self.chainstateBytes = chainstateBytes
        self.indexesBytes = indexesBytes
        self.walletsBytes = walletsBytes
        self.totalDataDirBytes = totalDataDirBytes
        self.rpcSizeOnDisk = rpcSizeOnDisk
        self.isAvailable = isAvailable
        self.failureReason = failureReason
        self.blocksQuality = blocksQuality
        self.chainstateQuality = chainstateQuality
        self.indexesQuality = indexesQuality
        self.walletsQuality = walletsQuality
        self.totalQuality = totalQuality
        self.measuredAt = measuredAt
    }

    /// Convenience initializer mapping uniform measurementQuality across all components.
    public init(
        blocksBytes: Int64,
        chainstateBytes: Int64,
        indexesBytes: Int64,
        walletsBytes: Int64,
        totalDataDirBytes: Int64,
        rpcSizeOnDisk: Int64? = nil,
        isAvailable: Bool = true,
        failureReason: String? = nil,
        measurementQuality: StorageMeasurementQuality,
        measuredAt: Date = Date()
    ) {
        self.init(
            blocksBytes: blocksBytes,
            chainstateBytes: chainstateBytes,
            indexesBytes: indexesBytes,
            walletsBytes: walletsBytes,
            totalDataDirBytes: totalDataDirBytes,
            rpcSizeOnDisk: rpcSizeOnDisk,
            isAvailable: isAvailable,
            failureReason: failureReason,
            blocksQuality: measurementQuality,
            chainstateQuality: measurementQuality,
            indexesQuality: measurementQuality,
            walletsQuality: measurementQuality,
            totalQuality: measurementQuality,
            measuredAt: measuredAt
        )
    }

    private func formatComponent(bytes: Int64, quality: StorageMeasurementQuality) -> String {
        guard isAvailable && quality != .unavailable else { return "Unavailable" }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        switch quality {
        case .measuredAllocated:
            return size
        case .fallbackLogicalEstimate:
            return "~\(size) (logical)"
        case .partial:
            return "\(size) (partial)"
        case .unavailable:
            return "Unavailable"
        }
    }

    public var formattedBlocksSize: String {
        formatComponent(bytes: blocksBytes, quality: blocksQuality)
    }

    public var formattedChainstateSize: String {
        formatComponent(bytes: chainstateBytes, quality: chainstateQuality)
    }

    public var formattedIndexesSize: String {
        formatComponent(bytes: indexesBytes, quality: indexesQuality)
    }

    public var formattedWalletsSize: String {
        formatComponent(bytes: walletsBytes, quality: walletsQuality)
    }

    public var formattedTotalSize: String {
        guard isAvailable else {
            return failureReason != nil ? "Unavailable (\(failureReason!))" : "Unavailable"
        }
        return formatComponent(bytes: totalDataDirBytes, quality: totalQuality)
    }

    public var formattedRpcSizeOnDisk: String? {
        guard let rpcSizeOnDisk = rpcSizeOnDisk, rpcSizeOnDisk > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: rpcSizeOnDisk, countStyle: .file)
    }

    /// Asynchronous nonblocking measurement executed on a detached background utility thread.
    public static func measureAsync(dataDirectory: URL, rpcSizeOnDisk: Int64? = nil) async -> StorageBreakdownSnapshot {
        await Task.detached(priority: .utility) {
            measure(dataDirectory: dataDirectory, rpcSizeOnDisk: rpcSizeOnDisk)
        }.value
    }

    /// Synchronous measurement safely bounded to prevent symlink traversal.
    public static func measure(dataDirectory: URL, rpcSizeOnDisk: Int64? = nil) -> StorageBreakdownSnapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dataDirectory.path) else {
            return StorageBreakdownSnapshot(
                blocksBytes: 0,
                chainstateBytes: 0,
                indexesBytes: 0,
                walletsBytes: 0,
                totalDataDirBytes: 0,
                rpcSizeOnDisk: rpcSizeOnDisk,
                isAvailable: false,
                failureReason: "Directory not found",
                measurementQuality: .unavailable
            )
        }

        // Refuse to follow symbolic link escaping the intended data directory
        if let rootValues = try? dataDirectory.resourceValues(forKeys: [.isSymbolicLinkKey]),
           rootValues.isSymbolicLink == true {
            return StorageBreakdownSnapshot(
                blocksBytes: 0,
                chainstateBytes: 0,
                indexesBytes: 0,
                walletsBytes: 0,
                totalDataDirBytes: 0,
                rpcSizeOnDisk: rpcSizeOnDisk,
                isAvailable: false,
                failureReason: "Symlink root rejected",
                measurementQuality: .unavailable
            )
        }

        let blocksURL = dataDirectory.appendingPathComponent("blocks")
        let chainstateURL = dataDirectory.appendingPathComponent("chainstate")
        let indexesURL = dataDirectory.appendingPathComponent("indexes")
        let walletsURL = dataDirectory.appendingPathComponent("wallets")

        let blocksMeasurement = directoryMeasurement(at: blocksURL, isOptional: true)
        let chainstateMeasurement = directoryMeasurement(at: chainstateURL, isOptional: true)
        let indexesMeasurement = directoryMeasurement(at: indexesURL, isOptional: true)
        let walletsMeasurement = directoryMeasurement(at: walletsURL, isOptional: true)
        let totalMeasurement = directoryMeasurement(at: dataDirectory, isOptional: false)

        // Evaluate aggregate quality across components
        let componentQualities = [blocksMeasurement.quality, chainstateMeasurement.quality, indexesMeasurement.quality, walletsMeasurement.quality]
        let totalQuality: StorageMeasurementQuality
        if totalMeasurement.quality == .unavailable {
            totalQuality = .unavailable
        } else if totalMeasurement.quality == .partial || componentQualities.contains(.partial) || componentQualities.contains(.unavailable) {
            totalQuality = .partial
        } else if totalMeasurement.quality == .fallbackLogicalEstimate || componentQualities.contains(.fallbackLogicalEstimate) {
            totalQuality = .fallbackLogicalEstimate
        } else {
            totalQuality = .measuredAllocated
        }

        let isAvailable = (totalQuality != .unavailable)

        return StorageBreakdownSnapshot(
            blocksBytes: blocksMeasurement.bytes,
            chainstateBytes: chainstateMeasurement.bytes,
            indexesBytes: indexesMeasurement.bytes,
            walletsBytes: walletsMeasurement.bytes,
            totalDataDirBytes: totalMeasurement.bytes,
            rpcSizeOnDisk: rpcSizeOnDisk,
            isAvailable: isAvailable,
            failureReason: isAvailable ? nil : "Data directory unreadable",
            blocksQuality: blocksMeasurement.quality,
            chainstateQuality: chainstateMeasurement.quality,
            indexesQuality: indexesMeasurement.quality,
            walletsQuality: walletsMeasurement.quality,
            totalQuality: totalQuality,
            measuredAt: Date()
        )
    }

    private struct DirectoryMeasurement {
        let bytes: Int64
        let quality: StorageMeasurementQuality
    }

    private static func directoryMeasurement(at url: URL, isOptional: Bool = false) -> DirectoryMeasurement {
        let fm = FileManager.default

        // Handle absent optional directory (e.g. indexes/ or wallets/ when disabled or unused)
        guard fm.fileExists(atPath: url.path) else {
            return DirectoryMeasurement(bytes: 0, quality: .measuredAllocated)
        }

        // Guard against unreadable directory
        guard fm.isReadableFile(atPath: url.path) else {
            return DirectoryMeasurement(bytes: 0, quality: .unavailable)
        }

        // Guard against symlink root
        if let rootValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           rootValues.isSymbolicLink == true {
            return DirectoryMeasurement(bytes: 0, quality: .unavailable)
        }

        var hasInaccessibleFile = false
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isDirectoryKey
            ],
            options: [.skipsPackageDescendants], // Hidden files are deliberately included to measure true disk consumption
            errorHandler: { _, _ in
                hasInaccessibleFile = true
                return true
            }
        ) else {
            return DirectoryMeasurement(bytes: 0, quality: .unavailable)
        }

        var total: Int64 = 0
        var hasLogicalFallback = false

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isDirectoryKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ]) else {
                hasInaccessibleFile = true
                continue
            }
            if values.isSymbolicLink == true {
                // Strictly refuse to traverse into directory symlinks or count symlink targets
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }

            if let alloc = values.totalFileAllocatedSize {
                total += Int64(alloc)
            } else if let alloc = values.fileAllocatedSize {
                total += Int64(alloc)
            } else if let logical = values.fileSize {
                hasLogicalFallback = true
                total += Int64(logical)
            } else {
                hasInaccessibleFile = true
            }
        }

        let quality: StorageMeasurementQuality
        if hasInaccessibleFile {
            quality = .partial
        } else if hasLogicalFallback {
            quality = .fallbackLogicalEstimate
        } else {
            quality = .measuredAllocated
        }

        return DirectoryMeasurement(bytes: total, quality: quality)
    }
}
