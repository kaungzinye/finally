import SwiftUI

/// Not started, In progress and Complete as one control. On iOS 26 it is a glass track with a
/// tinted glass lens over the chosen status. A finger drags the lens across the segments, each
/// new segment ticks a selection haptic, and lifting snaps the lens to the nearest segment and
/// commits it. The lens tint runs red, orange, green, and blends between neighbours mid-drag.
/// VoiceOver reads it as one adjustable element. Earlier systems draw a segmented picker.
struct StatusControl: View {
    @Binding var selection: TaskStatus
    var label: (TaskStatus) -> String = { $0.rawValue }

    var body: some View {
        if #available(iOS 26, *) {
            GlassStatusTrack(selection: $selection, label: label)
        } else {
            Picker("Status", selection: $selection) {
                ForEach(StatusTrack.statuses, id: \.self) { status in
                    Text(label(status)).tag(status)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// The lens tint for a status, each deep enough to carry a white label in both modes.
    static func color(for status: TaskStatus) -> Color {
        switch status {
        case .notStarted: Palette.urgentFill
        case .inProgress: Palette.highFill
        case .done: Palette.done
        }
    }
}

@available(iOS 26, *)
private struct GlassStatusTrack: View {
    @Binding var selection: TaskStatus
    let label: (TaskStatus) -> String

    @Namespace private var glass
    @State private var width: Double = 0
    /// The lens position while a finger holds it. A lens at rest sits on `selection`.
    @State private var dragPosition: Double?

    private static let lensHeight: CGFloat = 34
    private static let inset: CGFloat = 4
    private static let space = "status-track"

    private var track: StatusTrack { StatusTrack(width: width) }
    private var position: Double { dragPosition ?? StatusTrack.position(of: selection) }
    /// The segment under the lens while a finger holds it.
    private var heldStatus: TaskStatus? { dragPosition.map(StatusTrack.status(atPosition:)) }

    private var tint: Color {
        let blend = StatusTrack.tint(atPosition: position)
        return StatusControl.color(for: blend.from)
            .mix(with: StatusControl.color(for: blend.to), by: blend.fraction)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            GlassEffectContainer {
                lensShape
                    .fill(.clear)
                    .glassEffect(.regular.tint(tint).interactive(), in: .capsule)
                    .glassEffectID("lens", in: glass)
                    .lensFrame(width: track.segmentWidth, position: position)
            }
            labels
                .foregroundStyle(Palette.ink)
                .mask {
                    Rectangle()
                        .overlay(alignment: .leading) {
                            lensShape
                                .lensFrame(width: track.segmentWidth, position: position)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
            labels
                .foregroundStyle(.white)
                .mask(alignment: .leading) {
                    lensShape.lensFrame(width: track.segmentWidth, position: position)
                }
        }
        .frame(height: Self.lensHeight)
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
        .coordinateSpace(.named(Self.space))
        .padding(Self.inset)
        .glassEffect(.regular, in: .capsule)
        .contentShape(Capsule())
        .gesture(drag)
        .sensoryFeedback(.selection, trigger: heldStatus) { old, new in
            guard let new else { return false }
            return new != (old ?? selection)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status")
        .accessibilityValue(label(selection))
        .accessibilityAdjustableAction { direction in
            let index = StatusTrack.statuses.firstIndex(of: selection) ?? 0
            let next = switch direction {
            case .increment: index + 1
            case .decrement: index - 1
            @unknown default: index
            }
            guard StatusTrack.statuses.indices.contains(next) else { return }
            withAnimation(.snappy) { selection = StatusTrack.statuses[next] }
        }
    }

    private var lensShape: Capsule { Capsule() }

    private var labels: some View {
        HStack(spacing: 0) {
            ForEach(StatusTrack.statuses, id: \.self) { status in
                Text(label(status))
                    .font(.chip)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// A touch moves the lens under the finger, and lifting it commits the nearest segment, so a
    /// tap and a drag take the same path.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let position = track.position(atX: value.location.x)
                if dragPosition == nil {
                    withAnimation(.snappy) { dragPosition = position }
                } else {
                    dragPosition = position
                }
            }
            .onEnded { value in
                let status = StatusTrack.status(atPosition: track.position(atX: value.location.x))
                withAnimation(.snappy) {
                    dragPosition = nil
                    if status != selection { selection = status }
                }
            }
    }
}

private extension View {
    /// The lens's frame for segments `width` wide, slid to a fractional segment `position`.
    func lensFrame(width: Double, position: Double) -> some View {
        frame(width: max(width, 0))
            .offset(x: position * width)
    }
}
