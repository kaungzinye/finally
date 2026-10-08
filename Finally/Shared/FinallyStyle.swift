import SwiftUI
import UIKit

/// Finally's warm monotone palette: ink on paper, with color reserved for priority and deadlines.
/// The app and the widget both compile this file.
enum Palette {
    static let paper = Color(light: 0xF5F2EB, dark: 0x161412)
    static let card = Color(light: 0xFDFBF7, dark: 0x24211D)
    static let sheet = Color(light: 0xFAF6EE, dark: 0x1A1714)
    static let ink = Color(light: 0x27221F, dark: 0xF2EEE6)
    static let muted = Color(light: 0x6A6762, dark: 0xAAA59D)
    /// Text and symbols drawn on an ink fill.
    static let onInk = Color(light: 0xFDFBF7, dark: 0x161412)
    static let hairline = ink.opacity(0.14)
    static let wash = ink.opacity(0.06)
    static let selection = ink.opacity(0.1)

    static let urgent = Color(light: 0xB83A26, dark: 0xE0644E)
    static let high = Color(light: 0xB8652A, dark: 0xE39A55)
    static let medium = Color(light: 0x5B7A9C, dark: 0x8AA6C6)
    static let low = muted

    /// The priority color for a stored priority name. A task without a priority draws in `low`.
    static func priority(named name: String?) -> Color {
        switch name {
        case "Urgent": urgent
        case "High": high
        case "Medium": medium
        default: low
        }
    }
}

extension Font {
    /// Chrome speaks in SF Pro Rounded. Task text stays in SF Pro.
    static let pageTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let cardTitle = Font.system(.title2, design: .rounded, weight: .semibold)
    static let eyebrow = Font.system(.footnote, design: .rounded, weight: .semibold)
    static let chip = Font.system(.subheadline, design: .rounded, weight: .medium)
    static let meta = Font.system(.footnote, design: .rounded)
    static let action = Font.system(.body, design: .rounded, weight: .semibold)
}

/// The checkbox ring. Its stroke carries the task's priority, and a finished task fills with ink.
struct PriorityRing: View {
    let color: Color
    let isDone: Bool
    var diameter: CGFloat = 22

    var body: some View {
        ZStack {
            if isDone {
                Circle().fill(Palette.ink)
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.45, weight: .bold))
                    .foregroundStyle(Palette.onInk)
            } else {
                Circle().fill(color.opacity(0.1))
                Circle().strokeBorder(color, lineWidth: 1.8)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
