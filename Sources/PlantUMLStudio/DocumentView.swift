import AppKit
import ERModule
import PlantUMLCore
import Rendering
import SequenceModule
import StudioDesign
import SwiftUI
import WebKit

struct DocumentView: View {
  @ObservedObject var workspace: Workspace
  @ObservedObject var document: StudioDocument
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        }.frame(width: 190)
        Menu {
          Toggle("Вертикальное разделение", isOn: $vertical)
        } label: {
          Image(systemName: "rectangle.split.2x1")
        }.fixedSize().help("Расположение панелей")
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
        }.fixedSize()
        Button {
          historyVisible = true
        } label: {
          Image(systemName: "clock.arrow.circlepath")
        }.help("История сохранений")
        Button("Шаблоны") { templatesVisible = true }
        Spacer()
        Picker("Режим", selection: $document.modeOverride) {
          Text("Авто").tag(Optional<DiagramKind>.none)
          Text("Sequence").tag(Optional(DiagramKind.sequence))
          Text("ER").tag(Optional(DiagramKind.er))
          Text("Component").tag(Optional(DiagramKind.component))
          Text("Только текст").tag(Optional(DiagramKind.unknown))
        }.frame(width: 150)
      }.padding(.horizontal, 12).frame(height: 48).background(DesignToken.elevatedSurface.color)
      if document.searchVisible { SearchBar(document: document) }
      Divider().overlay(DesignToken.border.color)
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
        Text(document.operationError).font(.caption).foregroundStyle(DesignToken.warning.color)
          .padding(8)
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
        Text(document.error).font(.caption).foregroundStyle(DesignToken.error.color).textSelection(
          .enabled
        ).frame(
          maxWidth: .infinity, alignment: .leading
        ).padding(8).background(DesignToken.error.color.opacity(0.08))
      }
      HStack {
        Image(systemName: document.canEdit ? "checkmark.circle" : "clock").foregroundStyle(
          document.canEdit ? DesignToken.success.color : DesignToken.secondaryText.color)
        Text("\(document.source.components(separatedBy:"\n").count) строк")
        Spacer()
        Text(
          document.canEdit
            ? "Конструктор синхронизирован"
            : "Последнее корректное состояние · конструктор недоступен")
      }.font(.caption).foregroundStyle(DesignToken.secondaryText.color).padding(8)
    }.modifier(StudioStyle()).animation(
      reduceMotion ? nil : .easeInOut(duration: 0.12), value: layout
    )
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: vertical)
    .sheet(item: $comparison) { DiffView(comparison: $0) }
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
    VStack(spacing: 0) {
      PanelHeader(title: "Код PlantUML", icon: "curlybraces") { EmptyView() }
      CodeEditor(
        text: $document.source, focusRequested: document.focusRequest == "editor",
        onFocused: { document.focusRequest = "" },
        onCursor: { range in
          guard document.parsed.source == document.source else { return }
          document.navigationRange = nil
          document.selectedTextRange = range.length > 0 ? range : nil
          document.selection =
            DocumentNavigation.element(at: range.location, in: document.parsed)?.id
        }, diagnosticLine: document.errorLine,
        selectedSourceRange: document.navigationRange
      ).frame(maxWidth: .infinity, maxHeight: .infinity)
    }.frame(minWidth: 250, minHeight: 222).background(DesignToken.surface.color)
  }
  var preview: some View {
    VStack(spacing: 0) {
      PanelHeader(title: "Диаграмма", icon: "point.3.connected.trianglepath.dotted") {
        Button {
          document.zoom = max(0.2, zoom - 0.1)
        } label: {
          Image(systemName: "minus.magnifyingglass")
        }.help("Уменьшить")
        Menu(zoom > 0 ? "\(Int(zoom*100))%" : "Fit") {
          Button("Вписать в окно") { document.zoom = 0 }
          Button("Вписать по ширине") { document.zoom = -1 }
          Button("100%") { document.zoom = 1 }
          Button("К выделению") { document.previewReturn += 1 }
        }.frame(width: 65)
        Button {
          document.zoom = min(3, max(0.2, zoom) + 0.1)
        } label: {
          Image(systemName: "plus.magnifyingglass")
        }.help("Увеличить")
      }
      Preview(document: document, zoom: zoom).frame(minWidth: 300, minHeight: 180)
    }.background(DesignToken.surface.color)
  }
}
