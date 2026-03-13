import Foundation
import SwiftData

extension ModelContainer {
    /// Creates a shared ModelContainer using the App Group container for cross-target data sharing.
    static func shared() throws -> ModelContainer {
        let schema = Schema([
            TaskItem.self,
            ProjectItem.self,
            ReminderItem.self,
            UserSession.self,
        ])

        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID)!
            .appendingPathComponent("Finally.store")

        let config = ModelConfiguration(
            "Finally",
            schema: schema,
            url: storeURL,
            allowsSave: true
        )

        return try ModelContainer(for: schema, configurations: [config])
    }
}
