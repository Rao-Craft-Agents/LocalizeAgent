import Foundation

/// What a call can say instead of writing.
public enum LocalizeError: Error, Equatable, CustomStringConvertible {
    /// What the call asks that cannot be done, a sentence a problem: every one at once, so all are fixed in one call.
    case refused([String])
    /// A call that finds nothing to localize.
    case nothing(String)
    /// A file that cannot be read, or one the call made that does not read back as written.
    case unreadable(String)

    public var description: String {
        switch self {
        case .refused(let reasons):
            return reasons.count == 1 ? "nothing was written: \(reasons[0])"
                : "\(reasons.count) things in the call cannot be done, so nothing was written:\n" + reasons.map { "- \($0)" }.joined(separator: "\n")
        case .nothing(let reason): return "nothing to localize: \(reason)"
        case .unreadable(let reason): return "nothing was written: \(reason)"
        }
    }
}
