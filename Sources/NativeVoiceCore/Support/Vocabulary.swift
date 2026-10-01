import Foundation

/// Custom terms sent along with the audio.
///
/// This is the single most effective lever on quality the app has — measured,
/// not assumed. On one recording, with nothing else changed, a company name
/// came back as an unrelated German word, `Cloudflare Worker` became
/// `Cloud for Work`, `safetensors` became `Sage Sensor` and `D1` became `Z1`.
/// With the vocabulary, every one of them correct.
///
/// It works because proper nouns and jargon are a finite known list.
public enum Vocabulary {
    /// API limits. Exceeding either costs the whole transcription, so the
    /// list is clipped here rather than letting the server reject it.
    public static let maxTerms = 1000
    public static let maxTermLength = 50

    /// Puts the template in place if there is nothing there yet, and returns
    /// whether a file now exists.
    ///
    /// The menu row that opens this file is useless if the file is missing,
    /// and a person who clicks it and gets an empty document or an error has
    /// learned nothing about what the feature is for.
    @discardableResult
    public static func ensureFile(at path: String) -> Bool {
        let manager = FileManager.default
        let directory = (path as NSString).deletingLastPathComponent

        if manager.fileExists(atPath: path) {
            // Measured on this machine: the directory was already there from
            // an earlier version, at 755, and the early return left it that
            // way. The file names the people and clients someone dictates
            // about, so the permissions are corrected on every launch rather
            // than only when the directory is new.
            try? manager.setAttributes([.posixPermissions: 0o700],
                                       ofItemAtPath: directory)
            return true
        }

        do {
            // The file lists names, clients and places someone dictates
            // about, so the directory stays private to its owner.
            try manager.createDirectory(atPath: directory,
                                        withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try Data(template.utf8).write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            appLog("vocabulary: could not create \(path): \(error.localizedDescription)")
            return false
        }
    }

    public static func terms(from text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let term = clipped(line)
            guard seen.insert(term).inserted else { continue }
            out.append(term)
            if out.count == maxTerms { break }
        }
        return out
    }

    /// Shortens a term to the API's limit.
    ///
    /// The documentation says "max characters per keyterm: 50" without saying
    /// what it counts. Swift's `prefix(50)` counts grapheme clusters, which is
    /// the most generous reading; a server counting Unicode scalars would see
    /// more. `Ž` written as Z plus a combining caron is one grapheme and two
    /// scalars, and a term of fifty such letters would pass here and be
    /// rejected there — costing the whole transcription, which is exactly
    /// what this clipping exists to prevent.
    ///
    /// So it satisfies both readings: at most 50 graphemes **and** at most 50
    /// scalars. For plain Latin text the two agree and nothing changes.
    static func clipped(_ term: String) -> String {
        var out = ""
        var scalars = 0
        for character in term {
            let width = character.unicodeScalars.count
            if out.count == maxTermLength || scalars + width > maxTermLength { break }
            out.append(character)
            scalars += width
        }
        return out
    }

    /// Shipped as the initial file. Deliberately empty of actual terms: the
    /// predecessor shipped a vocabulary naming the author's clients.
    public static let template = """
    # Custom vocabulary — one term per line, # starts a comment.
    #
    # This is the most effective way to improve accuracy. Proper nouns and
    # jargon are what transcription gets wrong, and they are a finite list
    # only you know. Add the names of people, products and projects you say
    # out loud.
    #
    # Read before every transcription, so changes apply immediately.
    # At most 1000 terms, 50 characters each.
    #
    # For example, a developer might add:
    #   PostgreSQL
    #   Kubernetes
    #   OAuth

    """
}
