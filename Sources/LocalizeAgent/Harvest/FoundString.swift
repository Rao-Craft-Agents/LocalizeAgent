//  WHAT: One localizable string the Swift asks for, where it was found and what it is.

import Foundation

struct FoundString: Equatable, Sendable {
    /// The key as the runtime asks for it: `%lld recipes`.
    var key: String
    /// The source text the call gives beside its key (`defaultValue:`, `value:`), when it gives one.
    var value: String?
    /// The comment the call gives, when it gives one.
    var comment: String?
    /// What it is on screen, said to the model: "a button", "a screen title".
    var role: String
    /// The file it is in, relative to the project, and its line.
    var file: String
    var line: Int
}
