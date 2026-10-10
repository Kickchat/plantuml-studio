import PlantUMLCore
import Rendering
import XCTest

final class IntegrationTests: XCTestCase {
  func testOfficialSequenceSVGAndPNG() throws {
    let source = "@startuml\nactor User\nparticipant API\nUser -> API : Hello\n@enduml\n"
    let svg = try Renderer.render(source)
    XCTAssertTrue(String(decoding: svg.data, as: UTF8.self).contains("<svg"))
    let png = try Renderer.render(source, format: "png")
    XCTAssertEqual(Array(png.data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
  }
  func testOfficialERWithoutGraphviz() throws {
    let source =
      "@startuml\nentity User {\n * id : integer\n}\nentity Session {\n id : integer\n}\nUser ||--o{ Session : owns\n@enduml\n"
    let output = try Renderer.render(source)
    XCTAssertTrue(String(decoding: output.data, as: UTF8.self).contains("owns"))
  }
  func testConstructorToRendererAndFileRoundTrip() throws {
    let source = "@startuml\n' Keep this\nparticipant A\nparticipant B\nA -> B : hello\n@enduml\n"
    let parsed = SourceDocument.parse(source)
    let element = try XCTUnwrap(parsed.elements.first { $0.kind == "message" })
    let changed = try SourceDocument.changeField("label", of: element, to: "goodbye", in: parsed)
    let output = try Renderer.render(changed)
    XCTAssertTrue(String(decoding: output.data, as: UTF8.self).contains("goodbye"))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".puml")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(changed.utf8).write(to: file)
    let reopened = try String(contentsOf: file, encoding: .utf8)
    XCTAssertEqual(reopened, changed)
    XCTAssertEqual(SourceDocument.parse(reopened).source, changed)
  }
  func testOfficialSyntaxError() {
    XCTAssertThrowsError(try Renderer.render("@startuml\nthis is invalid syntax !!!\n@enduml"))
  }
  func testUnknownSyntaxStillRendersAndSurvives() throws {
    let source = "@startuml\nhide footbox\nparticipant A\nA -> A : hello\n@enduml\n"
    let parsed = SourceDocument.parse(source)
    XCTAssertTrue(parsed.elements.contains { $0.kind == "unsupported" })
    XCTAssertEqual(try SourceDocument.apply([], to: source), source)
    XCTAssertFalse(try Renderer.render(source).data.isEmpty)
  }
  func testMoveWithinBlockAndRejectAcrossBranch() throws {
    let source =
      "@startuml\nparticipant A\nalt case\nA -> A : first\nA -> A : second\nelse other\nA -> A : third\nend\n@enduml\n"
    let d = SourceDocument.parse(source)
    let messages = d.elements.filter { $0.kind == "message" }
    let moved = try ConstructorOperations.move(messages[1], up: true, in: d)
    XCTAssertTrue(moved.contains("A -> A : second\nA -> A : first"))
    XCTAssertFalse(try Renderer.render(moved).data.isEmpty)
    XCTAssertThrowsError(try ConstructorOperations.move(messages[2], up: true, in: d))
  }
}

extension IntegrationTests {
  func testFixtureCorpus() throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("Fixtures")
    for file in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "puml"
    {
      let source = try String(contentsOf: file, encoding: .utf8)
      XCTAssertEqual(
        try SourceDocument.apply([], to: SourceDocument.parse(source).source), source,
        file.lastPathComponent)
      if file.lastPathComponent == "invalid.puml" {
        XCTAssertThrowsError(try Renderer.render(source))
        continue
      }
      XCTAssertFalse(try Renderer.render(source).data.isEmpty, file.lastPathComponent)
    }
  }
}

extension IntegrationTests {
  func testAllConstructorArrowsParticipantsAndBlocks() throws {
    let types = [
      "actor", "participant", "boundary", "control", "entity", "database", "collections", "queue",
    ]
    let arrows = [
      "->", "-->", "->>", "-->>", "<-", "<--", "<<-", "<<--", "<->", "->x", "o->", "->o",
    ]
    var lines = ["@startuml"]
    lines += types.enumerated().map { "\($0.element) P\($0.offset)" }
    lines += arrows.map { "P0 \($0) P1 : \($0)" }
    for type in ["alt", "opt", "loop", "par", "break", "critical", "group"] {
      lines += ["\(type) test", "P0 -> P1 : inside \(type)"]
      if type == "alt" || type == "par" { lines += ["else branch", "P1 --> P0 : branch"] }
      lines += ["end"]
    }
    lines += ["@enduml"]
    let source = lines.joined(separator: "\n")
    let parsed = SourceDocument.parse(source)
    XCTAssertTrue(parsed.canEdit)
    XCTAssertEqual(parsed.elements.filter { $0.kind == "participant" }.count, 8)
    XCTAssertEqual(parsed.elements.filter { $0.kind == "block" }.count, 7)
    XCTAssertFalse(try Renderer.render(source).data.isEmpty)
  }
}
