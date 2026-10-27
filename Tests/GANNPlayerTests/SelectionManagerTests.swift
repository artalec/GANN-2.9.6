import XCTest
@testable import GANNPlayer

final class SelectionManagerTests: XCTestCase {

    func testSelectSingleReplacesSelection() {
        let s = SelectionManager()
        let a = UUID(), b = UUID()

        s.selectSingle(a)
        XCTAssertTrue(s.isSelected(a))

        s.selectSingle(b)
        XCTAssertFalse(s.isSelected(a))
        XCTAssertTrue(s.isSelected(b))
        XCTAssertEqual(s.count, 1)
    }

    func testToggleAddsAndRemoves() {
        let s = SelectionManager()
        let a = UUID()

        s.toggle(a)
        XCTAssertTrue(s.isSelected(a))

        s.toggle(a)
        XCTAssertFalse(s.isSelected(a))
        XCTAssertTrue(s.isEmpty)
    }

    func testSelectRangeUsesLastClickAsAnchor() {
        let ids = (0..<6).map { _ in UUID() }
        let s = SelectionManager()

        // Клик по индексу 1 задаёт anchor.
        s.selectSingle(ids[1])
        // ⇧-клик по индексу 4 должен выделить диапазон [1...4].
        s.selectRange(to: ids[4], in: ids)

        XCTAssertEqual(s.selectedIDs, Set(ids[1...4]))
    }

    func testSelectRangeAfterToggleKeepsLastAnchor() {
        // Регрессия на баг из review: toggle (⌘-клик) должен двигать anchor
        // так же, как и обычный клик, иначе следующий ⇧-клик выделит
        // неожиданный диапазон.
        let ids = (0..<5).map { _ in UUID() }
        let s = SelectionManager()

        s.selectSingle(ids[0])
        s.toggle(ids[3])          // anchor теперь ids[3]
        s.selectRange(to: ids[4], in: ids)

        XCTAssertEqual(s.selectedIDs, Set(ids[3...4]))
    }

    func testSelectAllAndClear() {
        let ids = (0..<4).map { _ in UUID() }
        let s = SelectionManager()

        s.selectAll(ids)
        XCTAssertEqual(s.selectedIDs, Set(ids))

        s.clear()
        XCTAssertTrue(s.isEmpty)
    }

    func testPruneRemovesStaleIDs() {
        let a = UUID(), b = UUID(), c = UUID()
        let s = SelectionManager()
        s.selectAll([a, b, c])

        // b удалили из плейлиста — выделение должно почиститься само,
        // иначе зависший id ломает подсчёт "N выделено" в TrackList.
        s.prune(keeping: [a, c])

        XCTAssertEqual(s.selectedIDs, Set([a, c]))
    }

    func testSelectedTracksFiltersInOriginalOrder() {
        let t1 = Track(name: "One", path: "/tmp/1.mp3")
        let t2 = Track(name: "Two", path: "/tmp/2.mp3")
        let t3 = Track(name: "Three", path: "/tmp/3.mp3")
        let s = SelectionManager()
        s.setSelectedIDs([t3.id, t1.id])

        let result = s.selectedTracks(from: [t1, t2, t3])

        XCTAssertEqual(result.map(\.id), [t1.id, t3.id])
    }
}
