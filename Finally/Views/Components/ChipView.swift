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

/// A chip holding a value the user can remove with its ✕.
struct RemovableChip: View {
    let label: String
    var icon: String?
    /// An inert chip is saved but has nothing to fire against yet.
    var isInert = false
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .imageScale(.small)
            }
            Text(label)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .frame(width: 24, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(label)")
            .accessibilityIdentifier("remove \(label)")
        }
        .font(.chip)
        .foregroundStyle(isInert ? Palette.muted : Palette.ink)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 32)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A + chip opening a short menu of choices.
struct AddChipMenu<Choice: Hashable>: View {
    let choices: [Choice]
    let title: (Choice) -> String
    let accessibilityLabel: String
    let onPick: (Choice) -> Void

    var body: some View {
        Menu {
            ForEach(choices, id: \.self) { choice in
                Button(title(choice)) { onPick(choice) }
            }
        } label: {
            Image(systemName: "plus")
                .font(.chip)
                .foregroundStyle(Palette.ink)
                .frame(width: 40, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .contentShape(Rectangle())
        }
        .accessibilityLabel(accessibilityLabel)
    }
}
