//  WHAT: An app's translations, as a Granite agent package. A call names the languages; the run reads every
//        localizable string out of the app's Swift (`Text("…")`, `Button("…")`, `String(localized: "…")` and the rest,
//        interpolations as format specifiers), writes the source language, has the host's model translate what is
//        new or changed into each language in checked batches, and adds the languages to the Xcode project.
//  IN:   Input: the languages, the source language, `.strings` or a String Catalog, the folder, the folders to read,
//        whether to translate everything again, whether to write a `localized()` helper, the rounds an answer gets.
//  OUT:  LocalizeResult: the files written, the app's languages, how many strings were found, added and translated,
//        which languages still wait, and what was left out.
//  PIN:  THE MODEL TRANSLATES; THE PACKAGE KEEPS THE APP WORKING. Keys, specifiers, files and the project are the
//        package's, the same every time; the model writes only text, and a text that loses a specifier, a line break
//        or its language is never written. Without a model the source language is still written.

import Foundation
import GraniteAgents

public struct LocalizeAgent: GraniteAgentPackage {
    public struct Input: Codable, Sendable {
        /// The languages to add or bring up to date: `fr`, `de`, `ja`, `zh-Hans`, `pt-BR`, or `loom` for Loom's 28.
        /// Every language the app already has when left out.
        public var languages: [String]?
        /// The language the Swift's strings are written in; `en` when left out.
        public var source: String?
        /// `strings` (one `Localizable.strings` a language) or `catalog` (one `Localizable.xcstrings`); what the
        /// project already uses when left out, else `strings`.
        public var format: LocalizeFormat?
        /// The folder holding the `.lproj` folders or the catalog, relative to the project; where the project keeps
        /// them already, else `Shared/i18n`.
        public var into: String?
        /// The folders or Swift files to read strings from; the whole project when left out.
        public var scan: [String]?
        /// Whether every string of the languages named is translated again; false when left out.
        public var refresh: Bool?
        /// Whether to write `String+Localized.swift` with `localized()` beside the strings' folder; false when left out.
        public var helper: Bool?
        /// How many times a batch is asked for before what still fails stays in the source language; 3 when left out.
        public var rounds: Int?
        /// The host's folder.
        public var directory: String?

        public init(languages: [String]? = nil, source: String? = nil, format: LocalizeFormat? = nil, into: String? = nil,
                    scan: [String]? = nil, refresh: Bool? = nil, helper: Bool? = nil, rounds: Int? = nil, directory: String? = nil) {
            self.languages = languages; self.source = source; self.format = format; self.into = into; self.scan = scan
            self.refresh = refresh; self.helper = helper; self.rounds = rounds; self.directory = directory
        }
    }

    public typealias Event = LocalizeFrame
    public typealias Output = LocalizeResult
    public typealias Compute = Void

    public static let word = "localize"
    public static let summary = "harvests every localizable string from an app's Swift, writes its source language and has the host's model translate it into the languages asked, checked and incremental, then adds them to the Xcode project."
    public static let fields = [
        "languages": "the languages to add or bring up to date, as codes: fr, de, ja, zh-Hans, pt-BR; `loom` for Loom's 28; left out, every language the app already has",
        "source": "the language the Swift's strings are written in; en when left out",
        "format": "strings for one Localizable.strings a language; catalog for one Localizable.xcstrings; left out, what the project already uses",
        "into": "the folder that holds the <lang>.lproj folders or the catalog, relative to the project; where the project keeps them already, else Shared/i18n",
        "scan": "the folders (or Swift files) to read strings from, relative to the project; the whole project when left out (build folders, packages and tests are skipped)",
        "refresh": "true translates every string again in the languages named (every language when none are named); false when left out: existing translations are kept",
        "helper": "true writes String+Localized.swift with `localized()` for keys an app holds as a String; false when left out",
        "rounds": "how many times a batch of texts is asked for before what still fails stays in the source language; 3 when left out, at most 6",
    ]
    public static let guide = """
        Tag localize to translate an app. It reads every localizable string out of the Swift: the literal in \
        `Text("…")`, `Button("…")`, `Label("…", systemImage:)`, `Toggle("…")`, `Section("…")`, `TextField("…")`, \
        `.navigationTitle("…")`, `.help("…")`, `.alert("…")`, `String(localized: "…")`, `LocalizedStringKey`, \
        `NSLocalizedString("…")`, `"KEY".localized()`, and a literal given to a property or parameter the app declares \
        as a `LocalizedStringKey`. An interpolation becomes the format specifier the runtime asks for: \
        `Text("\\(count) recipes")` is the key `%lld recipes`. A call's `comment:` is kept for the translator. It writes \
        the source language (a key in capitals such as `RECIPE_TITLE` gets its English from the model), then asks the \
        host's model for each language in checked batches: every specifier and line break kept, never left in English; \
        a bad answer is asked again with what was wrong, and what still fails stays in English and is named in the \
        notes. Only new or changed strings are asked for, so call it again after adding screens. It adds the \
        languages to the Xcode project's knownRegions and makes sure the strings' folder builds into every app target. \
        Without a model it writes the source language and says which languages wait.
        A first translation: {"languages": ["fr", "de", "ja", "ar"]}. Loom's 28 languages: {"languages": ["loom"]}. \
        After new screens, every language the app has: {}. A String Catalog: {"languages": ["es", "pt-BR"], \
        "format": "catalog"}. Translate one language again from scratch: {"languages": ["fr"], "refresh": true}. Also \
        write the localized() helper: {"languages": ["it"], "helper": true}. Only some folders: {"languages": ["ko"], \
        "scan": ["Components", "Shared/Views"]}. Write the Swift's strings as natural text in the source language \
        (`Text("Save recipe")`), not keys, before calling. Not for an app's images, fonts or App Store text.
        """

    /// One call at a time: two calls into one project's strings would each write the files from what they read, and
    /// the later would undo the earlier.
    public static let lanes: Int? = 1

    public static func output(from events: [LocalizeFrame]) -> LocalizeResult? { events.compactMap(\.result).last }

    public init() {}

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<LocalizeFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await LocalizeRun(input: input, host: context.host) { continuation.yield($0) }.run()
                    continuation.yield(.written(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
