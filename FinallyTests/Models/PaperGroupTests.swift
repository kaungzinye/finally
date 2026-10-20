import XCTest
@testable import Finally

final class PaperGroupTests: XCTestCase {
    func testARowAtRestHasSquareCornersSoItJoinsItsGroup() {
        XCTAssertEqual(PaperGroup.swipeCornerRadius(forOffset: 0), 0)
    }

    func testTheCornersRoundInStepWithTheFirstSixtyPointsOfASwipe() {
        XCTAssertEqual(PaperGroup.swipeCornerRadius(forOffset: 15), 6.5, accuracy: 0.001)
        XCTAssertEqual(PaperGroup.swipeCornerRadius(forOffset: 30), 13, accuracy: 0.001)
        XCTAssertEqual(PaperGroup.swipeCornerRadius(forOffset: 60), 26, accuracy: 0.001)
    }

    func testASwipeEitherWayRoundsTheSame() {
        XCTAssertEqual(PaperGroup.swipeCornerRadius(forOffset: -15), 6.5, accuracy: 0.001)
        XCTAssertEqual(PaperGroup.swipeCornerRadius(forOffset: -90), 26, accuracy: 0.001)
    }

    func testTheCornersStopAtTheGroupRadiusPastSixtyPoints() {
        XCTAssertEqual(PaperGroup.swipeCornerRadius(forOffset: 61), 26)
        XCTAssertEqual(PaperGroup.swipeCornerRadius(forOffset: 400), 26)
    }
}
