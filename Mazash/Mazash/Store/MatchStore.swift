import Foundation
import Observation

// Called exclusively from the main thread via AppController.
@Observable
final class MatchStore {
    private(set) var matches: [Match] = []
    private let fileURL: URL

    // Computed once at first access; .applicationSupportDirectory does not change at runtime.
    static let defaultDirectory: URL =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mazash")

    init(directory: URL = MatchStore.defaultDirectory) {
        self.fileURL = directory.appendingPathComponent("matches.txt")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var lastMatch: Match? { matches.last }

    func add(_ match: Match) {
        matches.append(match)
        appendToFile(match)
    }

    private func appendToFile(_ match: Match) {
        let line = match.formattedLine + "\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            // Try to open for appending; if the file doesn't exist yet, catch and create it.
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEndOfFile()
            try handle.write(contentsOf: data)
        } catch CocoaError.fileNoSuchFile {
            try? data.write(to: fileURL, options: .atomic)
        } catch {
            print("MatchStore: failed to write match — \(error)")
        }
    }
}
