import AppKit
import PlantUMLCore
import SwiftUI

struct StudioCommand: Identifiable {
  let id: String
  let name: String
  let shortcut: String
  let action: () -> Void
}
@MainActor enum StudioCommands {
  static func available(_ document: StudioDocument) -> [StudioCommand] {
    var commands = [
      StudioCommand(id: "save", name: "Сохранить", shortcut: "⌘S", action: { document.save() }),
      StudioCommand(
        id: "search", name: "Найти и заменить", shortcut: "⌘F",
        action: { document.searchVisible = true }),
      StudioCommand(
        id: "fit", name: "Вписать диаграмму", shortcut: "", action: { document.zoom = 0 }),
      StudioCommand(
        id: "reset", name: "Масштаб 100%", shortcut: "⌘0", action: { document.zoom = 1 }),
      StudioCommand(
        id: "undo", name: "Отменить", shortcut: "⌘Z", action: { document.undoManager.undo() }),
      StudioCommand(
        id: "redo", name: "Повторить", shortcut: "⇧⌘Z", action: { document.undoManager.redo() }),
      StudioCommand(
        id: "focusEditor", name: "Фокус: редактор", shortcut: "",
        action: { document.focusRequest = "editor" }),
      StudioCommand(
        id: "focusDiagram", name: "Фокус: диаграмма", shortcut: "",
        action: { document.focusRequest = "diagram" }),
      StudioCommand(
        id: "focusProperties", name: "Фокус: свойства", shortcut: "",
        action: { document.focusRequest = "properties" }),
    ]
    guard document.canEdit else { return commands }
    let ns = document.source as NSString
    let ids = document.parsed.elements.filter { ["participant", "entity"].contains($0.kind) }
      .compactMap { ($0.fields["alias"] ?? $0.fields["name"]).map { ns.substring(with: $0) } }
    var number = 1
    while ids.contains("New\(number)") { number += 1 }
    let unique = "New\(number)"
    func add(_ id: String, _ name: String, _ fragment: String) {
      commands.append(
        StudioCommand(
          id: id, name: name, shortcut: "",
          action: { document.edit { try SourceDocument.insert(fragment, in: document.source) } }))
    }
    if document.parsed.kind == .sequence {
      add("participant", "Добавить участника", "participant \(unique)")
      if let first = ids.first {
        add("message", "Добавить сообщение", "\(first) -> \(ids.last ?? first) : Message")
      }
      add("block", "Добавить блок", "alt condition\nend")
    } else if document.parsed.kind == .er {
      add("entity", "Добавить сущность", "entity \(unique) {\n * id : integer <<PK>>\n}")
      if ids.count > 1 { add("relation", "Добавить связь", "\(ids[0]) ||--o{ \(ids[1]) : relates") }
    }
    let selectedElements = document.parsed.elements.filter {
      document.multiSelection.contains($0.id)
    }
    if !selectedElements.isEmpty && selectedElements.allSatisfy({ $0.kind == "message" }) {
      for type in ["alt", "opt", "loop"] {
        commands.append(
          StudioCommand(
            id: "wrap." + type, name: "Обернуть выделенные сообщения в " + type, shortcut: "",
            action: {
              document.edit {
                try QuickOperations.wrap(selectedElements, with: type, in: document.parsed)
              }
            }))
      }
    }
    if selectedElements.count == 2 && selectedElements.allSatisfy({ $0.kind == "entity" }) {
      let names = selectedElements.compactMap {
        ($0.fields["alias"] ?? $0.fields["name"]).map { ns.substring(with: $0) }
      }
      if names.count == 2 {
        add(
          "selectedRelation", "Связь между выделенными сущностями",
          "\(names[0]) ||--o{ \(names[1]) : relates")
      }
    }
    if let selected = document.parsed.elements.first(where: { $0.id == document.selection }) {
      if selected.kind == "entity" {
        commands.append(
          StudioCommand(
            id: "attribute", name: "Добавить атрибут", shortcut: "",
            action: {
              document.edit {
                try QuickOperations.addAttributes(
                  "attribute : text", to: selected, in: document.parsed)
              }
            }))
      }
      if ["message", "block", "entity"].contains(selected.kind) {
        commands.append(
          StudioCommand(
            id: "duplicate", name: "Дублировать выделенное", shortcut: "",
            action: {
              document.edit { try QuickOperations.duplicate(selected, in: document.parsed) }
            }))
      }
    }
    return commands
  }
}
struct CommandPalette: View {
  @ObservedObject var document: StudioDocument
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var selected = 0
  @FocusState private var focused: Bool
  var matches: [StudioCommand] {
    StudioCommands.available(document).filter {
      query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
    }
  }
  var body: some View {
    VStack(spacing: 8) {
      TextField("Введите команду", text: $query).textFieldStyle(.roundedBorder).focused($focused)
        .onSubmit { execute() }
      ScrollView {
        VStack(spacing: 2) {
          ForEach(Array(matches.enumerated()), id: \.element.id) { index, command in
            Button {
              command.action()
              dismiss()
            } label: {
              HStack {
                Text(command.name)
                Spacer()
                Text(command.shortcut).foregroundStyle(.secondary)
              }.padding(8)
                .background(selected == index ? Color.accentColor.opacity(0.15) : Color.clear)
            }.buttonStyle(.plain)
          }
        }
      }.frame(height: 300)
    }.padding(16).frame(width: 520).onAppear { focused = true }
      .onChange(of: query) { selected = 0 }
      .onKeyPress(.downArrow) {
        selected = min(max(0, matches.count - 1), selected + 1)
        return .handled
      }
      .onKeyPress(.upArrow) {
        selected = max(0, selected - 1)
        return .handled
      }
      .onMoveCommand { direction in
        if direction == .down { selected = min(max(0, matches.count - 1), selected + 1) }
        if direction == .up { selected = max(0, selected - 1) }
      }.onExitCommand { dismiss() }
  }
  func execute() {
    guard matches.indices.contains(selected) else { return }
    matches[selected].action()
    dismiss()
  }
}
