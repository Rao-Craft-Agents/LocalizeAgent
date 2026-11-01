import Foundation
import XCTest
@testable import LocalizeAgent

/// The Xcode project edited as Xcode would: the languages known once, the strings' folder built into every app target.
final class ProjectTests: XCTestCase {
    private func kitchen(_ edit: (String) -> String = { $0 }) throws -> XcodeProject {
        let url = try Fixture.folder().appendingPathComponent("Kitchen.xcodeproj/project.pbxproj")
        return XcodeProject(url: url, text: edit(Fixture.project))
    }

    private func reads(_ project: XcodeProject) throws -> [String: Any] {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(project.text.utf8), format: nil) as? [String: Any], "reads as a property list")
    }

    func testLanguagesAreAddedOnce() throws {
        var project = try kitchen()
        XCTAssertEqual(project.addRegions(["en", "fr", "zh-Hans", "pt-BR"]), ["fr", "zh-Hans", "pt-BR"])
        XCTAssertTrue(project.text.contains("\t\t\t\tBase,\n\t\t\t\tfr,\n\t\t\t\t\"zh-Hans\",\n\t\t\t\t\"pt-BR\",\n\t\t\t);"), project.text)
        let once = project.text
        XCTAssertEqual(project.addRegions(["fr", "zh-Hans"]), [])
        XCTAssertEqual(project.text, once, "a second call adds nothing")
        XCTAssertEqual(project.knownRegions, ["en", "Base", "fr", "zh-Hans", "pt-BR"])
        XCTAssertNoThrow(try project.check(regions: ["fr", "pt-BR"]))
        _ = try reads(project)
    }

    func testAFolderInsideASynchronizedFolderNeedsNothing() throws {
        var project = try kitchen()
        XCTAssertEqual(project.ensureBuilt("Shared/i18n", file: "Localizable.strings"), [])
        XCTAssertEqual(project.text, Fixture.project)
    }

    func testATargetWithoutTheFolderGetsIt() throws {
        // The macOS app does not build Shared.
        var project = try kitchen { $0.replacingOccurrences(of: "\t\t\t\t140000000000000000000001 /* Shared */,\n\t\t\t\t140000000000000000000004 /* Components */,\n\t\t\t\t140000000000000000000003 /* macOS */,",
                                                            with: "\t\t\t\t140000000000000000000004 /* Components */,\n\t\t\t\t140000000000000000000003 /* macOS */,") }
        XCTAssertEqual(project.ensureBuilt("Shared/i18n", file: "Localizable.strings"), ["added the synchronized folder Shared to Kitchen-macOS"])
        XCTAssertEqual(project.appTargets.first { $0.name == "Kitchen-macOS" }?.groups.contains("140000000000000000000001"), true)
        XCTAssertEqual(project.ensureBuilt("Shared/i18n", file: "Localizable.strings"), [], "a second call adds nothing")
    }

    func testAFolderOutsideEverySynchronizedFolderGetsOneOfItsOwn() throws {
        var project = try kitchen()
        XCTAssertEqual(project.ensureBuilt("Resources/i18n", file: "Localizable.strings"),
                       ["added Resources/i18n to the project as a synchronized folder of Kitchen-iOS and Kitchen-macOS"])
        let plist = try reads(project)
        let objects = try XCTUnwrap(plist["objects"] as? [String: [String: Any]])
        let made = try XCTUnwrap(objects.first { $0.value["path"] as? String == "Resources/i18n" })
        XCTAssertEqual(made.key.count, 24)
        XCTAssertEqual(made.value["isa"] as? String, "PBXFileSystemSynchronizedRootGroup")
        for target in project.appTargets { XCTAssertTrue(target.groups.contains(made.key), target.name) }
        XCTAssertEqual(project.ensureBuilt("Resources/i18n", file: "Localizable.strings"), [], "a second call adds nothing")
        let url = try Fixture.folder().appendingPathComponent("project.pbxproj")
        try project.text.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(try Call.lint(url))
    }

    func testAClassicProjectGetsEachLanguagesFile() throws {
        let classic = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tclasses = {
        \t};
        \tobjectVersion = 60;
        \tobjects = {

        /* Begin PBXFileReference section */
        \t\tA10000000000000000000001 /* en */ = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = en; path = en.lproj/Localizable.strings; sourceTree = "<group>"; };
        /* End PBXFileReference section */

        /* Begin PBXGroup section */
        \t\tA20000000000000000000001 = {
        \t\t\tisa = PBXGroup;
        \t\t\tchildren = (
        \t\t\t\tA20000000000000000000002 /* Shared */,
        \t\t\t);
        \t\t\tsourceTree = "<group>";
        \t\t};
        \t\tA20000000000000000000002 /* Shared */ = {
        \t\t\tisa = PBXGroup;
        \t\t\tchildren = (
        \t\t\t\tA20000000000000000000003 /* i18n */,
        \t\t\t);
        \t\t\tpath = Shared;
        \t\t\tsourceTree = "<group>";
        \t\t};
        \t\tA20000000000000000000003 /* i18n */ = {
        \t\t\tisa = PBXGroup;
        \t\t\tchildren = (
        \t\t\t\tA30000000000000000000001 /* Localizable.strings */,
        \t\t\t);
        \t\t\tpath = i18n;
        \t\t\tsourceTree = "<group>";
        \t\t};
        /* End PBXGroup section */

        /* Begin PBXNativeTarget section */
        \t\tA40000000000000000000001 /* Pantry */ = {
        \t\t\tisa = PBXNativeTarget;
        \t\t\tname = Pantry;
        \t\t\tproductType = "com.apple.product-type.application";
        \t\t};
        /* End PBXNativeTarget section */

        /* Begin PBXProject section */
        \t\tA50000000000000000000001 /* Project object */ = {
        \t\t\tisa = PBXProject;
        \t\t\tdevelopmentRegion = en;
        \t\t\tknownRegions = (
        \t\t\t\ten,
        \t\t\t\tBase,
        \t\t\t);
        \t\t\tmainGroup = A20000000000000000000001;
        \t\t\ttargets = (
        \t\t\t\tA40000000000000000000001 /* Pantry */,
        \t\t\t);
        \t\t};
        /* End PBXProject section */

        /* Begin PBXVariantGroup section */
        \t\tA30000000000000000000001 /* Localizable.strings */ = {
        \t\t\tisa = PBXVariantGroup;
        \t\t\tchildren = (
        \t\t\t\tA10000000000000000000001 /* en */,
        \t\t\t);
        \t\t\tname = Localizable.strings;
        \t\t\tsourceTree = "<group>";
        \t\t};
        /* End PBXVariantGroup section */
        \t};
        \trootObject = A50000000000000000000001 /* Project object */;
        }

        """
        let url = try Fixture.folder().appendingPathComponent("Pantry.xcodeproj/project.pbxproj")
        var project = XcodeProject(url: url, text: classic)
        XCTAssertEqual(project.ensureBuilt("Shared/i18n", file: "Localizable.strings"), [])
        project.addVariants(["en", "fr", "zh-Hans"], file: "Localizable.strings")
        project.addRegions(["en", "fr", "zh-Hans"])
        let plist = try reads(project)
        let objects = try XCTUnwrap(plist["objects"] as? [String: [String: Any]])
        let group = try XCTUnwrap(objects["A30000000000000000000001"]?["children"] as? [String])
        XCTAssertEqual(group.count, 3)
        XCTAssertEqual(Set(group.compactMap { objects[$0]?["path"] as? String }),
                       ["en.lproj/Localizable.strings", "fr.lproj/Localizable.strings", "zh-Hans.lproj/Localizable.strings"])
        var again = XcodeProject(url: url, text: project.text)
        _ = again.ensureBuilt("Shared/i18n", file: "Localizable.strings")
        again.addVariants(["en", "fr", "zh-Hans"], file: "Localizable.strings")
        XCTAssertEqual(again.text, project.text, "a second call adds nothing")
        var elsewhere = XcodeProject(url: url, text: classic)
        XCTAssertEqual(elsewhere.ensureBuilt("Shared/i8n", file: "Localizable.strings"),
                       ["Pantry.xcodeproj keeps Localizable.strings in Shared/i18n, not Shared/i8n: call with `into` set to it"])
    }
}
