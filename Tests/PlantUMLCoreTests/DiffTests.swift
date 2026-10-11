import Foundation
import PlantUMLCore
import XCTest

final class DiffTests: XCTestCase {
  func testTextLineNumbersAndUnicode() {
    let rows = DiagramDiff.text("a\n😀\nc", "a\nchanged\nc\nd")
    XCTAssertEqual(rows[1].status, .modified)
    XCTAssertEqual(rows[1].leftLine, 2)
    XCTAssertEqual(rows[1].right, "changed")
    XCTAssertEqual(rows.last?.status, .added)
    XCTAssertEqual(rows.last?.rightLine, 4)
  }
  func testMessageChangeAndAmbiguity() {
    let left = "@startuml\nA -> B : one\n@enduml"
    let changed = DiagramDiff.compare(left, left.replacingOccurrences(of: "one", with: "two"))
    XCTAssertEqual(changed.changes.first?.status, .modified)
    let repeated = "@startuml\nA -> B : one\nA -> B : two\n@enduml"
    let ambiguous = DiagramDiff.compare(
      repeated, repeated.replacingOccurrences(of: "two", with: "three"))
    XCTAssertTrue(ambiguous.changes.allSatisfy { $0.status == .ambiguous })
  }
  func testERAttributeAndCardinality() {
    let left =
      "@startuml\nentity A {\n id : integer\n}\nentity B {\n id : integer\n}\nA ||--o{ B : owns\n@enduml"
    let right = left.replacingOccurrences(of: "id : integer", with: "id : text")
      .replacingOccurrences(of: "o{", with: "|{")
    let changes = DiagramDiff.compare(left, right).changes
    XCTAssertEqual(changes.filter { $0.status == .modified }.count, 3)
    XCTAssertFalse(changes.contains { $0.status == .ambiguous })
  }
  func testComponentContainerChangeAndFallback() {
    let a =
      "@startuml\npackage P {\n component API\n}\ncomponent Worker\nAPI --> Worker : call\n@enduml"
    let b = a.replacingOccurrences(of: "call", with: "event")
    XCTAssertEqual(DiagramDiff.compare(a, b).changes.first?.status, .modified)
    let mixed = DiagramDiff.compare(
      a, a.replacingOccurrences(of: "@enduml", with: "skinparam componentStyle rectangle\n@enduml"))
    XCTAssertTrue(mixed.changes.contains { $0.status == .textFallback })
    XCTAssertTrue(DiagramDiff.compare("invalid", a).textOnly)
  }
  func testReorderAndLargeFallback() {
    let a = "@startuml\nA -> B : one\nB -> C : two\n@enduml"
    let b = "@startuml\nB -> C : two\nA -> B : one\n@enduml"
    XCTAssertEqual(DiagramDiff.compare(a, b).changes.filter { $0.status == .moved }.count, 2)
    let lines = (0..<2100).map(String.init).joined(separator: "\n")
    XCTAssertEqual(DiagramDiff.text(lines, lines + "\nextra").last?.status, .added)
  }
}

extension DiffTests {
  func testTypeAndLineChange() {
    let component = "@startuml\ncomponent API\ncomponent Worker\nAPI --> Worker\n@enduml"
    let changes = DiagramDiff.compare(
      component, component.replacingOccurrences(of: "component API", with: "interface API")
    ).changes
    XCTAssertTrue(changes.contains { $0.status == .modified })
    let sequence = "@startuml\nA -> B : request\n@enduml"
    XCTAssertEqual(
      DiagramDiff.compare(sequence, sequence.replacingOccurrences(of: "->", with: "-->")).changes
        .first?.status, .modified)
  }
}
