import Foundation
import Rendering
import XCTest

@testable import PlantUMLCore

final class SemanticTests: XCTestCase {
  var fixture: String {
    get throws { try String(contentsOfFile: "Fixtures/semantic-workflow.puml", encoding: .utf8) }
  }
  func testSemanticNamesBranchesAndSettings() throws {
    let doc = SourceDocument.parse(try fixture)
    XCTAssertTrue(doc.canEdit)
    let sections = SemanticStructure.sections(doc)
    let participants = try XCTUnwrap(sections.first { $0.id == "objects" })
    XCTAssertEqual(participants.nodes.map(\.title), ["Client", "Service", "Worker"])
    XCTAssertEqual(participants.nodes[0].subtitle, "Boundary")
    XCTAssertEqual(participants.nodes[0].color, "#DDDDFF")
    let scenario = try XCTUnwrap(sections.first { $0.id == "scenario" })
    XCTAssertEqual(scenario.nodes[0].title, "Отправить запрос")
    XCTAssertEqual(scenario.nodes[0].subtitle, "Client → Service")
    XCTAssertFalse(scenario.nodes.contains { SemanticStructure.isSetting($0.element) })
    let alt = try XCTUnwrap(scenario.nodes.first { $0.title.hasPrefix("ALT:") })
    XCTAssertEqual(alt.children.count, 3)
    XCTAssertTrue(alt.children[0].initialBranch)
    XCTAssertEqual(alt.children[0].children.first?.title, "LOOP: Повторная проверка")
    XCTAssertEqual(alt.children[0].children.first?.children.last?.title, "OPT: Есть результат")
    XCTAssertEqual(alt.children[1].children.map(\.title), ["Сохранить решение", "Обновить задачу"])
    XCTAssertEqual(alt.children[2].children.first?.children.count, 2)
    let results = SemanticStructure.sections(doc, query: "Проверка данных")
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.nodes.first?.children.count, 1)
    XCTAssertTrue(
      sections.first { $0.id == "settings" }!.nodes.contains { $0.element.kind == "diagramSetting" }
    )
    _ = try Renderer.render(doc.source)
  }
  func testERAttributesAndCardinalityNeverInferPK() throws {
    let doc = SourceDocument.parse(
      "@startuml\nentity \"Customer\" as C {\n  id : UUID\n  * key : UUID <<PK>>\n  --\n  email : VARCHAR\n}\nentity Order {\n  id : UUID\n}\nC ||--o{ Order : places\n@enduml\n"
    )
    let sections = SemanticStructure.sections(doc)
    let entity = sections[0].nodes[0]
    XCTAssertEqual(entity.title, "Customer")
    XCTAssertEqual(entity.children[0].title, "id · UUID")
    XCTAssertEqual(entity.children[1].title, "key · UUID · PK")
    XCTAssertEqual(sections[1].nodes[0].title, "Customer → Order")
    XCTAssertEqual(sections[1].nodes[0].subtitle, "1 : 0…N · places")
    let moved = try ConstructorOperations.move(entity.children[1].element, up: true, in: doc)
    XCTAssertTrue(moved.contains("  * key : UUID <<PK>>\n  id : UUID"))
    _ = try Renderer.render(moved)
  }
  func testCombinedPropertiesAliasNotesAndPreservation() throws {
    let doc = SourceDocument.parse(
      "@startuml\r\n' preserved 😀\r\nparticipant \"Front\" as F #DDDDFF\r\nparticipant B\r\nskinparam roundcorner 12\r\nnote over F,B : F is literal prose\r\nF -> B : Request\r\n@enduml\r\n"
    )
    let participant = doc.elements.first { $0.kind == "participant" }!
    let edited = try SemanticOperations.properties(
      ["name": "New Front", "alias": "Client", "color": "#00AA88"], of: participant, in: doc)
    XCTAssertTrue(edited.contains("participant \"New Front\" as Client #00AA88"))
    XCTAssertTrue(edited.contains("note over Client,B : F is literal prose"))
    XCTAssertTrue(edited.contains("Client -> B : Request"))
    XCTAssertTrue(edited.contains("' preserved 😀\r\n"))
    XCTAssertTrue(edited.contains("skinparam roundcorner 12\r\n"))
    XCTAssertThrowsError(
      try SemanticOperations.properties(["label": "bad\nend"], of: doc.elements.last!, in: doc))
    let stale = SourceDocument.parse(edited)
    XCTAssertThrowsError(
      try SemanticOperations.properties(["name": "Oops"], of: participant, in: stale))
    _ = try Renderer.render(edited)
  }
  func testDisplayNameKeepsBareIdentifierReferences() throws {
    let doc = SourceDocument.parse("@startuml\nparticipant A\nA -> A : hi\n@enduml")
    let edited = try SemanticOperations.properties(
      ["name": "Readable Name"], of: doc.elements[0], in: doc)
    XCTAssertTrue(edited.contains("participant \"Readable Name\" as A"))
    XCTAssertTrue(edited.contains("A -> A : hi"))
  }
  func testDependenciesRequireExplicitCascadeAndUnknownBlocksIt() throws {
    let doc = SourceDocument.parse(
      "@startuml\nparticipant A\nparticipant B\nnote over A,B : note\nA -> B : request\nB -> B : unrelated\n@enduml\n"
    )
    let a = doc.elements[0]
    XCTAssertEqual(try SemanticOperations.dependencies(of: a, in: doc).count, 2)
    XCTAssertThrowsError(try SemanticOperations.delete(a, includingDependencies: false, in: doc))
    let deleted = try SemanticOperations.delete(a, includingDependencies: true, in: doc)
    XCTAssertEqual(deleted, "@startuml\nparticipant B\nB -> B : unrelated\n@enduml\n")
    let unsafe = SourceDocument.parse(
      doc.source.replacingOccurrences(of: "@enduml", with: "!define TARGET A\n@enduml"))
    XCTAssertThrowsError(
      try SemanticOperations.delete(unsafe.elements[0], includingDependencies: true, in: unsafe))
    _ = try Renderer.render(deleted)
  }
  func testInsertionAndDeletionRespectBranchBoundaries() throws {
    let doc = SourceDocument.parse(try fixture)
    let alt = doc.elements.first { $0.kind == "block" }!
    let branch = doc.elements.first { $0.kind == "branch" }!
    let first = try SemanticOperations.insertIntoFirstBranch(
      "client -> worker : first added", block: alt, in: doc)
    XCTAssertTrue(first.contains("first added\nelse request_valid"))
    let second = try SemanticOperations.insert(
      "client -> worker : second added", intoBranch: branch, in: doc)
    XCTAssertTrue(second.contains("second added\nelse Проверка отложена"))
    let deleted = try SemanticOperations.delete(branch, includingDependencies: false, in: doc)
    XCTAssertFalse(deleted.contains("Обновить задачу"))
    XCTAssertTrue(deleted.contains("else Проверка отложена"))
    XCTAssertTrue(SourceDocument.parse(deleted).canEdit)
    _ = try Renderer.render(second)
    _ = try Renderer.render(deleted)
  }
  func testSettingsPreserveUnknownAndComplexAutonumber() throws {
    let doc = SourceDocument.parse(try fixture)
    let changed = try SemanticOperations.setAutonumber(false, in: doc)
    XCTAssertFalse(changed.contains("\nautonumber\n"))
    XCTAssertTrue(changed.contains("skinparam sequence {\n  LifeLineBorderColor #334155\n}"))
    let complex = SourceDocument.parse(
      doc.source.replacingOccurrences(of: "autonumber", with: "autonumber 10 5"))
    XCTAssertThrowsError(try SemanticOperations.setAutonumber(false, in: complex))
  }
  func testIdentitiesSurviveMoveAndInsertionWithoutStealing() throws {
    let doc = SourceDocument.parse(
      "@startuml\nparticipant A\nA -> A : first\nA -> A : second\n@enduml\n")
    let messages = doc.elements.filter { $0.kind == "message" }
    let moved = SourceDocument.reconcile(
      SourceDocument.parse(try ConstructorOperations.move(messages[1], up: true, in: doc)),
      with: doc)
    XCTAssertEqual(moved.elements.first { $0.text.contains("second") }?.id, messages[1].id)
    let inserted = SourceDocument.reconcile(
      SourceDocument.parse(
        doc.source.replacingOccurrences(of: "A -> A : first", with: "A -> A : new\nA -> A : first")),
      with: doc)
    XCTAssertEqual(inserted.elements.first { $0.text.contains("first") }?.id, messages[0].id)
    XCTAssertNotEqual(inserted.elements.first { $0.text.contains("new") }?.id, messages[0].id)
  }
  func testImplicitParticipantsAndReverseDirection() {
    let doc = SourceDocument.parse("@startuml\nAlice <- Bob : Reply\n@enduml")
    let sections = SemanticStructure.sections(doc)
    XCTAssertEqual(sections[0].nodes.map(\.title), ["Alice", "Bob"])
    XCTAssertEqual(sections[0].nodes.map(\.implicitIdentifier), ["Alice", "Bob"])
    XCTAssertEqual(sections[1].nodes[0].subtitle, "Bob → Alice")
  }
  func testStaleRowsNeverReadRangesFromReplacementDocument() throws {
    let old = SourceDocument.parse(try fixture)
    let replacement = SourceDocument.parse("@startuml\nA -> B : hi\n@enduml")
    for element in old.elements {
      XCTAssertThrowsError(try ConstructorOperations.move(element, up: true, in: replacement))
      XCTAssertThrowsError(try ConstructorOperations.span(element, in: replacement))
      XCTAssertThrowsError(
        try SemanticOperations.properties(["label": "Changed"], of: element, in: replacement))
    }
  }
  func testAddingAliasPreservesDisplayNameAndUpdatesQuotedReferences() throws {
    for declaration in ["participant A", "participant \"Some Name\""] {
      let identity = declaration.replacingOccurrences(of: "participant ", with: "")
      let doc = SourceDocument.parse(
        "@startuml\n" + declaration + "\n" + identity + " -> " + identity + " : hi\n@enduml")
      let changed = try SemanticOperations.properties(
        ["alias": "NewAlias"], of: doc.elements[0], in: doc)
      XCTAssertTrue(changed.contains("NewAlias -> NewAlias : hi"))
      let parsed = SourceDocument.parse(changed)
      XCTAssertEqual(
        SemanticStructure.readable(
          SemanticStructure.value("name", of: parsed.elements[0], in: parsed)),
        SemanticStructure.readable(identity))
      XCTAssertEqual(
        SemanticStructure.value("alias", of: parsed.elements[0], in: parsed), "NewAlias")
      _ = try Renderer.render(changed)
    }
  }
  func testMultilineNoteEditPreservesCRLFAndCannotEscapeNote() throws {
    let doc = SourceDocument.parse(
      "@startuml\r\nparticipant A\r\nnote over A\r\nold\r\ntext\r\nend note\r\nA -> A : hi\r\n@enduml\r\n"
    )
    let note = doc.elements.first { $0.kind == "note" }!
    XCTAssertTrue(
      SourceDocument.hasLineBreak(note.text), "note=\(note.text), diagnostics=\(doc.diagnostics)")
    let edited = try SemanticOperations.properties(["label": "new\ntext\n"], of: note, in: doc)
    XCTAssertTrue(edited.contains("note over A\r\nnew\r\ntext\r\nend note"))
    XCTAssertThrowsError(
      try SemanticOperations.properties(
        ["label": "end note\nparticipant Evil\n"], of: note, in: doc))
    _ = try Renderer.render(edited)
  }
  func testCRLFIsRejectedInSingleLinePropertiesAndAliases() throws {
    let doc = SourceDocument.parse("@startuml\nparticipant A\nA -> A : hi\n@enduml")
    XCTAssertTrue(SourceDocument.hasLineBreak("first\r\nsecond"))
    XCTAssertThrowsError(
      try SourceDocument.changeField(
        "label", of: doc.elements[1], to: "bad\r\nA -> A : injected", in: doc))
    XCTAssertThrowsError(
      try ConstructorOperations.renameAlias(doc.elements[0], to: "NewAlias\r\n", in: doc))
  }
  func testAttributeWithoutTypeAndQuotedNameWithoutAlias() throws {
    let er = SourceDocument.parse("@startuml\nentity Customer {\n  * id <<PK>>\n}\n@enduml")
    let attribute = er.elements.first { $0.kind == "attribute" }!
    let changed = try SemanticOperations.properties(["datatype": "UUID"], of: attribute, in: er)
    XCTAssertTrue(changed.contains("* id : UUID <<PK>>"))
    _ = try Renderer.render(changed)
    let sequence = SourceDocument.parse(
      "@startuml\nparticipant \"Old Name\"\n\"Old Name\" -> \"Old Name\" : hi\n@enduml")
    let renamed = try SemanticOperations.properties(
      ["name": "New Name"], of: sequence.elements[0], in: sequence)
    XCTAssertTrue(renamed.contains("participant \"New Name\" as Object1"))
    XCTAssertTrue(renamed.contains("Object1 -> Object1 : hi"))
    _ = try Renderer.render(renamed)
  }
  func testComponentBracketPropertyFormPreservesIdentity() throws {
    let doc = SourceDocument.parse(
      "@startuml\n[API]\ncomponent Worker\n[API] --> Worker : uses\n@enduml")
    let edited = try SemanticOperations.properties(
      ["name": "Display Name"], of: doc.elements[0], in: doc)
    XCTAssertTrue(edited.contains("[Display Name] as API"))
    XCTAssertTrue(edited.contains("[API] --> Worker"))
    _ = try Renderer.render(edited)
    let renamed = try SemanticOperations.properties(
      ["alias": "Backend", "name": "Display Name"], of: doc.elements[0], in: doc)
    XCTAssertTrue(renamed.contains("[Display Name] as Backend"))
    XCTAssertTrue(renamed.contains("[Backend] --> Worker"))
    _ = try Renderer.render(renamed)
  }
  func testNotePositionTargetAndColorAreSeparateProperties() throws {
    for note in [
      "note right of A #LightBlue : hello", "note right of A #LightBlue\nhello\nend note",
    ] {
      let doc = SourceDocument.parse(
        "@startuml\nparticipant A\nparticipant B\n" + note + "\nA -> B : hi\n@enduml")
      let element = doc.elements.first { $0.kind == "note" }!
      XCTAssertEqual(SemanticStructure.value("target", of: element, in: doc), "A")
      XCTAssertEqual(SemanticStructure.value("color", of: element, in: doc), "#LightBlue")
      let edited = try SemanticOperations.properties(
        ["position": "over", "target": "B"], of: element, in: doc)
      XCTAssertTrue(edited.contains("note over B #LightBlue"))
      _ = try Renderer.render(edited)
    }
  }
  func testLargeSemanticTree() {
    let source =
      "@startuml\nparticipant A\nparticipant B\n"
      + (0..<1500).map { "loop Step \($0)\nA -> B : Message \($0)\nend" }.joined(separator: "\n")
      + "\n@enduml"
    let start = Date()
    let doc = SourceDocument.parse(source)
    let sections = SemanticStructure.sections(doc)
    XCTAssertEqual(sections.first { $0.id == "scenario" }?.nodes.count, 1500)
    let next = SourceDocument.reconcile(
      SourceDocument.parse("' Added comment\n" + source), with: doc)
    XCTAssertEqual(next.elements.map(\.id), doc.elements.map(\.id))
    XCTAssertLessThan(Date().timeIntervalSince(start), 5)
  }
}
