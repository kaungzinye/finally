import Foundation

enum ProviderSessionRoute: Equatable {
    case connect
    case databaseSetup
    case tasks

    static func resolve(selectedWorkspace: UserSession?) -> Self {
        guard let selectedWorkspace else { return .connect }
        if selectedWorkspace.providerIdentity == .notion,
           selectedWorkspace.tasksDatabaseId.isEmpty {
            return .databaseSetup
        }
        return .tasks
    }
}

extension Notification.Name {
    static let providerWorkspaceChanged = Notification.Name("providerWorkspaceChanged")
}
