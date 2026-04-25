import Foundation
import Observation

@Observable
final class MatchStore {
    private(set) var matches: [Match] = []
    private let fileURL: URL

    init(directory: URL = MatchStore.defaultDirectory) {
        self.fileURL = directory.appendingPathComponent("matches.txt")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func add(_ match: Match) {
        matches.append(match)
        appendToFile(match)
    }

    var lastMatch: Match? { matches.last }

    private func appendToFile(_ match: Match) {
        let line = match.formattedLine + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mazash")
    }
}
