import XCTest

@testable import PlantUMLCore

final class SourceTests: XCTestCase {
  let sequence =
    "@startuml\r\n' Keep this comment\r\nactor \"User name\" as U\r\nparticipant API\r\nalt success\r\n  U -> API : hello\r\n  loop again\r\n    API --> U : reply\r\n  end\r\nelse failure\r\n  API -> U : no\r\nend\r\n@enduml\r\n"
  func testRoundTrip() throws {
    XCTAssertEqual(try SourceDocument.apply([], to: sequence), sequence)
  }
  func testNestedBlocks() {
    let d = SourceDocument.parse(sequence)
    XCTAssertEqual(d.kind, .sequence)
    XCTAssertTrue(d.canEdit)
    XCTAssertEqual(d.elements.filter { $0.kind == "message" }.map(\.depth), [1, 2, 1])
  }
  func testMinimalMessageEdit() throws {
    let d = SourceDocument.parse(sequence)
    let e = try XCTUnwrap(d.elements.first { $0.kind == "message" })
    let edited = try SourceDocument.changeField("label", of: e, to: "bonjour", in: d)
    XCTAssertEqual(edited, sequence.replacingOccurrences(of: "hello", with: "bonjour"))
  }
  func testAliasRenameOnlyReferences() throws {
    let d = SourceDocument.parse(sequence)
    let e = try XCTUnwrap(d.elements.first { $0.kind == "participant" })
    let edited = try ConstructorOperations.renameAlias(e, to: "Client", in: d)
    XCTAssertTrue(edited.contains("' Keep this comment\r\n"))
    XCTAssertTrue(edited.contains("as Client"))
    XCTAssertTrue(edited.contains("Client -> API"))
    XCTAssertTrue(edited.contains("API --> Client"))
  }
  func testUnknownReferenceBlocksRename() throws {
    let source = sequence.replacingOccurrences(of: "@enduml", with: "!define X U\r\n@enduml")
    let d = SourceDocument.parse(source)
    let e = try XCTUnwrap(d.elements.first { $0.kind == "participant" })
    XCTAssertThrowsError(try ConstructorOperations.renameAlias(e, to: "Client", in: d))
  }
  func testER() {
    let d = SourceDocument.parse(
      "@startuml\nentity \"User\" as U {\n * id : integer <<PK>>\n --\n name : text\n}\nentity Session {\n id : integer\n}\nU ||--o{ Session : owns\n@enduml\n"
    )
    XCTAssertEqual(d.kind, .er)
    XCTAssertTrue(d.canEdit)
    XCTAssertEqual(d.elements.filter { $0.kind == "attribute" }.count, 3)
    XCTAssertEqual(d.elements.filter { $0.kind == "relation" }.count, 1)
  }
  func testCardinalities() {
    for left in ["||", "|o", "}o", "}|"] {
      for right in ["||", "o|", "o{", "|{"] {
        let d = SourceDocument.parse("@startuml\nA \(left)..\(right) B\n@enduml")
        XCTAssertEqual(d.elements.first?.kind, "relation")
      }
    }
  }
  func testInvalidNesting() {
    XCTAssertFalse(
      SourceDocument.parse("@startuml\nparticipant A\nloop test\nelse bad\n@enduml").canEdit)
  }
  func testOverlappingEditsRejected() {
    XCTAssertThrowsError(
      try SourceDocument.apply(
        [
          TextEdit(range: NSRange(location: 0, length: 4), replacement: "x"),
          TextEdit(range: NSRange(location: 2, length: 2), replacement: "y"),
        ], to: "abcdef"))
  }
  func testUnicodeUTF16() throws {
    let source = "@startuml\nparticipant А\nА -> А : 😀 Привет\n@enduml"
    let d = SourceDocument.parse(source)
    let e = try XCTUnwrap(d.elements.first { $0.kind == "message" })
    XCTAssertEqual(
      try SourceDocument.changeField("label", of: e, to: "Ответ", in: d),
      source.replacingOccurrences(of: "😀 Привет", with: "Ответ"))
  }
  func testDeleteNestedBlock() throws {
    let d = SourceDocument.parse(sequence)
    let e = try XCTUnwrap(d.elements.first { $0.kind == "block" })
    let result = try ConstructorOperations.delete(e, in: d)
    XCTAssertFalse(result.contains("alt success"))
    XCTAssertTrue(result.contains("' Keep this comment"))
    XCTAssertTrue(SourceDocument.parse(result).canEdit)
  }
  func testMultilineNotePreserved() {
    let source =
      "@startuml\nparticipant A\nnote over A\nA -> B : not a message\nend note\nA -> A : real\n@enduml"
    let d = SourceDocument.parse(source)
    XCTAssertEqual(d.elements.filter { $0.kind == "message" }.count, 1)
    XCTAssertEqual(d.source, source)
  }
  func testInsertionPreservesCRLF() throws {
    let result = try SourceDocument.insert("U -> API : new", in: sequence)
    XCTAssertTrue(result.contains("U -> API : new\r\n@enduml"))
  }
}

extension SourceTests {
  func testAlternativeDeclarationForms() throws {
    let d = SourceDocument.parse(
      "@startuml\nparticipant U as \"User name\" #red order 10\nU -> U : hello\n@enduml")
    let e = try XCTUnwrap(d.elements.first { $0.kind == "participant" })
    let ns = d.source as NSString
    XCTAssertEqual(ns.substring(with: try XCTUnwrap(e.fields["alias"])), "U")
    XCTAssertEqual(ns.substring(with: try XCTUnwrap(e.fields["name"])), "\"User name\"")
    XCTAssertTrue(
      try ConstructorOperations.renameAlias(e, to: "Client", in: d).contains("Client -> Client"))
  }
  func testMoveDoesNotCrossComments() throws {
    let d = SourceDocument.parse(
      "@startuml\nparticipant A\nA -> A : first\n' Associated comment\nA -> A : second\n@enduml")
    let e = try XCTUnwrap(d.elements.last { $0.kind == "message" })
    XCTAssertThrowsError(try ConstructorOperations.move(e, up: true, in: d))
  }
  func testAliasInMultilineNoteRenamesTargetOnly() throws {
    let d = SourceDocument.parse(
      "@startuml\nparticipant \"User\" as U\nnote over U\nhello\nend note\nU -> U : message\n@enduml"
    )
    let e = try XCTUnwrap(d.elements.first { $0.kind == "participant" })
    let renamed = try ConstructorOperations.renameAlias(e, to: "Client", in: d)
    XCTAssertTrue(renamed.contains("note over Client\nhello\nend note"))
    XCTAssertTrue(renamed.contains("Client -> Client : message"))
  }
}

extension SourceTests {
  func testBlockExtentIgnoresEndInNote() throws {
    let source =
      "@startuml\nparticipant A\nalt test\nnote over A\nend\nend note\nA -> A : message\nend\n@enduml\n"
    let d = SourceDocument.parse(source)
    let block = try XCTUnwrap(d.elements.first { $0.kind == "block" })
    let deleted = try ConstructorOperations.delete(block, in: d)
    XCTAssertEqual(deleted, "@startuml\nparticipant A\n@enduml\n")
  }
  func testDeletionChecksNestedReferences() throws {
    let d = SourceDocument.parse(sequence)
    let participant = try XCTUnwrap(d.elements.first { $0.kind == "participant" })
    XCTAssertThrowsError(try ConstructorOperations.delete(participant, in: d))
  }
  func testIdentityAfterPrefixInsertion() {
    let previous = SourceDocument.parse(sequence)
    let next = SourceDocument.reconcile(
      SourceDocument.parse(
        sequence.replacingOccurrences(of: "actor", with: "' New comment\r\nactor")), with: previous)
    XCTAssertEqual(
      previous.elements.filter { $0.kind == "message" }.map(\.id),
      next.elements.filter { $0.kind == "message" }.map(\.id))
  }
}

extension SourceTests {
  func testInsertionPreservesClosingIndentation() throws {
    let source = "@startuml\nparticipant A\n  loop test\n    A -> A : first\n  end\n  @enduml\n"
    let d = SourceDocument.parse(source)
    let loop = try XCTUnwrap(d.elements.first { $0.kind == "block" })
    let result = try ConstructorOperations.insertInside(
      "A -> A : second", element: loop, document: d)
    XCTAssertEqual(
      result, source.replacingOccurrences(of: "  end\n", with: "    A -> A : second\n  end\n"))
    XCTAssertEqual(
      try SourceDocument.insert("title Hello", in: source),
      source.replacingOccurrences(of: "  @enduml", with: "title Hello\n  @enduml"))
  }
}

extension SourceTests {
  func testInvalidSentinelRangeRejected() {
    XCTAssertThrowsError(
      try SourceDocument.apply(
        [TextEdit(range: NSRange(location: NSNotFound, length: 1), replacement: "bad")],
        to: "source"))
  }
}
