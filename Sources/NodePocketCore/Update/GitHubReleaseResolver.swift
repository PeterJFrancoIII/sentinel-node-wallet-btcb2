import Foundation

/// Resolves Sentinel Node Wallet release metadata from GitHub Releases API and Sparkle Appcast feeds.
/// Implements HTTP conditional caching (ETag / If-None-Match), rate limit backoff,
/// and strict architecture and channel eligibility filtering.
public final class GitHubReleaseResolver: Sendable {
    public let repositoryOwner: String
    public let repositoryName: String
    public let session: URLSession

    public init(
        repositoryOwner: String = "PeterJFrancoIII",
        repositoryName: String = "sentinel-node-wallet-btcb2",
        session: URLSession = .shared
    ) {
        self.repositoryOwner = repositoryOwner
        self.repositoryName = repositoryName
        self.session = session
    }

    /// Evaluates candidate releases against the host environment, installed version, and user configuration.
    /// Returns the newest eligible release if one exists, or nil if already up to date.
    public func findEligibleUpdate(
        from releases: [AppReleaseInfo],
        installedVersion: AppVersion,
        hostArchitecture: AppArchitecture = .current,
        channel: UpdateChannel = .stable,
        skippedVersions: Set<String> = []
    ) -> Result<AppReleaseInfo?, SoftwareUpdateError> {
        // 1. Filter by channel
        let channelFiltered = releases.filter { rel in
            if rel.isDraft { return false }
            if channel == .stable && rel.isPrerelease {
                return false
            }
            return true
        }

        // 2. Filter by version newer than installed (strictly candidate > installed)
        let newerReleases = channelFiltered.filter { rel in
            rel.version > installedVersion
        }

        guard !newerReleases.isEmpty else {
            return .success(nil) // Already up to date
        }

        // 3. Sort by highest version descending (ensuring build 10 > build 3)
        let sorted = newerReleases.sorted { $0.version > $1.version }
        guard let highest = sorted.first else {
            return .success(nil)
        }

        // 4. Check if skipped
        if skippedVersions.contains(highest.version.description) ||
           skippedVersions.contains(highest.version.shortDescription) ||
           skippedVersions.contains(highest.tagName) {
            return .success(nil) // Skipped by user
        }

        // 5. Check architecture compatibility:
        // Must match host architecture or be universal.
        let compatibleAssets = sorted.filter { $0.architecture.isCompatible(with: hostArchitecture) }
        guard let bestCompatible = compatibleAssets.first else {
            return .failure(.incompatibleArchitecture(target: highest.architecture, host: hostArchitecture))
        }

        return .success(bestCompatible)
    }

    /// Fetches and parses releases from Sparkle Appcast XML feed with conditional HTTP caching.
    public func fetchFromAppcast(
        appcastUrl: URL,
        cachedETag: String? = nil
    ) async throws -> (releases: [AppReleaseInfo], newETag: String?) {
        var request = URLRequest(url: appcastUrl)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15.0
        if let etag = cachedETag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SoftwareUpdateError.networkError("Invalid HTTP response")
        }

        if httpResponse.statusCode == 304 {
            throw SoftwareUpdateError.notModified
        }

        if httpResponse.statusCode == 429 || httpResponse.statusCode == 403 {
            var retrySeconds: TimeInterval? = nil
            if let retryHeader = httpResponse.value(forHTTPHeaderField: "Retry-After"),
               let s = TimeInterval(retryHeader) {
                retrySeconds = s
            }
            throw SoftwareUpdateError.rateLimited(retryAfter: retrySeconds)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SoftwareUpdateError.networkError("HTTP status \(httpResponse.statusCode)")
        }

        let newETag = httpResponse.value(forHTTPHeaderField: "ETag")
        let parsed = try SparkleAppcastParser.parse(xmlData: data)
        return (parsed, newETag)
    }

    /// Parses GitHub Releases API JSON into standardized AppReleaseInfo records.
    public static func parseGitHubReleasesJSON(
        data: Data
    ) throws -> [AppReleaseInfo] {
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SoftwareUpdateError.invalidAppcast("Failed to parse GitHub releases JSON array")
        }

        let isoFormatter = ISO8601DateFormatter()
        var releases: [AppReleaseInfo] = []

        for item in jsonArray {
            guard let tagName = item["tag_name"] as? String,
                  let parsedVersion = AppVersion.parse(tagName) else {
                continue
            }

            let id = "\(item["id"] ?? tagName)"
            let name = (item["name"] as? String) ?? tagName
            let body = (item["body"] as? String) ?? ""
            let isPrerelease = (item["prerelease"] as? Bool) ?? false
            let isDraft = (item["draft"] as? Bool) ?? false

            var pubDate = Date()
            if let dateStr = item["published_at"] as? String,
               let d = isoFormatter.date(from: dateStr) {
                pubDate = d
            }

            // Inspect assets
            let assets = (item["assets"] as? [[String: Any]]) ?? []
            for asset in assets {
                let assetName = (asset["name"] as? String) ?? ""
                guard assetName.hasSuffix(".dmg") || assetName.hasSuffix(".pkg") || assetName.hasSuffix(".zip") else {
                    continue
                }

                let detectedArch = AppArchitecture.detect(from: assetName)
                let downloadUrlStr = (asset["browser_download_url"] as? String)
                let downloadUrl = downloadUrlStr != nil ? URL(string: downloadUrlStr!) : nil
                let size = (asset["size"] as? Int64) ?? Int64((asset["size"] as? Int) ?? 0)

                let release = AppReleaseInfo(
                    id: "\(id)_\(assetName)",
                    tagName: tagName,
                    version: parsedVersion,
                    name: name,
                    releaseNotes: body,
                    publishedAt: pubDate,
                    isPrerelease: isPrerelease,
                    isDraft: isDraft,
                    downloadUrl: downloadUrl,
                    downloadSize: size,
                    architecture: detectedArch,
                    sparkleEdSignature: nil,
                    sha256Digest: nil,
                    minOSVersion: "13.0"
                )
                releases.append(release)
            }
        }

        return releases
    }
}
