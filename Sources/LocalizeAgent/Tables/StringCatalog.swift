//  WHAT: An app's strings kept as one String Catalog (`Localizable.xcstrings`): read into a table, and the table
//        written back into the catalog's own JSON, everything the call does not own (plural variations, a device's
//        variant, Xcode's extraction state, `shouldTranslate`) kept as it was.
//  PIN:  A STATE, NOT A COMMENT. A translation the model wrote is `translated`; the source text standing in is
//        `needs_review`, which Xcode shows as needing work and the next call asks for again.

import Foundation

enum StringCatalog {
    static let fileName = "Localizable.xcstrings"

    static func url(in folder: URL) -> URL { folder.appendingPathComponent(fileName) }

    /// The catalog's JSON, or an empty one when there is no file.
    static func document(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalizeError.unreadable("\(fileName) is not a String Catalog this call can read")
        }
        return document
    }

    /// The source language a catalog names.
    static func sourceLanguage(_ document: [String: Any]) -> Language? {
        (document["sourceLanguage"] as? String).flatMap(Language.init)
    }

    static func load(_ document: [String: Any], source: Language) -> StringTable {
        var table = StringTable(source: source)
        let strings = document["strings"] as? [String: Any] ?? [:]
        for (key, raw) in strings {
            let entry = raw as? [String: Any] ?? [:]
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            var found = StringTable.Key(source: StringTable.natural(key), comment: entry["comment"] as? String)
            found.translatable = entry["shouldTranslate"] as? Bool ?? true
            for (code, rawLocalization) in localizations {
                let localization = rawLocalization as? [String: Any] ?? [:]
                guard let language = Language(code) else { continue }
                let unit = localization["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                if language == source {
                    if let value { found.source = value }
                    continue
                }
                if let value {
                    let state = unit?["state"] as? String ?? "translated"
                    table.texts[language, default: [:]][key] = StringTable.Text(value: value, from: nil, waiting: state != "translated")
                } else if localization["variations"] != nil {
                    // Plural or device variations: the person's own, kept and never asked for.
                    table.texts[language, default: [:]][key] = StringTable.Text(value: key, from: nil, waiting: false)
                }
            }
            if !found.translatable { found.source = found.source ?? key }
            table.keys[key] = found
        }
        return table
    }

    /// The catalog's text with the table written in.
    static func render(_ table: StringTable, into original: [String: Any]) throws -> String {
        var document = original
        document["sourceLanguage"] = table.source.code
        document["version"] = document["version"] ?? "1.0"
        var strings = document["strings"] as? [String: Any] ?? [:]
        for (key, entry) in table.keys {
            var item = strings[key] as? [String: Any] ?? [:]
            if let comment = entry.comment { item["comment"] = comment }
            var localizations = item["localizations"] as? [String: Any] ?? [:]
            if let source = entry.source, source != key {
                localizations[table.source.code] = ["stringUnit": ["state": "translated", "value": source]]
            }
            for (language, texts) in table.texts {
                guard let text = texts[key] else { continue }
                if let existing = localizations[language.code] as? [String: Any], existing["variations"] != nil { continue }
                localizations[language.code] = ["stringUnit": ["state": text.waiting ? "needs_review" : "translated", "value": text.value]]
            }
            if !localizations.isEmpty { item["localizations"] = localizations }
            strings[key] = item
        }
        document["strings"] = strings
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw LocalizeError.unreadable("\(fileName) does not read back as written")
        }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
