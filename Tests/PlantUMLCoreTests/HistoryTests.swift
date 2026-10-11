import Foundation
import PlantUMLCore
import XCTest

final class HistoryTests: XCTestCase {
  func testRoundtripDedupeLimitsAndSeparateDocuments() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = VersionHistory(directory: dir)
    XCTAssertEqual(try store.versions(for: "missing").count, 0)
    for source in ["one", "two", "three", "three"] {
      try store.record(source, for: "file1", limits: HistoryLimits(count: 2))
    }
    XCTAssertEqual(try store.versions(for: "file1").map(\.source), ["two", "three"])
    try store.record("other", for: "file2")
    XCTAssertEqual(try store.versions(for: "file2").map(\.source), ["other"])
    try store.record(
      String(repeating: "x", count: 3000), for: "file1", limits: HistoryLimits(bytes: 1024))
    XCTAssertTrue(try store.versions(for: "file1").isEmpty)
  }
}
