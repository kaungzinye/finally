import SwiftUI

@Observable
final class NavigationRouter {
    enum Tab: Int, CaseIterable {
        case today = 0
        case upcoming
        case board
        case browse
    }

    var selectedTab: Tab = .today
    /// The project a new task starts in, set while a project's screen is open.
    var creatorProject: ProjectItem?
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
