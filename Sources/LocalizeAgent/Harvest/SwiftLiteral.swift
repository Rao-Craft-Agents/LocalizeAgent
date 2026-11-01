//  WHAT: A string literal as written: its text, escapes decoded, and the source of each interpolation in order.

import Foundation

struct SwiftLiteral: Equatable, Sendable {
    enum Piece: Equatable, Sendable {
        case text(String)
        /// What stands between `\(` and its `)`, as written.
        case interpolation(String)
    }

    var pieces: [Piece]

    var isInterpolated: Bool { pieces.contains { if case .interpolation = $0 { return true } else { return false } } }

    /// The text, when nothing is interpolated.
    var plain: String? {
        guard !isInterpolated else { return nil }
        return pieces.map { if case .text(let text) = $0 { return text } else { return "" } }.joined()
    }

    /// Each interpolation's source, in order.
    var interpolations: [String] { pieces.compactMap { if case .interpolation(let source) = $0 { return source } else { return nil } } }
}
