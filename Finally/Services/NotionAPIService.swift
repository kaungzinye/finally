import Foundation

protocol NotionAPIClient {
    func retrieveDatabase(id: String) async throws -> NotionDatabase
    func queryAllPages(
        databaseId: String,
        filter: [String: Any]?,
        sorts: [[String: Any]]?
    ) async throws -> [NotionPage]
    func createPage(databaseId: String, properties: [String: Any]) async throws -> NotionPage
    func updatePage(pageId: String, properties: [String: Any]) async throws -> NotionPage
}

// MARK: - Notion API Error Types

enum NotionAPIError: Error, LocalizedError {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case notFound
    case badRequest(String)
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Your Notion connection has expired. Please reconnect."
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        case .notFound:
            return "The requested resource was not found in Notion."
        case .badRequest(let message):
            return "Bad request: \(message)"
        case .serverError(let code):
            return "Notion server error (\(code)). Please try again later."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError:
            return "Failed to parse Notion response."
        }
    }
}

extension Notification.Name {
    static let notionSessionExpired = Notification.Name("notionSessionExpired")
    static let notionDatabasesReset = Notification.Name("notionDatabasesReset")
}

// MARK: - Notion JSON Structures

struct NotionDatabaseQueryResponse: Decodable {
    let results: [NotionPage]
    let hasMore: Bool
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

struct NotionPage: Decodable {
    let id: String
    let lastEditedTime: String
    let properties: [String: NotionPropertyValue]

    enum CodingKeys: String, CodingKey {
        case id
        case lastEditedTime = "last_edited_time"
        case properties
    }
}

struct NotionPropertyValue: Decodable {
    let type: String
    let title: [NotionRichText]?
    let status: NotionStatusValue?
    let date: NotionDateValue?
    let select: NotionSelectOption?
    let multiSelect: [NotionSelectOption]?
    let relation: [NotionRelation]?
    let richText: [NotionRichText]?
    let checkbox: Bool?

    enum CodingKeys: String, CodingKey {
        case type, title, status, date, select, relation, checkbox
        case multiSelect = "multi_select"
        case richText = "rich_text"
    }
}

struct NotionRichText: Decodable {
    let plainText: String

    enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
    }
}

struct NotionStatusValue: Decodable {
    let name: String
}

struct NotionDateValue: Decodable {
    let start: String?
    let end: String?
}

struct NotionSelectOption: Decodable {
    let id: String?
    let name: String
    let color: String?
}

struct NotionRelation: Decodable {
    let id: String
}

// MARK: - Database Schema Types

struct NotionDatabase: Decodable {
    let id: String
    let title: [NotionRichText]
    let properties: [String: NotionPropertySchema]
}

struct NotionPropertySchema: Decodable {
    let id: String
    let type: String
    let status: NotionStatusSchema?
    let select: NotionSelectSchema?
    let multiSelect: NotionSelectSchema?
    let relation: NotionRelationSchema?

    enum CodingKeys: String, CodingKey {
        case id, type, status, select, relation
        case multiSelect = "multi_select"
    }
}

struct NotionStatusSchema: Decodable {
    let options: [NotionSelectOption]
    let groups: [NotionStatusGroup]?
}

struct NotionStatusGroup: Decodable {
    let id: String
    let name: String
    let optionIds: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name
        case optionIds = "option_ids"
    }
}

struct NotionSelectSchema: Decodable {
    let options: [NotionSelectOption]
}

struct NotionRelationSchema: Decodable {
    let databaseId: String

    enum CodingKeys: String, CodingKey {
        case databaseId = "database_id"
    }
}

// MARK: - Notion API Service

@Observable
final class NotionAPIService: NotionAPIClient {
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private var accessToken: String? {
        KeychainHelper.readNotionToken()
    }

    // MARK: - Request Building

    private func buildRequest(path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
        guard let token = accessToken else { throw NotionAPIError.unauthorized }
        guard let url = URL(string: "\(AppConstants.notionAPIBase)\(path)") else {
            throw NotionAPIError.badRequest("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConstants.notionAPIVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    // MARK: - Request Execution

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NotionAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionAPIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw NotionAPIError.decodingError(error)
            }
        case 401:
            handleUnauthorizedResponse()
            throw NotionAPIError.unauthorized
        case 404:
            throw NotionAPIError.notFound
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) } ?? 1.0
            throw NotionAPIError.rateLimited(retryAfter: retryAfter)
        default:
            throw NotionAPIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Database Operations

    func retrieveDatabase(id: String) async throws -> NotionDatabase {
        let request = try buildRequest(path: "/databases/\(id)")
        return try await execute(request)
    }

    func queryDatabase(
        id: String,
        filter: [String: Any]? = nil,
        sorts: [[String: Any]]? = nil,
        startCursor: String? = nil
    ) async throws -> NotionDatabaseQueryResponse {
        var body: [String: Any] = [
            "page_size": AppConstants.notionPageSize
        ]
        if let filter { body["filter"] = filter }
        if let sorts { body["sorts"] = sorts }
        if let startCursor { body["start_cursor"] = startCursor }

        let request = try buildRequest(path: "/databases/\(id)/query", method: "POST", body: body)
        return try await execute(request)
    }

    /// Fetch all pages from a database, handling pagination automatically.
    func queryAllPages(
        databaseId: String,
        filter: [String: Any]? = nil,
        sorts: [[String: Any]]? = nil
    ) async throws -> [NotionPage] {
        var allPages: [NotionPage] = []
        var cursor: String? = nil

        repeat {
            let response = try await queryDatabase(
                id: databaseId,
                filter: filter,
                sorts: sorts,
                startCursor: cursor
            )
            allPages.append(contentsOf: response.results)
            cursor = response.hasMore ? response.nextCursor : nil
        } while cursor != nil

        return allPages
    }

    // MARK: - Page Operations

    func createPage(databaseId: String, properties: [String: Any]) async throws -> NotionPage {
        let body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": properties,
        ]
        let request = try buildRequest(path: "/pages", method: "POST", body: body)
        return try await execute(request)
    }

    func updatePage(pageId: String, properties: [String: Any]) async throws -> NotionPage {
        let body: [String: Any] = [
            "properties": properties
        ]
        let request = try buildRequest(path: "/pages/\(pageId)", method: "PATCH", body: body)
        return try await execute(request)
    }

    // MARK: - Search (for database discovery after OAuth)

    struct NotionSearchResponse: Decodable {
        let results: [NotionSearchResult]
    }

    struct NotionSearchResult: Decodable {
        let id: String
        let object: String
        let title: [NotionRichText]?
        let parent: NotionParent?

        struct NotionParent: Decodable {
            let type: String
        }

        /// True if this is a full-page database (not an inline database inside a page)
        var isFullPageDatabase: Bool {
            parent?.type == "workspace" || parent?.type == "page_id"
        }
    }

    func searchDatabases() async throws -> [NotionSearchResult] {
        let body: [String: Any] = [
            "filter": ["value": "database", "property": "object"]
        ]
        let request = try buildRequest(path: "/search", method: "POST", body: body)
        let response: NotionSearchResponse = try await execute(request)
        // Only return full-page databases, filter out inline databases
        return response.results.filter { $0.title?.first?.plainText != nil }
    }
}
    private func handleUnauthorizedResponse() {
        KeychainHelper.deleteNotionToken()
        NotificationCenter.default.post(name: .notionSessionExpired, object: nil)
    }
