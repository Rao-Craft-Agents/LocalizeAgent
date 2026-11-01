//  WHAT: What the harvest knows of a project's declarations: the type of each name, as far as an interpolation's
//        format specifier needs it (`count: Int` makes `\(count)` a `%lld`), and the parameters that take a localized
//        key (`title: LocalizedStringKey`), so a call that passes one a literal is harvested.
//  PIN:  READ, NOT TYPE-CHECKED. A name declared in the file wins over one declared elsewhere; a name declared with
//        two kinds of type is `%@`. A wrong guess costs one translation (the runtime asks another key and shows the
//        source text), never a crash: every text carries exactly the specifiers of its own key.

import Foundation

struct SwiftDeclarations: Sendable {
    /// A parameter that takes a localized key: who takes it (a type, for its initializers, or a function) and its
    /// label (`_` when it has none).
    struct Parameter: Hashable, Sendable {
        var callee: String
        var label: String
    }

    /// Each name's specifiers, by file and over the project.
    private var byFile: [String: [String: Set<String>]] = [:]
    private var project: [String: Set<String>] = [:]
    /// What each function answers, by name.
    private var returns: [String: Set<String>] = [:]
    private(set) var localized: Set<Parameter> = []
    /// Every initializer label: how many initializers take it as a localized key, and how many as anything else.
    private var initLabels: [String: (localized: Int, plain: Int)] = [:]

    static let localizedTypes: Set<String> = ["LocalizedStringKey", "LocalizedStringResource", "LocalizationValue"]

    /// The specifier SwiftUI and Foundation write for a value of `type` in a localized key.
    static func specifier(forType type: String) -> String {
        switch type.split(separator: ".").last.map(String.init) ?? type {
        case "Int", "Int64": return "%lld"
        case "Int32", "Int16", "Int8": return "%d"
        case "UInt", "UInt64": return "%llu"
        case "UInt32", "UInt16", "UInt8": return "%u"
        case "Double", "CGFloat", "Float64", "TimeInterval": return "%lf"
        case "Float", "Float32": return "%f"
        default: return "%@"
        }
    }

    // MARK: - Reading

    mutating func read(_ scan: SwiftScanner.Scan, file: String) {
        readNames(scan.code, file: file)
        readLiterals(scan.tokens, file: file)
        readParameters(scan.tokens)
    }

    /// `let name = "…"`: a string, which the blanked code no longer shows.
    private mutating func readLiterals(_ tokens: [SwiftToken], file: String) {
        for index in tokens.indices.dropLast(3) where tokens[index].isWord("let") || tokens[index].isWord("var") {
            guard let name = tokens[index + 1].word, tokens[index + 2].isSymbol("="), tokens[index + 3].literal != nil else { continue }
            byFile[file, default: [:]][name, default: []].insert("%@")
            project[name, default: []].insert("%@")
        }
    }

    private static let sources: [(String, Kind)] = [
        (#"\b(?:let|var)\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w.]*)(\??)"#, .typed),
        (#"[(,]\s*(?:[A-Za-z_]\w*\s+)?([A-Za-z_]\w*)\s*:\s*(?:inout\s+|borrowing\s+|consuming\s+)?([A-Z][\w.]*)(\??)(?!\s*[(.\w])"#, .typed),
        (#"\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*-?\d[\d_]*(\.\d[\d_]*)?(?![\w.])"#, .number),
        (#"\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*([A-Z]\w*)\s*\("#, .made),
        (#"\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*[\w.?!]+\.count\b(?!\s*[(.])"#, .integer),
        (#"\bfor\s+([A-Za-z_]\w*)\s+in\s+-?\d"#, .integer),
        (#"\bfor\s+\(\s*([A-Za-z_]\w*)\s*,\s*[A-Za-z_]\w*\s*\)\s+in\s+[^{\n]*\.enumerated\(\)"#, .integer),
        (#"ForEach\(\s*(?:Array\()?\s*-?\d+\s*\.\.[.<][^{\n]*\{\s*\(?\s*([A-Za-z_]\w*)"#, .integer),
        (#"\.enumerated\(\)[^{\n]*\{\s*\(?\s*([A-Za-z_]\w*)\s*,"#, .integer),
    ]

    private static let patterns: [(NSRegularExpression, Kind)] = sources.map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    private static let function = try! NSRegularExpression(
        pattern: #"\bfunc\s+([A-Za-z_]\w*)\s*(?:<[^>\n]*>)?\s*\([^)]*\)\s*(?:async\s+)?(?:throws\s+)?->\s*([A-Z][\w.]*)(\??)"#)

    private enum Kind: Sendable { case typed, number, made, integer }

    private mutating func readNames(_ code: String, file: String) {
        let text = code as NSString
        let whole = NSRange(location: 0, length: text.length)
        var names: [String: Set<String>] = byFile[file] ?? [:]
        for (pattern, kind) in Self.patterns {
            for match in pattern.matches(in: code, range: whole) {
                let name = text.substring(with: match.range(at: 1))
                let specifier: String
                switch kind {
                case .typed:
                    let optional = match.range(at: 3).length > 0
                    specifier = optional ? "%@" : Self.specifier(forType: text.substring(with: match.range(at: 2)))
                case .number: specifier = match.range(at: 2).location == NSNotFound ? "%lld" : "%lf"
                case .made: specifier = Self.specifier(forType: text.substring(with: match.range(at: 2)))
                case .integer: specifier = "%lld"
                }
                names[name, default: []].insert(specifier)
                project[name, default: []].insert(specifier)
            }
        }
        byFile[file] = names
        for match in Self.function.matches(in: code, range: whole) {
            let optional = match.range(at: 3).length > 0
            returns[text.substring(with: match.range(at: 1)), default: []]
                .insert(optional ? "%@" : Self.specifier(forType: text.substring(with: match.range(at: 2))))
        }
    }

    /// The specifier a name's type gives, read in `file` first, then the project; nil when unknown or unsure.
    func specifier(forName name: String, in file: String) -> String? {
        if let local = byFile[file]?[name], local.count == 1 { return local.first }
        if let anywhere = project[name], anywhere.count == 1 { return anywhere.first }
        return nil
    }

    func specifier(forFunction name: String) -> String? {
        guard let found = returns[name], found.count == 1 else { return nil }
        return found.first
    }

    // MARK: - Parameters

    private mutating func readParameters(_ tokens: [SwiftToken]) {
        var braces: [String?] = []          // the type each open brace is the body of, if any
        var pendingType: String?
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if let word = token.word {
                switch word {
                case "struct", "class", "enum", "actor", "extension", "protocol":
                    // `extension Kit.Card` is Card's.
                    var cursor = index + 1, name: String?
                    while cursor < tokens.count, let part = tokens[cursor].word, part.first?.isUppercase == true {
                        name = part
                        guard cursor + 2 < tokens.count, tokens[cursor + 1].isSymbol(".") else { break }
                        cursor += 2
                    }
                    pendingType = name
                // A declaration's `init`, never a call's `.init(`.
                case "init" where braces.last.flatMap({ $0 }) != nil && !(index > 0 && tokens[index - 1].isSymbol(".")):
                    var open = index + 1
                    if open < tokens.count, tokens[open].isSymbol("?") || tokens[open].isSymbol("!") { open += 1 }
                    if open < tokens.count, tokens[open].isSymbol("("), let type = braces.last.flatMap({ $0 }) {
                        for parameter in Self.parameters(tokens, open: open) {
                            if parameter.localized { localized.insert(Parameter(callee: type, label: parameter.label)) }
                            var counts = initLabels[parameter.label] ?? (0, 0)
                            if parameter.localized { counts.localized += 1 } else { counts.plain += 1 }
                            initLabels[parameter.label] = counts
                        }
                    }
                case "func":
                    if index + 2 < tokens.count, let name = tokens[index + 1].word {
                        var open = index + 2
                        // Skip a generic clause: `func show<T>(…)`.
                        if tokens[open].symbol?.hasPrefix("<") == true {
                            var depth = 0
                            while open < tokens.count {
                                let symbol = tokens[open].symbol ?? ""
                                depth += symbol.filter { $0 == "<" }.count - symbol.filter { $0 == ">" }.count
                                open += 1
                                if depth <= 0 { break }
                            }
                        }
                        if open < tokens.count, tokens[open].isSymbol("(") {
                            for parameter in Self.parameters(tokens, open: open) where parameter.localized {
                                localized.insert(Parameter(callee: name, label: parameter.label))
                            }
                        }
                    }
                case "let", "var":
                    // A stored property of a type is a label of its memberwise initializer.
                    if let type = braces.last.flatMap({ $0 }), index + 3 < tokens.count, let name = tokens[index + 1].word,
                       tokens[index + 2].isSymbol(":") {
                        let typeEnd = Self.typeEnd(tokens, from: index + 3)
                        let computed = typeEnd < tokens.count && tokens[typeEnd].isSymbol("{")
                        if !computed {
                            let isLocalized = Self.isLocalizedType(tokens, from: index + 3)
                            if isLocalized { localized.insert(Parameter(callee: type, label: name)) }
                            var counts = initLabels[name] ?? (0, 0)
                            if isLocalized { counts.localized += 1 } else { counts.plain += 1 }
                            initLabels[name] = counts
                        }
                    }
                default: break
                }
            } else if token.isSymbol("{") {
                braces.append(pendingType)
                pendingType = nil
            } else if token.isSymbol("}") {
                _ = braces.popLast()
            } else if token.isSymbol(";") {
                pendingType = nil
            }
            index += 1
        }
    }

    /// Whether the type written at `start` is a localized key (`LocalizedStringKey`, `String.LocalizationValue`, optional or not).
    static func isLocalizedType(_ tokens: [SwiftToken], from start: Int) -> Bool {
        var cursor = start
        while cursor < tokens.count, let word = tokens[cursor].word {
            if localizedTypes.contains(word) { return true }
            guard cursor + 2 < tokens.count, tokens[cursor + 1].isSymbol(".") else { return false }
            cursor += 2
        }
        return false
    }

    /// Where a type written at `start` ends: past its dotted name, generic and bracketed parts and `?`, on its line.
    private static func typeEnd(_ tokens: [SwiftToken], from start: Int) -> Int {
        guard start < tokens.count else { return start }
        let line = tokens[start].line
        var cursor = start, depth = 0
        while cursor < tokens.count {
            let token = tokens[cursor]
            if token.isSymbol("[") || token.isSymbol("(") { depth += 1; cursor += 1; continue }
            if token.isSymbol("]") || token.isSymbol(")") { if depth == 0 { break }; depth -= 1; cursor += 1; continue }
            if depth > 0 { cursor += 1; continue }
            guard token.line == line else { break }
            if token.word != nil || token.isSymbol(".") || token.symbol.map({ $0.allSatisfy { "<>?!".contains($0) } }) == true { cursor += 1; continue }
            break
        }
        return cursor
    }

    /// The parameters of a declaration whose list opens at `open`: each label, and whether it takes a localized key.
    static func parameters(_ tokens: [SwiftToken], open: Int) -> [(label: String, localized: Bool)] {
        var found: [(String, Bool)] = []
        var depth = 0, start = open + 1, cursor = open + 1
        func finish(_ end: Int) {
            guard end > start else { return }
            // `[external] internal: Type [= default]`
            guard let colon = (start..<end).first(where: { tokens[$0].isSymbol(":") }), colon > start else { return }
            let names = (start..<colon).compactMap { tokens[$0].word }.filter { !["inout", "borrowing", "consuming", "isolated", "sending"].contains($0) }
            guard let label = names.first else { return }
            var typeStart = colon + 1
            while typeStart < end, let word = tokens[typeStart].word, ["inout", "borrowing", "consuming", "sending", "isolated"].contains(word) { typeStart += 1 }
            if typeStart < end, tokens[typeStart].isSymbol("@") { typeStart += 2 }
            found.append((label, isLocalizedType(tokens, from: typeStart)))
        }
        while cursor < tokens.count {
            let token = tokens[cursor]
            if token.isSymbol("(") || token.isSymbol("[") || token.isSymbol("{") { depth += 1 }
            else if token.isSymbol(")") || token.isSymbol("]") || token.isSymbol("}") {
                if depth == 0 { finish(cursor); break }
                depth -= 1
            } else if token.isSymbol(","), depth == 0 {
                finish(cursor)
                start = cursor + 1
            }
            cursor += 1
        }
        return found
    }

    /// Whether `.init(label: …)`, whose type the code does not say, takes a localized key there: every initializer
    /// the project declares with that label does.
    func initTakesLocalized(_ label: String) -> Bool {
        guard let counts = initLabels[label] else { return false }
        return counts.localized > 0 && counts.plain == 0
    }
}
