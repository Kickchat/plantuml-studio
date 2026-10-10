import AppKit
import ERModule
import PlantUMLCore
import Rendering
import SequenceModule
import SwiftUI
import WebKit

@MainActor final class Workspace: ObservableObject {
  @Published var documents: [StudioDocument] = []
  @Published var selected: UUID?
  init() {
    if ProcessInfo.processInfo.environment["PLANTUML_STUDIO_SMOKE_DIR"] == nil,
      let session = UserDefaults.standard.array(forKey: "sessionDocuments") as? [[String: String]]
    {
      documents = session.compactMap { state in
        guard let source = state["source"] else { return nil }
        let url = state["path"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let doc = StudioDocument(source: source, url: url)
        doc.restoreSavedState(url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
        return doc
      }
    }
    if documents.isEmpty { new(.sequence) } else { selected = documents.first?.id }
  }
  var current: StudioDocument? { documents.first { $0.id == selected } }
  func new(_ kind: DiagramKind) {
    let doc = StudioDocument(source: kind == .er ? erTemplate : sequenceTemplate)
    documents.append(doc)
    selected = doc.id
  }
  func open() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = []
    guard panel.runModal() == .OK else { return }
    for url in panel.urls {
      do {
        let doc = StudioDocument(source: try String(contentsOf: url, encoding: .utf8), url: url)
        documents.append(doc)
        selected = doc.id
      } catch {
        let alert = NSAlert()
        alert.messageText = error.localizedDescription
        alert.runModal()
      }
    }
  }
  func close(_ doc: StudioDocument) {
    if doc.dirty {
      let alert = NSAlert()
      alert.messageText = "Сохранить изменения в \(doc.name)?"
      alert.addButton(withTitle: "Сохранить")
      alert.addButton(withTitle: "Отмена")
      alert.addButton(withTitle: "Не сохранять")
      let result = alert.runModal()
      if result == .alertSecondButtonReturn { return }
      if result == .alertFirstButtonReturn {
        doc.save()
        if doc.dirty { return }
      }
    }
    documents.removeAll { $0.id == doc.id }
    if selected == doc.id { selected = documents.first?.id }
  }
  func persist() {
    UserDefaults.standard.set(
      documents.map { ["source": $0.source, "path": $0.url?.path ?? ""] },
      forKey: "sessionDocuments")
  }
}
