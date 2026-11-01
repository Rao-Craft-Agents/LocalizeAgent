//  WHAT: The localizable strings of one Swift file: each literal SwiftUI or Foundation reads as a localized key, with
//        the key as the runtime asks for it, the comment its call gives, its source text when the call gives one,
//        and what it is on screen.
//  PIN:  THE KEY IS THE RUNTIME'S. `Text("\(count) recipes")` asks the table for `%lld recipes`, a `%` beside an
//        interpolation is doubled, and a key written any other way is never found: the app shows the source text.
//  PIN:  READ AS A KEY: a literal that is the whole first argument of a view or modifier that takes one (or a branch of
//        a ternary that is), `String(localized:)`, `LocalizedStringResource`, `LocalizedStringKey`,
//        `NSLocalizedString`, `"KEY".localized(…)`, a literal given to a property or parameter the project declares
//        as a key, and a literal a computed key returns. NOT A KEY: `Text(verbatim:)`, a literal built into a `String`
//        (`Text("a" + b)`), another table's string, a string with no letters (`"•"`, `"\(name)"`: every language shows
//        it as it is), and a preview's sample text.

import Foundation

struct Harvester {
    let declarations: SwiftDeclarations

    func strings(in scan: SwiftScanner.Scan, file: String, lineOffset: Int = 0) -> [FoundString] {
        let tokens = scan.tokens
        let shape = Shape(tokens)
        var found: [FoundString] = []
        for index in tokens.indices {
            guard let literal = tokens[index].literal, !shape.skipped(index) else { continue }
            if let hit = classify(index, tokens: tokens, shape: shape, file: file) {
                let key = Self.key(literal, file: file, declarations: declarations) + hit.suffix
                if Self.hasLetters(key) {
                    found.append(FoundString(key: key, value: hit.value, comment: hit.comment, role: hit.role, file: file,
                                             line: tokens[index].line + lineOffset))
                }
            }
            // A literal inside an interpolation is read as any other: `Text("Tap \(Text("here").bold())")`.
            for source in literal.interpolations where source.contains("\"") {
                found += strings(in: SwiftScanner.scan(source), file: file, lineOffset: tokens[index].line - 1 + lineOffset)
            }
        }
        return found
    }

    // MARK: - Keys

    /// The key a literal is looked up by: its text, each interpolation its specifier, `%` doubled beside them.
    static func key(_ literal: SwiftLiteral, file: String, declarations: SwiftDeclarations) -> String {
        guard literal.isInterpolated else { return literal.plain ?? "" }
        return literal.pieces.map { piece -> String in
            switch piece {
            case .text(let text): return text.replacingOccurrences(of: "%", with: "%%")
            case .interpolation(let source): return InterpolationSpecifier.specifier(source, file: file, declarations: declarations)
            }
        }.joined()
    }

    /// Whether a key says anything a language would say differently: a letter outside its specifiers.
    static func hasLetters(_ key: String) -> Bool {
        FormatSpecifiers.removing(from: key).unicodeScalars.contains { $0.properties.isAlphabetic }
    }

    // MARK: - What a literal is

    private struct Hit { var role: String; var comment: String?; var value: String?; var suffix = "" }

    private func classify(_ index: Int, tokens: [SwiftToken], shape: Shape, file: String) -> Hit? {
        let literal = tokens[index].literal!
        // "KEY".localized(…): the project's own helper, a key read with ` %@` after it when `formatted`.
        if index + 2 < tokens.count, tokens[index + 1].isSymbol("."), tokens[index + 2].isWord("localized"), !literal.isInterpolated {
            var hit = Hit(role: "text", comment: nil, value: nil)
            if index + 3 < tokens.count, tokens[index + 3].isSymbol("("),
               shape.arguments(index + 3, tokens: tokens).contains(where: { $0.label == "formatted" && $0.value.count == 1 && tokens[$0.value.lowerBound].isWord("true") }) {
                hit.suffix = " %@"
            }
            return hit
        }
        // `let title: LocalizedStringKey = "Recipes"`, and a parameter's default.
        if index >= 3, tokens[index - 1].isSymbol("=") {
            var type = index - 2
            if tokens[type].isSymbol("?") { type -= 1 }
            if type >= 1, let word = tokens[type].word, SwiftDeclarations.localizedTypes.contains(word),
               tokens[type - 1].isSymbol(":") || (type >= 3 && tokens[type - 1].isSymbol(".") && tokens[type - 2].isWord("String") && tokens[type - 3].isSymbol(":")) {
                return Hit(role: "text", comment: nil, value: nil)
            }
        }
        if let open = shape.parent[index], tokens[open].isSymbol("(") {
            return call(index, open: open, tokens: tokens, shape: shape, file: file)
        }
        if shape.inLocalizedScope(index, tokens: tokens) { return Hit(role: "text", comment: nil, value: nil) }
        return nil
    }

    /// A literal inside a call's parentheses: a key when the call takes one there.
    private func call(_ index: Int, open: Int, tokens: [SwiftToken], shape: Shape, file: String) -> Hit? {
        let arguments = shape.arguments(open, tokens: tokens)
        guard let position = arguments.firstIndex(where: { $0.range.contains(index) }) else { return nil }
        let argument = arguments[position]
        guard Self.isWholeOrBranch(index, argument.value, tokens: tokens) else { return nil }
        guard open >= 1, let callee = tokens[open - 1].word else { return nil }
        let isMember = open >= 2 && tokens[open - 2].isSymbol(".")
        let literal = tokens[index].literal!

        var role: String?
        if let label = argument.label {
            if let named = LocalizableCalls.named[callee]?[label] { role = named }
            else if callee == "init", isMember, !(open >= 3 && (tokens[open - 3].isWord("self") || tokens[open - 3].isWord("super"))) {
                if declarations.initTakesLocalized(label) { role = LocalizableCalls.role(forLabel: label, callee: "an initializer") }
            } else if declarations.localized.contains(.init(callee: callee, label: label)) {
                role = LocalizableCalls.role(forLabel: label, callee: callee)
            }
        } else if position == 0 {
            if callee == "NSLocalizedString" {
                guard !literal.isInterpolated else { return nil }
                role = "text"
            } else if let named = LocalizableCalls.initializers[callee], !isMember || open >= 3 && tokens[open - 3].word?.first?.isUppercase == true {
                role = named
            } else if let named = LocalizableCalls.modifiers[callee], isMember {
                role = named
            } else if declarations.localized.contains(.init(callee: callee, label: "_")) {
                role = LocalizableCalls.role(forLabel: "", callee: callee)
            } else if callee == "init", isMember, let outer = shape.parent[open - 2], outer + 1 == open - 2, tokens[outer].isSymbol("("),
                      outer >= 1, let made = tokens[outer - 1].word {
                // `Text(.init("…"))`: a key made in place, its type the one the call it is given to takes.
                let outerMember = outer >= 2 && tokens[outer - 2].isSymbol(".")
                role = outerMember ? LocalizableCalls.modifiers[made] : LocalizableCalls.initializers[made]
            }
        }
        guard let role else { return nil }

        // The call's other arguments: a comment, another table, another bundle, the source text.
        var hit = Hit(role: role, comment: nil, value: nil)
        for other in arguments where other.label != nil && other.label != argument.label {
            let single = other.value.count == 1 ? tokens[other.value.lowerBound].literal : nil
            switch other.label! {
            case "comment": hit.comment = single?.plain.flatMap { $0.isEmpty ? nil : $0 }
            case "tableName", "table":
                if let table = single?.plain, table != "Localizable" { return nil }
            case "bundle":
                if other.value.contains(where: { tokens[$0].isWord("module") }) { return nil }
            case let label where LocalizableCalls.valueLabels.contains(label):
                if let text = single { hit.value = Self.key(text, file: file, declarations: declarations) }
            default: break
            }
        }
        return hit
    }

    /// Whether the literal at `index` is the whole of `value`, or one whole branch of a ternary that is.
    private static func isWholeOrBranch(_ index: Int, _ value: Range<Int>, tokens: [SwiftToken]) -> Bool {
        if value == index..<(index + 1) { return true }
        guard index > value.lowerBound else { return false }
        let before = tokens[index - 1], after = index + 1 < value.upperBound ? tokens[index + 1] : nil
        if before.isSymbol("?"), after?.isSymbol(":") == true { return true }
        if before.isSymbol(":"), index + 1 == value.upperBound,
           (value.lowerBound..<(index - 1)).contains(where: { tokens[$0].isSymbol("?") }) { return true }
        return false
    }

    // MARK: - The shape of a file

    /// What the harvest reads of a file's structure: which bracket each token stands in, the arguments of a call,
    /// the bodies of computed keys, and what previews hold.
    struct Shape {
        /// The innermost open bracket around each token.
        var parent: [Int?]
        /// Where each opening bracket closes.
        var closing: [Int: Int] = [:]
        /// The `{` of each computed property or function that answers a localized key.
        var scopes: Set<Int> = []
        /// Token ranges of previews.
        var previews: [Range<Int>] = []

        init(_ tokens: [SwiftToken]) {
            parent = Array(repeating: nil, count: tokens.count)
            var stack: [Int] = []
            for (index, token) in tokens.enumerated() {
                parent[index] = stack.last
                if token.isSymbol("(") || token.isSymbol("[") || token.isSymbol("{") {
                    stack.append(index)
                    if token.isSymbol("{"), Self.opensLocalizedScope(index, tokens: tokens) { scopes.insert(index) }
                } else if token.isSymbol(")") || token.isSymbol("]") || token.isSymbol("}") {
                    if let open = stack.popLast() { closing[open] = index }
                    parent[index] = stack.last
                }
            }
            // `#Preview { … }` and a `PreviewProvider`'s body show sample text, not the app's.
            for (index, token) in tokens.enumerated() {
                var brace: Int?
                if token.isWord("#Preview") {
                    var cursor = index + 1
                    if cursor < tokens.count, tokens[cursor].isSymbol("("), let end = closing[cursor] { cursor = end + 1 }
                    if cursor < tokens.count, tokens[cursor].isSymbol("{") { brace = cursor }
                } else if token.isWord("PreviewProvider") {
                    brace = (index..<min(tokens.count, index + 12)).first { tokens[$0].isSymbol("{") }
                }
                if let brace, let end = closing[brace] { previews.append(brace..<(end + 1)) }
            }
        }

        func skipped(_ index: Int) -> Bool { previews.contains { $0.contains(index) } }

        /// `var title: LocalizedStringKey {`, `func label() -> LocalizedStringKey {` (optional or not).
        private static func opensLocalizedScope(_ brace: Int, tokens: [SwiftToken]) -> Bool {
            var type = brace - 1
            if type >= 0, tokens[type].isSymbol("?") { type -= 1 }
            guard type >= 1, let word = tokens[type].word, SwiftDeclarations.localizedTypes.contains(word) else { return false }
            var before = type - 1
            if word == "LocalizationValue", before >= 1, tokens[before].isSymbol("."), tokens[before - 1].isWord("String") { before -= 2 }
            return before >= 0 && (tokens[before].isSymbol(":") || tokens[before].isSymbol("->"))
        }

        /// Whether the literal at `index` is what a computed key returns: inside its body through blocks alone (never
        /// a call's parentheses or a collection's brackets), after `return`, a `{`, a case's colon or a ternary.
        func inLocalizedScope(_ index: Int, tokens: [SwiftToken]) -> Bool {
            guard index >= 1 else { return false }
            let before = tokens[index - 1]
            guard before.isWord("return") || before.isSymbol("{") || before.isSymbol(":") || before.isSymbol("?") else { return false }
            var cursor = parent[index]
            while let open = cursor {
                guard tokens[open].isSymbol("{") else { return false }
                if scopes.contains(open) { return true }
                cursor = parent[open]
            }
            return false
        }

        struct Argument {
            var label: String?
            /// The argument's tokens, its label included.
            var range: Range<Int>
            /// Its value's tokens.
            var value: Range<Int>
        }

        /// The arguments of the call whose `(` is at `open`.
        func arguments(_ open: Int, tokens: [SwiftToken]) -> [Argument] {
            guard let close = closing[open] else { return [] }
            var arguments: [Argument] = []
            var start = open + 1
            func finish(_ end: Int) {
                guard end > start else { return }
                if end - start >= 3, let label = tokens[start].word, tokens[start + 1].isSymbol(":") {
                    arguments.append(Argument(label: label, range: start..<end, value: (start + 2)..<end))
                } else {
                    arguments.append(Argument(label: nil, range: start..<end, value: start..<end))
                }
            }
            for index in (open + 1)..<close where parent[index] == open && tokens[index].isSymbol(",") {
                finish(index)
                start = index + 1
            }
            finish(close)
            return arguments
        }
    }
}
