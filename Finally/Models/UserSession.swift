import Foundation
import SwiftData

@Model
final class UserSession {
    var id: UUID = UUID()
    var workspaceId: String
    var workspaceName: String
    var providerConfigurationData: Data?
    var lastFullSyncAt: Date?
    var createdAt: Date = Date()
    var providerRaw: String
    var isSelected: Bool = true

    init(
        workspaceId: String,
        workspaceName: String,
        providerIdentity: TaskProviderIdentity
    ) {
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        providerRaw = providerIdentity.rawValue
    }

    var providerIdentity: TaskProviderIdentity {
        get { TaskProviderIdentity(rawValue: providerRaw) }
        set { providerRaw = newValue.rawValue }
    }
}
