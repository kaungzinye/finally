import SwiftUI

/// Today's list drawn by UIKit, placed inside SwiftUI.
///
/// `UIViewControllerRepresentable` is the bridge. SwiftUI calls `makeUIViewController` once, when
/// the list first appears, and keeps that controller alive. After that, every time Today's state
/// changes, SwiftUI calls `updateUIViewController` with fresh values, and the controller decides
/// what on screen has to change. SwiftUI owns the data and UIKit owns the drawing.
struct TodayList: UIViewControllerRepresentable {
    let picks: [TaskItem]
    let otherTasks: [TaskItem]

    func makeUIViewController(context: Context) -> TodayListController {
        TodayListController()
    }

    func updateUIViewController(_ controller: TodayListController, context: Context) {
        controller.show(picks: picks, otherTasks: otherTasks)
    }
}
