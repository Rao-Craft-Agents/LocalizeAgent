import Foundation
import GraniteAgents
@testable import LocalizeAgent

enum Call {
    /// One call as a host makes it, in `folder`, offered `model` (none when nil).
    static func localize(_ input: LocalizeAgent.Input, in folder: URL, model: FakeHostModel?) async throws -> LocalizeResult {
        var input = input
        input.directory = folder.path
        let host = AgentHost(directory: folder.path, ask: "translate the app", model: model)
        return try await LocalizeRun(input: input, host: host, yield: { _ in }).run()
    }

    /// The entries of a `.strings` file, by key.
    static func strings(_ url: URL) throws -> [String: String] {
        let file = try StringsFile.read(Data(contentsOf: url)).unwrap()
        return Dictionary(file.entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    /// `plutil -lint`'s verdict on a file: nil when it passes.
    static func lint(_ url: URL) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = ["-lint", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return process.terminationStatus == 0 ? nil : output
    }
}

extension Optional {
    struct Missing: Error {}
    func unwrap() throws -> Wrapped {
        guard let self else { throw Missing() }
        return self
    }
}
