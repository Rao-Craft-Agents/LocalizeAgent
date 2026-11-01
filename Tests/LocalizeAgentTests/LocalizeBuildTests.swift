import Foundation
import XCTest
@testable import LocalizeAgent

/// The recipe app localized, built and run as an app would be: four languages from a scripted model (one bad answer
/// it must ask again), every table linted, the app built for macOS and the iOS Simulator with xcodebuild, the compiled
/// tables read out of each built app, the compiler's own keys matched, and the macOS app run in French and German.
/// Gated (`LOCALIZE_BUILD=1`): two builds take a while.
final class LocalizeBuildTests: XCTestCase {
    /// Whether the scripted model has given its one bad French answer yet.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var spent = false
        func first() -> Bool { lock.withLock { defer { spent = true }; return !spent } }
    }

    func testTheAppBuildsAndReadsItsTranslations() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LOCALIZE_BUILD"] == "1", "set LOCALIZE_BUILD=1 to build the app")
        let app = try Fixture.kitchen()
        let bad = Once()
        let model = FakeHostModel(answer: { ask in
            // The first French answer loses a specifier and a string: it must be asked for again.
            if Translations.language(ask.user) == "fr", bad.first() {
                var answer = Translations.asked(ask.user).compactMapValues { Translations.table["fr"]?[$0] }
                if let id = answer.first(where: { $0.value == "%lld recettes" })?.key { answer[id] = "recettes" }
                if let id = answer.first(where: { $0.value == "Annuler" })?.key { answer[id] = nil }
                return Translations.reply(answer)
            }
            return Translations.answer(ask)
        })
        let result = try await Call.localize(.init(languages: ["fr", "de", "ja", "ar"], helper: true), in: app, model: model)
        XCTAssertEqual(result.notes, [])
        XCTAssertEqual(result.waiting, [])
        XCTAssertEqual(result.translated, 100)
        let french = model.asked.filter { Translations.language($0.user) == "fr" }
        XCTAssertEqual(french.count, 2, "the bad answer was asked for again")
        XCTAssertTrue(french[1].user.contains("it must keep exactly %lld; it has none") && french[1].user.contains("it was missing from the answer"), french[1].user)

        let tables = ["en", "fr", "de", "ja", "ar"].map { app.appendingPathComponent("Shared/i18n/\($0).lproj/Localizable.strings") }
        for table in tables { XCTAssertNil(try Call.lint(table), table.path) }
        let english = Set(try Call.strings(tables[0]).keys)

        let derived = app.appendingPathComponent("dd")
        let mac = try xcodebuild(["-project", app.appendingPathComponent("Kitchen.xcodeproj").path, "-scheme", "Kitchen-macOS",
                                  "-destination", "platform=macOS", "-derivedDataPath", derived.path, "CODE_SIGNING_ALLOWED=NO", "build"], in: app)
        XCTAssertEqual(mac.status, 0, mac.log)
        let built = derived.appendingPathComponent("Build/Products/Debug/Kitchen.app")
        for code in ["en", "fr", "de", "ja", "ar"] {
            let compiled = built.appendingPathComponent("Contents/Resources/\(code).lproj/Localizable.strings")
            let table = try XCTUnwrap(NSDictionary(contentsOf: compiled) as? [String: String], "\(code).lproj is in the app")
            XCTAssertEqual(Set(table.keys), english, code)
        }
        let frenchURL = built.appendingPathComponent("Contents/Resources/fr.lproj/Localizable.strings")
        XCTAssertTrue(try Self.compiled(Data(contentsOf: frenchURL)), "the build compiled the table, never copied the source")
        let builtFrench = try XCTUnwrap(NSDictionary(contentsOf: frenchURL) as? [String: String])
        XCTAssertEqual(builtFrench["%lld recipes"], "%lld recettes", "a specifier survived the bad answer and the build")
        XCTAssertEqual(builtFrench["Cancel"], "Annuler")

        // Xcode's own extraction, from the build: every key the compiler says the app asks for is in the table.
        let compiler = try extracted(under: derived.appendingPathComponent("Build/Intermediates.noindex"))
        XCTAssertFalse(compiler.isEmpty, "the build extracted its strings")
        XCTAssertEqual(compiler.filter(Harvester.hasLetters).subtracting(["Preview only"]), english)

        // Run: the strings as a French and a German reader see them, the German one reordered by its numbers.
        let binary = built.appendingPathComponent("Contents/MacOS/Kitchen").path
        let inFrench = try run(binary, ["--strings", "-AppleLanguages", "(fr)"], in: app)
        XCTAssertEqual(inFrench.log, "3 recettes enregistrées\nCuisiné par Ada en 20 minutes\nRecettes\n")
        let inGerman = try run(binary, ["--strings", "-AppleLanguages", "(de)"], in: app)
        XCTAssertEqual(inGerman.log, "3 Rezepte gesichert\nIn 20 Minuten von Ada gekocht\nRezepte\n")

        let phone = try xcodebuild(["-project", app.appendingPathComponent("Kitchen.xcodeproj").path, "-scheme", "Kitchen-iOS",
                                    "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", derived.path, "CODE_SIGNING_ALLOWED=NO", "build"], in: app)
        XCTAssertEqual(phone.status, 0, phone.log)
        let phoneFrench = derived.appendingPathComponent("Build/Products/Debug-iphonesimulator/Kitchen.app/fr.lproj/Localizable.strings")
        XCTAssertEqual(Set(try XCTUnwrap(NSDictionary(contentsOf: phoneFrench) as? [String: String]).keys), english)
        XCTAssertTrue(try Self.compiled(Data(contentsOf: phoneFrench)))
    }

    /// Whether a built table is the build's own form (UTF-16 or a binary property list), not the UTF-8 source.
    private static func compiled(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) || data.starts(with: Array("bplist00".utf8))
    }

    /// Every key in the `.stringsdata` files the compiler wrote under `folder`.
    private func extracted(under folder: URL) throws -> Set<String> {
        var keys: Set<String> = []
        let urls = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
        for url in urls where url.pathExtension == "stringsdata" {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            for case let entries as [[String: Any]] in (object["tables"] as? [String: Any] ?? [:]).values {
                for entry in entries { if let key = entry["key"] as? String { keys.insert(key) } }
            }
        }
        return keys
    }

    private func xcodebuild(_ arguments: [String], in folder: URL) throws -> (status: Int32, log: String) {
        let result = try run("/usr/bin/xcrun", ["xcodebuild"] + arguments, in: folder)
        return (result.status, String(result.log.suffix(4_000)))
    }

    private func run(_ executable: String, _ arguments: [String], in folder: URL) throws -> (status: Int32, log: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = folder
        let log = folder.appendingPathComponent("run-\(UUID().uuidString.prefix(6)).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        try handle.close()
        return (process.terminationStatus, try String(contentsOf: log, encoding: .utf8))
    }
}
