import SwiftUI

@Observable
final class NavigationRouter {
    enum Tab: Int, CaseIterable {
        case inbox = 0
        case today
        case upcoming
        case search
        case browse
    }

    var selectedTab: Tab = .today
    var deepLinkTaskId: String?
    var showNewTaskSheet: Bool = false
    var showReauthPrompt: Bool = false
    var pendingOAuthCode: String?

    // MARK: - URL Handling

    func handleURL(_ url: URL) {
        guard url.scheme == AppConstants.urlScheme else { return }

        let host = url.host()
        let path = url.path()

        switch host {
        case "oauth-callback":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            pendingOAuthCode = components?.queryItems?.first(where: { $0.name == "code" })?.value
        case "tasks":
            if path == "/new" || path == "new" {
                showNewTaskSheet = true
            } else {
                // Path is the task ID: /taskNotionPageId
                let taskId = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !taskId.isEmpty {
                    deepLinkTaskId = taskId
                }
            }
        default:
            break
        }
    }
}
