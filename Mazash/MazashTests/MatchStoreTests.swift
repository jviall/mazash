import XCTest
import ShazamKit
@testable import Mazash

final class MatchStoreTests: XCTestCase {
    var tempDir: URL!
    var store: MatchStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = MatchStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAddMatchAppendsToMemory() {
        let mediaItem = SHMediaItem(properties: [.title: "Test Song", .artist: "Test Artist"])
        let match = Match(timestamp: Date(), mediaItem: mediaItem)
        store.add(match)
        XCTAssertEqual(store.matches.count, 1)
        XCTAssertEqual(store.matches[0].title, "Test Song")
    }

    func testAddMatchWritesToFile() throws {
        // Use a fixed Gregorian calendar so this test is timezone-agnostic.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 24
        components.hour = 10
        components.minute = 5
        let date = cal.date(from: components)!

        let mediaItem = SHMediaItem(properties: [.title: "Test Song", .artist: "Test Artist"])
        let match = Match(timestamp: date, mediaItem: mediaItem)
        store.add(match)

        let fileURL = tempDir.appendingPathComponent("matches.txt")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(
            contents.trimmingCharacters(in: .newlines),
            "2026-04-24 10:05 | Test Song - Test Artist"
        )
    }

    func testMultipleMatchesAppend() throws {
        let item1 = SHMediaItem(properties: [.title: "Song A", .artist: "Artist A"])
        let item2 = SHMediaItem(properties: [.title: "Song B", .artist: "Artist B"])
        let date = Date()
        store.add(Match(timestamp: date, mediaItem: item1))
        store.add(Match(timestamp: date, mediaItem: item2))

        let fileURL = tempDir.appendingPathComponent("matches.txt")
        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
    }

    func testLastMatchReturnsNewest() {
        let item1 = SHMediaItem(properties: [.title: "Song A", .artist: "Artist A"])
        let item2 = SHMediaItem(properties: [.title: "Song B", .artist: "Artist B"])
        store.add(Match(timestamp: Date(), mediaItem: item1))
        store.add(Match(timestamp: Date(), mediaItem: item2))
        XCTAssertEqual(store.lastMatch?.title, "Song B")
    }
}
