//  WHAT: What the model is told: how a good interface translation reads, a worked example from a recipe app, then
//        the texts of one batch by id, what each one is, and, when asking again, what was wrong with each.
//  PIN:  IDS, NOT KEYS. A batch names its texts `1`, `2`, `3`: a model copying a long key back as a JSON key changes
//        it (a quote, a space, a translated word) and the answer no longer matches; an id cannot be miscopied.
//  PIN:  THE EXAMPLE IS ANOTHER APP'S. A local model copies the example it is shown; one from the app it is asked
//        about would come back with the example's words.

import Foundation

enum TranslationPrompt {
    // MARK: - Translating

    static func translateSystem(into language: Language, from source: Language) -> String {
        let example = language.base == "es" ? frenchExample : spanishExample
        return """
        You translate the interface of an app from \(source.name) into \(language.name). You answer with one JSON object, {"translations": {"<id>": "<text>"}}: every id you are given, each with its text in \(language.name), and nothing else.

        How a good translation reads:
        - It says what the \(source.name) says, the way an app made in \(language.name) says it: short, natural interface words. A button is an action, a title names a screen, a placeholder invites typing.
        - Every format specifier stays exactly as written: %@, %lld, %d, %lf, %.1f. A numbered one (%1$@, %2$lld) may move to where the sentence needs it and keeps its number. %% stays %%. A line break stays a line break.
        - Names stay as they are: the app's name, a company's or a product's, a handle or a code ("@name", "#tag", "URL").
        - The text is the translation alone: no quotes around it, no note, no \(source.name) beside it.

        An example from a recipe app, translated into \(example.language):
        {"1": "Save Recipe", "2": "%lld servings", "3": "Cooked by %1$@ in %2$lld minutes", "4": "Search recipes"}
        answers
        \(example.answer)
        """
    }

    private static let spanishExample = (language: "Spanish",
        answer: #"{"translations": {"1": "Guardar receta", "2": "%lld porciones", "3": "Cocinado por %1$@ en %2$lld minutos", "4": "Buscar recetas"}}"#)
    private static let frenchExample = (language: "French",
        answer: #"{"translations": {"1": "Enregistrer la recette", "2": "%lld portions", "3": "Cuisiné par %1$@ en %2$lld minutes", "4": "Rechercher des recettes"}}"#)

    static func translateUser(_ batch: [(id: String, item: Translator.Item)], app: String, into language: Language, from source: Language,
                              problems: [String: String]) -> String {
        var parts: [String] = []
        if problems.isEmpty {
            parts.append("The app is \(app). Translate these \(batch.count) texts from \(source.name) into \(language.spoken).")
        } else {
            parts.append("The app is \(app). These \(batch.count) texts from \(source.name) into \(language.spoken) came back wrong; translate them again.")
        }
        parts.append("Texts, by id:\n" + json(batch.map { ($0.id, $0.item.text) }))
        let contexts = batch.compactMap { pair in pair.item.context.map { "\(pair.id): \($0)" } }
        if !contexts.isEmpty { parts.append("What each one is:\n" + contexts.joined(separator: "\n")) }
        if !problems.isEmpty {
            parts.append("What was wrong:\n" + batch.compactMap { pair in problems[pair.id].map { "\(pair.id): \($0)." } }.joined(separator: "\n"))
        }
        parts.append("Answer {\"translations\": {…}} with every id: \(batch.map(\.id).joined(separator: ", ")).")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Writing the source text of keys in capitals

    static func sourceSystem(_ source: Language) -> String {
        """
        You write the \(source.name) an app's interface shows for keys its code names in capitals. You answer with one JSON object, {"translations": {"<id>": "<text>"}}: every id you are given, each with the words a person reads on screen, and nothing else.

        How the text reads:
        - The key says what the text is; write what an app says there, in plain \(source.name): short, sentence case, a title in title case.
        - Every format specifier in the key stays in the text, as written: "%@ RECIPE_SERVINGS" is "%@ servings".
        - No capitals and underscores in the answer, and no quotes around it.

        An example from a recipe app:
        {"1": "PANTRY_TITLE", "2": "RECIPE_SAVE_BUTTON", "3": "%@ RECIPE_SERVINGS", "4": "RECIPES_EMPTY"}
        answers
        {"translations": {"1": "Pantry", "2": "Save recipe", "3": "%@ servings", "4": "No recipes yet"}}
        """
    }

    static func sourceUser(_ batch: [(id: String, item: Translator.Item)], app: String, source: Language, problems: [String: String]) -> String {
        var parts: [String] = []
        parts.append(problems.isEmpty ? "The app is \(app). Write the \(source.name) for these \(batch.count) keys."
                                      : "The app is \(app). These \(batch.count) keys came back wrong; write their \(source.name) again.")
        parts.append("Keys, by id:\n" + json(batch.map { ($0.id, $0.item.text) }))
        let contexts = batch.compactMap { pair in pair.item.context.map { "\(pair.id): \($0)" } }
        if !contexts.isEmpty { parts.append("Where each one is used:\n" + contexts.joined(separator: "\n")) }
        if !problems.isEmpty {
            parts.append("What was wrong:\n" + batch.compactMap { pair in problems[pair.id].map { "\(pair.id): \($0)." } }.joined(separator: "\n"))
        }
        parts.append("Answer {\"translations\": {…}} with every id: \(batch.map(\.id).joined(separator: ", ")).")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Shapes

    /// `{"translations": {"1": string, …}}`, every id required.
    static func schema(ids: [String]) -> Data {
        let text: [String: Any] = ["type": "string"]
        let translations: [String: Any] = ["type": "object", "required": ids, "additionalProperties": false,
                                           "properties": Dictionary(uniqueKeysWithValues: ids.map { ($0, text) })]
        let answer: [String: Any] = ["type": "object", "required": ["translations"], "properties": ["translations": translations]]
        return (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// `{"1": "Save", "2": "%lld recipes"}`, in id order.
    static func json(_ pairs: [(String, String)]) -> String {
        "{" + pairs.map { "\(StringsFolder.quote($0.0)): \(StringsFolder.quote($0.1))" }.joined(separator: ", ") + "}"
    }
}
