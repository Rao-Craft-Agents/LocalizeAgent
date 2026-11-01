//  WHAT: One token of Swift source as the harvest reads it: a name, a number, a piece of punctuation or an operator,
//        or a string literal, with the line it starts on.

import Foundation

struct SwiftToken: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// An identifier or keyword (`Text`, `return`, `#Preview`), a backticked name without its backticks.
        case word(String)
        case number(String)
        /// `(` `)` `[` `]` `{` `}` `,` `:` `;` `.`, or an operator run (`?`, `=`, `->`, `==`, `??`).
        case symbol(String)
        case string(SwiftLiteral)
    }

    var kind: Kind
    var line: Int

    var word: String? { if case .word(let word) = kind { return word } else { return nil } }
    var symbol: String? { if case .symbol(let symbol) = kind { return symbol } else { return nil } }
    var literal: SwiftLiteral? { if case .string(let literal) = kind { return literal } else { return nil } }

    func isSymbol(_ text: String) -> Bool { symbol == text }
    func isWord(_ text: String) -> Bool { word == text }
}
