import AppKit
import ERModule
import PlantUMLCore
import Rendering
import SequenceModule
import SwiftUI
import WebKit

struct DocumentView: View {
  @ObservedObject var document: StudioDocument
  @State var layout = "All"
  @State var vertical = false
  @State var zoom = 1.0
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
        Spacer()
        Picker("Режим", selection: $document.modeOverride) {
          Text("Авто").tag(Optional<DiagramKind>.none)
          Text("Sequence").tag(Optional(DiagramKind.sequence))
          Text("ER").tag(Optional(DiagramKind.er))
          Text("Только текст").tag(Optional(DiagramKind.unknown))
        }.frame(width: 150)
        Button {
          zoom = max(0.2, zoom - 0.1)
        } label: {
          Image(systemName: "minus.magnifyingglass")
        }
        Button("Вписать") { zoom = 0 }
        Button("100%") { zoom = 1 }
        Button {
          zoom = min(3, zoom + 0.1)
        } label: {
          Image(systemName: "plus.magnifyingglass")
        }
      }.padding(10)
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
    }
  }
  var editor: some View {
    CodeEditor(
      text: $document.source, diagnosticLine: document.errorLine,
      selectedSourceRange: document.parsed.source == document.source
        ? document.parsed.elements.first { $0.id == document.selection }?.range : nil
    ).frame(minWidth: 250, minHeight: 180)
  }
  var preview: some View {
    Preview(document: document, zoom: zoom).frame(minWidth: 300, minHeight: 180)
  }
}
