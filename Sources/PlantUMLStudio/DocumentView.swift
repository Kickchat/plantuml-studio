import AppKit
import ERModule
import PlantUMLCore
import Rendering
import SequenceModule
import SwiftUI
import WebKit

struct DocumentView: View {
  @ObservedObject var workspace: Workspace
  @ObservedObject var document: StudioDocument
  @State var layout = "All"
  @State var vertical = false
  @State private var comparison: Comparison?
  @State private var historyVisible = false
  @State private var templatesVisible = false
  var zoom: Double { document.zoom }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Picker("Панели", selection: $layout) {
          Text("Все панели").tag("All")
          Text("Код и диаграмма").tag("Split")
          Text("Код").tag("Code")
          Text("Диаграмма").tag("Diagram")
        }.frame(width: 220)
        Toggle("Вертикально", isOn: $vertical).toggleStyle(.button)
        Menu("Сравнить") {
          Button("Текущий с сохранённым") {
            comparison = Comparison(
              left: document.savedText, right: document.source, leftName: "Последнее сохранение",
              rightName: document.name)
          }
          Button("Два файла…") { compareFiles() }
          ForEach(workspace.documents.filter { $0.id != document.id }) { other in
            Button("С документом " + other.name) {
              comparison = Comparison(
                left: other.source, right: document.source, leftName: other.name,
                rightName: document.name)
            }
          }
        }
        Button("История") { historyVisible = true }
        Button("Шаблоны") { templatesVisible = true }
        Spacer()
        Picker("Режим", selection: $document.modeOverride) {
          Text("Авто").tag(Optional<DiagramKind>.none)
          Text("Sequence").tag(Optional(DiagramKind.sequence))
          Text("ER").tag(Optional(DiagramKind.er))
          Text("Component").tag(Optional(DiagramKind.component))
          Text("Только текст").tag(Optional(DiagramKind.unknown))
        }.frame(width: 150)
        Button {
          document.zoom = max(0.2, zoom - 0.1)
        } label: {
          Image(systemName: "minus.magnifyingglass")
        }
        Button("Вписать") { document.zoom = 0 }
        Button("По ширине") { document.zoom = -1 }
        Button("К выделению") { document.previewReturn += 1 }
        Button("100%") { document.zoom = 1 }
        Button {
          document.zoom = min(3, zoom + 0.1)
        } label: {
          Image(systemName: "plus.magnifyingglass")
        }
      }.padding(10)
      if document.searchVisible { SearchBar(document: document) }
      Divider()
      HSplitView {
        if layout == "Code" {
          editor
        } else if layout == "Diagram" {
          preview
        } else if vertical {
          VSplitView {
            editor
            preview
          }
        } else {
          HSplitView {
            editor
            preview
          }
        }
        if layout == "All" || layout == "Diagram" {
          Constructor(document: document).frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
        }
      }
      if !document.operationError.isEmpty {
        Text(document.operationError).font(.caption).foregroundStyle(.orange).padding(8)
      }
      if let line = document.errorLine {
        Button("Перейти к ошибке: строка \(line + 1)") {
          let lines = document.source.components(separatedBy: "\n")
          let offset = lines.prefix(line).reduce(0) { $0 + ($1 as NSString).length + 1 }
          document.navigationRange = NSRange(
            location: min(offset, (document.source as NSString).length), length: 0)
        }
      }
      if !document.error.isEmpty {
        Text(document.error).font(.caption).foregroundStyle(.red).textSelection(.enabled).frame(
          maxWidth: .infinity, alignment: .leading
        ).padding(8).background(.red.opacity(0.06))
      }
      HStack {
        Text("\(document.source.components(separatedBy:"\n").count) строк")
        Spacer()
        Text(
          document.canEdit
            ? "Конструктор синхронизирован"
            : "Последнее корректное состояние · конструктор недоступен")
      }.font(.caption).foregroundStyle(.secondary).padding(8)
    }.sheet(item: $comparison) { DiffView(comparison: $0) }
      .sheet(isPresented: $historyVisible) { HistoryView(document: document) }
      .sheet(isPresented: $document.paletteVisible) { CommandPalette(document: document) }
      .sheet(isPresented: $templatesVisible) { TemplatesView(document: document) }
  }
  func compareFiles() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK, panel.urls.count == 2 else { return }
    do {
      comparison = Comparison(
        left: try String(contentsOf: panel.urls[0], encoding: .utf8),
        right: try String(contentsOf: panel.urls[1], encoding: .utf8),
        leftName: panel.urls[0].lastPathComponent, rightName: panel.urls[1].lastPathComponent)
    } catch { document.operationError = error.localizedDescription }
  }
  var editor: some View {
    CodeEditor(
      text: $document.source, focusRequested: document.focusRequest == "editor",
      onFocused: { document.focusRequest = "" },
      onCursor: { range in
        guard document.parsed.source == document.source else { return }
        document.navigationRange = nil
        document.selectedTextRange = range.length > 0 ? range : nil
        document.selection = DocumentNavigation.element(at: range.location, in: document.parsed)?.id
      }, diagnosticLine: document.errorLine,
      selectedSourceRange: document.navigationRange
    ).frame(minWidth: 250, minHeight: 180)
  }
  var preview: some View {
    Preview(document: document, zoom: zoom).frame(minWidth: 300, minHeight: 180)
  }
}
