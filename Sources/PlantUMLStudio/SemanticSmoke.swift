import AppKit
import PlantUMLCore
import StudioDesign
import SwiftUI
import WebKit

@MainActor enum SemanticSmoke {
  static func run(directory: URL) async throws {
    let fixture =
      "@startuml\n' Preserved comment\nskinparam sequenceMessageAlign left\nboundary \"Client\" as F #DDDDFF\nparticipant \"Service\" as B\nautonumber\nalt Проверка запроса\n F -> B : Отправить запрос\n loop Повторная проверка\n  B -> B : Проверка данных\n end\nelse Отказ\n opt Сообщить клиенту\n  B --> F : Результат обработки\n end\nend\n@enduml\n"
    let document = StudioDocument(source: fixture)
    try await SmokeTest.wait { document.canEdit }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1160, height: 780),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let workspace = Workspace()
    workspace.documents = [document]
    workspace.selected = document.id
    window.contentView = NSHostingView(
      rootView: DocumentView(workspace: workspace, document: document))
    window.makeKeyAndOrderFront(nil)
    defer {
      window.orderOut(nil)
      ThemeStore.shared.mode = .system
    }
    try await Task.sleep(for: .seconds(1))
    let sections = SemanticStructure.sections(document.parsed)
    guard sections.first?.nodes.map(\.title) == ["Client", "Service"],
      let block = document.parsed.elements.first(where: { $0.kind == "block" }),
      let message = document.parsed.elements.first(where: { $0.kind == "message" })
    else { throw SmokeTest.failure("Semantic presentation failed") }
    let blockKey = "element-\(block.id)"
    document.collapsedSemanticNodes.insert(blockKey)
    document.selectObject(message)
    guard !document.collapsedSemanticNodes.contains(blockKey),
      document.navigationRange == message.range
    else { throw SmokeTest.failure("Constructor selection did not reveal ancestors and code") }
    document.collapsedSemanticNodes.insert(blockKey)
    document.undoManager.removeAllActions()
    document.edit {
      try SemanticOperations.properties(["label": "Новый запрос"], of: message, in: document.parsed)
    }
    try await SmokeTest.wait { document.canEdit && document.source.contains("Новый запрос") }
    guard document.selection == message.id, document.collapsedSemanticNodes.contains(blockKey)
    else { throw SmokeTest.failure("Selection or collapse state lost on property edit") }
    document.undoManager.undo()
    try await SmokeTest.wait { document.canEdit && document.source == fixture }
    guard document.selection == message.id else {
      throw SmokeTest.failure("Selection lost on Undo")
    }
    document.undoManager.redo()
    try await SmokeTest.wait { document.canEdit && document.source.contains("Новый запрос") }
    let valid = document.source
    let validIDs = document.parsed.elements.map(\.id)
    document.source = valid.replacingOccurrences(of: "else Отказ", with: "else Отказ\nend\nend")
    try await SmokeTest.wait { !document.error.isEmpty }
    guard !document.canEdit, document.parsed.elements.map(\.id) == validIDs else {
      throw SmokeTest.failure("Invalid code destroyed last valid constructor state")
    }
    document.source = valid
    try await SmokeTest.wait { document.canEdit }
    document.selectObject(document.parsed.elements.first { $0.kind == "message" }!)
    func editors(_ root: NSView) -> [NSTextView] {
      (root as? NSTextView).map { [$0] } ?? root.subviews.flatMap(editors)
    }
    func webs(_ root: NSView) -> [WKWebView] {
      (root as? WKWebView).map { [$0] } ?? root.subviews.flatMap(webs)
    }
    try await Task.sleep(for: .milliseconds(400))
    guard let editor = editors(window.contentView!).first,
      editor.selectedRange().location == document.navigationRange?.location
    else { throw SmokeTest.failure("Object-to-code navigation did not select source") }
    let returnMessage = document.parsed.elements.last { $0.kind == "message" }!
    editor.setSelectedRange(NSRange(location: returnMessage.range.location + 2, length: 0))
    try await Task.sleep(for: .milliseconds(200))
    guard document.selection == returnMessage.id else {
      throw SmokeTest.failure("Code-to-object navigation failed")
    }
    func scrolls(_ root: NSView) -> [NSScrollView] {
      (root as? NSScrollView).map { [$0] } ?? root.subviews.flatMap(scrolls)
    }
    try await Task.sleep(for: .milliseconds(250))
    let constructorScrolls = scrolls(window.contentView!).filter {
      $0.convert($0.bounds, to: window.contentView!).minX > window.contentView!.bounds.width * 0.55
    }
    guard constructorScrolls.contains(where: { abs($0.contentView.bounds.origin.y) > 1 }) else {
      throw SmokeTest.failure("Constructor did not scroll to the object selected in code")
    }
    guard let web = webs(window.contentView!).first else {
      throw SmokeTest.failure("Semantic preview missing")
    }
    document.zoom = -1
    try await Task.sleep(for: .milliseconds(300))
    let coordinator = Preview.Coordinator(document)
    guard coordinator.element(["text": "Результат обработки"])?.id == returnMessage.id else {
      throw SmokeTest.failure("Exact SVG-to-model mapping failed")
    }
    // A repeated label must have no guessed SVG mapping.
    let repeated = StudioDocument(
      source: "@startuml\nparticipant A\nA -> A : Duplicate\nA -> A : Duplicate\n@enduml")
    try await SmokeTest.wait { repeated.canEdit }
    guard Preview.Coordinator(repeated).element(["text": "Duplicate"]) == nil else {
      throw SmokeTest.failure("Ambiguous SVG label was guessed")
    }
    for mode in [ThemeMode.light, .dark] {
      ThemeStore.shared.mode = mode
      try await Task.sleep(for: .milliseconds(350))
      try AppearanceSmoke.capture(
        window.contentView!, to: directory.appendingPathComponent("semantic-\(mode.rawValue).png"))
    }
    let beforeZoom = document.zoom
    document.constructorVisible = false
    window.setContentSize(NSSize(width: 1250, height: 800))
    try await Task.sleep(for: .milliseconds(300))
    let fitted =
      try await web.evaluateJavaScript("Number(document.querySelector('svg').style.zoom)")
      as? Double
    guard let fitted, fitted > 0, document.zoom == beforeZoom else {
      throw SmokeTest.failure("Fit or preserved zoom failed after panel resize")
    }
    document.constructorVisible = true
    document.source = "@startuml\nAlice -> Bob : Hello\n@enduml"
    try await SmokeTest.wait { document.canEdit }
    guard SemanticStructure.sections(document.parsed)[0].nodes.count == 2 else {
      throw SmokeTest.failure("Implicit participants absent")
    }
    let implicitSource = document.source
    document.selectImplicitParticipant(
      "Alice", reference: document.parsed.elements.first { $0.kind == "message" }!)
    guard document.source == implicitSource, document.selectedImplicitParticipant == "Alice" else {
      throw SmokeTest.failure("Implicit selection changed source")
    }
    document.declareParticipant("Alice")
    try await SmokeTest.wait { document.canEdit && document.source.contains("participant Alice") }
    guard
      document.parsed.elements.first(where: { $0.id == document.selection })?.kind == "participant"
    else { throw SmokeTest.failure("Implicit participant declaration did not open properties") }
    let empty = StudioDocument(source: "@startuml\nentity Only {\n id : UUID\n}\n@enduml")
    try await SmokeTest.wait { empty.canEdit }
    let only = empty.parsed.elements.first { $0.kind == "entity" }!
    empty.edit {
      try SemanticOperations.delete(only, includingDependencies: false, in: empty.parsed)
    }
    try await SmokeTest.wait { empty.canEdit && empty.parsed.elements.isEmpty }
    guard empty.parsed.kind == .er else {
      throw SmokeTest.failure("Deleting the last entity lost diagram context")
    }
    empty.edit { try SourceDocument.insert("entity Again {\n id : UUID\n}", in: empty.source) }
    try await SmokeTest.wait {
      empty.canEdit && empty.parsed.elements.contains { $0.kind == "entity" }
    }
    document.panelLayout = "Diagram"
    document.constructorQuery = "Alice"
    try await Task.sleep(for: .milliseconds(300))
    guard document.panelLayout == "Diagram", document.constructorQuery == "Alice" else {
      throw SmokeTest.failure("Per-document panel state missing")
    }
  }
}
