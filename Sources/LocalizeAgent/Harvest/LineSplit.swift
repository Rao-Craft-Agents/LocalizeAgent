//  WHAT: Splitting source text where a separator stands outside brackets, parentheses and quotes: an interpolation's
//        arguments, an expression's operands.

import Foundation

enum LineSplit {
    /// `text` cut at every `separator` that stands at the top level, each piece trimmed, empty pieces dropped.
    static func top(_ text: String, on separator: Character) -> [String] {
        var pieces: [String] = [], current = "", depth = 0, quoted = false, escaped = false
        for character in text {
            if quoted {
                current.append(character)
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { quoted = false }
                continue
            }
            switch character {
            case "\"": quoted = true; current.append(character)
            case "[", "(", "{": depth += 1; current.append(character)
            case "]", ")", "}": depth = max(0, depth - 1); current.append(character)
            case separator where depth == 0:
                pieces.append(current); current = ""
            default: current.append(character)
            }
        }
        pieces.append(current)
        return pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Whether the parenthesis that opens `text` is the one that closes it: `(a + b)`, not `(a) + (b)`.
    static func closes(_ text: String) -> Bool {
        var depth = 0
        for (offset, character) in text.enumerated() {
            if character == "(" { depth += 1 } else if character == ")" { depth -= 1; if depth == 0 { return offset == text.count - 1 } }
        }
        return false
    }

    /// The first `character` standing alone at the top level (not part of `??`, `?.`, `!=` or `->`).
    static func firstTopOperator(_ text: String, _ character: Character) -> String.Index? {
        var depth = 0, quoted = false
        let characters = Array(text)
        var index = text.startIndex
        for offset in characters.indices {
            let c = characters[offset]
            defer { index = text.index(after: index) }
            if c == "\"" { quoted.toggle(); continue }
            if quoted { continue }
            if "[({".contains(c) { depth += 1; continue }
            if "])}".contains(c) { depth = max(0, depth - 1); continue }
            guard depth == 0, c == character else { continue }
            let before = offset > 0 ? characters[offset - 1] : " ", after = offset + 1 < characters.count ? characters[offset + 1] : " "
            if character == "?", before != " " || after == "?" || after == "." { continue }
            if character == ":", before == ":" || after == ":" { continue }
            return index
        }
        return nil
    }

    /// The operands of a top-level `+ - * / %` expression; the whole text when there is no such operator.
    static func topOperands(_ text: String) -> [String] {
        var operands: [String] = [], current = "", depth = 0, quoted = false
        let characters = Array(text)
        for (offset, c) in characters.enumerated() {
            if c == "\"" { quoted.toggle() }
            if !quoted {
                if "[({".contains(c) { depth += 1 } else if "])}".contains(c) { depth = max(0, depth - 1) }
                let before = offset > 0 ? characters[offset - 1] : " ", after = offset + 1 < characters.count ? characters[offset + 1] : " "
                // A binary operator stands between spaces: `a + 1`, never `-1` or `a?.b`.
                if depth == 0, "+-*/%".contains(c), before == " ", after == " " {
                    operands.append(current.trimmingCharacters(in: .whitespaces)); current = ""; continue
                }
            }
            current.append(c)
        }
        operands.append(current.trimmingCharacters(in: .whitespaces))
        return operands.filter { !$0.isEmpty }
    }
}
