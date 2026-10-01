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

    public static func terms(from text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let term = String(line.prefix(maxTermLength))
            guard seen.insert(term).inserted else { continue }
            out.append(term)
            if out.count == maxTerms { break }
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
