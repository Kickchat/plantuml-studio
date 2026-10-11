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
  @Published var selection: Int? {
    didSet {
      if selection != oldValue { selectionFirstBranch = false }
      revealSelection()
    }
  }
  @Published var selectionFirstBranch = false
  @Published var selectedImplicitParticipant: String?
  @Published var collapsedSemanticNodes: Set<String> = []
  @Published var collapsedSemanticSections: Set<String> = ["settings"]
  @Published var constructorQuery = ""
  @Published var propertiesCollapsed = false
  @Published var constructorVisible = true
  @Published var panelLayout = "All"
  @Published var verticalPanels = false
  @Published var paletteVisible = false
  @Published var focusRequest = ""
  @Published var searchVisible = false
  @Published var selectedTextRange: NSRange?
  @Published var navigationRange: NSRange?
  @Published var previewReturn = 0
  @Published var zoom = 0.0
  private var task: Task<Void, Never>?
  private var revision = 0
  private var pendingParticipantSelection: String?
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
        var decoded = SourceDocument.parse(snapshot, mode: mode)
        if mode == nil, decoded.kind == .unknown, previous.kind != .unknown,
          DocumentNavigation.outline(decoded).allSatisfy({ SemanticStructure.isSetting($0.element) }
          )
        {
          decoded = SourceDocument.parse(snapshot, mode: previous.kind)
        }
        let candidate = SourceDocument.reconcile(decoded, with: previous)
        let result = Result { try Renderer.render(snapshot, cancellation: cancellation) }
        return (candidate, result)
      }.value
      guard !Task.isCancelled, version == revision else { return }
      switch result {
      case .success(let output):
        if candidate.diagnostics.isEmpty {
          parsed = candidate
          let identities = Set(candidate.elements.map(\.id))
          if let selection, !identities.contains(selection) { self.selection = nil }
          multiSelection.formIntersection(identities)
          collapsedSemanticNodes = collapsedSemanticNodes.filter { identity in
            let value = identity.replacingOccurrences(of: "element-", with: "")
              .replacingOccurrences(of: "first-", with: "")
            return Int(value).map { identities.contains($0) } ?? false
          }
          if let identifier = pendingParticipantSelection {
            pendingParticipantSelection = nil
            if let participant = candidate.elements.first(where: {
              $0.kind == "participant"
                && SemanticStructure.value(
                  $0.fields["alias"] == nil ? "name" : "alias", of: $0, in: candidate) == identifier
            }) {
              selectObject(participant)
            }
          }
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
      let candidate = SourceDocument.parse(proposed, mode: modeOverride ?? parsed.kind)
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
  func selectImplicitParticipant(_ identifier: String, reference: Element) {
    selection = nil
    multiSelection = []
    selectedImplicitParticipant = identifier
    if parsed.source == source {
      navigationRange = ["from", "to"].first(where: {
        SemanticStructure.value($0, of: reference, in: parsed) == identifier
      }).flatMap { reference.fields[$0] }
    }
  }
  func declareParticipant(_ identifier: String) {
    guard canEdit else { return }
    pendingParticipantSelection = identifier
    edit { try SemanticOperations.insertSetting("participant " + identifier, in: parsed) }
  }
  func selectObject(_ element: Element, navigate: Bool = true, additive: Bool = false) {
    selectedImplicitParticipant = nil
    selectionFirstBranch = false
    selection = element.id
    if additive {
      if multiSelection.contains(element.id) {
        multiSelection.remove(element.id)
      } else {
        multiSelection.insert(element.id)
      }
    } else {
      multiSelection = [element.id]
    }
    if navigate && parsed.source == source {
      navigationRange = element.fullRange ?? element.range
      previewReturn += 1
    }
  }
  func revealSelection() {
    guard let selection else { return }
    func reveal(_ node: SemanticNode) -> Bool {
      let contains = node.children.map(reveal).contains(true) || node.element.id == selection
      if contains { collapsedSemanticNodes.remove(node.id) }
      return contains
    }
    for section in SemanticStructure.sections(parsed) {
      if section.nodes.map(reveal).contains(true) { collapsedSemanticSections.remove(section.id) }
    }
  }
  func requestDelete(_ element: Element) {
    guard canEdit else { return }
    do {
      let dependencies = try SemanticOperations.dependencies(of: element, in: parsed)
      var cascade = false
      if !dependencies.isEmpty {
        let alert = NSAlert()
        alert.messageText = "Удалить объект и связанные элементы?"
        alert.informativeText =
          "Связанных элементов: \(dependencies.count). Сообщения, связи, активации и заметки будут удалены вместе с объектом. Действие можно отменить через Undo."
        if dependencies.contains(where: { $0.kind == "unsupported" }) {
          alert.informativeText =
            "Объект используется в неподдерживаемой конструкции. Удаление через конструктор заблокировано; проверьте ссылки в коде."
          alert.addButton(withTitle: "Перейти к коду")
          alert.addButton(withTitle: "Отмена")
          if alert.runModal() == .alertFirstButtonReturn { selectObject(element) }
          return
        }
        alert.addButton(withTitle: "Отмена")
        alert.addButton(withTitle: "Удалить со связями")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        cascade = true
      }
      edit { try SemanticOperations.delete(element, includingDependencies: cascade, in: parsed) }
    } catch { operationError = error.localizedDescription }
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
