import Foundation

/// What a run says as it goes.
public enum LocalizeFrame: Sendable {
    /// The Swift was read: how many distinct strings, in how many files.
    case harvested(strings: Int, files: Int)
    /// One language's texts came back: how many were checked good, how many stayed in the source language.
    case translated(language: String, strings: Int, failed: Int)
    /// The files are written.
    case written(LocalizeResult)

    public var result: LocalizeResult? {
        if case .written(let result) = self { return result }
        return nil
    }
}
