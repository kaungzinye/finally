import Foundation
@testable import Finally

final class MockNotionAPIClient: NotionAPIClient {
    struct QueryCall {
        let databaseId: String
        let filter: [String: Any]?
        let sorts: [[String: Any]]?
    }

    var retrieveDatabaseQueue: [NotionDatabase] = []
    var queryAllPagesResult: [String: [NotionPage]] = [:]
    var queryCalls: [QueryCall] = []
    var createdPages: [(databaseId: String, properties: [String: Any])] = []
    var updatedPages: [(pageId: String, properties: [String: Any])] = []

    func retrieveDatabase(id: String) async throws -> NotionDatabase {
        if !retrieveDatabaseQueue.isEmpty {
            return retrieveDatabaseQueue.removeFirst()
        }
        throw NotionAPIError.notFound
    }

    func queryAllPages(
        databaseId: String,
        filter: [String: Any]?,
        sorts: [[String: Any]]?
    ) async throws -> [NotionPage] {
        queryCalls.append(QueryCall(databaseId: databaseId, filter: filter, sorts: sorts))
        return queryAllPagesResult[databaseId] ?? []
    }

    func createPage(databaseId: String, properties: [String: Any]) async throws -> NotionPage {
        createdPages.append((databaseId: databaseId, properties: properties))
        return NotionPage(
            id: "remote-\(createdPages.count)",
            lastEditedTime: "2026-03-13T00:00:00.000Z",
            properties: [:]
        )
    }

    func updatePage(pageId: String, properties: [String: Any]) async throws -> NotionPage {
        updatedPages.append((pageId: pageId, properties: properties))
        return NotionPage(
            id: pageId,
            lastEditedTime: "2026-03-13T00:00:00.000Z",
            properties: [:]
        )
    }
}

enum NotionTestFactory {
    static func makeDatabase(properties: [String: NotionPropertySchema]) -> NotionDatabase {
        NotionDatabase(
            id: UUID().uuidString,
            title: [NotionRichText(plainText: "DB")],
            properties: properties
        )
    }

    static func schema(
        id: String = UUID().uuidString,
        type: String
    ) -> NotionPropertySchema {
        NotionPropertySchema(
            id: id,
            type: type,
            status: type == "status" ? NotionStatusSchema(options: [], groups: nil) : nil,
            select: type == "select" ? NotionSelectSchema(options: []) : nil,
            multiSelect: type == "multi_select" ? NotionSelectSchema(options: []) : nil,
            relation: type == "relation" ? NotionRelationSchema(databaseId: "rel-db") : nil
        )
    }

    static func page(
        id: String = UUID().uuidString,
        lastEditedTime: String = "2026-03-13T00:00:00.000Z",
        properties: [String: NotionPropertyValue]
    ) -> NotionPage {
        NotionPage(id: id, lastEditedTime: lastEditedTime, properties: properties)
    }

    static func propertyValue(
        type: String,
        title: [NotionRichText]? = nil,
        statusName: String? = nil,
        dateStart: String? = nil,
        selectName: String? = nil,
        multiSelectNames: [String]? = nil,
        relationIds: [String]? = nil
    ) -> NotionPropertyValue {
        NotionPropertyValue(
            type: type,
            title: title,
            status: statusName.map { NotionStatusValue(name: $0) },
            date: dateStart.map { NotionDateValue(start: $0, end: nil) },
            select: selectName.map { NotionSelectOption(id: nil, name: $0, color: nil) },
            multiSelect: multiSelectNames?.map { NotionSelectOption(id: nil, name: $0, color: nil) },
            relation: relationIds?.map { NotionRelation(id: $0) },
            richText: nil,
            checkbox: nil
        )
    }
}
