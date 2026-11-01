//  WHAT: Every localizable string of a project's Swift: the folders walked, every file's declarations read first (a
//        name's type, a parameter that takes a key, wherever it is declared), then every file harvested.
//  PIN:  THE APP'S OWN STRINGS. A package keeps its strings in its own bundle, a test's are never shown, and build
//        folders hold copies: `.build`, `DerivedData`, a folder with a `Package.swift`, and test folders are left out
//        unless `scan` names them.

import Foundation

struct ProjectHarvest {
    var strings: [FoundString] = []
    /// How many Swift files were read.
    var files = 0
    /// Files (relative) that declare a `localized(` of their own on `String`.
    var helpers: [String] = []

    static func run(folders: [URL], explicit: Bool, relative: (URL) -> String) -> ProjectHarvest {
        var urls: [URL] = []
        for folder in folders { urls += swiftFiles(in: folder, explicit: explicit) }
        var seen: Set<String> = [], unique: [URL] = []
        for url in urls where seen.insert(url.path).inserted { unique.append(url) }
        let files = unique.map { (relative($0), $0) }.sorted { $0.0 < $1.0 }

        var scans: [(String, SwiftScanner.Scan)] = []
        var declarations = SwiftDeclarations()
        var harvest = ProjectHarvest()
        for (name, url) in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let scan = SwiftScanner.scan(text)
            declarations.read(scan, file: name)
            scans.append((name, scan))
            if scan.code.range(of: #"extension\s+String\b"#, options: .regularExpression) != nil,
               scan.code.range(of: #"func\s+localized\s*\("#, options: .regularExpression) != nil {
                harvest.helpers.append(name)
            }
        }
        let harvester = Harvester(declarations: declarations)
        for (name, scan) in scans { harvest.strings += harvester.strings(in: scan, file: name) }
        harvest.files = scans.count
        return harvest
    }

    private static let skippedNames: Set<String> = [".build", "build", "DerivedData", "Pods", "Carthage", "node_modules", ".swiftpm", "xcuserdata"]
    private static let skippedExtensions: Set<String> = ["xcodeproj", "xcworkspace", "xcassets", "lproj", "app", "framework",
                                                         "xcframework", "bundle", "playground", "docc", "xcstrings", "appex"]

    /// The Swift files under `folder` (or `folder` itself when it is one).
    static func swiftFiles(in folder: URL, explicit: Bool) -> [URL] {
        let manager = FileManager.default
        var isFolder: ObjCBool = false
        guard manager.fileExists(atPath: folder.path, isDirectory: &isFolder) else { return [] }
        guard isFolder.boolValue else { return folder.pathExtension == "swift" ? [folder] : [] }
        var found: [URL] = []
        var pending = [folder]
        while let current = pending.popLast() {
            guard let names = try? manager.contentsOfDirectory(atPath: current.path) else { continue }
            for name in names.sorted() {
                let url = current.appendingPathComponent(name)
                var childIsFolder: ObjCBool = false
                guard manager.fileExists(atPath: url.path, isDirectory: &childIsFolder) else { continue }
                if childIsFolder.boolValue {
                    if skips(url, name: name) { continue }
                    pending.append(url)
                } else if url.pathExtension == "swift", name != "Package.swift" {
                    found.append(url)
                }
            }
        }
        return found
    }

    private static func skips(_ url: URL, name: String) -> Bool {
        if name.hasPrefix(".") || skippedNames.contains(name) || skippedExtensions.contains(url.pathExtension) { return true }
        if name == "Tests" || name.hasSuffix("Tests") || name.hasSuffix("UITests") { return true }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
    }
}
