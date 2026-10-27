import XCTest
@testable import GANNPlayer

final class PlaylistOrderingTests: XCTestCase {

    func testMovedToLaterPosition() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let ids = [a, b, c, d]

        let result = PlaylistOrdering.moved(ids, moving: a, onto: c)

        XCTAssertEqual(result, [b, c, a, d])
    }

    func testMovedToEarlierPosition() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let ids = [a, b, c, d]

        let result = PlaylistOrdering.moved(ids, moving: d, onto: b)

        XCTAssertEqual(result, [a, d, b, c])
    }

    func testMovedOntoSelfReturnsNil() {
        let a = UUID(), b = UUID()
        let ids = [a, b]

        XCTAssertNil(PlaylistOrdering.moved(ids, moving: a, onto: a))
    }

    func testMovedWithUnknownIDsReturnsNil() {
        let a = UUID(), b = UUID(), ghost = UUID()
        let ids = [a, b]

        XCTAssertNil(PlaylistOrdering.moved(ids, moving: ghost, onto: a))
        XCTAssertNil(PlaylistOrdering.moved(ids, moving: a, onto: ghost))
    }

    func testMovedPreservesCountAndUniqueness() {
        let ids = (0..<10).map { _ in UUID() }
        guard let moving = ids.first, let target = ids.last else {
            return XCTFail("нужно хотя бы два элемента")
        }

        let result = PlaylistOrdering.moved(ids, moving: moving, onto: target)

        XCTAssertEqual(result?.count, ids.count)
        XCTAssertEqual(Set(result ?? []), Set(ids))
    }
}
