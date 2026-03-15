import Foundation

enum AppConstants {
    static let appGroupID = "group.com.kaungzinye.finally"
    static let urlScheme = "finally"
    static let keychainService = "com.kaungzinye.finally"
    static let keychainTokenAccount = "notion_access_token"

    // Notion API
    static let notionAPIBase = "https://api.notion.com/v1"
    static let notionAPIVersion = "2022-06-28"
    static let notionOAuthClientID = "322d872b-594c-81ee-9a0c-003713ecb1cb" // Set via environment or config
    static let notionOAuthRedirectURI = "\(vercelAPIBase)/api/notion/callback"

    // Vercel token exchange
    static let vercelAPIBase = "https://finally-auth.vercel.app"
    static let tokenExchangeEndpoint = "\(vercelAPIBase)/api/notion/token"

    // Sync
    static let syncIntervalSeconds: TimeInterval = 90
    static let fullSyncIntervalHours: Int = 24
    static let notionPageSize = 100

    // Notifications
    static let maxScheduledNotifications = 60 // Leave 4 buffer from iOS 64 limit
    static let backgroundRefreshID = "com.kaungzinye.finally.refresh"

    // Widget
    static let widgetKind = "TaskListWidget"
}
