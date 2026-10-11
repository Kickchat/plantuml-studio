import AppKit
import ERModule
import PlantUMLCore
import Rendering
import SequenceModule
import SwiftUI
import WebKit

struct Constructor: View {
  @ObservedObject var document: StudioDocument
  @FocusState private var outlineFocused: Bool
  @State private var selectedIDs: Set<Int> = []
  @State private var attributesVisible = false
  @State private var attributesText = ""
  @State var outlineQuery = ""
  @State var fieldValues: [String: String] = [:]

  var selected: Element? { document.parsed.elements.first { $0.id == document.selection } }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Конструктор").font(.headline).onChange(of: document.focusRequest) {
        if document.focusRequest == "properties" {
          outlineFocused = true
          document.focusRequest = ""
        }
      }
      Menu("Добавить элемент") {
        if document.parsed.kind == .sequence {
          ForEach(ParticipantType.allCases.map(\.rawValue), id: \.self) { type in
            Button(type) { add("\(type) \"Participant\" as \(uniqueIdentifier(prefix:"P"))") }
          }
          Button("Сообщение") { add(messageTemplate) }
          ForEach(BlockType.allCases.map(\.rawValue), id: \.self) { type in
            Button(type) { add("\(type) condition\nend") }
          }
          Button("Note") { add("note right of \(identifiers.last ?? "API") : Note") }
          Button("activate") { add("activate \(identifiers.last ?? "API")") }
          Button("deactivate") { add("deactivate \(identifiers.last ?? "API")") }
          Button("destroy") { add("destroy \(identifiers.last ?? "API")") }
          Button("Заголовок") { add("title Diagram") }
          Button("Разделитель") { add("== Section ==") }
          Button("Задержка") { add("... waiting ...") }
          Button("Автонумерация") { add("autonumber") }
        } else if document.parsed.kind == .er {
          Button("Сущность") {
            add(
              "entity \"Entity\" as \(uniqueIdentifier(prefix:"E")) {\n  * id : integer <<PK>>\n}")
          }
          Button("Связь") { add(relationTemplate) }
        }
      }.disabled(!document.canEdit)
      TextField("Поиск структуры", text: $outlineQuery).textFieldStyle(.roundedBorder).focused(
        $outlineFocused)
      List(selection: $selectedIDs) {
        if outlineQuery.isEmpty {
          ForEach(DocumentNavigation.outline(document.parsed)) { node in
            OutlineRow(node: node, document: document)
          }
        } else {
          ForEach(DocumentNavigation.search(outlineQuery, in: document.parsed)) { element in
            Text(element.text.trimmingCharacters(in: .whitespaces)).tag(element.id)
          }
        }
      }.onChange(of: selectedIDs) {
        document.multiSelection = selectedIDs
        if selectedIDs.count == 1 {
          if document.selection != selectedIDs.first {
            document.navigationRange =
              document.parsed.elements.first { $0.id == selectedIDs.first }?.range
          }
          document.selection = selectedIDs.first
        }
      }.onChange(of: document.selection) {
        if let selection = document.selection, !selectedIDs.contains(selection) {
          selectedIDs = [selection]
        }
        if document.selection == nil { selectedIDs = [] }
      }
      if let selected {
        Text(selected.kind.capitalized).font(.headline)
        if selected.kind == "entity" {
          Button("Добавить несколько атрибутов…") { attributesVisible = true }
            .sheet(isPresented: $attributesVisible) {
              VStack {
                Text("Атрибуты: по одному на строку")
                TextEditor(text: $attributesText).font(.system(.body, design: .monospaced)).frame(
                  width: 450, height: 200)
                HStack {
                  Button("Отмена") { attributesVisible = false }
                  Button("Добавить") {
                    document.edit {
                      try QuickOperations.addAttributes(
                        attributesText, to: selected, in: document.parsed)
                    }
                    attributesVisible = false
                  }
                }
              }.padding()
            }
        }
        if selected.kind == "unsupported" {
          Text("Эта конструкция сохраняется в исходнике. Редактируйте её в коде.").font(.caption)
        }
        ScrollView {
          VStack(alignment: .leading) {
            ForEach(selected.fields.keys.sorted(), id: \.self) { key in
              if let range = selected.fields[key] {
                Text(fieldTitle(key)).font(.caption).foregroundStyle(.secondary)
                if key == "label",
                  (document.parsed.source as NSString).substring(with: range).contains("\n")
                {
                  TextEditor(
                    text: Binding(
                      get: {
                        fieldValues[key]
                          ?? (document.parsed.source as NSString).substring(with: range)
                      }, set: { fieldValues[key] = $0 })
                  ).frame(height: 90)
                } else {
                  let binding = Binding<String>(
                    get: {
                      fieldValues[key]
                        ?? (document.parsed.source as NSString).substring(with: range)
                    }, set: { fieldValues[key] = $0 })
                  let options = choices(key, element: selected)
                  if options.isEmpty {
                    TextField(key, text: binding).textFieldStyle(.roundedBorder)
                  } else {
                    Picker(key, selection: binding) {
                      ForEach(Array(Set(options + [binding.wrappedValue])).sorted(), id: \.self) {
                        value in Text(value).tag(value)
                      }
                    }.labelsHidden()
                  }
                }
              }
            }
            Button("Применить") {
              document.edit {
                var edits: [TextEdit] = []
                for (key, value) in fieldValues {
                  guard let range = selected.fields[key],
                    (!value.contains("\n") && !value.contains("\r"))
                      || (key == "label" && selected.text.contains("\n"))
                  else { throw SourceError.invalidEdit }
                  edits.append(TextEdit(range: range, replacement: value))
                }
                if selected.fields["alias"] == nil,
                  ["participant", "entity"].contains(selected.kind), let name = fieldValues["name"]
                {
                  guard fieldValues.count == 1 else { throw SourceError.invalidEdit }
                  return try ConstructorOperations.renameAlias(
                    selected, to: name, in: document.parsed)
                }
                if let alias = fieldValues["alias"] {
                  guard fieldValues.count == 1 else { throw SourceError.invalidEdit }
                  return try ConstructorOperations.renameAlias(
                    selected, to: alias, in: document.parsed)
                }
                return try SourceDocument.apply(edits, to: document.source)
              }
              fieldValues = [:]
            }.disabled(!document.canEdit || selected.fields.isEmpty)
            HStack {
              Button("↑ Выше") {
                document.edit {
                  try ConstructorOperations.move(selected, up: true, in: document.parsed)
                }
              }
              Button("↓ Ниже") {
                document.edit {
                  try ConstructorOperations.move(selected, up: false, in: document.parsed)
                }
              }
            }.disabled(
              !document.canEdit || ["branch", "unsupported", "activation"].contains(selected.kind))
            Button("Удалить", role: .destructive) {
              document.edit { try ConstructorOperations.delete(selected, in: document.parsed) }
            }.disabled(
              !document.canEdit || selected.kind == "unsupported" || selected.kind == "branch")
            if ["message", "relation"].contains(selected.kind), selected.fields["label"] == nil {
              Button("Добавить подпись") {
                document.edit {
                  try SourceDocument.apply(
                    [
                      TextEdit(
                        range: NSRange(location: NSMaxRange(selected.range), length: 0),
                        replacement: " : Message")
                    ], to: document.source)
                }
              }
            }
            if ["participant", "entity"].contains(selected.kind), selected.fields["color"] == nil {
              Button("Добавить цвет") {
                document.edit {
                  let location =
                    selected.kind == "entity"
                    ? (document.source as NSString).range(
                      of: "{", options: .backwards, range: selected.range
                    ).location
                    : (selected.fields["order"].map {
                      (document.source as NSString).range(
                        of: "order", options: .backwards,
                        range: NSRange(
                          location: selected.range.location,
                          length: $0.location - selected.range.location)
                      ).location
                    } ?? NSMaxRange(selected.range))
                  return try SourceDocument.apply(
                    [
                      TextEdit(
                        range: NSRange(location: location, length: 0), replacement: " #LightBlue ")
                    ], to: document.source)
                }
              }
            }
            if selected.kind == "attribute" {
              Toggle(
                "Обязательное поле (*)",
                isOn: Binding(
                  get: { selected.fields["mandatory"] != nil },
                  set: { enabled in
                    document.edit {
                      try ConstructorOperations.setAttributeMandatory(
                        selected, enabled: enabled, in: document.parsed)
                    }
                  }))
              Toggle(
                "Визуальная метка PK",
                isOn: Binding(
                  get: {
                    selected.fields["stereotype"].map {
                      (document.parsed.source as NSString).substring(with: $0) == "<<PK>>"
                    } ?? false
                  },
                  set: { enabled in
                    document.edit {
                      try ConstructorOperations.setAttributeKey(
                        selected, enabled: enabled, in: document.parsed)
                    }
                  }))
              Text("* обозначает обязательность; PK — подпись на диаграмме, без ограничений БД.")
                .font(.caption).foregroundStyle(.secondary)
            }
            if selected.kind == "entity" {
              Button("Добавить атрибут") {
                document.edit {
                  try ConstructorOperations.insertInside(
                    "field : text", element: selected, document: document.parsed)
                }
              }
              Button("Разделитель атрибутов") {
                document.edit {
                  try ConstructorOperations.insertInside(
                    "--", element: selected, document: document.parsed)
                }
              }
            }
            if selected.kind == "block" {
              Button("Сообщение внутри блока") {
                document.edit {
                  try ConstructorOperations.insertInside(
                    messageTemplate, element: selected, document: document.parsed)
                }
              }
              Menu("Вложенный блок") {
                ForEach(BlockType.allCases.map(\.rawValue), id: \.self) { type in
                  Button(type) {
                    document.edit {
                      try ConstructorOperations.insertInside(
                        "\(type) condition\nend", element: selected, document: document.parsed)
                    }
                  }
                }
              }
              if selected.text.trimmingCharacters(in: .whitespaces).hasPrefix("alt")
                || selected.text.trimmingCharacters(in: .whitespaces).hasPrefix("par")
              {
                Button("Добавить ветвь else") {
                  document.edit {
                    try ConstructorOperations.insertInside(
                      "else condition", element: selected, document: document.parsed)
                  }
                }
              }
            }
          }
        }.frame(maxHeight: 220)
      }
    }.padding(12).onChange(of: document.selection) { fieldValues = [:] }.onChange(
      of: document.source
    ) { fieldValues = [:] }
  }
  func fieldTitle(_ key: String) -> String {
    [
      "name": "Название", "alias": "Алиас", "type": "Тип", "from": "Отправитель / источник",
      "to": "Получатель / цель", "arrow": "Стрелка", "label": "Текст", "target": "Участник",
      "left": "Кардинальность слева", "right": "Кардинальность справа", "line": "Линия",
      "position": "Положение", "datatype": "Тип данных", "mandatory": "Обязательность",
      "stereotype": "Стереотип", "color": "Цвет", "order": "Порядок", "options": "Параметры",
    ][key] ?? key
  }
  func choices(_ key: String, element: Element) -> [String] {
    switch key {
    case "from", "to", "target": return identifiers
    case "arrow": return SequenceArrow.allCases.map(\.rawValue)
    case "left": return Cardinality.allCases.map(\.leftSymbol)
    case "right": return Cardinality.allCases.map(\.rightSymbol)
    case "line": return RelationshipLine.allCases.map(\.rawValue)
    case "position": return ["left", "right", "over"]
    case "type":
      if element.kind == "participant" { return ParticipantType.allCases.map(\.rawValue) }
      if element.kind == "activation" { return ["activate", "deactivate", "destroy"] }
      return []
    default: return []
    }
  }
  func uniqueIdentifier(prefix: String) -> String {
    var number = 1
    while identifiers.contains("\(prefix)\(number)") { number += 1 }
    return "\(prefix)\(number)"
  }
  var identifiers: [String] {
    let ns = document.source as NSString
    return document.parsed.elements.filter { ["participant", "entity"].contains($0.kind) }
      .compactMap { element in
        guard let range = element.fields["alias"] ?? element.fields["name"] else { return nil }
        return ns.substring(with: range)
      }
  }
  var messageTemplate: String {
    "\(identifiers.first ?? "A") -> \(identifiers.last ?? "B") : Message"
  }
  var relationTemplate: String {
    "\(identifiers.first ?? "A") ||--o{ \(identifiers.last ?? "B") : relation"
  }
  func add(_ text: String) {
    document.edit { try SourceDocument.insert(text, in: document.source) }
  }
}
