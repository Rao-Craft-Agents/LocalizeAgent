//  WHAT: One language's texts asked of the host's model, a batch at a time, every answer checked; what fails is asked
//        again with the reason, up to the call's rounds. Also the source text for keys in capitals, asked the same way.
//  PIN:  NARROW ASKS. A batch is at most 40 texts and about 2,400 characters of source, its answer budgeted for a
//        local model (~50 tokens a second): long enough for the texts, never a file. Each ask is a fresh session, so a
//        retry carries the texts again with what was wrong with each.

import Foundation
import GraniteAgents

struct Translator: Sendable {
    struct Item: Equatable, Sendable {
        var key: String
        /// What is asked: the source text to translate, or the key to write the source text of.
        var text: String
        /// What it is and where, said beside its id.
        var context: String?
    }

    struct Outcome: Equatable, Sendable {
        /// Key → the checked text.
        var done: [String: String] = [:]
        /// Key → why its last answer could not be used.
        var failed: [String: String] = [:]
    }

    let model: any AgentHostModel
    let rounds: Int
    let app: String
    let note: @Sendable (String) -> Void

    static let batchSize = 40
    static let batchCharacters = 2_400

    /// `items` cut into batches of at most `batchSize` texts and about `batchCharacters` characters.
    static func batches(_ items: [Item]) -> [[Item]] {
        var batches: [[Item]] = [], current: [Item] = [], characters = 0
        for item in items {
            if !current.isEmpty, current.count >= batchSize || characters + item.text.count > batchCharacters {
                batches.append(current); current = []; characters = 0
            }
            current.append(item)
            characters += item.text.count
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    func translate(_ items: [Item], into language: Language, from source: Language) async throws -> Outcome {
        let system = TranslationPrompt.translateSystem(into: language, from: source)
        return try await ask(items, label: language.code, system: system) { batch, problems in
            TranslationPrompt.translateUser(batch, app: app, into: language, from: source, problems: problems)
        } check: { answer, item in
            TranslationCheck.translation(answer, of: item.text, into: language, from: source)
        }
    }

    func writeSource(_ items: [Item], in source: Language) async throws -> Outcome {
        try await ask(items, label: source.code, system: TranslationPrompt.sourceSystem(source)) { batch, problems in
            TranslationPrompt.sourceUser(batch, app: app, source: source, problems: problems)
        } check: { answer, item in
            TranslationCheck.sourceText(answer, forKey: item.text)
        }
    }

    private func ask(_ items: [Item], label: String, system: String,
                     user: ([(id: String, item: Item)], [String: String]) -> String,
                     check: (String, Item) -> TranslationCheck.Verdict) async throws -> Outcome {
        var outcome = Outcome()
        let batches = Self.batches(items)
        for (number, batch) in batches.enumerated() {
            let named = batch.enumerated().map { (id: String($0.offset + 1), item: $0.element) }
            var pending = named
            var problems: [String: String] = [:]
            for round in 1...rounds {
                try Task.checkCancellation()
                let asked = user(pending, round == 1 ? [:] : problems)
                let budget = 256 + pending.reduce(0) { $0 + 24 + $1.item.text.count * 3 / 2 }
                let maxTokens = min(budget, 8_000)
                var answers: [String: String]?
                do {
                    let data = try await model.object(schema: TranslationPrompt.schema(ids: pending.map(\.id)), system: system, user: asked,
                                                      maxTokens: maxTokens, seconds: 60 + Double(maxTokens) / 25)
                    answers = TranslationAnswer.decode(data)
                    if answers == nil { for pair in pending { problems[pair.id] = "the answer was not the JSON object asked for" } }
                } catch {
                    if error is CancellationError || Task.isCancelled { throw CancellationError() }
                    for pair in pending { problems[pair.id] = "no answer came back (\(error))" }
                }
                if let answers {
                    var still: [(id: String, item: Item)] = []
                    for pair in pending {
                        guard let answer = answers[pair.id] ?? answers[pair.item.text] else {
                            problems[pair.id] = "it was missing from the answer"
                            still.append(pair)
                            continue
                        }
                        switch check(answer, pair.item) {
                        case .good(let text): outcome.done[pair.item.key] = text; problems[pair.id] = nil
                        case .bad(let why): problems[pair.id] = why; still.append(pair)
                        }
                    }
                    pending = still
                }
                if pending.isEmpty { break }
                if round < rounds, let first = pending.first, let why = problems[first.id] {
                    let place = batches.count > 1 ? " (batch \(number + 1) of \(batches.count))" : ""
                    note("\(label)\(place): asking again for \(pending.count): \(first.item.text.prefix(40)) — \(why)")
                }
            }
            for pair in pending { outcome.failed[pair.item.key] = problems[pair.id] ?? "no answer came back" }
        }
        return outcome
    }
}
