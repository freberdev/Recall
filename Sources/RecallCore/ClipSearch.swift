import Foundation

/// Text search over the history.
public enum ClipSearch {
    /// The clips that contain every word of `query`, in their original order.
    /// Case and accents are ignored the way `locale` expects. An empty query matches everything.
    public static func filter(_ clips: [Clip], query: String, locale: Locale = .current) -> [Clip] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return clips }
        return clips.filter { clip in
            words.allSatisfy { word in
                clip.text.range(
                    of: word, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
            }
        }
    }
}
