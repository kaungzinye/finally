import SwiftUI

/// A field chip. A set field shows its value on an ink wash, and an empty field shows a dashed placeholder.
/// Color tints only the icon and text, never the fill.
struct ChipView: View {
    let label: String
    var icon: String?
    var color: Color = Palette.ink
    var isPlaceholder = false
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .imageScale(.small)
                }
                Text(label)
                    .lineLimit(1)
            }
            .font(.chip)
            .foregroundStyle(isPlaceholder ? Palette.muted : color)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                if isPlaceholder {
                    shape.strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else {
                    shape.fill(Palette.wash)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
