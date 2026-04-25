import XCTest
import ShazamKit
@testable import Mazash

final class MatchTests: XCTestCase {
    func testFormattedLine() {
        var components = DateComponents()
        components.calendar = .current
        components.year = 2026
        components.month = 4
        components.day = 24
        components.hour = 16
        components.minute = 32
        let date = Calendar.current.date(from: components)!

        // SHMediaItem can't be meaningfully instantiated for formatting tests,
        // so we test the static formatting function directly.
        let line = Match.formatLine(title: "Espresso", artist: "Sabrina Carpenter", date: date)
        XCTAssertEqual(line, "2026-04-24 16:32 | Espresso - Sabrina Carpenter")
    }
}
