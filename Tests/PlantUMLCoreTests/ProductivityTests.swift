import Foundation
import XCTest

@testable import PlantUMLCore

final class ProductivityTests: XCTestCase {
  let source =
    "@startuml\r\nparticipant A\r\nparticipant B\r\nloop retries\r\n  A -> B : Request\r\n  B --> A : Response\r\nend\r\n@enduml\r\n"
  func testOutlineAndCursor() {
    let doc = SourceDocument.parse(source)
    let tree = DocumentNavigation.outline(doc)
    let block = tree.first { $0.element.kind == "block" }!
    XCTAssertEqual(block.children.count, 2)
    XCTAssertEqual(
      DocumentNavigation.element(at: block.children[0].element.range.location + 3, in: doc)?.id,
      block.children[0].id)
    XCTAssertNil(DocumentNavigation.element(at: 0, in: doc))
    XCTAssertEqual(DocumentNavigation.search("response", in: doc).count, 1)
  }
  func testSearchCapturesCaseAndLiteralReplacement() throws {
    let text = "API api 😀"
    XCTAssertEqual(try SourceSearch.matches("api", in: text, options: SearchOptions()).count, 2)
    XCTAssertEqual(
      try SourceSearch.matches("api", in: text, options: SearchOptions(caseSensitive: true)).count,
      1)
    XCTAssertEqual(
      try SourceSearch.replace("api", with: "$1", in: text, options: SearchOptions()), "$1 $1 😀")
    XCTAssertEqual(
      try SourceSearch.replace(
        "(A)(PI)", with: "$2$1", in: text, options: SearchOptions(caseSensitive: true, regex: true)),
      "PIA api 😀")
    XCTAssertThrowsError(
      try SourceSearch.matches("[", in: text, options: SearchOptions(regex: true)))
  }
  func testReplyDuplicateWrapPreserveCRLF() throws {
    let doc = SourceDocument.parse(source)
    let messages = doc.elements.filter { $0.kind == "message" }
    let reply = try QuickOperations.reply(to: messages[0], in: doc)
    XCTAssertTrue(reply.contains("  A -> B : Request\r\n  B --> A : Response\r\n"))
    let duplicated = try QuickOperations.duplicate(messages[0], in: doc)
    XCTAssertEqual(duplicated.components(separatedBy: "A -> B : Request").count, 3)
    let wrapped = try QuickOperations.wrap(messages, with: "opt", in: doc)
    XCTAssertTrue(
      wrapped.contains("  opt condition\r\n  A -> B : Request\r\n  B --> A : Response\r\n  end\r\n")
    )
    XCTAssertTrue(SourceDocument.parse(wrapped).canEdit)
    XCTAssertThrowsError(try QuickOperations.wrap([doc.elements[0]], with: "alt", in: doc))
  }
  func testEntityDuplicateAndAttributes() throws {
    let doc = SourceDocument.parse(
      "@startuml\nentity User {\n id : integer\n}\nentity User2 {\n id : integer\n}\nUser ||--o{ User2\n@enduml\n"
    )
    let entity = doc.elements.first { $0.kind == "entity" }!
    let duplicate = try QuickOperations.duplicate(entity, in: doc)
    XCTAssertTrue(duplicate.contains("entity User3 {"))
    XCTAssertTrue(duplicate.contains("User ||--o{ User2"))
    let attributes = try QuickOperations.addAttributes(
      "name : text\n* email : text", to: entity, in: doc)
    XCTAssertTrue(SourceDocument.parse(attributes).canEdit)
    XCTAssertThrowsError(try QuickOperations.addAttributes("}\nentity Evil {", to: entity, in: doc))
  }
  func testSafeFormatPreservesUnknownAndComments() throws {
    let doc = SourceDocument.parse(
      "@startuml\nparticipant A\nloop x\nA -> A : self\n' comment\n  skinparam backgroundColor white\nend\n@enduml"
    )
    let formatted = try QuickOperations.format(
      NSRange(location: 0, length: (doc.source as NSString).length), in: doc)
    XCTAssertTrue(formatted.contains("  A -> A : self"))
    XCTAssertTrue(formatted.contains("' comment\n  skinparam backgroundColor white"))
  }
}

extension ProductivityTests {
  func testBuiltInTemplatesAndConflicts() throws {
    XCTAssertEqual(TemplateLibrary.builtins.count, 11)
    for template in TemplateLibrary.builtins {
      let kind: DiagramKind = template.kind == "er" ? .er : .sequence
      let initial =
        kind == .er
        ? "@startuml\nentity Item {\n id : integer\n}\n@enduml\n"
        : "@startuml\nparticipant Client\nparticipant API\n@enduml\n"
      let doc = SourceDocument.parse(initial, mode: kind)
      let first = try TemplateLibrary.insert(template, in: doc)
      let second = try TemplateLibrary.insert(template, in: SourceDocument.parse(first, mode: kind))
      XCTAssertTrue(SourceDocument.parse(second, mode: kind).canEdit, template.name)
      let parsed = SourceDocument.parse(second, mode: kind)
      let ns = second as NSString
      let names = parsed.elements.filter { ["participant", "entity"].contains($0.kind) }.compactMap
      { ($0.fields["alias"] ?? $0.fields["name"]).map { ns.substring(with: $0) } }
      XCTAssertEqual(Set(names).count, names.count, template.name)
    }
  }
}

extension ProductivityTests {
  func testEditorAssistance() {
    let doc = SourceDocument.parse(source)
    XCTAssertEqual(EditorAssistance.completions(prefix: "pa", in: doc), ["par", "participant"])
    XCTAssertEqual(
      EditorAssistance.newline(after: "  loop retries", newline: "\r\n"), "\r\n    \r\n  end")
    XCTAssertEqual(EditorAssistance.newline(after: "A -> B : hi"), "\n")
    let block = doc.elements.first { $0.kind == "block" }!
    let range = EditorAssistance.foldableBody(of: block, in: doc)!
    XCTAssertEqual(
      (source as NSString).substring(with: range), "  A -> B : Request\r\n  B --> A : Response\r\n")
  }
}

extension ProductivityTests {
  func testSyntaxHintsCoverRecognizedModel() {
    let doc = SourceDocument.parse(source)
    for node in doc.elements { XCTAssertFalse(SyntaxHints.hint(for: node, in: doc).isEmpty) }
    XCTAssertTrue(
      SyntaxHints.hint(for: doc.elements.first { $0.kind == "message" }!, in: doc).contains("->>"))
  }
}
