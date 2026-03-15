import XCTest
@testable import Finally

final class NotionDataShapeUnitTests: XCTestCase {
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
