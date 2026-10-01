import Foundation

/// One published release, as GitHub describes it.
///
/// Reading and comparing are kept apart from fetching so both can be tested
/// without a network, and so the awkward cases — a release with no archive, a
/// tag that is not a version — are decided somewhere a test can reach.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: String
    public let archiveURL: URL
    public let pageURL: URL

    public init(version: String, archiveURL: URL, pageURL: URL) {
        self.version = version
        self.archiveURL = archiveURL
        self.pageURL = pageURL
    }

    public static func parse(_ json: Data) -> ReleaseInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let page = object["html_url"] as? String,
              let pageURL = URL(string: page),
              let assets = object["assets"] as? [[String: Any]]
        else { return nil }

        // The zip is what the updater can install. A release carrying only a
        // DMG is for people to download by hand, and a release whose upload
        // has not finished has no assets at all; neither is an update, and
        // offering one would download nothing and say nothing.
        let archive = assets.first { asset in
            (asset["name"] as? String)?.lowercased().hasSuffix(".zip") == true
        }
        guard let archive,
              let link = archive["browser_download_url"] as? String,
              let archiveURL = URL(string: link)
        else { return nil }

        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return ReleaseInfo(version: version, archiveURL: archiveURL, pageURL: pageURL)
    }

    /// Numeric comparison, component by component.
    ///
    /// Anything that is not purely digits and dots returns false rather than
    /// a guess. A build that offers "1.1.0-beta" to somebody running the
    /// finished 1.1.0 has made their day worse for no reason.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let left = components(of: candidate),
              let right = components(of: current) else { return false }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(of version: String) -> [Int]? {
        guard !version.isEmpty else { return nil }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber),
                  let value = Int(part) else { return nil }
            numbers.append(value)
        }
        return numbers.isEmpty ? nil : numbers
    }
}
