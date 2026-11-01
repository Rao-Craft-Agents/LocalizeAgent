//  WHAT: Swift source read into the tokens the harvest needs: names, numbers, punctuation, operators and string
//        literals (their text with escapes decoded, each interpolation's source kept), comments dropped. Beside the
//        tokens, the source with every comment and literal blanked: what declarations are read from.
//  PIN:  A LEXER, NOT A PARSER. Strings, comments and brackets are read exactly (raw strings, multi-line strings,
//        nested interpolations, nested comments); everything else is only told apart well enough to see the calls
//        around a literal. The compiler checks the rest when the app builds.

import Foundation

struct SwiftScanner {
    /// The tokens of one file, and its source with comments and literals blanked (lines kept).
    struct Scan: Sendable {
        var tokens: [SwiftToken]
        var code: String
    }

    private let source: [Unicode.Scalar]
    private var blanked: [Unicode.Scalar]
    private var index = 0
    private var line = 1
    private var tokens: [SwiftToken] = []

    private init(_ text: String) {
        source = Array(text.unicodeScalars)
        blanked = source
    }

    static func scan(_ text: String) -> Scan {
        var scanner = SwiftScanner(text)
        scanner.run()
        var code = String.UnicodeScalarView()
        code.append(contentsOf: scanner.blanked)
        return Scan(tokens: scanner.tokens, code: String(code))
    }

    private func at(_ offset: Int) -> Unicode.Scalar? {
        let position = index + offset
        return position < source.count ? source[position] : nil
    }

    private mutating func blank(from start: Int, to end: Int) {
        for position in start..<min(end, blanked.count) where blanked[position] != "\n" { blanked[position] = " " }
    }

    private mutating func run() {
        while index < source.count {
            let c = source[index]
            if c == "\n" { line += 1; index += 1; continue }
            if c.properties.isWhitespace { index += 1; continue }
            if c == "/", at(1) == "/" { lineComment(); continue }
            if c == "/", at(1) == "*" { blockComment(); continue }
            if c == "\"" || (c == "#" && opensRawString()) { string(); continue }
            if Self.isIdentifierStart(c) { word(); continue }
            if c == "#", let next = at(1), Self.isIdentifierStart(next) { index += 1; word(prefix: "#"); continue }
            if c == "`" { backticked(); continue }
            if c == "$", let next = at(1), Self.isIdentifierStart(next) || next.properties.numericType != nil { index += 1; word(prefix: "$"); continue }
            if c.properties.numericType != nil, c.isASCII { number(); continue }
            if "()[]{},:;@\\".unicodeScalars.contains(c) { tokens.append(SwiftToken(kind: .symbol(String(c)), line: line)); index += 1; continue }
            if c == "." {
                if at(1) == "." { operatorRun(); continue }
                tokens.append(SwiftToken(kind: .symbol("."), line: line)); index += 1; continue
            }
            if Self.operatorScalars.contains(c) { operatorRun(); continue }
            index += 1
        }
    }

    private static let operatorScalars = Set("/=-+!*%<>&|^~?".unicodeScalars)

    static func isIdentifierStart(_ c: Unicode.Scalar) -> Bool {
        c == "_" || c.properties.isAlphabetic
    }

    static func isIdentifierPart(_ c: Unicode.Scalar) -> Bool {
        isIdentifierStart(c) || c.properties.numericType != nil || c.properties.generalCategory == .nonspacingMark
    }

    private mutating func lineComment() {
        let start = index
        while index < source.count, source[index] != "\n" { index += 1 }
        blank(from: start, to: index)
    }

    private mutating func blockComment() {
        let start = index
        var depth = 0
        while index < source.count {
            if source[index] == "/", at(1) == "*" { depth += 1; index += 2; continue }
            if source[index] == "*", at(1) == "/" { depth -= 1; index += 2; if depth == 0 { break }; continue }
            if source[index] == "\n" { line += 1 }
            index += 1
        }
        blank(from: start, to: index)
    }

    private mutating func word(prefix: String = "") {
        var text = prefix
        while index < source.count, Self.isIdentifierPart(source[index]) { text.unicodeScalars.append(source[index]); index += 1 }
        tokens.append(SwiftToken(kind: .word(text), line: line))
    }

    private mutating func backticked() {
        index += 1
        var text = ""
        while index < source.count, source[index] != "`", source[index] != "\n" { text.unicodeScalars.append(source[index]); index += 1 }
        if index < source.count, source[index] == "`" { index += 1 }
        tokens.append(SwiftToken(kind: .word(text), line: line))
    }

    private mutating func number() {
        var text = ""
        while index < source.count {
            let c = source[index]
            if c == ".", let next = at(1), next.isASCII, next.properties.numericType != nil { text.unicodeScalars.append(c); index += 1; continue }
            guard c.isASCII, c.properties.isAlphabetic || c.properties.numericType != nil || c == "_" else { break }
            text.unicodeScalars.append(c)
            index += 1
        }
        tokens.append(SwiftToken(kind: .number(text), line: line))
    }

    private mutating func operatorRun() {
        var text = ""
        let dots = source[index] == "."
        while index < source.count {
            let c = source[index]
            if dots ? (c == "." || c == "<") : Self.operatorScalars.contains(c) {
                // A comment opens a comment, never an operator.
                if c == "/", let next = at(1), next == "/" || next == "*" { break }
                text.unicodeScalars.append(c)
                index += 1
            } else { break }
        }
        if text.isEmpty { index += 1; return }
        tokens.append(SwiftToken(kind: .symbol(text), line: line))
    }

    private func opensRawString() -> Bool { Self.startsLiteral(source, at: index) }

    private mutating func string() {
        let start = index, startLine = line
        let read = Self.literal(in: source, at: index)
        for position in start..<min(read.end, source.count) where source[position] == "\n" { line += 1 }
        blank(from: start, to: read.end)
        index = read.end
        tokens.append(SwiftToken(kind: .string(read.literal), line: startLine))
    }

    // MARK: - Literals

    /// The literal that opens at `start` (its `#`s or first quote), and where it ends.
    static func literal(in source: [Unicode.Scalar], at start: Int) -> (literal: SwiftLiteral, end: Int) {
        var position = start, hashes = 0
        while position < source.count, source[position] == "#" { hashes += 1; position += 1 }
        let multiline = position + 2 < source.count && source[position + 1] == "\"" && source[position + 2] == "\""
        if multiline, let read = multilineLiteral(in: source, from: position + 3, hashes: hashes) { return read }
        return singleLine(in: source, from: position + 1, hashes: hashes)
    }

    private static func closes(_ source: [Unicode.Scalar], at position: Int, hashes: Int) -> Bool {
        guard position < source.count, source[position] == "\"" else { return false }
        for offset in 0..<hashes where position + 1 + offset >= source.count || source[position + 1 + offset] != "#" { return false }
        return true
    }

    /// Whether a backslash at `position` starts an escape (in a raw string, only one followed by its `#`s does).
    private static func escapes(_ source: [Unicode.Scalar], at position: Int, hashes: Int) -> Bool {
        guard position < source.count, source[position] == "\\" else { return false }
        for offset in 0..<hashes where position + 1 + offset >= source.count || source[position + 1 + offset] != "#" { return false }
        return true
    }

    private static func singleLine(in source: [Unicode.Scalar], from begin: Int, hashes: Int) -> (literal: SwiftLiteral, end: Int) {
        var decoder = Decoder()
        var position = begin
        while position < source.count {
            if closes(source, at: position, hashes: hashes) { return (decoder.finish(), position + 1 + hashes) }
            if source[position] == "\n" { return (decoder.finish(), position) }
            if escapes(source, at: position, hashes: hashes) {
                position = decoder.escape(in: source, at: position + 1 + hashes, multiline: false)
                continue
            }
            decoder.append(source[position])
            position += 1
        }
        return (decoder.finish(), position)
    }

    /// A `"""` literal: its lines with the closing delimiter's indentation taken off each, escapes decoded.
    private static func multilineLiteral(in source: [Unicode.Scalar], from begin: Int, hashes: Int) -> (literal: SwiftLiteral, end: Int)? {
        // The content starts on the line after the opening delimiter.
        var position = begin
        while position < source.count, source[position] != "\n" { position += 1 }
        guard position < source.count else { return nil }
        position += 1
        var lines: [[Unicode.Scalar]] = [], current: [Unicode.Scalar] = []
        var closing: (indent: Int, end: Int)?
        var depth = 0
        while position < source.count {
            let c = source[position]
            // Inside an interpolation, a quote is another literal's; skip it whole.
            if depth > 0, startsLiteral(source, at: position) {
                let nested = literal(in: source, at: position)
                current += source[position..<nested.end]
                position = nested.end
                continue
            }
            if escapes(source, at: position, hashes: hashes), position + 1 + hashes < source.count, source[position + 1 + hashes] == "(" {
                current += source[position...(position + 1 + hashes)]
                position += 2 + hashes
                depth += 1
                continue
            }
            if depth > 0 {
                if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
                current.append(c); position += 1; continue
            }
            if c == "\n" { lines.append(current); current = []; position += 1; continue }
            if c == "\"", position + 2 < source.count, source[position + 1] == "\"", source[position + 2] == "\"",
               current.allSatisfy({ $0 == " " || $0 == "\t" }), closes(source, at: position + 2, hashes: hashes) {
                closing = (current.count, position + 3 + hashes)
                break
            }
            current.append(c)
            position += 1
        }
        guard let closing else { return nil }
        var decoder = Decoder()
        for (number, raw) in lines.enumerated() {
            let content = Array(raw.dropFirst(min(closing.indent, raw.prefix { $0 == " " || $0 == "\t" }.count)))
            var cursor = 0
            var continued = false
            while cursor < content.count {
                if escapes(content, at: cursor, hashes: hashes) {
                    let after = cursor + 1 + hashes
                    // A backslash that ends the line joins it to the next.
                    if content[after...].allSatisfy({ $0 == " " || $0 == "\t" }) { continued = true; break }
                    cursor = decoder.escape(in: content, at: after, multiline: true)
                    continue
                }
                decoder.append(content[cursor])
                cursor += 1
            }
            if number < lines.count - 1, !continued { decoder.append("\n") }
        }
        return (decoder.finish(), closing.end)
    }

    /// Text gathered piece by piece: escapes decoded, interpolations kept as their source.
    private struct Decoder {
        var pieces: [SwiftLiteral.Piece] = []
        var text = String.UnicodeScalarView()

        mutating func append(_ c: Unicode.Scalar) { text.append(c) }

        mutating func finish() -> SwiftLiteral {
            if !text.isEmpty || pieces.isEmpty { pieces.append(.text(String(text))) }
            text = String.UnicodeScalarView()
            // Adjacent text pieces read as one; an empty text between two interpolations is dropped.
            var merged: [SwiftLiteral.Piece] = []
            for piece in pieces {
                if case .text(let next) = piece, case .text(let previous)? = merged.last { merged[merged.count - 1] = .text(previous + next); continue }
                if case .text(let next) = piece, next.isEmpty, !merged.isEmpty { continue }
                merged.append(piece)
            }
            if merged.count > 1, case .text(let first) = merged[0], first.isEmpty { merged.removeFirst() }
            return SwiftLiteral(pieces: merged)
        }

        /// Decodes the escape whose letter is at `position`; answers where reading goes on.
        mutating func escape(in source: [Unicode.Scalar], at position: Int, multiline: Bool) -> Int {
            guard position < source.count else { return position }
            switch source[position] {
            case "n": text.append("\n")
            case "t": text.append("\t")
            case "r": text.append("\r")
            case "0": text.append("\0")
            case "\\": text.append("\\")
            case "\"": text.append("\"")
            case "'": text.append("'")
            case "u":
                var cursor = position + 1
                guard cursor < source.count, source[cursor] == "{" else { return position + 1 }
                cursor += 1
                var hex = ""
                while cursor < source.count, source[cursor] != "}" { hex.unicodeScalars.append(source[cursor]); cursor += 1 }
                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) { text.append(scalar) }
                return cursor + 1
            case "(":
                let end = SwiftScanner.closingParenthesis(in: source, from: position + 1)
                let inner = String(String.UnicodeScalarView(source[(position + 1)..<min(end, source.count)]))
                pieces.append(.text(String(text)))
                text = String.UnicodeScalarView()
                pieces.append(.interpolation(inner))
                return end + 1
            default: text.append(source[position])
            }
            return position + 1
        }
    }

    /// Whether a literal opens at `position`: a quote, or `#`s and then a quote.
    static func startsLiteral(_ source: [Unicode.Scalar], at position: Int) -> Bool {
        var cursor = position
        while cursor < source.count, source[cursor] == "#" { cursor += 1 }
        return cursor < source.count && source[cursor] == "\""
    }

    /// The index of the `)` that closes a parenthesis opened just before `start`, skipping nested literals.
    static func closingParenthesis(in source: [Unicode.Scalar], from start: Int) -> Int {
        var depth = 1, position = start
        while position < source.count {
            let c = source[position]
            if startsLiteral(source, at: position) {
                position = literal(in: source, at: position).end
                continue
            }
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1; if depth == 0 { return position } }
            position += 1
        }
        return position
    }
}
