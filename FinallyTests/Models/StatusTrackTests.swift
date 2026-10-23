import XCTest
@testable import Finally

final class StatusTrackTests: XCTestCase {
    /// Three 100-point segments: Not started, In progress, Complete.
    private let track = StatusTrack(width: 300)

    func testTheLensCentresOnTheFinger() {
        XCTAssertEqual(track.position(atX: 50), 0, accuracy: 0.0001)
        XCTAssertEqual(track.position(atX: 100), 0.5, accuracy: 0.0001)
        XCTAssertEqual(track.position(atX: 175), 1.25, accuracy: 0.0001)
        XCTAssertEqual(track.position(atX: 250), 2, accuracy: 0.0001)
    }

    func testTheLensStopsAtEitherEndOfTheTrack() {
        XCTAssertEqual(track.position(atX: 10), 0, accuracy: 0.0001)
        XCTAssertEqual(track.position(atX: -40), 0, accuracy: 0.0001)
        XCTAssertEqual(track.position(atX: 290), 2, accuracy: 0.0001)
        XCTAssertEqual(track.position(atX: 420), 2, accuracy: 0.0001)
    }

    func testLiftingTheFingerSnapsToTheNearestSegment() {
        XCTAssertEqual(StatusTrack.status(atPosition: 0.2), .notStarted)
        XCTAssertEqual(StatusTrack.status(atPosition: 0.6), .inProgress)
        XCTAssertEqual(StatusTrack.status(atPosition: 1.4), .inProgress)
        XCTAssertEqual(StatusTrack.status(atPosition: 1.7), .done)
    }

    func testEachStatusRestsOnItsOwnSegment() {
        XCTAssertEqual(StatusTrack.position(of: .notStarted), 0)
        XCTAssertEqual(StatusTrack.position(of: .inProgress), 1)
        XCTAssertEqual(StatusTrack.position(of: .done), 2)
    }

    func testALensAtRestTakesItsStatusColorExactly() {
        XCTAssertEqual(StatusTrack.tint(atPosition: 0), .init(from: .notStarted, to: .notStarted, fraction: 0))
        XCTAssertEqual(StatusTrack.tint(atPosition: 1), .init(from: .inProgress, to: .inProgress, fraction: 0))
        XCTAssertEqual(StatusTrack.tint(atPosition: 2), .init(from: .done, to: .done, fraction: 0))
    }

    func testADraggedLensBlendsTheColorsOfTheSegmentsItSitsBetween() {
        XCTAssertEqual(StatusTrack.tint(atPosition: 0.5), .init(from: .notStarted, to: .inProgress, fraction: 0.5))
        XCTAssertEqual(StatusTrack.tint(atPosition: 1.25), .init(from: .inProgress, to: .done, fraction: 0.25))
    }

    func testATintPastEitherEndKeepsTheEndColor() {
        XCTAssertEqual(StatusTrack.tint(atPosition: -0.4), .init(from: .notStarted, to: .notStarted, fraction: 0))
        XCTAssertEqual(StatusTrack.tint(atPosition: 2.3), .init(from: .done, to: .done, fraction: 0))
    }
}
