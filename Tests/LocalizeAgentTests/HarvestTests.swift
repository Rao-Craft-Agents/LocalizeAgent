import Foundation
import XCTest
@testable import LocalizeAgent

/// The strings read out of Swift: every form the guide promises, keys as the runtime asks for them, and nothing that
/// is not a key.
final class HarvestTests: XCTestCase {
    /// The keys one file yields, with `declarations` read from it and from `others`.
    private func keys(_ code: String, others: [String] = []) -> [String] {
        found(code, others: others).map(\.key)
    }

    private func found(_ code: String, others: [String] = []) -> [FoundString] {
        var declarations = SwiftDeclarations()
        let scan = SwiftScanner.scan(code)
        declarations.read(scan, file: "View.swift")
        for (index, other) in others.enumerated() { declarations.read(SwiftScanner.scan(other), file: "Other\(index).swift") }
        return Harvester(declarations: declarations).strings(in: scan, file: "View.swift")
    }

    func testEveryFormTheGuideNames() {
        let cases: [(String, [String])] = [
            (#"Text("Save")"#, ["Save"]),
            (#"Label("Pantry", systemImage: "cabinet")"#, ["Pantry"]),
            (#"Button("Delete") { remove() }"#, ["Delete"]),
            (#"Button("Delete", role: .destructive, action: remove)"#, ["Delete"]),
            (#"Toggle("Vegetarian", isOn: $on)"#, ["Vegetarian"]),
            (#"Section("Steps") { rows }"#, ["Steps"]),
            (#"TextField("Recipe name", text: $name)"#, ["Recipe name"]),
            (#"list.navigationTitle("Kitchen")"#, ["Kitchen"]),
            (#"row.help("Opens the recipe")"#, ["Opens the recipe"]),
            (#"let key = LocalizedStringKey("A key")"#, ["A key"]),
            (#"let text = String(localized: "Saved")"#, ["Saved"]),
            (#"let text = NSLocalizedString("Legacy", comment: "")"#, ["Legacy"]),
            (#"let text = "PANTRY_TITLE".localized()"#, ["PANTRY_TITLE"]),
            (#"let text = "Signed in as".localized(name, formatted: true)"#, ["Signed in as %@"]),
            (#"list.searchable(text: $query, prompt: "Find a recipe")"#, ["Find a recipe"]),
            (#"view.alert("Remove it?", isPresented: $asking) {}"#, ["Remove it?"]),
            (#"Text(showAll ? "Show less" : "Show all")"#, ["Show less", "Show all"]),
            (#"SwiftUI.Text("Qualified")"#, ["Qualified"]),
            (#"let resource = LocalizedStringResource("A resource")"#, ["A resource"]),
            (#"let title: LocalizedStringKey = "Typed""#, ["Typed"]),
            (#"Text("Tap \(Text("here").bold()) to start")"#, ["Tap %@ to start", "here"]),
        ]
        for (code, expected) in cases {
            XCTAssertEqual(keys(code), expected, code)
        }
    }

    func testWhatIsNotAKey() {
        for code in [#"Text(verbatim: "v1.0")"#, #"Text("Hello " + name)"#, #"Text(title)"#, #"Text("•")"#, #"Text("\(name)")"#,
                     #"Text("Other", tableName: "Onboarding")"#, #"Text("Pkg", bundle: .module)"#, #"print("Debug")"#,
                     #"let plain = "Not a key""#, #"view.keyboardShortcut("s")"#, #"Image(systemName: "star")"#,
                     #"let text = NSLocalizedString("Hello \(name)", comment: "")"#, "#Preview { Text(\"Sample\") }",
                     #"struct Row_Previews: PreviewProvider { static var previews: some View { Text("Sample") } }"#,
                     #"case "a": print("x")"#] {
            XCTAssertEqual(keys(code), [], code)
        }
    }

    func testInterpolationsBecomeTheRuntimesSpecifiers() {
        let declared = """
        struct Kinds { var count: Int; var small: Int32; var size: UInt; var ratio: Double; var scale: Float; var name: String; var maybe: Int? }
        func total() -> Int { 0 }
        """
        let cases: [(String, String)] = [
            (#"Text("\(count) recipes")"#, "%lld recipes"),
            (#"Text("\(small) small")"#, "%d small"),
            (#"Text("\(size) big")"#, "%llu big"),
            (#"Text("\(ratio) ratio")"#, "%lf ratio"),
            (#"Text("\(scale) scale")"#, "%f scale"),
            (#"Text("Hi \(name)")"#, "Hi %@"),
            (#"Text("Maybe \(maybe)")"#, "Maybe %@"),
            (#"Text("\(items.count) items")"#, "%lld items"),
            (#"Text("\(3) fixed")"#, "%lld fixed"),
            (#"Text("\(2.5) cups")"#, "%lf cups"),
            (#"Text("\(ratio, specifier: "%.1f") stars")"#, "%.1f stars"),
            (#"Text("On \(date, style: .date)")"#, "On %@"),
            (#"Text("Total \(price, format: .currency(code: "EUR"))")"#, "Total %@"),
            (#"Text("Step \(count + 1)")"#, "Step %lld"),
            (#"Text("\(total()) done")"#, "%lld done"),
            (#"Text("Rated \(Double(count))")"#, "Rated %lf"),
            (#"Text("50% of \(count)")"#, "50%% of %lld"),
            (#"Text("100% sure")"#, "100% sure"),
            (#"Text("Hello \(name), you have \(count) items")"#, "Hello %@, you have %lld items"),
        ]
        for (code, expected) in cases {
            XCTAssertEqual(keys(code, others: [declared]), [expected], code)
        }
        // A name declared in the file wins over one declared elsewhere.
        XCTAssertEqual(keys("let count = \"many\"\nText(\"\\(count) left\")", others: [declared]), ["%@ left"])
    }

    func testLiteralsAreReadExactly() {
        XCTAssertEqual(keys(#"Text("Line one\nLine two \"quoted\" \u{2014} done")"#), ["Line one\nLine two \"quoted\" \u{2014} done"])
        XCTAssertEqual(keys(##"Text(#"A "raw" \d string"#)"##), [#"A "raw" \d string"#])
        XCTAssertEqual(keys("Text(\"\"\"\n    First line\n    Second line\n    \"\"\")"), ["First line\nSecond line"])
        XCTAssertEqual(keys("// Text(\"In a comment\")\n/* Text(\"In a block\") */ Text(\"Real\")"), ["Real"])
    }

    func testCommentsRolesAndSourceTexts() throws {
        let strings = found(#"""
        Text("Save", comment: "The button that saves a recipe")
        let welcome = String(localized: "WELCOME_BACK", defaultValue: "Welcome back, \(name)", comment: "The greeting")
        let legacy = NSLocalizedString("LEGACY_KEY", value: "Legacy text", comment: "An older string")
        Button("Share") {}
        """#)
        XCTAssertEqual(strings.map(\.key), ["Save", "WELCOME_BACK", "LEGACY_KEY", "Share"])
        XCTAssertEqual(strings[0].comment, "The button that saves a recipe")
        XCTAssertEqual(strings[1].value, "Welcome back, %@")
        XCTAssertEqual(strings[2].value, "Legacy text")
        XCTAssertEqual(strings[2].comment, "An older string")
        XCTAssertEqual(strings[3].role, "a button")
        XCTAssertEqual(strings[3].line, 4)
    }

    func testWhatTheProjectDeclaresAsAKey() {
        let declarations = """
        struct Badge: View { let title: LocalizedStringKey; var tint: Color = .blue; var body: some View { Text(title) } }
        struct Banner { init(_ message: LocalizedStringKey, style: Int = 0) {} }
        final class Pager { var emptyText: LocalizedStringKey; init(emptyText: LocalizedStringKey) { self.emptyText = emptyText } }
        extension View { func hint(text: LocalizedStringKey) -> some View { self } }
        enum Sort { case hot, new
            var title: LocalizedStringKey {
                switch self {
                case .hot: return "Hot"
                case .new: "Newest"
                }
            }
            var label: String { "Not a key" }
        }
        """
        XCTAssertEqual(keys(declarations), ["Hot", "Newest"])
        let calls = #"""
        Badge(title: "New")
        Banner("Saved")
        let pager: Pager = .init(emptyText: "Nothing yet")
        row.hint(text: "Swipe to delete")
        Post(title: "A post's title")
        """#
        XCTAssertEqual(keys(calls, others: [declarations]), ["New", "Saved", "Nothing yet", "Swipe to delete"])
    }

    func testTheRecipeAppsStrings() throws {
        let folder = try Fixture.kitchen()
        let files = AgentFiles(directory: folder.path)
        let harvest = ProjectHarvest.run(folders: [folder], explicit: false, relative: files.relative)
        XCTAssertEqual(harvest.files, 9)
        XCTAssertEqual(Set(harvest.strings.map(\.key)), Fixture.kitchenKeys)
        let filters = try XCTUnwrap(harvest.strings.first { $0.key == "Filters" })
        XCTAssertEqual(filters.comment, "The header above the list's filters")
        XCTAssertEqual(filters.file, "Components/RecipeList/RecipeList.swift")
    }

    func testBuildFoldersPackagesAndTestsAreLeftOut() throws {
        let folder = try Fixture.folder()
        try Fixture.write([
            "App/Home.swift": #"Text("Home")"#,
            "App/.build/Copy.swift": #"Text("Copy")"#,
            "DerivedData/Gen.swift": #"Text("Generated")"#,
            "Packages/Kit/Package.swift": "// swift-tools-version:6.0",
            "Packages/Kit/Sources/Kit/Kit.swift": #"Text("Kit")"#,
            "AppTests/HomeTests.swift": #"Text("Test")"#,
        ], in: folder)
        let files = AgentFiles(directory: folder.path)
        XCTAssertEqual(ProjectHarvest.run(folders: [folder], explicit: false, relative: files.relative).strings.map(\.key), ["Home"])
        let asked = ProjectHarvest.run(folders: [folder.appendingPathComponent("Packages/Kit")], explicit: true, relative: files.relative)
        XCTAssertEqual(asked.strings.map(\.key), ["Kit"], "a package is read when the call names it")
    }

    /// The compiler's own extraction of the recipe app, as Xcode runs it when it builds: every key it finds that a
    /// language would say differently is a key the harvest finds, written the same way.
    func testTheKeysAreTheCompilersOwn() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun"), "no toolchain")
        let folder = try Fixture.kitchen()
        let out = folder.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let sources = Fixture.kitchenSwift.keys.filter { !$0.hasPrefix("iOS/") }.sorted().map { folder.appendingPathComponent($0).path }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["-sdk", "macosx", "swiftc", "-parse-as-library", "-wmo", "-swift-version", "5", "-module-name", "Kitchen",
                             "-target", "arm64-apple-macos14", "-emit-localized-strings", "-emit-localized-strings-path", out.path,
                             "-c", "-o", out.appendingPathComponent("Kitchen.o").path] + sources
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let log = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, log)
        var compiler: Set<String> = []
        for name in try FileManager.default.contentsOfDirectory(atPath: out.path) where name.hasSuffix(".stringsdata") {
            let data = try Data(contentsOf: out.appendingPathComponent(name))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            for case let entries as [[String: Any]] in (object["tables"] as? [String: Any] ?? [:]).values {
                for entry in entries { if let key = entry["key"] as? String { compiler.insert(key) } }
            }
        }
        let files = AgentFiles(directory: folder.path)
        let harvested = Set(ProjectHarvest.run(folders: [folder], explicit: false, relative: files.relative).strings.map(\.key))
        // The compiler also extracts a preview's sample text and strings with no letters, which the harvest leaves out.
        XCTAssertEqual(harvested, compiler.filter(Harvester.hasLetters).subtracting(["Preview only"]))
    }
}
