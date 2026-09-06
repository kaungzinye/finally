import SwiftData

extension Collection where Element == UserSession {
    var selectedProviderWorkspace: UserSession? {
        first(where: \.isSelected)
    }
}

extension ModelContext {
    func selectedProviderWorkspace() throws -> UserSession? {
        try fetch(FetchDescriptor<UserSession>()).selectedProviderWorkspace
    }
}

extension TaskItem {
    func belongs(to workspace: UserSession?) -> Bool {
        guard let workspace else { return false }
        return providerWorkspaceId == workspace.workspaceId
    }
}

extension ProjectItem {
    func belongs(to workspace: UserSession?) -> Bool {
        guard let workspace else { return false }
        return providerWorkspaceId == workspace.workspaceId
    }
}

extension Sequence where Element == TaskItem {
    func scoped(to workspace: UserSession?) -> [TaskItem] {
        filter { $0.belongs(to: workspace) }
    }
}

extension Sequence where Element == ProjectItem {
    func scoped(to workspace: UserSession?) -> [ProjectItem] {
        filter { $0.belongs(to: workspace) }
    }
}
