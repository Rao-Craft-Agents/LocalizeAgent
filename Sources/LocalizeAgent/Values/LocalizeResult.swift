import Foundation
import GraniteAgents

/// What a call answers: the files written, as absolute paths, and where the app's languages stand.
public struct LocalizeResult: AgentAnswer, Equatable {
    /// The first file written.
    public var path: String?
    /// Every file written: a table a language (or the catalog), the project file, the helper. A file that came out the
    /// same is not written and not named.
    public var paths: [String]
    /// The language the strings are written in.
    public var source: String
    /// Every language the app now has, the source first.
    public var languages: [String]
    /// The strings the app has in its source language.
    public var strings: Int
    /// The localizable strings the Swift asks for.
    public var found: Int
    /// Strings new to the app with this call.
    public var added: Int
    /// Texts the model wrote and the checks passed, every language together.
    public var translated: Int
    /// Languages with strings still shown in the source language: no model, or answers that failed every round.
    public var waiting: [String]
    /// One sentence each: what was left out, kept or changed, and why.
    public var notes: [String]

    public init(path: String?, paths: [String], source: String, languages: [String], strings: Int, found: Int, added: Int,
                translated: Int, waiting: [String], notes: [String]) {
        self.path = path; self.paths = paths; self.source = source; self.languages = languages; self.strings = strings
        self.found = found; self.added = added; self.translated = translated; self.waiting = waiting; self.notes = notes
    }
}
