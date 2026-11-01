//  WHAT: The format specifiers of a text (`%@`, `%lld`, `%1$@`, `%.1f`), told apart from a doubled `%%`: what every
//        translation must keep, each at its position, and the numbered form a source text takes when it has several.
//  PIN:  A TRANSLATION KEEPS EVERY ARGUMENT, OF ITS TYPE. The runtime fills a text's specifiers with the key's
//        arguments in order (or by number); a missing one drops a value, and one of another type (`%@` for an `Int`)
//        crashes. Numbered specifiers may move where another language's word order needs them; their numbers stay.

import Foundation

enum FormatSpecifiers {
    struct Specifier: Equatable, Sendable {
        /// The number of a numbered specifier (`%2$@` is 2); nil for one taken in order.
        var position: Int?
        /// Everything after the `%` and the number: `@`, `lld`, `.1f`.
        var body: String
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"%%|%(?:([1-9][0-9]*)\$)?([-+#0']*(?:[0-9]+|\*)?(?:\.(?:[0-9]+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGaAcCsSp])"#)

    static func parse(_ text: String) -> [Specifier] {
        let string = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: string.length)).compactMap { match in
            guard match.range(at: 2).location != NSNotFound else { return nil }
            let position = match.range(at: 1).location == NSNotFound ? nil : Int(string.substring(with: match.range(at: 1)))
            return Specifier(position: position, body: string.substring(with: match.range(at: 2)))
        }
    }

    /// Each argument's specifier by its position (taken-in-order ones numbered in order); nil when a text mixes
    /// numbered and unnumbered specifiers, or gives one position two types.
    static func signature(_ text: String) -> [Int: String]? {
        let found = parse(text)
        let numbered = found.filter { $0.position != nil }
        if !numbered.isEmpty, numbered.count != found.count { return nil }
        var signature: [Int: String] = [:]
        for (index, specifier) in found.enumerated() {
            let position = specifier.position ?? index + 1
            if let earlier = signature[position], earlier != specifier.body { return nil }
            signature[position] = specifier.body
        }
        return signature
    }

    /// The specifiers written as a person reads them: `%1$@, %2$lld`.
    static func listed(_ signature: [Int: String]) -> String {
        signature.keys.sorted().map { signature.count > 1 ? "%\($0)$\(signature[$0]!)" : "%\(signature[$0]!)" }.joined(separator: ", ")
    }

    /// The text with its unnumbered specifiers numbered, when it has two or more: `Cooked by %1$@ in %2$lld minutes`.
    static func positional(_ text: String) -> String {
        let found = parse(text)
        guard found.count >= 2, found.allSatisfy({ $0.position == nil }) else { return text }
        let string = text as NSString
        var result = "", cursor = 0, number = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            result += string.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if match.range(at: 2).location == NSNotFound {
                result += "%%"
            } else {
                number += 1
                result += "%\(number)$" + string.substring(with: match.range(at: 2))
            }
            cursor = match.range.location + match.range.length
        }
        return result + string.substring(from: cursor)
    }

    /// The text with every specifier and `%%` taken out.
    static func removing(from text: String) -> String {
        let string = text as NSString
        return pattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: string.length), withTemplate: " ")
    }
}
