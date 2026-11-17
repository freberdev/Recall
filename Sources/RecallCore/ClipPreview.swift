/// A one-line summary of a clip for the history list.
public enum ClipPreview {
    /// The start of the text on one line: surrounding whitespace removed, line breaks and runs
    /// of whitespace turned into single spaces, shortened to `limit` characters.
    ///
    /// Only the beginning of the text is looked at, so a very large clip costs no more than a small one.
    public static func line(for text: String, limit: Int = 160) -> String {
        var line = ""
        var count = 0
        var pendingSpace = false
        var examined = 0

        for character in text {
            examined += 1
            if examined > limit * 8 { break }
            if character.isWhitespace || character.isNewline {
                pendingSpace = count > 0
                continue
            }
            if pendingSpace {
                line.append(" ")
                count += 1
                pendingSpace = false
            }
            if count >= limit {
                return String(line.prefix(max(limit - 1, 0))) + "…"
            }
            line.append(character)
            count += 1
        }
        return line
    }
}
