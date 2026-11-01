import Foundation
import XCTest
@testable import LocalizeAgent

/// The model's answers checked, batched and asked again: what the app is given is never a text that loses a value,
/// a line or its language.
final class TranslateTests: XCTestCase {
    private let en = Language(known: "en"), fr = Language(known: "fr"), ja = Language(known: "ja"), de = Language(known: "de")

    func testEveryAnswerIsChecked() {
        typealias Verdict = TranslationCheck.Verdict
        let cases: [(String, String, Language, Verdict)] = [
            ("%lld recettes", "%lld recipes", fr, .good("%lld recettes")),
            ("  Enregistrer ", "Save", fr, .good("Enregistrer")),
            ("In %2$lld Minuten von %1$@ gekocht", "Cooked by %1$@ in %2$lld minutes", de, .good("In %2$lld Minuten von %1$@ gekocht")),
            ("Von %@ in %lld Minuten", "Cooked by %1$@ in %2$lld minutes", de, .good("Von %@ in %lld Minuten")),
            ("recettes", "%lld recipes", fr, .bad("it must keep exactly %lld; it has none")),
            ("%@ recettes", "%lld recipes", fr, .bad("it must keep exactly %lld; it has %@")),
            ("%lld Minuten von %@", "Cooked by %1$@ in %2$lld minutes", de, .bad("it must keep exactly %1$@, %2$lld; it has %1$lld, %2$@")),
            ("Ligne un Ligne deux", "Line one\nLine two", fr, .bad("it must keep its 1 line break (\\n); it has 0")),
            ("Ligne un\\nLigne deux", "Line one\nLine two", fr, .good("Ligne un\nLigne deux")),
            ("ms", " ms", fr, .good(" ms")),
            (" Trier : ", "Sort: ", fr, .good("Trier : ")),
            ("", "Save", fr, .bad("the answer was empty")),
            ("Clear All", "Clear All", fr, .bad("it is still in English: write it in French")),
            ("Dessert", "Dessert", fr, .good("Dessert")),
            ("Mastodon", "Mastodon", ja, .good("Mastodon")),
            ("OK", "OK", ja, .good("OK")),
            ("Nom de la recette", "Recipe name", ja, .bad("it is not written in Japanese")),
            ("レシピ名", "Recipe name", ja, .good("レシピ名")),
            ("Save", "Save", Language(known: "en-GB"), .good("Save")),
            ("Enregistrer la recette, une recette que vous avez aimée et que vous voulez garder pour plus tard, toujours", "Save", fr,
             .bad("it is far longer than the text: answer with the translation alone")),
        ]
        for (answer, source, language, verdict) in cases {
            XCTAssertEqual(TranslationCheck.translation(answer, of: source, into: language, from: en), verdict, "\(source) → \(answer)")
        }
        XCTAssertEqual(TranslationCheck.sourceText("No recipes yet", forKey: "RECIPES_EMPTY"), .good("No recipes yet"))
        XCTAssertEqual(TranslationCheck.sourceText("%@ servings", forKey: "%@ RECIPE_SERVINGS"), .good("%@ servings"))
        XCTAssertEqual(TranslationCheck.sourceText("servings", forKey: "%@ RECIPE_SERVINGS"), .bad("it must keep exactly %@; it has none"))
        XCTAssertEqual(TranslationCheck.sourceText("RECIPES_EMPTY", forKey: "RECIPES_EMPTY"), .bad("it is still a key in capitals: write the words a person reads"))
    }

    private func items(_ texts: [String]) -> [Translator.Item] { texts.map { Translator.Item(key: $0, text: $0, context: nil) } }

    func testABadAnswerIsAskedAgainWithWhatWasWrong() async throws {
        let model = FakeHostModel([
            Translations.reply(["1": "Enregistrer", "3": "Annuler"]),
            Translations.reply(["2": "%lld recettes"]),
        ])
        let translator = Translator(model: model, rounds: 3, app: "Kitchen", note: { _ in })
        // The first answer loses id 2; the second is asked for it alone, with why.
        let outcome = try await translator.translate(items(["Save", "%lld recipes", "Cancel"]), into: fr, from: en)
        XCTAssertEqual(outcome.done, ["Save": "Enregistrer", "%lld recipes": "%lld recettes", "Cancel": "Annuler"])
        XCTAssertEqual(outcome.failed, [:])
        XCTAssertEqual(model.asked.count, 2)
        let again = model.asked[1].user
        XCTAssertTrue(again.contains(#"{"2": "%lld recipes"}"#), again)
        XCTAssertTrue(again.contains("2: it was missing from the answer."), again)
        XCTAssertFalse(again.contains("Cancel"), "only what failed is asked again")
        XCTAssertTrue(model.asked[0].system.contains("recipe app"), "the example is another app's")
        XCTAssertTrue(model.asked[0].user.contains("The app is Kitchen."))
    }

    func testWhatStillFailsAfterTheRoundsIsReported() async throws {
        let model = FakeHostModel([Translations.reply(["1": "recettes"])])
        let outcome = try await Translator(model: model, rounds: 2, app: "Kitchen", note: { _ in })
            .translate(items(["%lld recipes"]), into: fr, from: en)
        XCTAssertEqual(outcome.done, [:])
        XCTAssertEqual(outcome.failed, ["%lld recipes": "it must keep exactly %lld; it has none"])
        XCTAssertEqual(model.asked.count, 2, "asked as many rounds as the call allows")
    }

    func testAnAskThatFailsIsARoundLostNotACall() async throws {
        let model = FakeHostModel([Data("not json".utf8), Translations.reply(["1": "Enregistrer"])])
        let outcome = try await Translator(model: model, rounds: 3, app: "Kitchen", note: { _ in }).translate(items(["Save"]), into: fr, from: en)
        XCTAssertEqual(outcome.done, ["Save": "Enregistrer"])
        let silent = FakeHostModel()
        let none = try await Translator(model: silent, rounds: 2, app: "Kitchen", note: { _ in }).translate(items(["Save"]), into: fr, from: en)
        XCTAssertEqual(none.failed.keys.first, "Save")
        XCTAssertTrue(none.failed["Save"]!.hasPrefix("no answer came back"))
    }

    func testAnswersKeyedByTheirTextAreRead() async throws {
        let model = FakeHostModel([try JSONSerialization.data(withJSONObject: ["Save": "Enregistrer"])])
        let outcome = try await Translator(model: model, rounds: 1, app: "Kitchen", note: { _ in }).translate(items(["Save"]), into: fr, from: en)
        XCTAssertEqual(outcome.done, ["Save": "Enregistrer"], "a bare object keyed by the text itself")
    }

    func testBatchesAreNarrow() throws {
        let many = items((1...95).map { "Recipe step \($0)" })
        XCTAssertEqual(Translator.batches(many).map(\.count), [40, 40, 15])
        let long = items((1...5).map { String(repeating: "a long paragraph \($0) ", count: 40) })
        XCTAssertTrue(Translator.batches(long).count > 1, "a batch holds about 2,400 characters")
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: TranslationPrompt.schema(ids: ["1", "2"])) as? [String: Any])
        let translations = try XCTUnwrap((schema["properties"] as? [String: Any])?["translations"] as? [String: Any])
        XCTAssertEqual(translations["required"] as? [String], ["1", "2"])
    }
}
