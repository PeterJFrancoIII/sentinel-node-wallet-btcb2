import Foundation

/// Fast, safe XML parser for Sparkle 2 Appcast RSS feeds.
/// Extracts release version, integer build, CPU architecture, EdDSA signatures,
/// release notes, and download enclosures without third-party dependencies.
public final class SparkleAppcastParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var releases: [AppReleaseInfo] = []

    // State for current item
    private var inItem = false
    private var currentElement = ""
    private var currentText = ""

    private var itemTitle: String = ""
    private var itemPubDate: String = ""
    private var itemReleaseNotesLink: String = ""
    private var itemDescription: String = ""
    private var itemSparkleVersion: String = ""
    private var itemSparkleShortVersion: String = ""
    private var itemMinOSVersion: String? = nil
    private var itemChannel: String? = nil

    private var enclosureUrl: URL? = nil
    private var enclosureLength: Int64? = nil
    private var enclosureSignature: String? = nil
    private var enclosureCpu: String? = nil
    private var enclosureOs: String? = nil

    private static let rfc822Formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    public static func parse(xmlData: Data) throws -> [AppReleaseInfo] {
        let parser = SparkleAppcastParser()
        let xmlParser = XMLParser(data: xmlData)
        xmlParser.delegate = parser
        guard xmlParser.parse() else {
            throw SoftwareUpdateError.invalidAppcast(xmlParser.parserError?.localizedDescription ?? "XML parse error")
        }
        return parser.releases
    }

    // MARK: - XMLParserDelegate

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        if elementName == "item" {
            inItem = true
            itemTitle = ""
            itemPubDate = ""
            itemReleaseNotesLink = ""
            itemDescription = ""
            itemSparkleVersion = ""
            itemSparkleShortVersion = ""
            itemMinOSVersion = nil
            itemChannel = nil
            enclosureUrl = nil
            enclosureLength = nil
            enclosureSignature = nil
            enclosureCpu = nil
            enclosureOs = nil
        } else if inItem && elementName == "enclosure" {
            if let urlStr = attributeDict["url"] {
                enclosureUrl = URL(string: urlStr)
            }
            if let lenStr = attributeDict["length"], let l = Int64(lenStr) {
                enclosureLength = l
            }
            enclosureSignature = attributeDict["sparkle:edSignature"] ?? attributeDict["edSignature"]
            enclosureCpu = attributeDict["sparkle:cpu"] ?? attributeDict["cpu"]
            enclosureOs = attributeDict["sparkle:os"] ?? attributeDict["os"]

            if let v = attributeDict["sparkle:version"] ?? attributeDict["version"] {
                if itemSparkleVersion.isEmpty { itemSparkleVersion = v }
            }
            if let sv = attributeDict["sparkle:shortVersionString"] ?? attributeDict["shortVersionString"] {
                if itemSparkleShortVersion.isEmpty { itemSparkleShortVersion = sv }
            }
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem {
            currentText += string
        }
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inItem {
            switch elementName {
            case "title":
                itemTitle = trimmed
            case "pubDate":
                itemPubDate = trimmed
            case "sparkle:releaseNotesLink", "releaseNotesLink":
                itemReleaseNotesLink = trimmed
            case "description":
                itemDescription = trimmed
            case "sparkle:version", "version":
                if itemSparkleVersion.isEmpty { itemSparkleVersion = trimmed }
            case "sparkle:shortVersionString", "shortVersionString":
                if itemSparkleShortVersion.isEmpty { itemSparkleShortVersion = trimmed }
            case "sparkle:minimumSystemVersion", "minimumSystemVersion":
                itemMinOSVersion = trimmed
            case "sparkle:channel", "channel":
                itemChannel = trimmed
            case "item":
                buildAndAppendRelease()
                inItem = false
            default:
                break
            }
        }
    }

    private func buildAndAppendRelease() {
        // Resolve version
        let versionCandidate: String
        if !itemSparkleShortVersion.isEmpty && !itemSparkleVersion.isEmpty {
            versionCandidate = "\(itemSparkleShortVersion) (build \(itemSparkleVersion))"
        } else if !itemSparkleShortVersion.isEmpty {
            versionCandidate = itemSparkleShortVersion
        } else if !itemSparkleVersion.isEmpty {
            versionCandidate = "1.0 (build \(itemSparkleVersion))"
        } else if !itemTitle.isEmpty {
            versionCandidate = itemTitle
        } else {
            return
        }

        guard let parsedVersion = AppVersion.parse(versionCandidate) else {
            return
        }

        // Parse date
        var date = Date()
        if let d = Self.rfc822Formatter.date(from: itemPubDate) {
            date = d
        } else if let d = Self.isoFormatter.date(from: itemPubDate) {
            date = d
        }

        // Architecture detection: attributes take precedence, fallback to URL detection
        let detectedArch: AppArchitecture
        if let cpu = enclosureCpu, !cpu.isEmpty {
            detectedArch = AppArchitecture.detect(from: cpu)
        } else if let urlStr = enclosureUrl?.absoluteString {
            detectedArch = AppArchitecture.detect(from: urlStr)
        } else {
            detectedArch = .arm64
        }

        // Channel evaluation
        let isPrerelease = (itemChannel?.lowercased() == "beta") || parsedVersion.isPrerelease

        let release = AppReleaseInfo(
            id: enclosureUrl?.absoluteString ?? itemSparkleVersion,
            tagName: "v\(parsedVersion.shortDescription)",
            version: parsedVersion,
            name: itemTitle.isEmpty ? "Sentinel Node Wallet \(parsedVersion.description)" : itemTitle,
            releaseNotes: !itemDescription.isEmpty ? itemDescription : (!itemReleaseNotesLink.isEmpty ? itemReleaseNotesLink : "Software update available."),
            publishedAt: date,
            isPrerelease: isPrerelease,
            isDraft: false,
            downloadUrl: enclosureUrl,
            downloadSize: enclosureLength,
            architecture: detectedArch,
            sparkleEdSignature: enclosureSignature,
            sha256Digest: nil,
            minOSVersion: itemMinOSVersion
        )

        releases.append(release)
    }
}
