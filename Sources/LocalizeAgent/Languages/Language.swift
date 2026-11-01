//  WHAT: A language as a localization names it (`fr`, `zh-Hans`, `pt-BR`): a code read the way a person or a model
//        writes it (`pt_br`, `ZH-hans`, `French`), its names in English and in itself, and whether it is written in
//        the Latin script (what the check of an answer left in English leans on).
//  PIN:  APPLE'S FOLDER NAMES. Chinese is `zh-Hans` or `zh-Hant` (as Xcode and Apple's apps name the folders), never
//        `zh-CN`; a region is upper-case, a script title-case; a bare `zh` says neither and is refused.

import Foundation

struct Language: Hashable, Sendable, Comparable, CustomStringConvertible {
    let code: String

    /// The language `text` names, or nil when it names none.
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let named = Self.byName[trimmed.lowercased()] { code = named; return }
        let parts = trimmed.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let first = parts.first?.lowercased(), (2...3).contains(first.count), first.allSatisfy({ $0.isASCII && $0.isLetter }),
              Self.isoCodes.contains(first) else { return nil }
        var script: String?, region: String?
        for part in parts.dropFirst() {
            if part.count == 4, part.allSatisfy({ $0.isASCII && $0.isLetter }) { script = part.prefix(1).uppercased() + part.dropFirst().lowercased() }
            else if part.count == 2, part.allSatisfy({ $0.isASCII && $0.isLetter }) { region = part.uppercased() }
            else if part.count == 3, part.allSatisfy(\.isNumber) { region = part }
            else { return nil }
        }
        if first == "zh" {
            if script == nil {
                switch region {
                case "CN", "SG": script = "Hans"
                case "TW", "MO": script = "Hant"
                case "HK": break
                default: return nil
                }
                if script != nil { region = nil }
            } else {
                region = nil
            }
        }
        code = [first, script, region].compactMap { $0 }.joined(separator: "-")
    }

    /// A code this package knows to be a language's.
    init(known code: String) { self.code = code }

    var description: String { code }

    static func < (a: Language, b: Language) -> Bool { a.code < b.code }

    /// The language without script or region: `pt` of `pt-BR`.
    var base: String { String(code.split(separator: "-").first ?? Substring(code)) }

    /// Its name in English: "French", "Chinese, Simplified".
    var name: String { Locale(identifier: "en").localizedString(forIdentifier: code) ?? code }

    /// Its name in itself: "français", "简体中文".
    var nativeName: String { Locale(identifier: code).localizedString(forIdentifier: code) ?? name }

    /// Whether it is written in the Latin script, by its likely script when the code names none.
    var isLatin: Bool { Locale.Language(identifier: code).maximalIdentifier.split(separator: "-").contains("Latn") }

    /// "French (fr, français)".
    var spoken: String { nativeName == name ? "\(name) (\(code))" : "\(name) (\(code), \(nativeName))" }

    /// The 28 languages Loom ships, English among them.
    static let loom = ["af", "ar", "bn", "da", "de", "el", "en", "es", "et", "fil", "fr", "hi", "hr", "id", "it", "ja", "ko", "nl",
                       "pl", "pt", "ru", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant"].map(Language.init(known:))

    private static let isoCodes: Set<String> = Set(Locale.LanguageCode.isoLanguageCodes.map(\.identifier))

    /// English names to codes, shortest code first, and the names people say for Apple's folders.
    private static let byName: [String: String] = {
        var names: [String: String] = [:]
        let english = Locale(identifier: "en")
        for code in isoCodes.sorted(by: { ($0.count, $0) < ($1.count, $1) }) {
            if let name = english.localizedString(forLanguageCode: code)?.lowercased(), names[name] == nil { names[name] = code }
        }
        let aliases = ["chinese, simplified": "zh-Hans", "chinese (simplified)": "zh-Hans", "simplified chinese": "zh-Hans",
                       "chinese simplified": "zh-Hans", "chinese, traditional": "zh-Hant", "chinese (traditional)": "zh-Hant",
                       "traditional chinese": "zh-Hant", "chinese traditional": "zh-Hant", "brazilian portuguese": "pt-BR",
                       "portuguese (brazil)": "pt-BR", "european portuguese": "pt-PT", "portuguese (portugal)": "pt-PT",
                       "latin american spanish": "es-419", "spanish (latin america)": "es-419", "mexican spanish": "es-MX",
                       "british english": "en-GB", "english (uk)": "en-GB", "australian english": "en-AU", "canadian french": "fr-CA",
                       "french (canada)": "fr-CA", "norwegian": "nb", "tagalog": "fil"]
        for (name, code) in aliases { names[name] = code }
        names.removeValue(forKey: "chinese")
        return names
    }()
}
