//  WHAT: One `Localizable.strings` file read and written: its entries in order, each with the comment above it. A
//        language's file also says, in an entry's comment, the source text its translation was made from (when that
//        is not the key) and whether the entry is the source text standing in for a translation.
//  PIN:  READ BACK BEFORE IT LANDS. A file written is parsed again by the system's property list reader and must give
//        back every entry exactly; an escape gone wrong is refused before the project sees it.

import Foundation

struct StringsFile: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var key: String
        var value: String
        /// The comment's lines.
        var comment: [String] = []
    }

    var entries: [Entry] = []

    // MARK: - Reading

    /// The entries of a `.strings` file's bytes (UTF-8, or UTF-16 with its mark); nil when they are not one.
    static func read(_ data: Data) -> StringsFile? {
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { text = String(data: data, encoding: .utf16) }
        else { text = String(data: data, encoding: .utf8) }
        guard let text else { return nil }
        return parse(text)
    }

    static func parse(_ text: String) -> StringsFile? {
        let s = Array(text.unicodeScalars)
        var i = 0, comments: [String] = [], file = StringsFile()
        func skipSpace() {
            while i < s.count {
                if s[i].properties.isWhitespace { i += 1; continue }
                if s[i] == "/", i + 1 < s.count, s[i + 1] == "*" {
                    let start = i + 2
                    i = start
                    while i + 1 < s.count, !(s[i] == "*" && s[i + 1] == "/") { i += 1 }
                    comments.append(String(String.UnicodeScalarView(s[start..<min(i, s.count)])))
                    i += 2
                    continue
                }
                if s[i] == "/", i + 1 < s.count, s[i + 1] == "/" {
                    let start = i + 2
                    while i < s.count, s[i] != "\n" { i += 1 }
                    comments.append(String(String.UnicodeScalarView(s[start..<i])))
                    continue
                }
                break
            }
        }
        func string() -> String? {
            guard i < s.count else { return nil }
            if s[i] != "\"" {
                var word = String.UnicodeScalarView()
                while i < s.count, s[i].properties.isAlphabetic || s[i].properties.numericType != nil || "_$+/:.-".unicodeScalars.contains(s[i]) {
                    word.append(s[i]); i += 1
                }
                return word.isEmpty ? nil : String(word)
            }
            i += 1
            var value = String.UnicodeScalarView()
            while i < s.count, s[i] != "\"" {
                if s[i] == "\\", i + 1 < s.count {
                    i += 1
                    switch s[i] {
                    case "n": value.append("\n")
                    case "t": value.append("\t")
                    case "r": value.append("\r")
                    case "a": value.append("\u{07}")
                    case "b": value.append("\u{08}")
                    case "f": value.append("\u{0C}")
                    case "v": value.append("\u{0B}")
                    case "U", "u":
                        let hex = String(String.UnicodeScalarView(s[(i + 1)..<min(i + 5, s.count)]))
                        if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) { value.append(scalar); i += 4 }
                        else { value.append(s[i]) }
                    case "0"..."7":
                        var digits = String(s[i]), cursor = i + 1
                        while cursor < s.count, digits.count < 3, ("0"..."7").contains(s[cursor]) { digits.unicodeScalars.append(s[cursor]); cursor += 1 }
                        if let code = UInt32(digits, radix: 8), let scalar = Unicode.Scalar(code) { value.append(scalar) }
                        i = cursor - 1
                    default: value.append(s[i])
                    }
                    i += 1
                    continue
                }
                value.append(s[i]); i += 1
            }
            guard i < s.count else { return nil }
            i += 1
            return String(value)
        }
        while true {
            skipSpace()
            if i >= s.count { break }
            guard let key = string() else { return nil }
            skipSpace()
            var value = key
            if i < s.count, s[i] == "=" {
                i += 1
                skipSpace()
                guard let read = string() else { return nil }
                value = read
                skipSpace()
            }
            guard i < s.count, s[i] == ";" else { return nil }
            i += 1
            let lines = comments.flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            file.entries.append(Entry(key: key, value: value, comment: lines))
            comments = []
        }
        return file
    }

    // MARK: - Writing

    /// The file's text: one entry a key, sorted, its comment above it, a blank line between entries.
    func text() -> String {
        entries.sorted { Self.order($0.key, $1.key) }.map { entry in
            var block = ""
            let comment = entry.comment.map { $0.replacingOccurrences(of: "*/", with: "* /") }.filter { !$0.isEmpty }
            if !comment.isEmpty { block += "/* " + comment.joined(separator: "\n   ") + " */\n" }
            return block + "\"\(Self.escape(entry.key))\" = \"\(Self.escape(entry.value))\";\n"
        }.joined(separator: "\n")
    }

    /// Keys in an order a person scans: letters before case, then exactly.
    static func order(_ a: String, _ b: String) -> Bool {
        let (la, lb) = (a.lowercased(), b.lowercased())
        return la == lb ? a < b : la < lb
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Whether `other` holds the same entries with the same comments, in whatever order.
    func same(as other: StringsFile) -> Bool {
        func shape(_ file: StringsFile) -> [String: [String]] {
            Dictionary(file.entries.map { ($0.key, [$0.value] + $0.comment.filter { !$0.isEmpty }) }, uniquingKeysWith: { _, last in last })
        }
        return entries.count == other.entries.count && shape(self) == shape(other)
    }

    /// Whether `text` reads back, by the system's property list reader, as exactly these entries.
    func readsBack(_ text: String) -> Bool {
        guard let parsed = try? PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: String] else {
            return entries.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return parsed == Dictionary(entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
    }
}
