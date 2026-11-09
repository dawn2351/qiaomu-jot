import Foundation

/// Describes only the text added by a top insertion, so undo can remove its separators too.
struct NoteTopInsertion {
    let offset: Int
    let leading: String
    let trailing: String
    let newline: String

    static func read(_ note: URL) throws -> String {
        let data = try Data(contentsOf: note)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return data.starts(with: [0xEF, 0xBB, 0xBF]) ? "\u{FEFF}" + text : text
    }

    static func plan(in note: String, for entry: String, isList: Bool) -> Self {
        let text = note as NSString
        let start = note.hasPrefix("\u{FEFF}") ? 1 : 0
        func line(at index: Int) -> (body: String, end: Int, newline: String)? {
            guard index < text.length else { return nil }
            var end = 0, contentsEnd = 0
            text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
            return (text.substring(with: NSRange(location: index, length: contentsEnd - index)), end,
                    text.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd)))
        }
        let first = line(at: start)
        let newline = first.flatMap { $0.newline.isEmpty ? nil : $0.newline } ?? "\n"
        var offset = start
        if let first, first.body.trimmingCharacters(in: .whitespaces) == "---", first.body.hasPrefix("---") {
            var cursor = first.end
            while let candidate = line(at: cursor) {
                let marker = candidate.body.trimmingCharacters(in: .whitespaces)
                if (marker == "---" || marker == "..."), candidate.body.hasPrefix(marker) {
                    offset = candidate.end
                    break
                }
                cursor = candidate.end
            }
        }

        var followsBlankLine = false
        func skipBlankLines() {
            while let current = line(at: offset), current.body.trimmingCharacters(in: .whitespaces).isEmpty {
                offset = current.end
                followsBlankLine = true
            }
        }
        skipBlankLines()
        if let title = line(at: offset) {
            if title.body.range(of: #"^ {0,3}#(?:[ \t]|$)"#, options: .regularExpression) != nil {
                offset = title.end
                followsBlankLine = false
            } else if let underline = line(at: title.end),
                      title.body.range(of: #"^[\p{L}\p{N}]"#, options: .regularExpression) != nil,
                      underline.body.range(of: #"^ {0,3}=+[ \t]*$"#, options: .regularExpression) != nil {
                offset = underline.end
                followsBlankLine = false
            }
        }
        skipBlankLines()

        let prefix = text.substring(to: offset)
        var leading = ""
        if offset > start {
            if prefix.last?.isNewline != true { leading += newline }
            if !followsBlankLine { leading += newline }
        }
        if offset == start, offset < text.length,
           entry.prefix(while: { !$0.isNewline }).replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) == "---" {
            // A captured delimiter at byte zero would turn body text into document properties.
            leading = newline
        }
        let tightList = isList && line(at: offset)?.body.hasPrefix("- ") == true
        let trailing = offset < text.length && !tightList ? newline : ""
        return Self(offset: offset, leading: leading, trailing: trailing, newline: newline)
    }

    func normalize(_ entry: String) -> String {
        entry.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: newline)
    }

    func wrapping(_ entry: String) -> String { leading + entry + trailing }

    func range(of entry: String, in note: String) -> Range<String.Index>? {
        let written = wrapping(entry)
        guard let range = Range(NSRange(location: offset, length: written.utf16.count), in: note),
              note[range].utf8.elementsEqual(written.utf8) else { return nil }
        return range
    }
}
