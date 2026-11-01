//  WHAT: One call, from the Swift to the files: the call read (every problem refused at once), the strings harvested,
//        the app's table read from its files, the new keys added, the source text of keys in capitals written by the
//        model, each language's missing or changed texts translated and checked, then the files, the project's
//        languages and the helper written together.
//  PIN:  INCREMENTAL. Only what is new or changed is asked for: a key no language has, a text whose source changed,
//        one that stands in for a translation. Existing translations are kept unless `refresh` says otherwise, and a
//        file whose text comes out the same is not written, so a second call with nothing new changes nothing.
//  PIN:  A CALL'S LANGUAGES ARE THE ONES IT NAMES. Named languages are the only ones asked for (a long ask on a
//        local model is the person's choice); left out, every language the app has is brought up to date.
//  PIN:  NO MODEL, STILL THE SOURCE. Without the host's model the source language is written and the languages that
//        wait for translations are named; a language's file is only made once it has a translation.

import Foundation
import GraniteAgents

struct LocalizeRun: Sendable {
    let input: LocalizeAgent.Input
    let host: AgentHost
    let yield: @Sendable (LocalizeFrame) -> Void

    func run() async throws -> LocalizeResult {
        let files = AgentFiles(directory: input.directory ?? host.directory)
        let call = try Self.read(input, files: files)
        let note = host.note

        // The Swift.
        let harvest = ProjectHarvest.run(folders: call.scan, explicit: input.scan != nil, relative: files.relative)
        yield(.harvested(strings: Set(harvest.strings.map(\.key)).count, files: harvest.files))
        note("found \(Set(harvest.strings.map(\.key)).count) strings in \(harvest.files) Swift file\(harvest.files == 1 ? "" : "s")")

        // What the app already has.
        var table: StringTable
        let catalogURL = StringCatalog.url(in: call.folder)
        var catalog: [String: Any] = [:]
        switch call.format {
        case .strings: table = try StringsFolder.load(call.folder, source: call.source)
        case .catalog:
            catalog = try StringCatalog.document(catalogURL)
            table = StringCatalog.load(catalog, source: call.source)
        }
        guard !harvest.strings.isEmpty || !table.keys.isEmpty else {
            throw LocalizeError.nothing("no localizable strings in \(harvest.files) Swift file\(harvest.files == 1 ? "" : "s") under \(call.scanned)")
        }
        var notes: [String] = []
        let added = Self.merge(harvest.strings, into: &table)
        let unseen = table.keys.values.filter { !$0.found }.count
        if unseen > 0, !harvest.strings.isEmpty {
            notes.append("\(unseen) \(unseen == 1 ? "string" : "strings") in the \(call.source.code) table \(unseen == 1 ? "is" : "are") not in the Swift and \(unseen == 1 ? "was" : "were") kept: a key built at run time is not seen")
        }

        let model = host.model
        let translator = model.map { Translator(model: $0, rounds: call.rounds, app: call.app, note: note) }

        // Keys in capitals: their source text, written by the model.
        let unwritten = table.keys.filter { $0.value.source == nil }.keys.sorted()
        if !unwritten.isEmpty, let translator {
            note("writing the \(call.source.name) of \(unwritten.count) key\(unwritten.count == 1 ? "" : "s") in capitals")
            let items = unwritten.map { Translator.Item(key: $0, text: $0, context: Self.context(table.keys[$0]!, withFile: true)) }
            let outcome = try await translator.writeSource(items, in: call.source)
            for (key, text) in outcome.done { table.keys[key]?.source = text }
        }
        let stillUnwritten = table.keys.filter { $0.value.source == nil }.keys.sorted()
        if !stillUnwritten.isEmpty {
            notes.append("\(stillUnwritten.count) key\(stillUnwritten.count == 1 ? " has" : "s have") no \(call.source.name) yet and \(stillUnwritten.count == 1 ? "is" : "are") left out until a model writes it (or it is written in the \(call.source.code) table): \(Self.list(stillUnwritten))")
        }

        // Every other language: what is missing or changed, translated.
        var translated = 0
        var waiting: [String] = []
        var failures: [(language: String, keys: [String], reason: String)] = []
        // The languages named, or every language the app has when none are: a call names its own scope.
        let targets = (call.languages.isEmpty ? Array(table.texts.keys) : call.languages).filter { $0 != call.source }.sorted()
        let asking = targets.filter { !Self.needed(table, language: $0, refreshing: input.refresh == true).isEmpty }
        if translator != nil, !asking.isEmpty {
            note("translating into \(asking.count == 1 ? asking[0].name : "\(asking.count) languages"): \(asking.map(\.code).joined(separator: ", "))")
        }
        for language in targets {
            try Task.checkCancellation()
            let needed = Self.needed(table, language: language, refreshing: input.refresh == true)
            guard !needed.isEmpty else { continue }
            guard let translator else {
                waiting.append(language.code)
                if table.texts[language] != nil { Self.standIn(needed, in: &table, language: language, keepOld: true) }
                continue
            }
            let items = needed.map { Translator.Item(key: $0, text: table.keys[$0]!.source!, context: Self.context(table.keys[$0]!, withFile: false)) }
            let outcome = try await translator.translate(items, into: language, from: call.source)
            for (key, value) in outcome.done {
                let source = table.keys[key]!.source!
                table.texts[language, default: [:]][key] = StringTable.Text(value: value, from: source == key ? nil : source, waiting: false)
            }
            if !outcome.failed.isEmpty {
                Self.standIn(Array(outcome.failed.keys), in: &table, language: language, keepOld: true)
                waiting.append(language.code)
                let keys = outcome.failed.keys.sorted()
                failures.append((language.code, keys, outcome.failed[keys[0]]!))
            }
            translated += outcome.done.count
            yield(.translated(language: language.code, strings: outcome.done.count, failed: outcome.failed.count))
            note("\(language.code): \(outcome.done.count) of \(items.count) translated" + (outcome.failed.isEmpty ? "" : ", \(outcome.failed.count) left in \(call.source.name)"))
        }
        if translator == nil, !waiting.isEmpty {
            notes.append("\(waiting.joined(separator: ", ")) wait\(waiting.count == 1 ? "s" : "") for a model: the host has none loaded, so only \(call.source.code) was written; call again with one")
        }
        notes += Self.failureNotes(failures, source: call.source, rounds: call.rounds)

        // The files.
        var planned: [(url: URL, text: String)] = []
        switch call.format {
        case .strings: planned += try StringsFolder.render(table, in: call.folder)
        case .catalog:
            // A catalog that holds the same once read is left as Xcode last wrote it.
            let text = try StringCatalog.render(table, into: catalog)
            let rendered = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
            if catalog.isEmpty || rendered.map({ !NSDictionary(dictionary: $0).isEqual(to: catalog) }) ?? true { planned.append((catalogURL, text)) }
        }
        let languages = table.languages.filter { language in
            language == table.source || !(table.texts[language] ?? [:]).isEmpty
        }
        if var project = XcodeProject(in: files.root) {
            let regions = languages.map(\.code)
            let before = project.text
            project.addRegions(regions)
            if let relative = Self.relative(call.folder, to: project.folder) {
                notes += project.ensureBuilt(relative, file: call.format == .catalog ? StringCatalog.fileName : StringsFolder.fileName)
                if call.format == .strings { project.addVariants(regions, file: StringsFolder.fileName) }
            } else {
                notes.append("\(files.relative(call.folder)) is outside \(project.name).xcodeproj's folder: add it to the app targets in Xcode")
            }
            if let development = project.developmentRegion, development != call.source.code, Language(development) != nil {
                notes.append("\(project.name).xcodeproj's development language is \(development), and the strings' source is \(call.source.code)")
            }
            if project.text != before {
                try project.check(regions: regions)
                planned.append((project.url, project.text))
            }
        } else {
            notes.append("no Xcode project in \(files.root.lastPathComponent): the languages are not added to one")
        }
        if input.helper == true {
            let helper = files.resolve(call.helperPath)
            let others = harvest.helpers.filter { files.resolve($0).path != helper.path }
            if let other = others.first {
                notes.append("String.localized() is already declared in \(other), so no helper was written")
            } else {
                planned.append((helper, LocalizedHelper.text))
            }
        }

        // Only what changed is written.
        let changed = planned.filter { (try? String(contentsOf: $0.url, encoding: .utf8)) != $0.text }
        let written = changed.isEmpty ? [] : try files.write(changed)
        note(written.isEmpty ? "nothing changed" : "wrote \(written.count) file\(written.count == 1 ? "" : "s")")
        if written.isEmpty, notes.isEmpty { notes.append("nothing changed: every string is in every language") }

        return LocalizeResult(path: written.first, paths: written, source: table.source.code, languages: languages.map(\.code),
                              strings: table.keys.values.filter { $0.source != nil }.count, found: Set(harvest.strings.map(\.key)).count,
                              added: added, translated: translated, waiting: Array(Set(waiting)).sorted(), notes: notes)
    }

    // MARK: - The call

    struct Call {
        var source: Language
        var languages: [Language]
        var format: LocalizeFormat
        var folder: URL
        var scan: [URL]
        var scanned: String
        var rounds: Int
        var app: String
        var helperPath: String
    }

    /// The call as the run needs it, or every reason it cannot be done.
    static func read(_ input: LocalizeAgent.Input, files: AgentFiles) throws -> Call {
        var reasons: [String] = []
        let source = Language(input.source ?? "en")
        if source == nil { reasons.append("`\(input.source ?? "")` is not a language code: `source` is the language the Swift's strings are written in, en when left out") }
        var languages: [Language] = []
        for word in input.languages ?? [] {
            if word.trimmingCharacters(in: .whitespaces).lowercased() == "loom" { languages += Language.loom; continue }
            if let language = Language(word) { languages.append(language) }
            else { reasons.append("`\(word)` is not a language code: write codes such as fr, de, ja, zh-Hans, pt-BR (zh alone says neither Simplified nor Traditional)") }
        }
        languages = languages.reduce(into: []) { if !$0.contains($1) && $1 != source { $0.append($1) } }

        let into = input.into ?? existingFolder(files.root, relative: files.relative) ?? "Shared/i18n"
        let folder = files.resolve(into)
        let present = StringsFolder.languages(in: folder)
        let hasCatalog = FileManager.default.fileExists(atPath: StringCatalog.url(in: folder).path)
        let format = input.format ?? (hasCatalog ? .catalog : .strings)
        if format == .catalog, !present.isEmpty {
            reasons.append("\(files.relative(folder)) already holds \(StringsFolder.fileName) in \(present.count) language\(present.count == 1 ? "" : "s"), and a catalog beside them would build each language twice: leave `format` out to keep them")
        }
        if format == .strings, hasCatalog {
            reasons.append("\(files.relative(folder)) already holds \(StringCatalog.fileName), and .strings files beside it would build each language twice: leave `format` out to keep the catalog")
        }

        var scan: [URL] = []
        for path in input.scan ?? [] {
            let url = files.resolve(path)
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue || url.pathExtension == "swift" { scan.append(url) }
            else { reasons.append("`\(path)` is not a folder or Swift file in the project") }
        }
        guard reasons.isEmpty, let source else { throw LocalizeError.refused(reasons) }

        // The source language read off a catalog that names one, when the call does not.
        var resolved = source
        if input.source == nil, format == .catalog, let document = try? StringCatalog.document(StringCatalog.url(in: folder)),
           let named = StringCatalog.sourceLanguage(document) { resolved = named }

        let app = XcodeProject(in: files.root)?.name ?? files.root.lastPathComponent
        let parent = (into as NSString).deletingLastPathComponent
        return Call(source: resolved, languages: languages, format: format, folder: folder, scan: scan.isEmpty ? [files.root] : scan,
                    scanned: scan.isEmpty ? files.root.lastPathComponent : (input.scan ?? []).joined(separator: ", "),
                    rounds: min(max(input.rounds ?? 3, 1), 6), app: app,
                    helperPath: (parent.isEmpty ? "Extensions" : parent + "/Extensions") + "/String+Localized.swift")
    }

    /// Where the project keeps its strings already: the folder of its `.lproj` folders or its catalog.
    static func existingFolder(_ root: URL, relative: (URL) -> String) -> String? {
        let manager = FileManager.default
        var pending: [(URL, Int)] = [(root, 0)]
        while !pending.isEmpty {
            let (folder, depth) = pending.removeFirst()
            guard let names = try? manager.contentsOfDirectory(atPath: folder.path) else { continue }
            if names.contains(StringCatalog.fileName) || !StringsFolder.languages(in: folder).isEmpty {
                return relative(folder)
            }
            guard depth < 4 else { continue }
            for name in names.sorted() where !name.hasPrefix(".") && !["build", "DerivedData", "Pods", "Packages", "node_modules"].contains(name) {
                let url = folder.appendingPathComponent(name)
                var isFolder: ObjCBool = false
                if manager.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue,
                   !["xcodeproj", "xcworkspace", "xcassets", "lproj", "app"].contains(url.pathExtension),
                   !manager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                    pending.append((url, depth + 1))
                }
            }
        }
        return nil
    }

    // MARK: - The table

    /// Adds what the harvest found; answers how many keys are new. The code's comment and source text win over the
    /// table's; a key the code gives neither keeps what the table has (a person's edit of the source text included).
    static func merge(_ found: [FoundString], into table: inout StringTable) -> Int {
        var added = 0
        for string in found {
            if var key = table.keys[string.key] {
                if !key.found {
                    key.found = true
                    key.role = string.role
                    key.file = string.file
                }
                if let comment = string.comment { key.comment = comment }
                // A source text the code gives is the code's: an edit there is a changed source text.
                if let value = string.value { key.source = value }
                table.keys[string.key] = key
            } else {
                added += 1
                table.keys[string.key] = StringTable.Key(source: string.value ?? StringTable.natural(string.key), comment: string.comment,
                                                         role: string.role, file: string.file, found: true)
            }
        }
        return added
    }

    /// The keys `language` needs asked for: no text yet, a text standing in, a text made from another source text.
    static func needed(_ table: StringTable, language: Language, refreshing: Bool) -> [String] {
        let texts = table.texts[language] ?? [:]
        return table.keys.filter { key, entry in
            guard let source = entry.source, entry.translatable, Harvester.hasLetters(source) else { return false }
            guard let text = texts[key] else { return true }
            return refreshing || text.waiting || (text.from != nil && text.from != source)
        }.keys.sorted()
    }

    /// The source text standing in for `keys` in `language` where the app would otherwise show a key in capitals;
    /// an older translation kept, marked, when `keepOld`.
    static func standIn(_ keys: [String], in table: inout StringTable, language: Language, keepOld: Bool) {
        for key in keys {
            guard let source = table.keys[key]?.source else { continue }
            if keepOld, var old = table.texts[language]?[key] {
                old.waiting = true
                table.texts[language]?[key] = old
            } else if source != key {
                table.texts[language, default: [:]][key] = StringTable.Text(value: source, from: source, waiting: true)
            } else {
                table.texts[language]?[key] = nil
            }
        }
    }

    /// What a string is, said beside it to the model; nothing for plain text with no comment.
    static func context(_ key: StringTable.Key, withFile: Bool) -> String? {
        var parts: [String] = []
        if let role = key.role, role != "text" { parts.append(role) }
        if let comment = key.comment { parts.append(comment) }
        if withFile, let file = key.file { parts.append("in " + (file.split(separator: "/").last.map(String.init) ?? file)) }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    /// One sentence for each set of strings that stayed in the source language, the languages that lost the same
    /// strings for the same reason together; at most three, then how many more languages there are.
    static func failureNotes(_ failures: [(language: String, keys: [String], reason: String)], source: Language, rounds: Int) -> [String] {
        var groups: [(languages: [String], keys: [String], reason: String)] = []
        for failure in failures {
            if let index = groups.firstIndex(where: { $0.keys == failure.keys && $0.reason == failure.reason }) { groups[index].languages.append(failure.language) }
            else { groups.append(([failure.language], failure.keys, failure.reason)) }
        }
        var notes = groups.prefix(3).map { group in
            let each = group.languages.count > 1 ? " each" : ""
            return "\(group.languages.joined(separator: ", ")): \(group.keys.count) string\(group.keys.count == 1 ? "" : "s")\(each) stayed in \(source.name) after \(rounds) round\(rounds == 1 ? "" : "s") (\(list(group.keys)); \(group.reason))"
        }
        let rest = groups.dropFirst(3).flatMap(\.languages)
        if !rest.isEmpty { notes.append("\(rest.count) more language\(rest.count == 1 ? "" : "s") kept strings in \(source.name): \(rest.joined(separator: ", "))") }
        return notes
    }

    static func list(_ keys: [String]) -> String {
        let shown = keys.prefix(4).map { "\"\($0.count > 40 ? $0.prefix(40) + "…" : Substring($0))\"" }.joined(separator: ", ")
        return keys.count > 4 ? shown + " and \(keys.count - 4) more" : shown
    }

    /// `folder` relative to `base`, when it is inside it.
    static func relative(_ folder: URL, to base: URL) -> String? {
        let path = AgentFiles.resolvingParents(folder.path), root = AgentFiles.resolvingParents(base.path)
        if path == root { return "" }
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : nil
    }
}
