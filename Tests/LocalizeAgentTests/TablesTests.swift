import Foundation
import XCTest
@testable import LocalizeAgent

/// The files an app's strings are kept in, read and written exactly, and the rules a text's specifiers keep.
final class TablesTests: XCTestCase {
    func testAStringsFileReadsBackExactly() throws {
        var file = StringsFile()
        file.entries = [
            .init(key: "Say \"hi\"", value: "Dis \"salut\"", comment: ["A greeting"]),
            .init(key: "Line one\nLine two", value: "Ligne un\nLigne deux"),
            .init(key: "Back\\slash\ttab", value: "Barre\\oblique\ttab"),
            .init(key: "Cooked by %@ in %lld minutes", value: "In %2$lld Minuten von %1$@ gekocht", comment: ["Shown under a recipe", "English: \"Cooked by %1$@ in %2$lld minutes\""]),
            .init(key: "Close */ comment", value: "日本語 — العربية", comment: ["A comment with */ inside"]),
        ]
        let text = file.text()
        XCTAssertTrue(file.readsBack(text), "the system's reader agrees:\n\(text)")
        let read = try XCTUnwrap(StringsFile.parse(text))
        XCTAssertEqual(Set(read.entries.map(\.key)), Set(file.entries.map(\.key)))
        XCTAssertEqual(read.entries.first { $0.key.hasPrefix("Cooked") }?.comment, ["Shown under a recipe", "English: \"Cooked by %1$@ in %2$lld minutes\""])
        XCTAssertTrue(text.hasPrefix("\"Back"), "sorted by key:\n\(text)")
        XCTAssertTrue(text.contains("\n/* A comment with * / inside */\n\"Close */ comment\" = "), "the comment above its entry, never closing early:\n\(text)")
        let url = try Fixture.folder().appendingPathComponent("Localizable.strings")
        try text.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(try Call.lint(url))
    }

    func testWhatOtherToolsWriteIsRead() throws {
        let text = """
        // A line comment
        /* Caf\\U00e9 */
        "Cafe" = "Caf\\U00e9";
        "Plain";
        unquoted = "value";
        "Octal" = "tab\\011end";
        """
        let file = try XCTUnwrap(StringsFile.parse(text))
        XCTAssertEqual(file.entries.map(\.key), ["Cafe", "Plain", "unquoted", "Octal"])
        XCTAssertEqual(file.entries.map(\.value), ["Café", "Plain", "value", "tab\tend"])
        XCTAssertEqual(file.entries[0].comment, ["A line comment", "Caf\\U00e9"])
        let utf16 = try XCTUnwrap(#""Save" = "Enregistrer";"#.data(using: .utf16))
        XCTAssertEqual(StringsFile.read(utf16)?.entries.first?.value, "Enregistrer", "Xcode's older UTF-16 files")
        XCTAssertNil(StringsFile.parse(#""Broken" = "no semicolon""#))
    }

    func testFormatSpecifiers() {
        XCTAssertEqual(FormatSpecifiers.positional("Cooked by %@ in %lld minutes"), "Cooked by %1$@ in %2$lld minutes")
        XCTAssertEqual(FormatSpecifiers.positional("%lld recipes"), "%lld recipes", "one specifier stays as it is")
        XCTAssertEqual(FormatSpecifiers.positional("50%% of %@ and %d"), "50%% of %1$@ and %2$d")
        XCTAssertEqual(FormatSpecifiers.signature("In %2$lld Minuten von %1$@"), [1: "@", 2: "lld"])
        XCTAssertEqual(FormatSpecifiers.signature("%@ of %lld"), FormatSpecifiers.signature("%1$@ of %2$lld"))
        XCTAssertEqual(FormatSpecifiers.signature("Rated %.1f"), [1: ".1f"])
        XCTAssertEqual(FormatSpecifiers.signature("100% sure"), [:], "a percent before a space is no specifier")
        XCTAssertEqual(FormatSpecifiers.signature("50%% done"), [:])
        XCTAssertNil(FormatSpecifiers.signature("%@ and %2$@"), "numbered and plain mixed")
        XCTAssertNil(FormatSpecifiers.signature("%1$@ then %1$d"), "one position, two types")
        XCTAssertEqual(FormatSpecifiers.listed([1: "@", 2: "lld"]), "%1$@, %2$lld")
    }

    func testKeysInCapitals() {
        for key in ["RECIPE_TITLE", "%@ SERVINGS_COUNT", "TITLE_SEARCH %@", "PANTRY_EMPTY_2"] { XCTAssertTrue(StringTable.isScreaming(key), key) }
        for key in ["OK", "Save", "URL", "Recipe_name", "%lld recipes", "IPFS"] { XCTAssertFalse(StringTable.isScreaming(key), key) }
        XCTAssertNil(StringTable.natural("RECIPE_TITLE"))
        XCTAssertEqual(StringTable.natural("%@ of %@"), "%1$@ of %2$@")
    }

    func testLanguagesAreReadAsPeopleAndModelsWriteThem() {
        let cases: [(String, String?)] = [("fr", "fr"), ("pt_br", "pt-BR"), ("ZH-hans", "zh-Hans"), ("zh-CN", "zh-Hans"), ("zh-TW", "zh-Hant"),
                                          ("es-419", "es-419"), ("French", "fr"), ("Simplified Chinese", "zh-Hans"), ("fil", "fil"),
                                          ("sr-latn", "sr-Latn"), ("zh", nil), ("xx", nil), ("french fries", nil), ("Base", nil)]
        for (text, code) in cases { XCTAssertEqual(Language(text)?.code, code, text) }
        XCTAssertTrue(Language(known: "fr").isLatin)
        XCTAssertFalse(Language(known: "ja").isLatin)
        XCTAssertFalse(Language(known: "sr").isLatin)
        XCTAssertTrue(Language(known: "sr-Latn").isLatin)
        XCTAssertEqual(Language(known: "fr").spoken, "French (fr, français)")
        XCTAssertEqual(Language.loom.count, 28)
    }

    func testACatalogKeepsWhatIsNotTheCalls() throws {
        let original: [String: Any] = ["sourceLanguage": "en", "version": "1.0", "strings": [
            "%lld recipes": ["localizations": ["fr": ["variations": ["plural": ["one": ["stringUnit": ["state": "translated", "value": "%lld recette"]],
                                                                                 "other": ["stringUnit": ["state": "translated", "value": "%lld recettes"]]]]]]],
            "Kitchen": ["shouldTranslate": false],
            "Old": ["extractionState": "stale", "localizations": ["fr": ["stringUnit": ["state": "needs_review", "value": "Vieux"]]]],
        ]]
        var table = StringCatalog.load(original, source: Language(known: "en"))
        XCTAssertFalse(table.keys["Kitchen"]!.translatable)
        XCTAssertEqual(table.texts[Language(known: "fr")]?["Old"]?.waiting, true, "needs review is asked again")
        XCTAssertEqual(LocalizeRun.needed(table, language: Language(known: "fr"), refreshing: false), ["Old"], "a plural the person wrote is not asked for")
        table.keys["Save"] = StringTable.Key(source: "Save", comment: "A button")
        table.keys["RECIPES_EMPTY"] = StringTable.Key(source: "No recipes yet")
        table.texts[Language(known: "fr")]?["Save"] = StringTable.Text(value: "Enregistrer")
        table.texts[Language(known: "fr")]?["RECIPES_EMPTY"] = StringTable.Text(value: "No recipes yet", from: "No recipes yet", waiting: true)
        let text = try StringCatalog.render(table, into: original)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let strings = try XCTUnwrap(document["strings"] as? [String: [String: Any]])
        XCTAssertEqual(strings["Kitchen"]?["shouldTranslate"] as? Bool, false)
        XCTAssertEqual(strings["Old"]?["extractionState"] as? String, "stale")
        XCTAssertNotNil(((strings["%lld recipes"]?["localizations"] as? [String: Any])?["fr"] as? [String: Any])?["variations"])
        XCTAssertEqual(strings["Save"]?["comment"] as? String, "A button")
        let reread = StringCatalog.load(document, source: Language(known: "en"))
        XCTAssertEqual(reread.keys["RECIPES_EMPTY"]?.source, "No recipes yet")
        XCTAssertEqual(reread.texts[Language(known: "fr")]?["Save"], StringTable.Text(value: "Enregistrer"))
        XCTAssertEqual(reread.texts[Language(known: "fr")]?["RECIPES_EMPTY"]?.waiting, true)
        XCTAssertTrue(text.contains(#""sourceLanguage" : "en""#), "Xcode's own layout")
    }
}
