import Foundation

/// Remembers which fields the user has heard stay on this iPhone, per provider workspace,
/// so that notice shows once for each workspace and field.
final class FieldNoticeLedger {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "shownFieldNotices") {
        self.defaults = defaults
        self.key = key
    }

    /// The fields the workspace has not been told about yet. They count as shown from here on.
    func takeUnshown(_ fields: Set<CanonicalTaskField>, in workspaceID: String) -> Set<CanonicalTaskField> {
        var shown = Set(defaults.stringArray(forKey: key) ?? [])
        let unshown = fields.filter { !shown.contains(Self.entry($0, workspaceID)) }
        guard !unshown.isEmpty else { return [] }
        shown.formUnion(unshown.map { Self.entry($0, workspaceID) })
        defaults.set(shown.sorted(), forKey: key)
        return unshown
    }

    private static func entry(_ field: CanonicalTaskField, _ workspaceID: String) -> String {
        "\(workspaceID)\u{1F}\(field.rawValue)"
    }
}
