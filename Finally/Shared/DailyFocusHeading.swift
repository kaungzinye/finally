/// The Daily Focus heading, "3 things to do" with the focus limit as the number. The Today tab and
/// the focus widget both read it.
enum DailyFocusHeading {
    static func text(focusLimit: Int) -> String {
        focusLimit == 1 ? "1 thing to do" : "\(focusLimit) things to do"
    }
}
