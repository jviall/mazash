import XCTest
import ShazamKit

final class ShazamKitValidationTests: XCTestCase {
    func testSHSessionInitializes() {
        // If ShazamKit requires a provisioned entitlement and rejects ad-hoc signing,
        // this will crash or produce a recognizable runtime error.
        let session = SHSession()
        XCTAssertNotNil(session)
    }
}
