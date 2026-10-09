import SwiftUI

// MARK: - Lists on paper

extension View {
    /// Cards on paper: inset groups over the paper background, with every row at least 48 points.
    func paperList(background: Color = Palette.paper) -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(background)
            .environment(\.defaultMinListRowHeight, 48)
            .contentMargins(.bottom, 72, for: .scrollContent)
    }

    /// A list row drawn on a cream card.
    func cardRow() -> some View {
        listRowBackground(Palette.card)
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

    /// Floating chrome uses Liquid Glass on iOS 26+ and thin material on iOS 17–18.
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
