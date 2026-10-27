import XCTest
@testable import GANNPlayer

final class TrackTrimTests: XCTestCase {

    func testSettingStartClampsToDurationMinusGap() {
        // Нельзя двигать Start дальше (duration - 0.1), иначе получится
        // нулевой или отрицательный effectiveDuration.
        let result = Track.clampedTrim(currentStart: 0, currentEnd: nil,
                                        newStart: 1000, newEnd: nil, duration: 120)

        XCTAssertEqual(result.start, 119.9, accuracy: 0.0001)
        XCTAssertNil(result.end)
    }

    func testSettingStartBelowZeroClampsToZero() {
        let result = Track.clampedTrim(currentStart: 5, currentEnd: nil,
                                        newStart: -50, newEnd: nil, duration: 120)

        XCTAssertEqual(result.start, 0, accuracy: 0.0001)
    }

    func testEndNearDurationCollapsesToNil() {
        // Точка End в пределах 0.05с от конца файла трактуется как "до конца",
        // иначе крошечные погрешности seek'а превращали бы "до конца" в
        // "до 119.98 с" после каждого перетаскивания маркера.
        let result = Track.clampedTrim(currentStart: 0, currentEnd: nil,
                                        newStart: nil, newEnd: 119.98, duration: 120)

        XCTAssertNil(result.end)
    }

    func testEndClampsToDuration() {
        let result = Track.clampedTrim(currentStart: 0, currentEnd: nil,
                                        newStart: nil, newEnd: 999, duration: 120)

        // 120 попадает в допуск "совпадает с концом файла" -> nil, а не 120.
        XCTAssertNil(result.end)
    }

    func testEndClampsToDurationWhenClearlyBeforeIt() {
        let result = Track.clampedTrim(currentStart: 0, currentEnd: nil,
                                        newStart: nil, newEnd: 90, duration: 120)

        XCTAssertEqual(result.end, 90, accuracy: 0.0001)
    }

    func testStartNeverCrossesEnd() {
        // Если новый Start оказался правее уже выставленного End — End важнее,
        // Start отодвигается назад, а не наоборот (иначе трек воспроизводился
        // бы задом наперёд по длительности).
        let result = Track.clampedTrim(currentStart: 0, currentEnd: 30,
                                        newStart: 50, newEnd: nil, duration: 120)

        XCTAssertLessThan(result.start, result.end ?? .infinity)
        XCTAssertEqual(result.end, 30, accuracy: 0.0001)
        XCTAssertEqual(result.start, 29.9, accuracy: 0.0001)
    }

    func testZeroDurationDoesNotClampStart() {
        // duration == 0 значит метаданные ещё не подгрузились (трек только
        // что добавлен) — в этом случае клампить по длительности нечем,
        // введённое значение принимается как есть (кроме нижней границы 0).
        let result = Track.clampedTrim(currentStart: 0, currentEnd: nil,
                                        newStart: 42, newEnd: nil, duration: 0)

        XCTAssertEqual(result.start, 42, accuracy: 0.0001)
    }

    func testUnrelatedBoundIsPreservedWhenOnlyOneSideChanges() {
        // Если двигаем только Start, End не должен сбрасываться.
        let result = Track.clampedTrim(currentStart: 10, currentEnd: 80,
                                        newStart: 20, newEnd: nil, duration: 120)

        XCTAssertEqual(result.start, 20, accuracy: 0.0001)
        XCTAssertEqual(result.end, 80, accuracy: 0.0001)
    }
}
