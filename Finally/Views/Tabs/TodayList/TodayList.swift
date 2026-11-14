import SwiftData
import SwiftUI

/// Today's list drawn by UIKit, wrapped so SwiftUI can place it.
///
/// `UIViewControllerRepresentable` is the bridge: SwiftUI calls `makeUIViewController` once to
/// create the controller and keeps it alive while the view stays on screen. Whenever the inputs
/// change, SwiftUI calls `updateUIViewController` with fresh values, and the controller decides
/// what on screen has to change. SwiftUI owns the data and UIKit owns the drawing.
struct TodayList: UIViewControllerRepresentable {
    let content: TodayListContent
    let actions: TodayListActions

    func makeUIViewController(context: Context) -> TodayListController {
        TodayListController()
    }

    func updateUIViewController(_ controller: TodayListController, context: Context) {
        controller.actions = actions
        controller.show(content)
    }
}

/// Everything the list draws, worked out by TodayView from SwiftData.
struct TodayListContent {
    var day: Date
    /// "3 things to do", over the numbered picks.
    var focusHeading: String
    /// The Daily Focus picks and open slots. Nil while the day's focus loads.
    var focus: DailyFocusList?
    /// The personal agent proposed the day, and the user has yet to confirm it.
    var needsConfirmation: Bool
    var showsReviewTheDay: Bool
    /// Earlier days with unfinished picks, each offered for replanning.
    var unfinishedDays: [DailyFocus]
    var otherTasks: [TaskItem]
    /// A save is in flight, so the list takes no input.
    var isSaving: Bool
}

/// What the list hands back to TodayView. Each one runs on the main actor.
struct TodayListActions {
    var select: (TaskItem) -> Void
    var toggleCompletion: (TaskItem) -> Void
    var reschedule: (TaskItem) -> Void
    var removePick: (DailyFocusPick) -> Void
    var focus: (TaskItem) -> Void
    /// Moves the pick at one place among the picks to another, both counted before the move.
    var movePick: (_ from: Int, _ to: Int) -> Void
    var addPick: () -> Void
    var reviewDay: () -> Void
    var replan: (DailyFocus) -> Void
    var confirm: () -> Void
    var refresh: () async -> Void
}
