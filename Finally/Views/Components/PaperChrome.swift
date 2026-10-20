import SwiftUI

// MARK: - Lists on paper

extension View {
    /// Cards on paper: inset groups over the paper background, with every row at least 48 points.
    /// The bottom margin lets the last row scroll clear of the floating add button.
    func paperList(background: Color = Palette.paper) -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(background)
            .environment(\.defaultMinListRowHeight, 48)
            .contentMargins(.bottom, 96, for: .scrollContent)
    }

    /// A list row drawn on a cream card.
    func cardRow() -> some View {
        listRowBackground(Palette.card)
    }

    /// A row drawn as its own rounded card, 44 points tall with a 4-point gap to the next, so it
    /// keeps its corners while it slides under a swipe. Rows that share a section with task rows
    /// use it too, so the section reads as one stack of cards.
    func roundedCardRow(fill: Color = Palette.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(fill, in: shape)
            .contentShape(shape)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .listRowSeparator(.hidden)
    }

    /// Insets that hold a 44-point row to the shared 48-point height.
    func compactRowInsets() -> some View {
        listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
    }

    /// A list row that sits directly on paper, outside any card.
    func paperRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    /// Floating chrome: liquid glass on iOS 26, a thin material with a hairline before it.
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Palette.hairline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }
}

/// An uppercase rounded label above a group, with an optional trailing note.
struct SectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.eyebrow)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            trailing
                .font(.meta)
                .textCase(nil)
        }
        .foregroundStyle(Palette.muted)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// A short note under a group, in muted rounded type.
struct SectionNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.meta)
            .foregroundStyle(Palette.muted)
            .textCase(nil)
    }
}

// MARK: - Buttons

/// The primary action: a capsule of ink with paper-colored text.
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.action)
            .foregroundStyle(Palette.onInk)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Palette.ink.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var ink: InkButtonStyle { InkButtonStyle() }
}

/// A sheet's confirming toolbar button, such as Done or Save. The system fills it with the tint
/// and draws its label white, so it tints with `Palette.inkControl` to stay legible in dark mode.
struct ConfirmToolbarButton: ToolbarContent {
    let title: String
    var isDisabled = false
    let action: () -> Void

    init(_ title: String, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(title, action: action)
                .disabled(isDisabled)
                .tint(Palette.inkControl)
        }
    }
}

// MARK: - Sheets

extension View {
    /// A sheet on the warm sheet paper.
    func paperSheet() -> some View {
        presentationBackground(Palette.sheet)
    }
}

// MARK: - Choices

/// A chip that is on or off, such as a filter that narrows a list.
struct FilterChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            HStack(spacing: 6) {
                if isOn {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                }
                Text(title)
            }
            .font(.chip)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isOn ? Palette.onInk : Palette.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(isOn ? Palette.ink : Palette.wash, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One choice out of a few, as a row of chips. The chosen chip fills with ink.
struct ChoiceChips<Value: Hashable>: View {
    let choices: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(choices, id: \.self) { choice in
                let isSelected = choice == selection
                Button {
                    withAnimation(.snappy) { selection = choice }
                } label: {
                    Text(title(choice))
                        .font(.chip)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(isSelected ? Palette.onInk : Palette.ink)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 38, minHeight: 34)
                        .background(isSelected ? Palette.ink : Palette.wash, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// A list row that chooses one value: its label, then an ink checkmark when chosen.
struct CheckRow<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                label
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .foregroundStyle(Palette.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .cardRow()
    }
}

// MARK: - Flow layout

/// Lays children out in rows, wrapping to a new row when the next child would not fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
