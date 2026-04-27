import Foundation
import Observation

// Called exclusively from the main thread via AppController.
@Observable
final class MatchStore {
    private(set) var matches: [Match] = []
    private let directory: URL
    private var lastWrittenKey: String? // "title|artist" of the last line appended to disk

    // Computed once at first access; .applicationSupportDirectory does not change at runtime.
    static let defaultDirectory: URL =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mazash")

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let sessionStartFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    init(directory: URL = MatchStore.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var lastMatch: Match? { matches.last }

    func writeSessionStart() {
        let line = "--- \(Self.sessionStartFormatter.string(from: Date())) listening started ---\n"
        guard let data = line.data(using: .utf8) else { return }
        lastWrittenKey = nil  // fresh session — always write the first match
        let url = fileURL(for: Date())
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            try handle.write(contentsOf: data)
        } catch CocoaError.fileNoSuchFile {
            try? data.write(to: url, options: .atomic)
        } catch {
            print("MatchStore: failed to write session start — \(error)")
        }
    }

    func add(_ match: Match) {
        matches.append(match)
        let key = "\(match.title)|\(match.artist)"
        if key != lastWrittenKey {
            appendToFile(match)
            lastWrittenKey = key
        }
        print("[Match] \(match.title) — \(match.artist)\(match.spotifyTrackId.map { " (Spotify: \($0))" } ?? "")")
    }

    // MARK: - Private

    private func fileURL(for date: Date) -> URL {
        let name = "matches-\(Self.fileDateFormatter.string(from: date)).txt"
        return directory.appendingPathComponent(name)
    }

    private func appendToFile(_ match: Match) {
        let url = fileURL(for: match.timestamp)
        let line = match.formattedLine + "\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            // Try to open for appending; if the file doesn't exist yet, catch and create it.
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            try handle.write(contentsOf: data)
        } catch CocoaError.fileNoSuchFile {
            try? data.write(to: url, options: .atomic)
        } catch {
            print("MatchStore: failed to write match — \(error)")
        }
    }
}
