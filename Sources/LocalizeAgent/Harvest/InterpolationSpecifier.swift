//  WHAT: The format specifier an interpolation becomes in a localized key, as SwiftUI and Foundation write it:
//        an `Int` is `%lld`, an `Int32` `%d`, a `UInt` `%llu`, a `Double` or `CGFloat` `%lf`, a `Float` `%f`, a value
//        with a `specifier:` that specifier, and anything else (a `String`, a `Text`, a formatted value) `%@`.
//  PIN:  THE TYPE IS GUESSED FROM WHAT THE PROJECT DECLARES: a literal, a numeric initializer, `.count`, a name or a
//        function's declared type, an arithmetic expression by its operands. Unsure is `%@`.

import Foundation

enum InterpolationSpecifier {
    static func specifier(_ source: String, file: String, declarations: SwiftDeclarations) -> String {
        let parts = LineSplit.top(source, on: ",")
        guard let value = parts.first else { return "%@" }
        for part in parts.dropFirst() {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let label = part[..<colon].trimmingCharacters(in: .whitespaces)
            let argument = part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if label == "specifier", argument.hasPrefix("\""), argument.hasSuffix("\""), argument.count >= 2 {
                return String(argument.dropFirst().dropLast())
            }
            if ["format", "style", "formatter", "relativeTo"].contains(label) { return "%@" }
        }
        return guess(value, file: file, declarations: declarations) ?? "%@"
    }

    /// The specifier of an expression, or nil when nothing says.
    static func guess(_ expression: String, file: String, declarations: SwiftDeclarations) -> String? {
        var text = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("("), text.hasSuffix(")"), LineSplit.closes(text) { text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces) }
        if text.hasSuffix("!") { text = String(text.dropLast()) }
        if text.hasPrefix("self.") { text = String(text.dropFirst(5)) }
        if text.isEmpty { return nil }
        if text.range(of: #"^-?\d[\d_]*$"#, options: .regularExpression) != nil { return "%lld" }
        if text.range(of: #"^-?\d[\d_]*\.\d[\d_]*([eE][-+]?\d+)?$"#, options: .regularExpression) != nil { return "%lf" }
        if text.hasPrefix("\"") || text.hasPrefix("#\"") { return "%@" }
        // `a ? b : c` reads as `b`; `a ?? b` as `a`, else `b`.
        if let question = LineSplit.firstTopOperator(text, "?"), let colon = LineSplit.firstTopOperator(String(text[text.index(after: question)...]), ":") {
            let rest = String(text[text.index(after: question)...])
            return guess(String(rest[..<colon]), file: file, declarations: declarations)
        }
        if let coalesce = text.range(of: "??") {
            return guess(String(text[..<coalesce.lowerBound]), file: file, declarations: declarations)
                ?? guess(String(text[coalesce.upperBound...]), file: file, declarations: declarations)
        }
        // Arithmetic: the first operand whose type is known decides.
        let operands = LineSplit.topOperands(text)
        if operands.count > 1 {
            for operand in operands { if let found = guess(operand, file: file, declarations: declarations), found != "%@" { return found } }
            return nil
        }
        // A numeric type made in place: `Int(x)`, `Double(total)`.
        if let open = text.firstIndex(of: "("), text.hasSuffix(")") {
            let callee = String(text[..<open])
            if callee.first?.isUppercase == true, !callee.contains(".") { return SwiftDeclarations.specifier(forType: callee) }
            let name = callee.split(separator: ".").last.map(String.init) ?? callee
            return declarations.specifier(forFunction: name)
        }
        let last = text.split(separator: ".").last.map(String.init) ?? text
        // A collection's `count` and an enumeration's `offset` are `Int`; a name of its own is what it is declared.
        if text.contains("."), last == "count" || last == "offset" { return "%lld" }
        guard last.range(of: #"^[A-Za-z_]\w*$"#, options: .regularExpression) != nil else { return nil }
        return declarations.specifier(forName: last, in: file)
    }
}
