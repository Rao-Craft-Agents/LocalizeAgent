//  WHAT: A model's answer read as texts by id: `{"translations": {"1": "…"}}`, or the bare object a model sometimes
//        answers instead. Anything that is not a string is no answer for its id.

import Foundation

enum TranslationAnswer {
    static func decode(_ data: Data) -> [String: String]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let inner = object["translations"] as? [String: Any] ?? object
        var answers: [String: String] = [:]
        for (id, value) in inner { if let text = value as? String { answers[id] = text } }
        return answers
    }
}
