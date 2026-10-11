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
      undoManager.registerUndo(withTarget: self) { target in
        MainActor.assumeIsolated { target.source = previous }
      }
      dirty = source != savedSource
      selection = nil
      selectedTextRange = nil
      navigationRange = nil
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
  @Published var multiSelection: Set<Int> = []
  @Published var selection: Int?
  @Published var paletteVisible = false
  @Published var focusRequest = ""
  @Published var searchVisible = false
  @Published var selectedTextRange: NSRange?
  @Published var navigationRange: NSRange?
  @Published var previewReturn = 0
  @Published var zoom = 1.0
  private var task: Task<Void, Never>?
  private var revision = 0
  private var renderCancellation: RenderCancellation?
  init(source: String, url: URL? = nil) {
    self.source = source
    self.savedSource = url == nil ? "" : source
    self.url = url
    dirty = url == nil
    parsed = SourceDocument.parse(source)
    refresh()
  }
  deinit {
    renderCancellation?.cancel()
    task?.cancel()
  }
  var errorLine: Int? {
    let lines = error.components(separatedBy: "\n")
    guard let index = lines.firstIndex(of: "ERROR"), lines.count > index + 1 else { return nil }
    return Int(lines[index + 1])
  }
  var savedText: String { savedSource }
  var history: VersionHistory {
    let root =
      ProcessInfo.processInfo.environment["PLANTUML_STUDIO_SMOKE_DIR"].map {
        URL(fileURLWithPath: $0)
      }
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("PlantUML Studio")
    return VersionHistory(directory: root.appendingPathComponent("History"))
  }
  var historyLimits: HistoryLimits {
    let count = UserDefaults.standard.integer(forKey: "studio.history.count")
    let megabytes = UserDefaults.standard.integer(forKey: "studio.history.mb")
    return HistoryLimits(
      count: count > 0 ? count : 30, bytes: (megabytes > 0 ? megabytes : 20) * 1024 * 1024)
  }
  var name: String { url?.lastPathComponent ?? "Untitled.puml" }
  func refresh() {
    renderingValid = false
    revision += 1
    let version = revision
    let snapshot = source
    let previous = parsed
    let mode = modeOverride
    task?.cancel()
    renderCancellation?.cancel()
    let cancellation = RenderCancellation()
    renderCancellation = cancellation
    task = Task {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      let (candidate, result) = await Task.detached {
        let candidate = SourceDocument.reconcile(
          SourceDocument.parse(snapshot, mode: mode), with: previous)
        let result = Result { try Renderer.render(snapshot, cancellation: cancellation) }
        return (candidate, result)
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
      do {
        try history.record(source, for: target.standardizedFileURL.path, limits: historyLimits)
      } catch {
        operationError = "Файл сохранён; история недоступна: " + error.localizedDescription
      }
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
