import PlantUMLCore
import SwiftUI

struct OutlineRow: View {
  let node: OutlineNode
  @ObservedObject var document: StudioDocument
  @State private var expanded = true
  var body: some View {
    Group {
      if node.children.isEmpty {
        label
      } else {
        DisclosureGroup(isExpanded: $expanded) {
          ForEach(node.children) { child in OutlineRow(node: child, document: document) }
        } label: {
          label
        }
      }
    }.tag(node.id).contextMenu {
      Button("Перейти к исходнику") {
        document.navigationRange = node.element.range
        document.selection = node.id
      }
      if node.element.kind == "message" {
        Button("Ответное сообщение") {
          document.edit { try QuickOperations.reply(to: node.element, in: document.parsed) }
        }
        Button("Сообщение перед") { insert(before: true) }
        Button("Сообщение после") { insert(before: false) }
        ForEach(["alt", "opt", "loop"], id: \.self) { type in
          Button("Обернуть в \(type)") {
            document.edit {
              try QuickOperations.wrap([node.element], with: type, in: document.parsed)
            }
          }
        }
      }
      if ["message", "block", "entity"].contains(node.element.kind) {
        Button("Дублировать") {
          document.edit { try QuickOperations.duplicate(node.element, in: document.parsed) }
        }
      }
      Button("Вверх") {
        document.edit {
          try ConstructorOperations.move(node.element, up: true, in: document.parsed)
        }
      }
      Button("Вниз") {
        document.edit {
          try ConstructorOperations.move(node.element, up: false, in: document.parsed)
        }
      }
      Button("Удалить") {
        document.edit { try ConstructorOperations.delete(node.element, in: document.parsed) }
      }
    }
  }
  var label: some View {
    Text(node.element.text.trimmingCharacters(in: .whitespacesAndNewlines)).lineLimit(2)
      .font(.system(size: 12, design: .monospaced))
  }
  func insert(before: Bool) {
    document.edit {
      try QuickOperations.insertMessage(
        relativeTo: node.element, before: before,
        text: node.element.text.trimmingCharacters(in: .whitespacesAndNewlines), in: document.parsed
      )
    }
  }
}

struct SearchBar: View {
  @ObservedObject var document: StudioDocument
  @State private var query = ""
  @State private var replacement = ""
  @State private var caseSensitive = false
  @State private var regex = false
  @State private var index = -1
  @State private var failure = ""
  var options: SearchOptions { SearchOptions(caseSensitive: caseSensitive, regex: regex) }
  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        TextField("Найти", text: $query).onSubmit { navigate(1) }
        Toggle("Aa", isOn: $caseSensitive)
        Toggle(".*", isOn: $regex)
        Button("↑") { navigate(-1) }
        Button("↓") { navigate(1) }
        Text(
          "\((try? SourceSearch.matches(query, in: document.source, options: options).count) ?? 0)")
        Button {
          document.searchVisible = false
        } label: {
          Image(systemName: "xmark")
        }
      }
      HStack {
        TextField("Заменить на", text: $replacement)
        Button("Заменить") { replace(all: false) }
        Button("Все") { replace(all: true) }
      }
      if !failure.isEmpty { Text(failure).foregroundStyle(.red).font(.caption) }
    }.textFieldStyle(.roundedBorder).padding(8)
      .onChange(of: document.source) { index = -1 }
      .onChange(of: query) { index = -1 }
      .onChange(of: regex) { index = -1 }
      .onChange(of: caseSensitive) { index = -1 }
  }
  func navigate(_ step: Int) {
    do {
      let matches = try SourceSearch.matches(query, in: document.source, options: options)
      guard !matches.isEmpty else { return }
      index =
        index < 0
        ? (step > 0 ? 0 : matches.count - 1) : (index + step + matches.count) % matches.count
      document.navigationRange = matches[index]
      failure = ""
    } catch { failure = error.localizedDescription }
  }
  func replace(all: Bool) {
    do {
      if !all && index < 0 { navigate(1) }
      guard all || index >= 0 else { return }
      document.source = try SourceSearch.replace(
        query, with: replacement, in: document.source, options: options, only: all ? nil : index)
      index = -1
      failure = ""
    } catch { failure = error.localizedDescription }
  }
}
