//  WHAT: An app's strings in every language, whatever file they are kept in: each key with its source text, its
//        comment and what it is, and each other language's text for it, with the source text that text was made
//        from and whether it still stands in for a translation.

import Foundation

struct StringTable: Sendable {
    struct Key: Equatable, Sendable {
        /// The source language's text; nil for a key in capitals no one has written the text of yet.
        var source: String?
        var comment: String?
        /// What it is on screen, when the Swift says.
        var role: String?
        /// Where the Swift asks for it (`RecipeList+View.swift`), when it does.
        var file: String?
        /// Whether this call's harvest found it.
        var found = false
        /// A catalog's `shouldTranslate: false`: kept, never asked for.
        var translatable = true
    }

    struct Text: Equatable, Sendable {
        var value: String
        /// The source text this was made from, when it is not the key itself.
        var from: String?
        /// The source text standing in until a translation is written.
        var waiting = false
    }

    var source: Language
    var keys: [String: Key] = [:]
    /// Every other language's texts, by key.
    var texts: [Language: [String: Text]] = [:]

    /// Every language the table holds, the source first.
    var languages: [Language] { [source] + texts.keys.filter { $0 != source }.sorted() }

    /// Whether `key` is a key in capitals (`RECIPE_TITLE`, `%@ SERVINGS_COUNT`) rather than the text itself.
    static func isScreaming(_ key: String) -> Bool {
        let words = FormatSpecifiers.removing(from: key).split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard !words.isEmpty else { return false }
        return words.allSatisfy { $0.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" } && $0.contains(where: \.isLetter) }
            && words.contains { $0.contains("_") }
    }

    /// The source text a key reads as when nothing else is written: the key itself, its specifiers numbered when it
    /// has several; nil for a key in capitals.
    static func natural(_ key: String) -> String? {
        isScreaming(key) ? nil : FormatSpecifiers.positional(key)
    }
}
