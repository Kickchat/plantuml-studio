import AppKit
import ComponentModule
import ERModule
import PlantUMLCore
import SequenceModule
import StudioDesign
import SwiftUI

struct Comparison: Identifiable {
  let id = UUID()
  let left: String
  let right: String
  let leftName: String
  let rightName: String
}
struct DiffView: View {
  let comparison: Comparison
  @Environment(\.dismiss) private var dismiss
  @State private var result: DiagramDiffResult?
  @State private var changeIndex = -1
  @State private var selectedRow: Int?
  @State private var diagrams = true
  @State private var zoom = 1.0
  @StateObject private var left: StudioDocument
  @StateObject private var right: StudioDocument
  init(comparison: Comparison) {
    self.comparison = comparison
    _left = StateObject(wrappedValue: StudioDocument(source: comparison.left))
    _right = StateObject(wrappedValue: StudioDocument(source: comparison.right))
  }
  var changedRows: [TextDiffRow] { result?.rows.filter { $0.status != .unchanged } ?? [] }
  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Text("Visual Diff").font(.title2)
        Toggle("Диаграммы", isOn: $diagrams)
        Button("−") { zoom = max(0.2, zoom - 0.1) }
        Button("+") { zoom = min(3, zoom + 0.1) }
        Button("Вписать") { zoom = 0 }
        Spacer()
        Button("Закрыть") { dismiss() }
      }
      HStack {
        Text(comparison.leftName).frame(maxWidth: .infinity)
        Text(comparison.rightName).frame(maxWidth: .infinity)
      }.font(.headline)
      if let result {
        if result.textOnly {
          Text("Структура не распознана или типы различаются: текстовый diff").foregroundStyle(
            DesignToken.warning.color)
        }
        ScrollViewReader { proxy in
          VStack {
            HStack {
              Button("Предыдущее изменение") { navigate(-1, proxy) }.disabled(changedRows.isEmpty)
              Button("Следующее изменение") { navigate(1, proxy) }.disabled(changedRows.isEmpty)
              Text("\(changedRows.count) изменённых строк")
            }
            ScrollView([.vertical, .horizontal]) {
              LazyVStack(spacing: 0) {
                ForEach(result.rows) { row in
                  HStack(alignment: .top, spacing: 0) {
                    line(row.left, row.leftLine, row.status, leftSide: true)
                    Divider()
                    line(row.right, row.rightLine, row.status, leftSide: false)
                  }.id(row.id)
                }
              }
            }.frame(minHeight: 180).onChange(of: selectedRow) {
              if let selectedRow { proxy.scrollTo(selectedRow, anchor: .center) }
            }
          }
        }
        if !result.changes.isEmpty {
          List(result.changes) { change in
            Button {
              if let node = change.after ?? change.before {
                let source = change.after == nil ? comparison.left : comparison.right
                let prefix = (source as NSString).substring(to: node.range.location)
                let lineNumber = prefix.components(separatedBy: "\n").count
                selectedRow =
                  result.rows.first {
                    change.after == nil ? $0.leftLine == lineNumber : $0.rightLine == lineNumber
                  }?.id
              }
              jump(change.before, document: left)
              jump(change.after, document: right)
            } label: {
              HStack {
                Text(statusLabel(change.status)).frame(width: 130, alignment: .leading)
                Text(change.after?.text ?? change.before?.text ?? change.reason).lineLimit(2)
                Spacer()
                Text(change.reason).font(.caption).foregroundStyle(DesignToken.secondaryText.color)
              }
            }.buttonStyle(.plain).disabled(
              change.status == .ambiguous || change.status == .textFallback)
          }.scrollContentBackground(.hidden).background(DesignToken.surface.color).frame(
            height: 130)
        }
      } else {
        ProgressView("Сравнение…")
      }
      if diagrams {
        HSplitView {
          Preview(document: left, zoom: zoom, editable: false)
          Preview(document: right, zoom: zoom, editable: false)
        }.frame(height: 230)
        if !left.error.isEmpty || !right.error.isEmpty {
          Text("Одна из версий не рендерится; её текст доступен выше").foregroundStyle(
            DesignToken.warning.color
          )
          .font(.caption)
        }
      }
    }.modifier(StudioStyle()).padding(16).frame(minWidth: 1100, minHeight: 720).background(
      DesignToken.background.color
    )
    .task {
      let a = comparison.left
      let b = comparison.right
      result = await Task.detached {
        let kind = SourceDocument.parse(a).kind
        if SourceDocument.parse(b).kind != kind { return DiagramDiff.compare(a, b) }
        switch kind {
        case .sequence: return SequenceContract().compare(a, b)
        case .er: return ERContract().compare(a, b)
        case .component: return ComponentContract().compare(a, b)
        case .unknown: return DiagramDiff.compare(a, b)
        }
      }.value
    }
  }
  func line(_ value: String?, _ number: Int?, _ status: DiffStatus, leftSide: Bool) -> some View {
    HStack(alignment: .top) {
      Text(number.map(String.init) ?? "").foregroundStyle(DesignToken.secondaryText.color).frame(
        width: 45, alignment: .trailing)
      Text(value ?? " ").textSelection(.enabled).frame(width: 430, alignment: .leading)
    }.font(.system(size: 12, design: .monospaced)).padding(4).background(
      color(status, leftSide: leftSide))
  }
  func color(_ status: DiffStatus, leftSide: Bool) -> Color {
    if status == .unchanged { return .clear }
    return leftSide ? DesignToken.diffRemoved.color : DesignToken.diffAdded.color
  }
  func statusLabel(_ status: DiffStatus) -> String {
    switch status {
    case .added: return "Добавлено"
    case .removed: return "Удалено"
    case .modified: return "Изменено"
    case .moved: return "Порядок изменён"
    case .ambiguous: return "Неоднозначно"
    case .textFallback: return "Только текст"
    case .unchanged: return "Без изменений"
    }
  }
  func navigate(_ direction: Int, _ proxy: ScrollViewProxy) {
    guard !changedRows.isEmpty else { return }
    changeIndex =
      changeIndex < 0
      ? (direction > 0 ? 0 : changedRows.count - 1)
      : (changeIndex + direction + changedRows.count) % changedRows.count
    proxy.scrollTo(changedRows[changeIndex].id, anchor: .center)
  }
  func jump(_ element: Element?, document: StudioDocument) {
    guard let element, document.parsed.source == document.source else { return }
    let matches = document.parsed.elements.filter {
      $0.kind == element.kind && $0.range == element.range
    }
    guard matches.count == 1 else { return }
    document.selection = matches[0].id
    document.previewReturn += 1
  }
}
