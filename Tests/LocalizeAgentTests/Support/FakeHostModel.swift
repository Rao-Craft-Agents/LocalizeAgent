import Foundation
import GraniteAgents

/// A host model that answers the next of its scripted replies to each ask (the last one again when it runs out), or,
/// past them, what `answer` makes of the ask; it keeps what it was asked.
final class FakeHostModel: AgentHostModel, @unchecked Sendable {
    struct Ask { let schema: Data; let system: String; let user: String }

    private let lock = NSLock()
    private var replies: [Data]
    private let answer: (@Sendable (Ask) -> Data)?
    private var kept: [Ask] = []

    init(_ replies: [Data] = [], answer: (@Sendable (Ask) -> Data)? = nil) {
        self.replies = replies
        self.answer = answer
    }

    var asked: [Ask] { lock.withLock { kept } }

    func object(schema: Data, system: String, user: String, maxTokens: Int, seconds: Double) async throws -> Data {
        let ask = Ask(schema: schema, system: system, user: user)
        let scripted: Data? = lock.withLock {
            kept.append(ask)
            if replies.count > 1 || (replies.count == 1 && answer != nil) { return replies.removeFirst() }
            return replies.first
        }
        if let scripted { return scripted }
        if let answer { return answer(ask) }
        throw AgentHostError.noAnswer("no reply scripted")
    }

    func text(system: String, user: String, maxTokens: Int, seconds: Double) async throws -> String { "" }
}
