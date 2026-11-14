import XCTest
@testable import Finally

/// A drag on the UIKit Today list reports a new order of picks, and the list turns it back into
/// one move for Daily Focus.
@MainActor
final class TodayListReorderTests: XCTestCase {
    func testMovingDownReportsTheRowAndItsNewPlace() {
        let move = TodayListController.singleMove(from: ["a", "b", "c"], to: ["b", "c", "a"])
        XCTAssertEqual(move?.from, 0)
        XCTAssertEqual(move?.to, 2)
    }

    func testMovingUpReportsTheRowAndItsNewPlace() {
        let move = TodayListController.singleMove(from: ["a", "b", "c"], to: ["c", "a", "b"])
        XCTAssertEqual(move?.from, 2)
        XCTAssertEqual(move?.to, 0)
    }

    func testSwappingNeighboursMovesTheUpperOneDown() {
        let move = TodayListController.singleMove(from: ["a", "b", "c"], to: ["b", "a", "c"])
        XCTAssertEqual(move?.from, 0)
        XCTAssertEqual(move?.to, 1)
    }

    func testTheSameOrderReportsNoMove() {
        XCTAssertNil(TodayListController.singleMove(from: ["a", "b"], to: ["a", "b"]))
    }
}
