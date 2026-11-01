//  WHAT: The app's Xcode project file, edited as text where localization needs it: the languages in `knownRegions`,
//        and the strings' folder inside a synchronized folder of every app target, so each `.lproj` is built into the
//        app with no file listed (in a project of classic groups, each new language's file in its
//        `Localizable.strings` variant group).
//  PIN:  TEXT EDITS, IDEMPOTENT. Lines go in beside their neighbours, in Xcode's own layout; a second call adds nothing
//        twice; a new object's id is 24 hex digits no object of the project has. The edited text must read back as a
//        property list holding what was added, or nothing is written.

import Foundation

struct XcodeProject {
    /// `<Name>.xcodeproj/project.pbxproj`.
    let url: URL
    private(set) var text: String
    private var made: Set<String> = []

    /// The first `.xcodeproj` directly in `folder`, read; nil when there is none.
    init?(in folder: URL) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".xcodeproj") }.sorted()
        guard let name = names.first else { return nil }
        let url = folder.appendingPathComponent(name).appendingPathComponent("project.pbxproj")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.url = url
        self.text = text
    }

    init(url: URL, text: String) {
        self.url = url
        self.text = text
    }

    /// The project's name: `Kitchen` of `Kitchen.xcodeproj`.
    var name: String { url.deletingLastPathComponent().deletingPathExtension().lastPathComponent }

    /// The folder the `.xcodeproj` is in: where its groups' paths start.
    var folder: URL { url.deletingLastPathComponent().deletingLastPathComponent() }

    // MARK: - Reading

    private var plist: [String: Any]? {
        try? PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: Any]
    }

    private var objects: [String: [String: Any]] { (plist?["objects"] as? [String: [String: Any]]) ?? [:] }

    private var root: [String: Any]? {
        guard let id = plist?["rootObject"] as? String else { return nil }
        return objects[id]
    }

    var knownRegions: [String] { root?["knownRegions"] as? [String] ?? [] }

    var developmentRegion: String? { root?["developmentRegion"] as? String }

    struct Target: Equatable { var id: String; var name: String; var groups: [String] }

    /// The application targets, with the synchronized folders each builds.
    var appTargets: [Target] {
        objects.compactMap { id, object in
            guard object["isa"] as? String == "PBXNativeTarget", object["productType"] as? String == "com.apple.product-type.application" else { return nil }
            return Target(id: id, name: object["name"] as? String ?? id, groups: object["fileSystemSynchronizedGroups"] as? [String] ?? [])
        }.sorted { $0.name < $1.name }
    }

    /// Every group's folder, relative to the project's folder, by id.
    var groupPaths: [String: String] {
        let objects = objects
        guard let main = root?["mainGroup"] as? String else { return [:] }
        var paths: [String: String] = [:]
        func walk(_ id: String, _ base: String) {
            guard let object = objects[id] else { return }
            var here = base
            if let path = object["path"] as? String {
                switch object["sourceTree"] as? String ?? "<group>" {
                case "<group>": here = base.isEmpty ? path : base + "/" + path
                case "SOURCE_ROOT": here = path
                default: break
                }
            }
            paths[id] = here
            if let children = object["children"] as? [String] { for child in children { walk(child, here) } }
        }
        walk(main, "")
        return paths
    }

    /// The synchronized folders, by id, with their paths.
    var synchronizedRoots: [(id: String, path: String)] {
        let paths = groupPaths
        return objects.compactMap { id, object in
            guard object["isa"] as? String == "PBXFileSystemSynchronizedRootGroup" else { return nil }
            return (id, paths[id] ?? (object["path"] as? String ?? ""))
        }.sorted { $0.path < $1.path }
    }

    // MARK: - Editing

    /// Adds every code `knownRegions` lacks; answers those added.
    @discardableResult
    mutating func addRegions(_ codes: [String]) -> [String] {
        let known = Set(knownRegions)
        let missing = codes.filter { !known.contains($0) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard !missing.isEmpty, let rootID = plist?["rootObject"] as? String else { return [] }
        for code in missing { insert(Self.quoted(code), intoList: "knownRegions", ofObject: rootID) }
        return missing
    }

    /// Makes sure the folder at `relative` (from the project's folder) is built into every app target: inside a
    /// synchronized folder each target builds, or one made for it. Answers a sentence for anything changed or wrong.
    mutating func ensureBuilt(_ relative: String, file: String) -> [String] {
        let targets = appTargets
        guard !targets.isEmpty else { return ["\(name).xcodeproj has no app target, so nothing builds \(relative)"] }
        let roots = synchronizedRoots
        if roots.isEmpty { return ensureVariants(relative, file: file) }
        let containing = roots.filter { relative == $0.path || relative.hasPrefix($0.path + "/") }
        var notes: [String] = []
        if containing.isEmpty {
            // A synchronized folder of its own, beside the project's others.
            let id = newID()
            let block = "\t\t\(id) /* \(Self.comment(relative)) */ = {\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = \(Self.quoted(relative));\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n"
            insertObject(block, section: "PBXFileSystemSynchronizedRootGroup")
            if let main = root?["mainGroup"] as? String { insert("\(id) /* \(Self.comment(relative)) */", intoList: "children", ofObject: main) }
            for target in targets { insert("\(id) /* \(Self.comment(relative)) */", intoList: "fileSystemSynchronizedGroups", ofObject: target.id) }
            notes.append("added \(relative) to the project as a synchronized folder of \(targets.map(\.name).joined(separator: " and "))")
            return notes
        }
        let ids = Set(containing.map(\.id))
        for target in targets where !target.groups.contains(where: ids.contains) {
            let root = containing[0]
            insert("\(root.id) /* \(Self.comment(root.path)) */", intoList: "fileSystemSynchronizedGroups", ofObject: target.id)
            notes.append("added the synchronized folder \(root.path) to \(target.name)")
        }
        return notes
    }

    /// In a project of classic groups: each language's `<code>.lproj/<file>` in the variant group named `file`.
    private mutating func ensureVariants(_ relative: String, file: String) -> [String] {
        let objects = objects, paths = groupPaths
        guard let (groupID, group) = objects.first(where: { $0.value["isa"] as? String == "PBXVariantGroup" && $0.value["name"] as? String == file }) else {
            return ["\(name).xcodeproj has no synchronized folder and no \(file) group: add \(relative) to the app targets in Xcode"]
        }
        let folder = paths[groupID] ?? ""
        guard folder == relative else {
            return ["\(name).xcodeproj keeps \(file) in \(folder.isEmpty ? "its top folder" : folder), not \(relative): call with `into` set to it"]
        }
        let children = group["children"] as? [String] ?? []
        let present = Set(children.compactMap { objects[$0]?["name"] as? String })
        pendingVariants = (groupID, present)
        return []
    }

    private var pendingVariants: (group: String, present: Set<String>)?

    /// Adds a file reference for each language the variant group found by `ensureBuilt` lacks.
    mutating func addVariants(_ codes: [String], file: String) {
        guard let (group, present) = pendingVariants else { return }
        for code in codes where !present.contains(code) {
            let id = newID()
            let line = "\t\t\(id) /* \(code) */ = {isa = PBXFileReference; lastKnownFileType = \(file.hasSuffix(".xcstrings") ? "text.json.xcstrings" : "text.plist.strings"); name = \(Self.quoted(code)); path = \(Self.quoted("\(code).lproj/\(file)")); sourceTree = \"<group>\"; };\n"
            insertObject(line, section: "PBXFileReference")
            insert("\(id) /* \(code) */", intoList: "children", ofObject: group)
        }
        pendingVariants = (group, present.union(codes))
    }

    /// Throws unless the text reads back as a project whose `knownRegions` hold `regions`.
    func check(regions: [String]) throws {
        guard plist != nil else { throw LocalizeError.unreadable("\(name).xcodeproj does not read back after the edit") }
        let known = Set(knownRegions)
        if let missing = regions.first(where: { !known.contains($0) }) {
            throw LocalizeError.unreadable("\(name).xcodeproj lacks \(missing) in knownRegions after the edit")
        }
    }

    // MARK: - Text

    /// Where the object `id`'s block is: from its line to its closing `};`.
    private func block(_ id: String) -> Range<String.Index>? {
        guard let start = text.range(of: #"(?m)^[ \t]*\#(id)(?:[ \t]*/\*.*?\*/)?[ \t]*=[ \t]*\{"#, options: .regularExpression) else { return nil }
        var depth = 0, quoted = false, escaped = false
        var index = text.index(before: start.upperBound)
        while index < text.endIndex {
            let c = text[index]
            if quoted {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }
            } else if c == "\"" { quoted = true }
            else if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 {
                    var end = text.index(after: index)
                    if end < text.endIndex, text[end] == ";" { end = text.index(after: end) }
                    return start.lowerBound..<end
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Adds `entry,` as the last line of the list `key = ( … );` inside the object `id`, making the list when it has none.
    private mutating func insert(_ entry: String, intoList key: String, ofObject id: String) {
        guard let range = block(id) else { return }
        let object = String(text[range])
        if let list = object.range(of: #"(?m)^([ \t]*)\#(key) = \($"#, options: .regularExpression),
           let close = object.range(of: #"(?m)^[ \t]*\);"#, options: .regularExpression, range: list.upperBound..<object.endIndex) {
            let indent = String(object[list].prefix { $0 == " " || $0 == "\t" })
            var edited = object
            edited.insert(contentsOf: "\(indent)\t\(entry),\n", at: close.lowerBound)
            text.replaceSubrange(range, with: edited)
            return
        }
        // No such list yet: one before the object's closing brace.
        guard let closing = object.range(of: #"(?m)^[ \t]*\};?$"#, options: [.regularExpression, .backwards]) else { return }
        let indent = String(object[closing].prefix { $0 == " " || $0 == "\t" }) + "\t"
        var edited = object
        edited.insert(contentsOf: "\(indent)\(key) = (\n\(indent)\t\(entry),\n\(indent));\n", at: closing.lowerBound)
        text.replaceSubrange(range, with: edited)
    }

    /// Adds an object's text at the end of its section, making the section when the project has none.
    private mutating func insertObject(_ block: String, section: String) {
        if let end = text.range(of: "/* End \(section) section */") {
            text.insert(contentsOf: block, at: end.lowerBound)
            return
        }
        // Sections are in name order: the new one goes before the first that sorts after it.
        let begins = text.ranges(of: #"/\* Begin (\w+) section \*/"#)
        let after = begins.first { String(String(text[$0]).dropFirst(9).prefix { $0 != " " }) > section }
        let made = "/* Begin \(section) section */\n\(block)/* End \(section) section */\n\n"
        if let after { text.insert(contentsOf: made, at: after.lowerBound) }
        else if let objectsEnd = text.range(of: "\t};\n\trootObject") { text.insert(contentsOf: "\n" + made, at: objectsEnd.lowerBound) }
    }

    private mutating func newID() -> String {
        while true {
            let id = (0..<24).map { _ in String("0123456789ABCDEF".randomElement()!) }.joined()
            if !text.contains(id), made.insert(id).inserted { return id }
        }
    }

    /// A value as the project file writes it: bare when it is letters, digits, `_`, `.`, `/` and `$`; quoted otherwise.
    static func quoted(_ value: String) -> String {
        if !value.isEmpty, value.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || "_./$".contains($0) }) { return value }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func comment(_ path: String) -> String {
        (path.split(separator: "/").last.map(String.init) ?? path).replacingOccurrences(of: "*/", with: "")
    }
}

private extension String {
    /// Every range `pattern` matches, in order.
    func ranges(of pattern: String) -> [Range<String.Index>] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap { Range($0.range, in: self) }
    }
}
