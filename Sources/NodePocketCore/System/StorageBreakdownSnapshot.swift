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
    public let isAvailable: Bool
    public let failureReason: String?
    public let measurementQuality: StorageMeasurementQuality
    public let measuredAt: Date

    public init(
        blocksBytes: Int64,
        chainstateBytes: Int64,
        indexesBytes: Int64,
        walletsBytes: Int64,
        totalDataDirBytes: Int64,
        isAvailable: Bool = true,
        failureReason: String? = nil,
        measurementQuality: StorageMeasurementQuality = .measuredAllocated,
        measuredAt: Date = Date()
    ) {
        self.blocksBytes = blocksBytes
        self.chainstateBytes = chainstateBytes
        self.indexesBytes = indexesBytes
        self.walletsBytes = walletsBytes
        self.totalDataDirBytes = totalDataDirBytes
        self.isAvailable = isAvailable
        self.failureReason = failureReason
        self.measurementQuality = measurementQuality
        self.measuredAt = measuredAt
    }

    public var formattedBlocksSize: String {
        guard isAvailable else { return "Unavailable" }
        let size = ByteCountFormatter.string(fromByteCount: blocksBytes, countStyle: .file)
        switch measurementQuality {
        case .measuredAllocated: return size
        case .fallbackLogicalEstimate: return "~\(size) (logical)"
        case .partial: return "\(size) (partial)"
        case .unavailable: return "Unavailable"
        }
    }

    public var formattedChainstateSize: String {
        guard isAvailable else { return "Unavailable" }
        let size = ByteCountFormatter.string(fromByteCount: chainstateBytes, countStyle: .file)
        switch measurementQuality {
        case .measuredAllocated: return size
        case .fallbackLogicalEstimate: return "~\(size) (logical)"
        case .partial: return "\(size) (partial)"
        case .unavailable: return "Unavailable"
        }
    }

    public var formattedIndexesSize: String {
        guard isAvailable else { return "Unavailable" }
        let size = ByteCountFormatter.string(fromByteCount: indexesBytes, countStyle: .file)
        switch measurementQuality {
        case .measuredAllocated: return size
        case .fallbackLogicalEstimate: return "~\(size) (logical)"
        case .partial: return "\(size) (partial)"
        case .unavailable: return "Unavailable"
        }
    }

    public var formattedWalletsSize: String {
        guard isAvailable else { return "Unavailable" }
        let size = ByteCountFormatter.string(fromByteCount: walletsBytes, countStyle: .file)
        switch measurementQuality {
        case .measuredAllocated: return size
        case .fallbackLogicalEstimate: return "~\(size) (logical)"
        case .partial: return "\(size) (partial)"
        case .unavailable: return "Unavailable"
        }
    }

    public var formattedTotalSize: String {
        guard isAvailable else { return failureReason != nil ? "Unavailable (\(failureReason!))" : "Unavailable" }
        let size = ByteCountFormatter.string(fromByteCount: totalDataDirBytes, countStyle: .file)
        switch measurementQuality {
        case .measuredAllocated: return size
        case .fallbackLogicalEstimate: return "~\(size) (logical)"
        case .partial: return "\(size) (partial)"
        case .unavailable: return "Unavailable"
        }
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
                isAvailable: false,
                failureReason: "Symlink root rejected",
                measurementQuality: .unavailable
            )
        }

        let blocksURL = dataDirectory.appendingPathComponent("blocks")
        let chainstateURL = dataDirectory.appendingPathComponent("chainstate")
        let indexesURL = dataDirectory.appendingPathComponent("indexes")
        let walletsURL = dataDirectory.appendingPathComponent("wallets")

        let blocksMeasurement = directoryMeasurement(at: blocksURL)
        let effectiveBlocks = (rpcSizeOnDisk != nil && rpcSizeOnDisk! > 0) ? rpcSizeOnDisk! : blocksMeasurement.bytes
        let chainstateMeasurement = directoryMeasurement(at: chainstateURL)
        let indexesMeasurement = directoryMeasurement(at: indexesURL)
        let walletsMeasurement = directoryMeasurement(at: walletsURL)
        let totalMeasurement = directoryMeasurement(at: dataDirectory)

        // Determine aggregate measurement quality
        let allQualities = [blocksMeasurement.quality, chainstateMeasurement.quality, indexesMeasurement.quality, walletsMeasurement.quality, totalMeasurement.quality]
        let aggregateQuality: StorageMeasurementQuality
        if allQualities.contains(.unavailable) {
            aggregateQuality = .unavailable
        } else if allQualities.contains(.partial) {
            aggregateQuality = .partial
        } else if allQualities.contains(.fallbackLogicalEstimate) {
            aggregateQuality = .fallbackLogicalEstimate
        } else {
            aggregateQuality = .measuredAllocated
        }

        return StorageBreakdownSnapshot(
            blocksBytes: effectiveBlocks,
            chainstateBytes: chainstateMeasurement.bytes,
            indexesBytes: indexesMeasurement.bytes,
            walletsBytes: walletsMeasurement.bytes,
            totalDataDirBytes: max(totalMeasurement.bytes, effectiveBlocks + chainstateMeasurement.bytes),
            isAvailable: true,
            failureReason: nil,
            measurementQuality: aggregateQuality,
            measuredAt: Date()
        )
    }

    private struct DirectoryMeasurement {
        let bytes: Int64
        let quality: StorageMeasurementQuality
    }

    private static func directoryMeasurement(at url: URL) -> DirectoryMeasurement {
        // Guard against symlink root
        if let rootValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           rootValues.isSymbolicLink == true {
            return DirectoryMeasurement(bytes: 0, quality: .unavailable)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return DirectoryMeasurement(bytes: 0, quality: .unavailable) }

        var total: Int64 = 0
        var hasLogicalFallback = false
        var hasInaccessibleFile = false

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]) else {
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
