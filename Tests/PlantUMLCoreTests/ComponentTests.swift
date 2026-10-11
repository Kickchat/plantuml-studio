import ComponentModule
import Foundation
import PlantUMLCore
import Rendering
import XCTest

final class ComponentTests: XCTestCase {
  let source =
    "@startuml\r\npackage Platform {\r\n component \"API Service\" as API #LightBlue\r\n interface Contract\r\n}\r\nnode Host {\r\n database Store\r\n}\r\nAPI --> Store : SQL\r\nContract ..> API : uses\r\n@enduml\r\n"
  func testTypedModelAndRanges() {
    let doc = SourceDocument.parse(source)
    XCTAssertEqual(doc.kind, .component)
    XCTAssertTrue(doc.canEdit)
    let model = ComponentModel(doc)
    XCTAssertEqual(model.nodes.count, 5)
    XCTAssertEqual(model.relationships.count, 2)
    let api = model.nodes.first { $0.alias == "API" }!
    XCTAssertNotNil(api.parent)
    XCTAssertEqual(api.name, "\"API Service\"")
  }
  func testRenameMoveAndSafeDelete() throws {
    let doc = SourceDocument.parse(source)
    let api = doc.elements.first { $0.fields["alias"] != nil }!
    let renamed = try ConstructorOperations.renameAlias(api, to: "Backend", in: doc)
    XCTAssertTrue(renamed.contains("Backend --> Store"))
    XCTAssertTrue(renamed.contains("Contract ..> Backend"))
    XCTAssertThrowsError(try ConstructorOperations.delete(api, in: doc))
    let platform = doc.elements.first { $0.kind == "container" }!
    XCTAssertThrowsError(try ConstructorOperations.delete(platform, in: doc))
    let host = doc.elements.last { $0.kind == "container" }!
    let moved = try ComponentOperations.move(api, into: host, in: doc)
    let result = SourceDocument.parse(moved)
    XCTAssertTrue(result.canEdit)
    XCTAssertEqual(
      ComponentModel(result).nodes.first { $0.alias == "API" }?.parent,
      result.elements.last { $0.kind == "container" }?.id)
    XCTAssertThrowsError(try ComponentOperations.move(platform, into: platform, in: doc))
  }
  func testTemplatesRenderAndConflictResolution() throws {
    for template in ComponentTemplates.builtins {
      let source = "@startuml\n" + template.fragment + "\n@enduml\n"
      XCTAssertTrue(SourceDocument.parse(source).canEdit, template.name)
      XCTAssertFalse(try Renderer.render(source).data.isEmpty)
      let inserted = try TemplateLibrary.insert(template, in: SourceDocument.parse(source))
      XCTAssertFalse(try Renderer.render(inserted).data.isEmpty, template.name)
    }
  }
  func testShorthandAndOpaqueStyle() {
    let doc = SourceDocument.parse(
      "@startuml\n[API] as Backend\n() Contract\nBackend --> Contract\n<style>\ncomponent {\n BackgroundColor blue\n}\n</style>\n@enduml"
    )
    XCTAssertTrue(doc.canEdit)
    XCTAssertEqual(ComponentModel(doc).nodes.count, 2)
    XCTAssertEqual(ComponentModel(doc).relationships.count, 1)
    XCTAssertEqual(doc.elements.filter { $0.kind == "unsupported" }.count, 5)
  }
}

extension ComponentTests {
  func testBracketReferencesAndUnknownGuard() throws {
    let doc = SourceDocument.parse("@startuml\n[API]\ncomponent Worker\n[API] --> Worker\n@enduml")
    let api = doc.elements.first { $0.kind == "component" }!
    let result = try ConstructorOperations.renameAlias(api, to: "Backend", in: doc)
    XCTAssertTrue(result.contains("[Backend] --> Worker"))
    let unsafe = SourceDocument.parse(
      doc.source.replacingOccurrences(
        of: "@enduml", with: "note right of API : unknown target\n@enduml"))
    XCTAssertThrowsError(
      try ConstructorOperations.renameAlias(unsafe.elements[0], to: "Backend", in: unsafe))
  }
  func testModuleContracts() {
    let contract = ComponentContract()
    XCTAssertTrue(contract.recognizes(source))
    XCTAssertTrue(contract.validate(contract.parse(source)).isEmpty)
    XCTAssertEqual(contract.declarationKinds, ["component", "interface", "container"])
  }
}

extension ComponentTests {
  func testOfficialShapesAndPNG() throws {
    let body =
      "@startuml\ncomponent API\ninterface Contract\npackage Group {\n node Host {\n  database Store\n }\n cloud External {\n  frame Boundary {\n   folder Files {\n    component Worker\n   }\n  }\n }\n}\nAPI --> Contract\nAPI ..> Store\nAPI o-- Worker : integration\n@enduml"
    let parsed = SourceDocument.parse(body)
    XCTAssertTrue(parsed.canEdit)
    XCTAssertEqual(Set(ComponentModel(parsed).nodes.map(\.type)), Set(ComponentType.allCases))
    XCTAssertFalse(try Renderer.render(body).data.isEmpty)
    let png = try Renderer.render(body, format: "png").data
    XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
  }
}

extension ComponentTests {
  func testComponentWordsInsideSequenceNoteDoNotChangeMode() {
    let sequence =
      "@startuml\nparticipant A\nnote right of A\ncomponent Example\nend note\nA -> A : hi\n@enduml"
    let doc = SourceDocument.parse(sequence)
    XCTAssertEqual(doc.kind, .sequence)
    XCTAssertTrue(doc.canEdit)
    XCTAssertEqual(doc.elements.filter { $0.kind == "note" }.count, 1)
    let commented = "@startuml\n/'\ncomponent Ignored\n'/\nparticipant A\nA -> A : hi\n@enduml"
    XCTAssertEqual(SourceDocument.parse(commented).kind, .sequence)
  }
}
