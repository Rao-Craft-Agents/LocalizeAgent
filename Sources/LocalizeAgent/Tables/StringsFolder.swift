//  WHAT: An app's strings kept as one `Localizable.strings` a language, each in its `<lang>.lproj` folder: read into a
//        table, and the table written back as one file a language.
//  PIN:  A LANGUAGE'S FILE HOLDS ITS TRANSLATIONS AND WHAT THEY WERE MADE FROM. A comment line `English: "…"` (in the
//        source language's name) says the source text a translation was made from when that is not the key itself,
//        so a changed source text is asked for again; a line `Not translated yet` marks the source text standing in.
//        A key that is its own text is left out of a language until it is translated: the app shows the key, which
//        is the source text.
//  PIN:  A LANGUAGE NOTHING CHANGED IN IS LEFT AS IT IS. A file whose entries and comments come out the same is not
//        written again, however it was ordered or spaced: a call touches only the languages it changed.

import Foundation

enum StringsFolder {
    static let fileName = "Localizable.strings"
    static let waitingLine = "Not translated yet: the source text shows until it is."

    /// The languages that have a `Localizable.strings` in `folder`.
    static func languages(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".lproj") && FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).appendingPathComponent(fileName).path) }
            .map { String($0.dropLast(6)) }.sorted()
    }

    static func url(_ language: Language, in folder: URL) -> URL {
        folder.appendingPathComponent("\(language.code).lproj", isDirectory: true).appendingPathComponent(fileName)
    }

    /// The table the folder's files hold. Throws when a file is there and cannot be read.
    static func load(_ folder: URL, source: Language) throws -> StringTable {
        var table = StringTable(source: source)
        let fromLine = source.name + ": "
        for code in languages(in: folder) where code != "Base" && Language(code) != nil {
            // A folder keeps the name it has.
            let language = Language(known: code)
            let url = url(language, in: folder)
            guard let data = try? Data(contentsOf: url), let file = StringsFile.read(data) else {
                throw LocalizeError.unreadable("\(code).lproj/\(fileName) is not a strings file this call can read")
            }
            if language == source {
                for entry in file.entries {
                    let comment = entry.comment.joined(separator: " ").nonEmpty
                    table.keys[entry.key] = StringTable.Key(source: entry.value, comment: comment)
                }
            } else {
                var texts: [String: StringTable.Text] = [:]
                for entry in file.entries {
                    var text = StringTable.Text(value: entry.value)
                    for line in entry.comment {
                        if line.hasPrefix(fromLine), let quoted = Self.unquote(String(line.dropFirst(fromLine.count))) { text.from = quoted }
                        if line.hasPrefix("Not translated yet") { text.waiting = true }
                    }
                    texts[entry.key] = text
                }
                table.texts[language] = texts
            }
        }
        // A key a language has and the source does not is still the app's.
        for (_, texts) in table.texts {
            for key in texts.keys where table.keys[key] == nil { table.keys[key] = StringTable.Key(source: StringTable.natural(key)) }
        }
        return table
    }

    /// One file a language: the source's every key with a text, each other language's texts.
    static func render(_ table: StringTable, in folder: URL) throws -> [(url: URL, text: String)] {
        var files: [(URL, String)] = []
        let fromLine = table.source.name + ": "
        for language in table.languages {
            var file = StringsFile()
            if language == table.source {
                for (key, entry) in table.keys {
                    guard let source = entry.source else { continue }
                    file.entries.append(.init(key: key, value: source, comment: entry.comment.map { [$0] } ?? []))
                }
            } else {
                for (key, text) in table.texts[language] ?? [:] {
                    var comment = table.keys[key]?.comment.map { [$0] } ?? []
                    if let from = text.from { comment.append(fromLine + Self.quote(from)) }
                    if text.waiting { comment.append(waitingLine) }
                    file.entries.append(.init(key: key, value: text.value, comment: comment))
                }
                if file.entries.isEmpty { continue }
            }
            let url = url(language, in: folder)
            if let data = try? Data(contentsOf: url), let existing = StringsFile.read(data), existing.same(as: file) { continue }
            let text = file.text()
            guard file.readsBack(text) else {
                throw LocalizeError.unreadable("\(language.code).lproj/\(fileName) does not read back as written")
            }
            files.append((url, text))
        }
        return files
    }

    /// A text as a JSON string literal: one line, its quotes and line breaks escaped, `*/` never closing a comment.
    static func quote(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? encoder.encode(text)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "*/", with: "*\\/")
    }

    static func unquote(_ text: String) -> String? {
        try? JSONDecoder().decode(String.self, from: Data(text.trimmingCharacters(in: .whitespaces).utf8))
    }
}

extension String {
    /// Nil when empty.
    var nonEmpty: String? { isEmpty ? nil : self }
}
