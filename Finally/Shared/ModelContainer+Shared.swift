import Foundation
import SwiftData

extension ModelContainer {
    private static var _shared: ModelContainer?

    /// Returns a shared ModelContainer singleton using the App Group container for cross-target data sharing.
    static func shared() throws -> ModelContainer {
        if let existing = _shared { return existing }

        let schema = Schema([
            TaskItem.self,
            ProjectItem.self,
            ReminderItem.self,
            UserSession.self,
        ])

        let storeURL: URL
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) {
            storeURL = groupURL.appendingPathComponent("Finally.store")
        } else {
            storeURL = URL.applicationSupportDirectory.appendingPathComponent("Finally.store")
        }

        let config = ModelConfiguration(
            "Finally",
            schema: schema,
            url: storeURL,
            allowsSave: true
        )

        let container = try ModelContainer(for: schema, configurations: [config])
        _shared = container
        return container
    }
}
