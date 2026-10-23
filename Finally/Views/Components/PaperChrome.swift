import SwiftUI

// MARK: - Lists on paper

/// The inset card group a list section draws on paper.
enum PaperGroup {
    /// The system's corner radius for an inset grouped section, which a swiped row takes too.
    static let cornerRadius: CGFloat = 26

    /// How far a swipe slides a row before its corners reach the group's radius.
    static let swipeRoundingDistance: CGFloat = 60

    /// The corner radius of a row slid `offset` points from rest, in either direction. A row at
    /// rest has square corners and joins its group, and the corners round in step with the
    /// swipe until they reach the group's radius.
    static func swipeCornerRadius(forOffset offset: CGFloat) -> CGFloat {
        min(abs(offset) / swipeRoundingDistance, 1) * cornerRadius
    }
}

extension View {
    /// Cards on paper: inset groups over the paper background, with every row at least
    /// `minRowHeight` points. The bottom margin lets the last row scroll clear of the floating
    /// add button.
    func paperList(background: Color = Palette.paper, minRowHeight: CGFloat = 48) -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(background)
            .environment(\.defaultMinListRowHeight, minRowHeight)
            .contentMargins(.bottom, 96, for: .scrollContent)
    }

    /// A list row drawn on a cream card.
    func cardRow() -> some View {
        listRowBackground(Palette.card)
    }

    /// A task row in its section's joined card group. At rest the row draws on the group's
    /// background. As a swipe slides it aside, its corners round toward the group's radius, so
    /// they show against the revealed action.
    func swipeableCardRow(fill: Color = Palette.card, minHeight: CGFloat = 48) -> some View {
        modifier(SwipeableCardRow(fill: fill, minHeight: minHeight))
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

/// A swipe slides the whole list cell, its row background included. The row background rounds
/// its corners with the row's distance from rest, so a row at rest joins its group and a swiped
/// row shows its corners against the revealed action. The system's own group corners still
/// round a section's first and last rows.
private struct SwipeableCardRow: ViewModifier {
    let fill: Color
    let minHeight: CGFloat
    /// Where the row rests, learned from its first frame at each width. A swipe moves the row
    /// without changing its width, and a new width, such as after rotation, means a new rest.
    @State private var rest: CGRect?
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaperGroup.swipeCornerRadius(forOffset: offset), style: .continuous)
        content
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(shape)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { frame in
                guard let rest, abs(rest.width - frame.width) < 0.5 else {
                    rest = frame
                    offset = 0
                    return
                }
                offset = frame.minX - rest.minX
            }
            .listRowBackground(shape.fill(fill))
            .listRowInsets(EdgeInsets())
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

/// A sheet's confirming toolbar button, such as Done or Save. On iOS 26 it is prominent glass
/// filled with ink, its label drawn in `onInk`, so it reads in both modes whatever label color
/// the system would pick. Earlier systems draw it as bold ink text.
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
            if #available(iOS 26, *) {
                Button(action: action) {
                    Text(title)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.onInk)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.ink)
                .disabled(isDisabled)
            } else {
                Button(title, action: action)
                    .fontWeight(.semibold)
                    .disabled(isDisabled)
            }
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
