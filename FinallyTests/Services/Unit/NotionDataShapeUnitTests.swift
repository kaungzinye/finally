import XCTest
@testable import Finally

final class NotionDataShapeUnitTests: XCTestCase {
    func testPageWrites_WhenNotionReturnsForbidden_ThrowPermissionDeniedMessage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ForbiddenNotionURLProtocol.self]
        let api = NotionAPIService(
            token: "test-token",
            session: URLSession(configuration: configuration)
        )

        let writes: [() async throws -> NotionPage] = [
            { try await api.createPage(databaseId: "tasks-db", properties: [:]) },
            { try await api.updatePage(pageId: "task-1", properties: [:]) },
        ]

        for write in writes {
            do {
                _ = try await write()
                XCTFail("Expected a permission-denied error")
            } catch NotionAPIError.permissionDenied(let message) {
                XCTAssertEqual(message, ForbiddenNotionURLProtocol.message)
            } catch {
                XCTFail("Expected permissionDenied, received \(error)")
            }
        }
    }

    func testQueryResponseDecoding_WithTypicalTaskShape_DecodesExpectedFields() throws {
        let json = """
        {
          "results": [
            {
              "id": "task-1",
              "last_edited_time": "2026-03-13T10:00:00.000Z",
              "properties": {
                "Name": { "type": "title", "title": [{ "plain_text": "Pay rent" }] },
                "Status": { "type": "status", "status": { "name": "Not Started" } },
                "Due Date": { "type": "date", "date": { "start": "2026-03-20" } },
                "Priority": { "type": "select", "select": { "id": "p1", "name": "High", "color": "orange" } },
                "Tags": { "type": "multi_select", "multi_select": [{ "id": "t1", "name": "Finance", "color": "blue" }] },
                "Project": { "type": "relation", "relation": [{ "id": "proj-1" }] }
              }
            }
          ],
          "has_more": false,
          "next_cursor": null
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(NotionDatabaseQueryResponse.self, from: data)

        XCTAssertEqual(decoded.results.count, 1)
        let page = try XCTUnwrap(decoded.results.first)
        XCTAssertEqual(page.id, "task-1")
        XCTAssertEqual(page.properties["Name"]?.title?.first?.plainText, "Pay rent")
        XCTAssertEqual(page.properties["Status"]?.status?.name, "Not Started")
        XCTAssertEqual(page.properties["Due Date"]?.date?.start, "2026-03-20")
        XCTAssertEqual(page.properties["Priority"]?.select?.name, "High")
        XCTAssertEqual(page.properties["Tags"]?.multiSelect?.first?.name, "Finance")
        XCTAssertEqual(page.properties["Project"]?.relation?.first?.id, "proj-1")
    }

    func testQueryResponseDecoding_WithSparseFields_StillDecodesWithoutCrashing() throws {
        let json = """
        {
          "results": [
            {
              "id": "task-2",
              "last_edited_time": "2026-03-13T10:00:00.000Z",
              "properties": {
                "Name": { "type": "title", "title": [] },
                "Status": { "type": "status", "status": { "name": "Done" } },
                "Due Date": { "type": "date", "date": null }
              }
            }
          ],
          "has_more": false,
          "next_cursor": null
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(NotionDatabaseQueryResponse.self, from: data)

        XCTAssertEqual(decoded.results.count, 1)
        let page = try XCTUnwrap(decoded.results.first)
        XCTAssertEqual(page.properties["Status"]?.status?.name, "Done")
        XCTAssertNil(page.properties["Due Date"]?.date?.start)
    }
}

private final class ForbiddenNotionURLProtocol: URLProtocol {
    static let message = "You do not have permission to edit this database."

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = Data(
            """
            {"object":"error","status":403,"code":"restricted_resource","message":"\(Self.message)"}
            """.utf8
        )

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
