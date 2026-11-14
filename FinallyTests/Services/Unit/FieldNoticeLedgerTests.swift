import XCTest
@testable import Finally

final class FieldNoticeLedgerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FieldNoticeLedgerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFirstNoticeForAFieldShows() {
        let ledger = FieldNoticeLedger(defaults: defaults)

        XCTAssertEqual(ledger.takeUnshown([.reminders], in: "notion"), [.reminders])
    }

    func testAFieldShownInAWorkspaceDoesNotShowAgain() {
        let ledger = FieldNoticeLedger(defaults: defaults)
        _ = ledger.takeUnshown([.reminders], in: "notion")

        XCTAssertEqual(ledger.takeUnshown([.reminders], in: "notion"), [])
    }

    func testAnotherWorkspaceStillGetsTheNotice() {
        let ledger = FieldNoticeLedger(defaults: defaults)
        _ = ledger.takeUnshown([.reminders], in: "notion")

        XCTAssertEqual(ledger.takeUnshown([.reminders], in: "server"), [.reminders])
    }

    func testOnlyTheNewFieldShowsInAWorkspaceThatSawAnother() {
        let ledger = FieldNoticeLedger(defaults: defaults)
        _ = ledger.takeUnshown([.reminders], in: "notion")

        XCTAssertEqual(ledger.takeUnshown([.reminders, .labels], in: "notion"), [.labels])
    }

    func testShownNoticesSurviveANewLedger() {
        _ = FieldNoticeLedger(defaults: defaults).takeUnshown([.reminders], in: "notion")

        XCTAssertEqual(FieldNoticeLedger(defaults: defaults).takeUnshown([.reminders], in: "notion"), [])
    }
}
