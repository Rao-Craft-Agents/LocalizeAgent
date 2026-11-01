import Foundation
import GraniteAgents
import XCTest
@testable import LocalizeAgent

/// The package as an app finds it: by its record, with the schema a model is shown and the guide a host prompts with.
final class LocalizeAgentTests: XCTestCase {
    func testTheRecordIsFoundWithNothingListed() throws {
        let localize = try XCTUnwrap(GraniteRoster.discovered().package("localize"), "the record is in this test binary")
        XCTAssertEqual(localize.module, "LocalizeAgent")
        XCTAssertEqual(localize.summary, LocalizeAgent.summary)
        XCTAssertEqual(localize.lanes, 1)
    }

    func testTheSchemaIsWhatAModelIsShown() {
        let localize = AnyAgentPackage(LocalizeAgent.self)
        XCTAssertEqual(localize.schema, .object([
            .init(name: "languages", schema: .array(.string), required: false),
            .init(name: "source", schema: .string, required: false),
            .init(name: "format", schema: .choice(["strings", "catalog"]), required: false),
            .init(name: "into", schema: .string, required: false),
            .init(name: "scan", schema: .array(.string), required: false),
            .init(name: "refresh", schema: .boolean, required: false),
            .init(name: "helper", schema: .boolean, required: false),
            .init(name: "rounds", schema: .integer, required: false),
            .init(name: "directory", schema: .string, required: false),
        ]))
        XCTAssertTrue(localize.takesDirectory)
        XCTAssertEqual(Set(localize.fields.keys), ["languages", "source", "format", "into", "scan", "refresh", "helper", "rounds"],
                       "a note beside every field the model sees")
        XCTAssertNotNil(LocalizeAgent.word.range(of: #"^[a-z][a-z0-9]{1,31}$"#, options: .regularExpression))
    }

    func testTheGuideTeachesEveryMode() {
        let guide = AnyAgentPackage(LocalizeAgent.self).guide
        for words in [#"{"languages": ["fr", "de", "ja", "ar"]}"#, #"{"languages": ["loom"]}"#, ": {}.", #""format": "catalog""#,
                      #""refresh": true"#, #""helper": true"#, #""scan": ["#, "Text(\"…\")", "String(localized: \"…\")", "%lld recipes",
                      "comment:", "knownRegions", "Without a model"] {
            XCTAssertTrue(guide.contains(words), "the guide says \(words)")
        }
        XCTAssertFalse(guide.contains("Lemmy") || guide.contains("Mastodon"), "the guide's examples are not Loom's")
    }

    /// The call as a host makes it: JSON in, the host's folder and model offered, JSON out naming the files.
    func testACallThroughTheRosterWritesTheFilesItNames() async throws {
        let folder = try Fixture.kitchen()
        let model = FakeHostModel(answer: Translations.answer)
        let input = try JSONSerialization.data(withJSONObject: ["languages": ["fr", "ja"], "directory": folder.path])
        let answer = try await AnyAgentPackage(LocalizeAgent.self).perform(input, host: AgentHost(directory: folder.path, ask: "translate the app", model: model))
        let result = try JSONDecoder().decode(LocalizeResult.self, from: answer)
        XCTAssertEqual(result.languages, ["en", "fr", "ja"])
        XCTAssertEqual(result.paths.count, 4, "three tables and the project")
        XCTAssertEqual(result.path, result.paths.first)
        for path in result.paths {
            XCTAssertTrue(path.hasPrefix(folder.path), path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
        }
        XCTAssertLessThan(answer.count, 1_200, "the answer is small: the model reads it")
    }
}
