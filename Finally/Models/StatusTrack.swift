import Foundation

/// A status control's track of equal segments, one per status: Not started, In progress, Complete.
/// A lens marks the chosen segment. Its position is a fractional segment index, so 0 sits on
/// Not started, 1 on In progress, and 1.5 halfway between In progress and Complete.
struct StatusTrack {
    static let statuses = TaskStatus.allCases

    let width: Double

    var segmentWidth: Double {
        width / Double(Self.statuses.count)
    }

    /// The lens position for a finger at `x`. The lens centres on the finger and stops at
    /// either end of the track.
    func position(atX x: Double) -> Double {
        guard segmentWidth > 0 else { return 0 }
        let position = x / segmentWidth - 0.5
        return min(max(position, 0), Double(Self.statuses.count - 1))
    }

    /// The status of the segment nearest a lens position, where a lifted finger settles.
    static func status(atPosition position: Double) -> TaskStatus {
        statuses[index(atPosition: position.rounded())]
    }

    /// Where the lens rests on a status's segment.
    static func position(of status: TaskStatus) -> Double {
        Double(statuses.firstIndex(of: status) ?? 0)
    }

    /// The lens's color at a position: `fraction` of the way from one status's color to its
    /// neighbour's. A lens resting on a segment takes that status's color exactly.
    struct Tint: Equatable {
        let from: TaskStatus
        let to: TaskStatus
        let fraction: Double
    }

    static func tint(atPosition position: Double) -> Tint {
        let clamped = min(max(position, 0), Double(statuses.count - 1))
        let lower = index(atPosition: clamped.rounded(.down))
        let fraction = clamped - Double(lower)
        guard fraction > 0 else { return Tint(from: statuses[lower], to: statuses[lower], fraction: 0) }
        return Tint(from: statuses[lower], to: statuses[lower + 1], fraction: fraction)
    }

    private static func index(atPosition position: Double) -> Int {
        min(max(Int(position), 0), statuses.count - 1)
    }
}
