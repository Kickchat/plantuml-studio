import AppKit
import ERModule
import PlantUMLCore
import Rendering
import SequenceModule
import SwiftUI
import WebKit

@MainActor final class StudioDocument: ObservableObject, Identifiable {
  let id = UUID()
  let undoManager = UndoManager()
  private var savedSource: String
  func restoreSavedState(_ saved: String) {
    savedSource = saved
    dirty = source != saved
  }
  @Published var source: String {
    didSet {
      guard source != oldValue else { return }
      let previous = oldValue
      undoManager.registerUndo(withTarget: self) { target in target.source = previous }
      dirty = source != savedSource
      selection = nil
      operationError = ""
      refresh()
    }
  }
  @Published var parsed: ParsedDocument
  @Published var svg = ""
  @Published var error = ""
  @Published var operationError = ""
  @Published var renderingValid = false
  @Published var dirty = false
  @Published var url: URL?
  @Published var modeOverride: DiagramKind? { didSet { refresh() } }
  @Published var selection: Int?
  private var task: Task<Void, Never>?
  private var revision = 0
  init(source: String, url: URL? = nil) {
    self.source = source
    self.savedSource = url == nil ? "" : source
    self.url = url
    dirty = url == nil
    parsed = SourceDocument.parse(source)
    refresh()
  }
  var errorLine: Int? {
    let lines = error.components(separatedBy: "\n")
    guard let index = lines.firstIndex(of: "ERROR"), lines.count > index + 1 else { return nil }
    return Int(lines[index + 1])
  }
  var name: String { url?.lastPathComponent ?? "Untitled.puml" }
  func refresh() {
    renderingValid = false
    revision += 1
    let version = revision
    let snapshot = source
    let candidate = SourceDocument.reconcile(
      SourceDocument.parse(source, mode: modeOverride), with: parsed)
    if !candidate.diagnostics.isEmpty { error = candidate.diagnostics.joined(separator: "\n") }
    task?.cancel()
    task = Task {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      let result = await Task.detached { () -> Result<RenderOutput, Error> in
        Result { try Renderer.render(snapshot) }
      }.value
      guard !Task.isCancelled, version == revision else { return }
      switch result {
      case .success(let output):
        if candidate.diagnostics.isEmpty {
          parsed = candidate
          renderingValid = true
        }
        svg = String(data: output.data, encoding: .utf8) ?? ""
        error = candidate.diagnostics.joined(separator: "\n")
      case .failure(let failure): error = failure.localizedDescription
      }
    }
  }
  var canEdit: Bool { renderingValid && parsed.source == source && parsed.canEdit && error.isEmpty }
  func edit(_ operation: () throws -> String) {
    guard canEdit else { return }
    do {
      let proposed = try operation()
      let original = source
      let candidate = SourceDocument.parse(proposed, mode: modeOverride)
      guard candidate.canEdit else { throw SourceError.invalidEdit }
      Task {
        let result = await Task.detached { Result { try Renderer.render(proposed) } }.value
        guard source == original else { return }
        switch result {
        case .success: source = proposed
        case .failure(let failure):
          operationError = "Изменение отклонено: \(failure.localizedDescription)"
        }
      }
    } catch { self.operationError = error.localizedDescription }
  }
  func save(asNew: Bool = false) {
    var target = url
    if asNew || target == nil {
      let panel = NSSavePanel()
      panel.nameFieldStringValue = name
      guard panel.runModal() == .OK else { return }
      target = panel.url
    }
    guard let target else { return }
    do {
      try Data(source.utf8).write(to: target, options: .atomic)
      url = target
      savedSource = source
      dirty = false
    } catch { self.error = error.localizedDescription }
  }
  func export(_ format: String) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = (name as NSString).deletingPathExtension + "." + format
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    let snapshot = source
    Task {
      let result = await Task.detached { Result { try Renderer.render(snapshot, format: format) } }
        .value
      do {
        let output = try result.get()
        try output.data.write(to: destination, options: .atomic)
      } catch { self.error = error.localizedDescription }
    }
  }
}
