//  WHAT: Whether one of the model's answers is a text the app can show for its source text: not empty, every format
//        specifier kept at its position and of its type, every line break kept, not left in the source language, not
//        a paragraph about the text. A source text written for a key in capitals is checked the same way, and must
//        not be a key itself.
//  PIN:  EVERY ANSWER IS CHECKED, NONE IS TRUSTED. A specifier lost drops a value from the screen and one of another
//        type crashes the app when the text is formatted; an answer that fails a check is asked for again with the
//        reason, and what still fails stays in the source language, said in the call's notes.

import Foundation

enum TranslationCheck {
    enum Verdict: Equatable {
        /// The text as the app will show it, after the repairs that change nothing it says.
        case good(String)
        /// Why it cannot be shown, in a sentence the model can act on.
        case bad(String)
    }

    /// A translation of `source` into `language`.
    static func translation(_ answer: String, of source: String, into language: Language, from sourceLanguage: Language) -> Verdict {
        let text = repaired(answer, like: source)
        if let problem = shapeProblem(text, of: source) { return .bad(problem) }
        guard language.base != sourceLanguage.base else { return .good(text) }
        // A phrase must come back in the language; a single word may be a name that reads the same everywhere
        // ("Menu", "Mastodon", "OK").
        if comparable(text) == comparable(source), words(in: comparable(source)) >= 2 {
            return .bad("it is still in \(sourceLanguage.name): write it in \(language.name)")
        }
        if !language.isLatin, latinWords(in: source) >= 2, !text.unicodeScalars.contains(where: isOtherScript) {
            return .bad("it is not written in \(language.name)")
        }
        return .good(text)
    }

    /// The source-language text for a key in capitals.
    static func sourceText(_ answer: String, forKey key: String) -> Verdict {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .bad("the answer was empty") }
        if text == key || text.range(of: #"\b[A-Z0-9]+_[A-Z0-9_]+\b"#, options: .regularExpression) != nil {
            return .bad("it is still a key in capitals: write the words a person reads")
        }
        if let problem = specifierProblem(text, of: key) { return .bad(problem) }
        if text.count > max(key.count * 8, 240) { return .bad("it is far longer than a label: answer with the text alone") }
        return .good(text)
    }

    // MARK: - The parts

    /// The source's own surrounding space, no more and no less (`" ms"` stays a word apart from the number before
    /// it); a written-out `\n` read as the line break it meant.
    static func repaired(_ answer: String, like source: String) -> String {
        var text = answer
        if source.contains("\n"), !text.contains("\n"), text.contains("\\n") { text = text.replacingOccurrences(of: "\\n", with: "\n") }
        let leading = String(source.prefix { $0 == " " || $0 == "\t" }), trailing = String(source.reversed().prefix { $0 == " " || $0 == "\t" })
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? trimmed : leading + trimmed + String(trailing.reversed())
    }

    private static func shapeProblem(_ text: String, of source: String) -> String? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "the answer was empty" }
        if let problem = specifierProblem(text, of: source) { return problem }
        let breaks = source.filter { $0 == "\n" }.count, said = text.filter { $0 == "\n" }.count
        if breaks != said { return "it must keep its \(breaks) line break\(breaks == 1 ? "" : "s") (\\n); it has \(said)" }
        if text.count > source.count * 6 + 40 { return "it is far longer than the text: answer with the translation alone" }
        return nil
    }

    private static func specifierProblem(_ text: String, of source: String) -> String? {
        let wanted = FormatSpecifiers.signature(source) ?? [:]
        guard let found = FormatSpecifiers.signature(text) else {
            return "its specifiers mix numbered and plain ones: keep exactly \(FormatSpecifiers.listed(wanted))"
        }
        guard found != wanted else { return nil }
        if wanted.isEmpty { return "it has a format specifier (\(FormatSpecifiers.listed(found))) the text does not: write % as %%" }
        return "it must keep exactly \(FormatSpecifiers.listed(wanted)); it has \(found.isEmpty ? "none" : FormatSpecifiers.listed(found))"
    }

    /// Letters and digits alone, lower-cased, specifiers out: what two texts are compared by.
    static func comparable(_ text: String) -> String {
        let plain = FormatSpecifiers.removing(from: text).lowercased()
        let kept = plain.unicodeScalars.map { $0.properties.isAlphabetic || $0.properties.numericType != nil ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Words of two letters or more.
    private static func words(in text: String) -> Int {
        text.split(separator: " ").filter { $0.filter(\.isLetter).count >= 2 }.count
    }

    /// The words a non-Latin language would write in its own letters: three Latin letters or more, one of them
    /// lower-case (`Save`, never `OK` or `URL`).
    private static func latinWords(in text: String) -> Int {
        FormatSpecifiers.removing(from: text).split(whereSeparator: { !$0.isLetter }).filter { word in
            word.count >= 3 && word.allSatisfy { $0.isASCII } && word.contains(where: \.isLowercase)
        }.count
    }

    private static func isOtherScript(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.properties.isAlphabetic else { return false }
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xAB30...0xAB6F, 0xFF21...0xFF5A:
            return false
        default:
            return true
        }
    }
}
