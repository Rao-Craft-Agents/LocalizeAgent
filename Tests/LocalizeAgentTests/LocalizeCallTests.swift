import Foundation
import XCTest
@testable import LocalizeAgent

/// Whole calls on the recipe app: what is written, what is asked for, and what a second call leaves alone.
final class LocalizeCallTests: XCTestCase {
    private let languages = ["fr", "de", "ja", "ar"]

    private func translated(_ folder: URL) async throws -> (LocalizeResult, FakeHostModel) {
        let model = FakeHostModel(answer: Translations.answer)
        return (try await Call.localize(.init(languages: languages), in: folder, model: model), model)
    }

    private func table(_ folder: URL, _ code: String) throws -> [String: String] {
        try Call.strings(folder.appendingPathComponent("Shared/i18n/\(code).lproj/Localizable.strings"))
    }

    func testAFirstCallWritesTheSourceAndEveryLanguage() async throws {
        let folder = try Fixture.kitchen()
        let (result, model) = try await translated(folder)
        XCTAssertEqual(result.languages, ["en", "ar", "de", "fr", "ja"])
        XCTAssertEqual(result.found, 25)
        XCTAssertEqual(result.added, 25)
        XCTAssertEqual(result.translated, 100)
        XCTAssertEqual(result.waiting, [])
        XCTAssertEqual(result.notes, [])
        XCTAssertEqual(Set(result.paths.map { $0.replacingOccurrences(of: folder.path + "/", with: "") }),
                       Set(["en", "fr", "de", "ja", "ar"].map { "Shared/i18n/\($0).lproj/Localizable.strings" } + ["Kitchen.xcodeproj/project.pbxproj"]))
        XCTAssertEqual(model.asked.count, 5, "the English of one key in capitals, then one batch a language")

        let en = try table(folder, "en")
        XCTAssertEqual(en.count, 25)
        XCTAssertEqual(en["RECIPES_EMPTY_TITLE"], "No recipes yet", "a key in capitals gets its English from the model")
        XCTAssertEqual(en["Cooked by %@ in %lld minutes"], "Cooked by %1$@ in %2$lld minutes", "several specifiers are numbered")
        XCTAssertEqual(try table(folder, "de")["Cooked by %@ in %lld minutes"], "In %2$lld Minuten von %1$@ gekocht")
        XCTAssertEqual(try table(folder, "fr")["Dessert"], "Dessert")
        XCTAssertEqual(try table(folder, "ja")["%lld recipes"], "%lld件のレシピ")
        let source = try String(contentsOf: folder.appendingPathComponent("Shared/i18n/en.lproj/Localizable.strings"), encoding: .utf8)
        XCTAssertTrue(source.contains("/* The header above the list's filters */\n\"Filters\" = \"Filters\";"), "a call's comment is kept")
        let french = try String(contentsOf: folder.appendingPathComponent("Shared/i18n/fr.lproj/Localizable.strings"), encoding: .utf8)
        XCTAssertTrue(french.contains("/* English: \"No recipes yet\" */\n\"RECIPES_EMPTY_TITLE\" = \"Aucune recette pour l'instant\";"), french)
        for code in ["en"] + languages {
            XCTAssertNil(try Call.lint(folder.appendingPathComponent("Shared/i18n/\(code).lproj/Localizable.strings")))
        }
        let project = try XCTUnwrap(XcodeProject(in: folder))
        XCTAssertEqual(project.knownRegions, ["en", "Base", "ar", "de", "fr", "ja"])
        // The prompt says what a string is: the model reads a button as an action.
        let french1 = try XCTUnwrap(model.asked.first { $0.user.contains("into French") })
        XCTAssertTrue(french1.user.contains(": a button"), french1.user)
        XCTAssertTrue(french1.user.contains("The header above the list's filters"), french1.user)
    }

    func testASecondCallAsksNothingAndWritesNothing() async throws {
        let folder = try Fixture.kitchen()
        _ = try await translated(folder)
        let model = FakeHostModel(answer: Translations.answer)
        let again = try await Call.localize(.init(), in: folder, model: model)
        XCTAssertEqual(again.paths, [])
        XCTAssertEqual(model.asked.count, 0)
        XCTAssertEqual(again.languages, ["en", "ar", "de", "fr", "ja"], "left out, the languages are the app's")
        XCTAssertEqual(again.notes, ["nothing changed: every string is in every language"])
    }

    func testOnlyANewStringIsAskedFor() async throws {
        let folder = try Fixture.kitchen()
        _ = try await translated(folder)
        let view = folder.appendingPathComponent("Shared/Views/Badge.swift")
        try (try String(contentsOf: view, encoding: .utf8) + "\nstruct Basket: View { var body: some View { Text(\"Shopping list\") } }\n")
            .write(to: view, atomically: true, encoding: .utf8)
        let model = FakeHostModel(answer: { ask in
            let texts = Translations.asked(ask.user)
            return Translations.reply(texts.mapValues { _ in "Liste de courses · 買い物リスト" })
        })
        let result = try await Call.localize(.init(), in: folder, model: model)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(model.asked.count, 4, "one ask a language")
        XCTAssertTrue(model.asked.allSatisfy { Translations.asked($0.user) == ["1": "Shopping list"] })
        XCTAssertEqual(result.paths.count, 5, "every table, the project unchanged")
    }

    func testAChangedSourceTextIsAskedForAgain() async throws {
        let folder = try Fixture.kitchen()
        _ = try await translated(folder)
        let english = folder.appendingPathComponent("Shared/i18n/en.lproj/Localizable.strings")
        try (try String(contentsOf: english, encoding: .utf8)).replacingOccurrences(of: "\"No recipes yet\"", with: "\"Your pantry is empty\"")
            .write(to: english, atomically: true, encoding: .utf8)
        let model = FakeHostModel(answer: { ask in Translations.reply(Translations.asked(ask.user).mapValues { _ in "Garde-manger vide · 空" }) })
        _ = try await Call.localize(.init(), in: folder, model: model)
        XCTAssertEqual(model.asked.count, 4)
        XCTAssertTrue(model.asked.allSatisfy { Translations.asked($0.user) == ["1": "Your pantry is empty"] })
        let french = try String(contentsOf: folder.appendingPathComponent("Shared/i18n/fr.lproj/Localizable.strings"), encoding: .utf8)
        XCTAssertTrue(french.contains("/* English: \"Your pantry is empty\" */\n\"RECIPES_EMPTY_TITLE\" = \"Garde-manger vide · 空\";"), french)
    }

    func testASourceTextTheCodeGivesIsTheCodes() async throws {
        let folder = try Fixture.folder()
        let view = folder.appendingPathComponent("Shared/Welcome.swift")
        try Fixture.write(["Shared/Welcome.swift": #"let welcome = String(localized: "WELCOME_BACK", defaultValue: "Welcome back")"#], in: folder)
        let model = FakeHostModel(answer: { ask in Translations.reply(Translations.asked(ask.user).mapValues { $0 == "Welcome back" ? "Bon retour" : "Content de vous revoir" }) })
        _ = try await Call.localize(.init(languages: ["fr"]), in: folder, model: model)
        XCTAssertEqual(model.asked.count, 1, "no English to ask for: the code gives it")
        try #"let welcome = String(localized: "WELCOME_BACK", defaultValue: "Good to see you again")"#.write(to: view, atomically: true, encoding: .utf8)
        _ = try await Call.localize(.init(), in: folder, model: model)
        XCTAssertEqual(Translations.asked(model.asked[1].user), ["1": "Good to see you again"], "the edited text is asked for again")
        XCTAssertEqual(try table(folder, "en")["WELCOME_BACK"], "Good to see you again")
        XCTAssertEqual(try table(folder, "fr")["WELCOME_BACK"], "Content de vous revoir")
    }

    func testACallAsksOnlyForTheLanguagesItNames() async throws {
        let folder = try Fixture.kitchen()
        _ = try await translated(folder)
        let view = folder.appendingPathComponent("Shared/Views/Badge.swift")
        try (try String(contentsOf: view, encoding: .utf8) + "\nstruct Basket: View { var body: some View { Text(\"Shopping list\") } }\n")
            .write(to: view, atomically: true, encoding: .utf8)
        let model = FakeHostModel(answer: { ask in Translations.reply(Translations.asked(ask.user).mapValues { _ in "Liste de courses" }) })
        let result = try await Call.localize(.init(languages: ["fr"]), in: folder, model: model)
        XCTAssertEqual(model.asked.count, 1, "French alone")
        XCTAssertEqual(Set(result.paths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent }), ["en.lproj", "fr.lproj"],
                       "the languages not named are left as they are")
    }

    func testRefreshAsksAgainForTheLanguagesNamed() async throws {
        let folder = try Fixture.kitchen()
        _ = try await translated(folder)
        let model = FakeHostModel(answer: Translations.answer)
        let result = try await Call.localize(.init(languages: ["de"], refresh: true), in: folder, model: model)
        XCTAssertEqual(model.asked.count, 1, "German alone")
        XCTAssertEqual(Translations.asked(model.asked[0].user).count, 25)
        XCTAssertEqual(result.translated, 25)
        XCTAssertEqual(result.paths, [], "the same translations again change nothing")
    }

    func testWithoutAModelTheSourceIsStillWritten() async throws {
        let folder = try Fixture.kitchen()
        let result = try await Call.localize(.init(languages: ["fr", "de"]), in: folder, model: nil)
        XCTAssertEqual(result.languages, ["en"])
        XCTAssertEqual(result.waiting, ["de", "fr"])
        XCTAssertEqual(result.strings, 24, "the key in capitals waits for its English")
        XCTAssertTrue(result.notes.contains("de, fr wait for a model: the host has none loaded, so only en was written; call again with one"), "\(result.notes)")
        XCTAssertTrue(result.notes.contains { $0.hasPrefix("1 key has no English yet") && $0.contains("RECIPES_EMPTY_TITLE") }, "\(result.notes)")
        XCTAssertEqual(try table(folder, "en").count, 24)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Shared/i18n/fr.lproj").path), "no language without a translation")
        // With a model, the next call does the rest.
        let model = FakeHostModel(answer: Translations.answer)
        let later = try await Call.localize(.init(), in: folder, model: model)
        XCTAssertEqual(later.languages, ["en"], "languages the app never got are asked for again by name")
        let named = try await Call.localize(.init(languages: ["fr", "de"]), in: folder, model: model)
        XCTAssertEqual(named.languages, ["en", "de", "fr"])
        XCTAssertEqual(try table(folder, "en")["RECIPES_EMPTY_TITLE"], "No recipes yet")
    }

    func testWhatStillFailsStaysInEnglishAndIsNamed() async throws {
        let folder = try Fixture.kitchen()
        // This model loses every specifier, in every round.
        let model = FakeHostModel(answer: { ask in
            var answer = Translations.asked(ask.user).compactMapValues { text -> String? in
                Translations.english[text] ?? Translations.table["fr"]?[text]
            }
            for (id, text) in answer where text.contains("%") { answer[id] = text.replacingOccurrences(of: "%lld", with: "") }
            return Translations.reply(answer)
        })
        let result = try await Call.localize(.init(languages: ["fr"], rounds: 2), in: folder, model: model)
        XCTAssertEqual(result.waiting, ["fr"])
        let note = try XCTUnwrap(result.notes.first { $0.hasPrefix("fr:") })
        XCTAssertTrue(note.hasPrefix("fr: 2 strings stayed in English after 2 rounds (\"%lld recipes\", \"Saved %lld recipes\""), note)
        XCTAssertTrue(note.contains("it must keep exactly %lld"), note)
        let french = try table(folder, "fr")
        XCTAssertNil(french["%lld recipes"], "a key that is its own English is left out: the app shows it")
        XCTAssertEqual(french["Recipes"], "Recettes")
    }

    func testAScreamingKeyStandsInWithItsEnglishUntilTranslated() async throws {
        let folder = try Fixture.kitchen()
        let model = FakeHostModel(answer: { ask in
            if ask.system.contains("keys its code names in capitals") { return Translations.answer(ask) }
            return Translations.reply(Translations.asked(ask.user).compactMapValues { $0 == "No recipes yet" ? nil : Translations.table["fr"]?[$0] })
        })
        _ = try await Call.localize(.init(languages: ["fr"], rounds: 1), in: folder, model: model)
        let french = try String(contentsOf: folder.appendingPathComponent("Shared/i18n/fr.lproj/Localizable.strings"), encoding: .utf8)
        XCTAssertTrue(french.contains("/* English: \"No recipes yet\"\n   \(StringsFolder.waitingLine) */\n\"RECIPES_EMPTY_TITLE\" = \"No recipes yet\";"), french)
        let next = FakeHostModel(answer: Translations.answer)
        _ = try await Call.localize(.init(), in: folder, model: next)
        XCTAssertEqual(next.asked.map { Translations.asked($0.user) }, [["1": "No recipes yet"]], "the stand-in is asked for again")
        XCTAssertEqual(try table(folder, "fr")["RECIPES_EMPTY_TITLE"], "Aucune recette pour l'instant")
    }

    func testEveryProblemIsRefusedAtOnceAndNothingIsWritten() async throws {
        let folder = try Fixture.kitchen()
        do {
            _ = try await Call.localize(.init(languages: ["fr", "english-ish", "zh"], source: "english?", scan: ["Nowhere"]), in: folder, model: nil)
            XCTFail("refused")
        } catch let error as LocalizeError {
            guard case .refused(let reasons) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(reasons.count, 4, "\(reasons)")
            XCTAssertTrue("\(error)".hasPrefix("4 things in the call cannot be done, so nothing was written"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Shared/i18n").path))
        let empty = try Fixture.folder()
        do {
            _ = try await Call.localize(.init(languages: ["fr"]), in: empty, model: nil)
            XCTFail("nothing to localize")
        } catch let error as LocalizeError {
            XCTAssertEqual(error, .nothing("no localizable strings in 0 Swift files under \(empty.lastPathComponent)"))
        }
    }

    func testAStringCatalog() async throws {
        let folder = try Fixture.kitchen()
        let result = try await Call.localize(.init(languages: ["fr", "ja"], format: .catalog), in: folder, model: FakeHostModel(answer: Translations.answer))
        let catalog = folder.appendingPathComponent("Shared/i18n/Localizable.xcstrings")
        XCTAssertEqual(result.paths.sorted(), [catalog.path, folder.appendingPathComponent("Kitchen.xcodeproj/project.pbxproj").path].sorted())
        // A catalog with .strings beside it would build twice.
        do {
            _ = try await Call.localize(.init(format: .strings), in: folder, model: nil)
            XCTFail("refused")
        } catch { XCTAssertTrue("\(error)".contains("already holds Localizable.xcstrings"), "\(error)") }
        // Laid out another way (as Xcode would), the same catalog is left alone.
        let compact = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(contentsOf: catalog)))
        try compact.write(to: catalog)
        let again = try await Call.localize(.init(), in: folder, model: FakeHostModel(answer: Translations.answer))
        XCTAssertEqual(again.paths, [], "left out, the format is the catalog the app has, and nothing in it changed")
        XCTAssertEqual(try Data(contentsOf: catalog), compact)
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun"), "no toolchain")
        let out = try Fixture.folder()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcstringstool", "compile", catalog.path, "--output-directory", out.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let french = try XCTUnwrap(NSDictionary(contentsOf: out.appendingPathComponent("fr.lproj/Localizable.strings")) as? [String: String])
        XCTAssertEqual(french["Cooked by %@ in %lld minutes"], "Cuisiné par %1$@ en %2$lld minutes")
        let english = try XCTUnwrap(NSDictionary(contentsOf: out.appendingPathComponent("en.lproj/Localizable.strings")) as? [String: String])
        XCTAssertEqual(english["RECIPES_EMPTY_TITLE"], "No recipes yet")
    }

    func testTheHelper() async throws {
        let folder = try Fixture.kitchen()
        let result = try await Call.localize(.init(helper: true), in: folder, model: nil)
        let helper = folder.appendingPathComponent("Shared/Extensions/String+Localized.swift")
        XCTAssertTrue(result.paths.contains(helper.path))
        XCTAssertTrue(try String(contentsOf: helper, encoding: .utf8).contains("func localized(_ value: String = \"\", formatted: Bool = false) -> String"))
        // A project that declares its own is left with it.
        try FileManager.default.removeItem(at: helper)
        try Fixture.write(["Shared/Extensions/String.swift": "import Foundation\nextension String { func localized() -> String { self } }\n"], in: folder)
        let second = try await Call.localize(.init(helper: true), in: folder, model: nil)
        XCTAssertFalse(second.paths.contains(helper.path))
        XCTAssertTrue(second.notes.contains("String.localized() is already declared in Shared/Extensions/String.swift, so no helper was written"), "\(second.notes)")
    }

    func testLoomsLanguages() async throws {
        let folder = try Fixture.kitchen()
        let result = try await Call.localize(.init(languages: ["loom"]), in: folder, model: nil)
        XCTAssertEqual(result.waiting.count, 27, "Loom's 28 less the source")
        XCTAssertTrue(result.waiting.contains("zh-Hant") && result.waiting.contains("fil"))
    }
}
