import Foundation

/// Reads E2E test credentials from environment variables.
/// Set these in your Xcode scheme's environment variables or in your shell before running tests:
///   NOTION_E2E_TOKEN      — Notion integration token with read/write access
///   NOTION_E2E_TASKS_DB   — Tasks database ID
///   NOTION_E2E_PROJECTS_DB — Projects database ID (optional)
enum E2EConfig {
    static var notionToken: String? {
        ProcessInfo.processInfo.environment["NOTION_E2E_TOKEN"]
    }

    static var tasksDatabaseId: String? {
        ProcessInfo.processInfo.environment["NOTION_E2E_TASKS_DB"]
    }

    static var projectsDatabaseId: String? {
        ProcessInfo.processInfo.environment["NOTION_E2E_PROJECTS_DB"]
    }

    /// True when all required credentials are present.
    static var isConfigured: Bool {
        notionToken != nil && tasksDatabaseId != nil
    }
}
