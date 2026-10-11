import AppKit
import ComponentModule
import ERModule
import PlantUMLCore
import SequenceModule
import StudioDesign
import SwiftUI

private struct ConstructorEntry: Identifiable {
  let id: String
  var section: SemanticSection? = nil
  var node: SemanticNode? = nil
  var depth = 0
  var settings = false
  var empty = false
}

struct Constructor: View {
  @ObservedObject var document: StudioDocument
  @FocusState private var outlineFocused: Bool
  @State private var attributesVisible = false
  @State private var fieldValues: [String: String] = [:]
  var selected: Element? { document.parsed.elements.first { $0.id == document.selection } }
  var sections: [SemanticSection] {
    SemanticStructure.sections(document.parsed, query: document.constructorQuery)
  }
  private var entries: [ConstructorEntry] {
    var result: [ConstructorEntry] = []
    let searching = !document.constructorQuery.isEmpty
    func append(_ node: SemanticNode, depth: Int) {
      result.append(ConstructorEntry(id: node.id, node: node, depth: depth))
      if searching || !document.collapsedSemanticNodes.contains(node.id) {
        for child in node.children { append(child, depth: depth + 1) }
      }
    }
    for section in sections {
      result.append(ConstructorEntry(id: "section-" + section.id, section: section))
      if searching || !document.collapsedSemanticSections.contains(section.id) {
        if section.id == "settings" {
          result.append(ConstructorEntry(id: "settings-controls", settings: true))
        }
        if section.nodes.isEmpty && section.id != "settings" {
          result.append(ConstructorEntry(id: "empty-" + section.id, empty: true))
        }
        for node in section.nodes { append(node, depth: 0) }
      }
    }
    return result
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Конструктор").font(.headline)
        Spacer()
        addMenu
      }
      TextField("Поиск объектов", text: $document.constructorQuery).textFieldStyle(.roundedBorder)
        .focused($outlineFocused)
      if !document.canEdit {
        Label(
          document.error.isEmpty ? "Синхронизация…" : "Последнее корректное состояние",
          systemImage: "clock.arrow.circlepath"
        )
        .font(.caption).foregroundStyle(DesignToken.warning.color)
      }
      VSplitView {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
              ForEach(entries) { entry in
                Group {
                  if let section = entry.section {
                    Button {
                      if document.collapsedSemanticSections.contains(section.id) {
                        document.collapsedSemanticSections.remove(section.id)
                      } else {
                        document.collapsedSemanticSections.insert(section.id)
                      }
                    } label: {
                      Label(
                        section.title + " (\(section.nodes.count))",
                        systemImage: document.collapsedSemanticSections.contains(section.id)
                          && document.constructorQuery.isEmpty ? "chevron.right" : "chevron.down"
                      )
                      .font(.system(size: 12, weight: .semibold)).frame(
                        maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).padding(.top, 5)
                  } else if entry.settings {
                    settingsControls
                  } else if entry.empty {
                    Text("Нет объектов").font(.caption).foregroundStyle(
                      DesignToken.secondaryText.color)
                  } else if let node = entry.node {
                    SemanticRow(node: node, document: document).padding(
                      .leading, CGFloat(entry.depth) * 14)
                  }
                }.id(entry.id)
              }
              if sections.isEmpty {
                Text("Объекты не найдены").foregroundStyle(DesignToken.secondaryText.color)
              }
            }.padding(8)
          }.onChange(of: document.selection) {
            if let selected = document.selection {
              let identity =
                document.selectionFirstBranch ? "first-\(selected)" : "element-\(selected)"
              Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard document.selection == selected else { return }
                proxy.scrollTo(identity, anchor: .center)
              }
            }
          }
        }.frame(minHeight: 130).background(DesignToken.surface.color)
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Button {
              document.propertiesCollapsed.toggle()
            } label: {
              Label(
                "Свойства",
                systemImage: document.propertiesCollapsed ? "chevron.right" : "chevron.down")
            }.buttonStyle(.plain).font(.headline)
            Spacer()
            if let selected {
              Button {
                document.selectObject(selected)
              } label: {
                Image(systemName: "curlybraces")
              }.help("Перейти к коду").disabled(document.parsed.source != document.source)
            }
          }
          if !document.propertiesCollapsed {
            ScrollView {
              if let identifier = document.selectedImplicitParticipant {
                VStack(alignment: .leading, spacing: 8) {
                  Text(SemanticStructure.readable(identifier)).font(.subheadline)
                  Text(
                    "Участник указан в сообщениях. Добавьте его объявление, чтобы изменить название, тип и цвет."
                  ).font(.caption).foregroundStyle(DesignToken.secondaryText.color)
                  Button("Добавить объявление участника") {
                    document.declareParticipant(identifier)
                  }.disabled(!document.canEdit)
                }.frame(maxWidth: .infinity, alignment: .leading)
              } else if let selected {
                properties(selected).disabled(!document.canEdit)
              } else {
                Text("Выберите объект в дереве, коде или диаграмме").font(.caption).foregroundStyle(
                  DesignToken.secondaryText.color
                ).padding(.vertical)
              }
            }.frame(minHeight: 100)
          }
        }.padding(.top, 8).frame(
          minHeight: document.propertiesCollapsed ? 30 : 160,
          idealHeight: document.propertiesCollapsed ? 30 : 280,
          maxHeight: document.propertiesCollapsed ? 30 : .infinity)
      }
    }.padding(DesignMetrics.panelPadding).background(DesignToken.elevatedSurface.color)
      .sheet(isPresented: $attributesVisible) {
        if let entity = selectedEntity { AttributeBatchEditor(document: document, entity: entity) }
      }
      .onChange(of: document.selection) { fieldValues = [:] }
      .onChange(of: document.parsed.source) { fieldValues = [:] }
      .onChange(of: document.focusRequest) {
        if document.focusRequest == "properties" {
          outlineFocused = true
          document.focusRequest = ""
        }
      }
  }
  var addMenu: some View {
    Menu {
      if document.parsed.kind == .sequence {
        Menu("Участник") {
          ForEach(ParticipantType.allCases.map(\.rawValue), id: \.self) { type in
            Button(type.capitalized) {
              add("\(type) \"Участник\" as \(uniqueIdentifier(prefix: "P"))", declaration: true)
            }
          }
        }
        Button("Сообщение") { add(messageTemplate) }.disabled(identifiers.isEmpty)
        Menu("Управляющий блок") {
          ForEach(BlockType.allCases.map(\.rawValue), id: \.self) { type in
            Button(type.uppercased()) { add("\(type) Условие\nend") }
          }
        }
        Button("Заметка") { add("note right of \(identifiers.last ?? "A") : Заметка") }.disabled(
          identifiers.isEmpty)
        Button("Разделитель") { add("== Раздел ==") }
        Button("Задержка") { add("... ожидание ...") }
        Menu("Активация") {
          ForEach(["activate", "deactivate", "destroy"], id: \.self) { type in
            Button(type) { add("\(type) \(identifiers.last ?? "A")") }
          }
        }.disabled(identifiers.isEmpty)
      } else if document.parsed.kind == .er {
        Button("Сущность") {
          add(
            "entity \"Сущность\" as \(uniqueIdentifier(prefix: "E")) {\n  * id : integer <<PK>>\n}",
            declaration: true)
        }
        Button("Атрибут") {
          if let entity = selectedEntity {
            document.edit {
              try ConstructorOperations.insertInside(
                "field : text", element: entity, document: document.parsed)
            }
          }
        }.disabled(selectedEntity == nil)
        Button("Связь") {
          add("\(identifiers.first ?? "A") ||--o{ \(identifiers.last ?? "B") : связь")
        }.disabled(identifiers.count < 2)
      } else if document.parsed.kind == .component {
        ForEach(ComponentType.allCases.map(\.rawValue), id: \.self) { type in
          Button(type.capitalized) {
            add(
              "\(type) \"Element\" as \(uniqueIdentifier(prefix: "C"))"
                + (["package", "node", "cloud", "frame", "folder"].contains(type) ? " {\n}" : ""))
          }
        }
        Button("Связь") { add("\(identifiers.first ?? "A") --> \(identifiers.last ?? "B") : uses") }
          .disabled(identifiers.count < 2)
      }
      Divider()
      Button("Название диаграммы") {
        document.edit {
          try SemanticOperations.insertSetting("title Диаграмма", in: document.parsed)
        }
      }.disabled(document.parsed.elements.contains { $0.kind == "title" })
      Menu("Оформление диаграммы") {
        ForEach(
          ["backgroundColor", "defaultFontName", "defaultFontSize", "sequenceMessageAlign"],
          id: \.self
        ) { key in
          Button(fieldSettingTitle(key)) {
            document.edit {
              try SemanticOperations.insertSetting(
                "skinparam \(key) \(key == "defaultFontSize" ? "14" : key == "defaultFontName" ? "Helvetica" : key == "sequenceMessageAlign" ? "left" : "white")",
                in: document.parsed)
            }
          }
          .disabled(
            document.parsed.elements.contains {
              $0.kind == "diagramSetting"
                && SemanticStructure.value("type", of: $0, in: document.parsed) == key
            })
        }
      }
    } label: {
      Image(systemName: "plus")
    }.menuStyle(.borderlessButton).fixedSize().help("Добавить объект").disabled(!document.canEdit)
  }
  var settingsControls: some View {
    Group {
      if document.parsed.kind == .sequence {
        let numbers = document.parsed.elements.filter { $0.kind == "autonumber" }
        Toggle(
          "Автонумерация сообщений",
          isOn: Binding(
            get: { !numbers.isEmpty },
            set: { enabled in
              document.edit { try SemanticOperations.setAutonumber(enabled, in: document.parsed) }
            })
        )
        .disabled(
          !document.canEdit || numbers.count > 1
            || numbers.contains {
              !SemanticStructure.value("options", of: $0, in: document.parsed).isEmpty
            })
        if numbers.count > 1
          || numbers.contains(where: {
            !SemanticStructure.value("options", of: $0, in: document.parsed).isEmpty
          })
        {
          Text("Пошаговая нумерация настроена в коде; её команды сохраняются.").font(.caption)
            .foregroundStyle(DesignToken.secondaryText.color)
        }
      }
    }.padding(.vertical, 4)
  }
  @ViewBuilder func properties(_ element: Element) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      let presentation = SemanticStructure.node(
        OutlineNode(element: element, children: []), in: document.parsed)
      Text(presentation.title).font(.subheadline).lineLimit(3)
      if element.kind == "autonumber" {
        Text(
          "Нумерация управляется в разделе «Настройки диаграммы». Сложные команды доступны в коде."
        ).font(.caption).foregroundStyle(DesignToken.secondaryText.color)
      } else if element.kind == "separator" {
        Text(
          "Разделитель групп атрибутов. Его можно переместить или удалить через контекстное меню."
        ).font(.caption).foregroundStyle(DesignToken.secondaryText.color)
      } else if element.kind == "unsupported"
        || element.fields.isEmpty && !["block", "branch"].contains(element.kind)
      {
        Text(
          "Эта конструкция пока не поддерживается формой. Она сохраняется без изменений; перейдите к коду для редактирования."
        ).font(.caption).foregroundStyle(DesignToken.secondaryText.color)
      } else {
        ForEach(propertyKeys(element), id: \.self) { key in
          Text(propertyTitle(key, element: element)).font(.caption).foregroundStyle(
            DesignToken.secondaryText.color)
          let binding = Binding<String>(
            get: {
              fieldValues[key]
                ?? (key == "name"
                  ? SemanticStructure.readable(
                    SemanticStructure.value(key, of: element, in: document.parsed))
                  : SemanticStructure.value(key, of: element, in: document.parsed))
            }, set: { fieldValues[key] = $0 })
          let options = choices(key, element: element)
          if key == "label" && SourceDocument.hasLineBreak(element.text) {
            TextEditor(text: binding).frame(minHeight: 70)
          } else if options.isEmpty {
            TextField(fieldTitle(key), text: binding).textFieldStyle(.roundedBorder)
          } else {
            Picker(fieldTitle(key), selection: binding) {
              ForEach(Array(Set(options + [binding.wrappedValue])).sorted(), id: \.self) { value in
                Text(optionTitle(value, key: key)).tag(value)
              }
            }.labelsHidden()
          }
        }
        Button("Применить") {
          document.edit {
            try SemanticOperations.properties(fieldValues, of: element, in: document.parsed)
          }
        }.disabled(fieldValues.isEmpty)
        if element.kind == "attribute" {
          Toggle(
            "Обязательное поле",
            isOn: Binding(
              get: { element.fields["mandatory"] != nil },
              set: { enabled in
                document.edit {
                  try ConstructorOperations.setAttributeMandatory(
                    element, enabled: enabled, in: document.parsed)
                }
              }))
          Toggle(
            "Визуальная метка PK",
            isOn: Binding(
              get: {
                SemanticStructure.value("stereotype", of: element, in: document.parsed) == "<<PK>>"
              },
              set: { enabled in
                document.edit {
                  try ConstructorOperations.setAttributeKey(
                    element, enabled: enabled, in: document.parsed)
                }
              })
          )
          .disabled(
            element.fields["stereotype"] != nil
              && SemanticStructure.value("stereotype", of: element, in: document.parsed) != "<<PK>>"
          )
          Text("Обязательность и метки — обозначения диаграммы, без ограничений БД.").font(.caption)
            .foregroundStyle(DesignToken.secondaryText.color)
        }
        if element.kind == "entity" {
          Button("Добавить несколько атрибутов…") { attributesVisible = true }
          Button("Добавить атрибут") {
            document.edit {
              try ConstructorOperations.insertInside(
                "field : text", element: element, document: document.parsed)
            }
          }
          Button("Разделитель атрибутов") {
            document.edit {
              try ConstructorOperations.insertInside(
                "--", element: element, document: document.parsed)
            }
          }
        }
        if ["block", "branch"].contains(element.kind) {
          Button("Добавить сообщение в ветвь") { insertScenario(messageTemplate, into: element) }
            .disabled(identifiers.isEmpty)
          Menu("Вложенный блок") {
            ForEach(BlockType.allCases.map(\.rawValue), id: \.self) { type in
              Button(type.uppercased()) { insertScenario("\(type) Условие\nend", into: element) }
            }
          }
          if element.kind == "block"
            && ["alt", "par"].contains(
              SemanticStructure.value("type", of: element, in: document.parsed))
          {
            Button("Добавить ветвь") {
              document.edit {
                try ConstructorOperations.insertInside(
                  "else Условие", element: element, document: document.parsed)
              }
            }
          }
        }
        if document.parsed.kind == .component
          && ["component", "interface", "container"].contains(element.kind)
        {
          Menu("Переместить в контейнер") {
            Button("Корень") {
              document.edit {
                try ComponentOperations.move(element, into: nil, in: document.parsed)
              }
            }
            ForEach(
              document.parsed.elements.filter { $0.kind == "container" && $0.id != element.id }
            ) { container in
              Button(
                SemanticStructure.readable(
                  SemanticStructure.value("name", of: container, in: document.parsed))
              ) {
                document.edit {
                  try ComponentOperations.move(element, into: container, in: document.parsed)
                }
              }
            }
          }
          if element.kind == "container" {
            Button("Добавить компонент внутрь") {
              document.edit {
                try ConstructorOperations.insertInside(
                  "component \(uniqueIdentifier(prefix: "C"))", element: element,
                  document: document.parsed)
              }
            }
          }
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  func propertyKeys(_ element: Element) -> [String] {
    var keys = [
      "name", "alias", "type", "from", "to", "label", "arrow", "left", "right", "line", "position",
      "target", "datatype", "stereotype", "color", "order", "value", "options",
    ].filter { element.fields[$0] != nil }
    if ["message", "relation", "componentRelation", "block", "branch"].contains(element.kind),
      !keys.contains("label")
    {
      keys.append("label")
    }
    if ["participant", "entity", "component", "interface", "container"].contains(element.kind) {
      if !keys.contains("alias") { keys.insert("alias", at: min(1, keys.count)) }
      if !keys.contains("color") { keys.append("color") }
    }
    if element.kind == "attribute", !keys.contains("datatype") { keys.append("datatype") }
    if element.kind == "diagramSetting" { keys.removeAll { $0 == "type" } }
    if element.kind == "autonumber" { keys = [] }
    return keys
  }
  func propertyTitle(_ key: String, element: Element) -> String {
    if element.kind == "message", ["from", "to"].contains(key) {
      let arrow = SemanticStructure.value("arrow", of: element, in: document.parsed)
      let reverse = arrow.contains("<") && !arrow.contains(">")
      return (key == "from") != reverse ? "Отправитель" : "Получатель"
    }
    return fieldTitle(key)
  }
  func fieldTitle(_ key: String) -> String {
    [
      "name": "Название", "alias": "Алиас", "type": "Тип", "from": "Отправитель / источник",
      "to": "Получатель / цель", "arrow": "Тип стрелки", "label": "Текст / условие",
      "target": "Связанный участник", "left": "Кардинальность источника",
      "right": "Кардинальность цели", "line": "Тип линии", "position": "Положение",
      "datatype": "Тип данных", "stereotype": "Стереотип", "color": "Цвет (#RRGGBB или #имя)",
      "order": "Порядок отображения", "value": "Значение", "options": "Параметры",
    ][key] ?? key
  }
  func fieldSettingTitle(_ key: String) -> String {
    [
      "backgroundColor": "Фон", "defaultFontName": "Шрифт", "defaultFontSize": "Размер шрифта",
      "sequenceMessageAlign": "Выравнивание сообщений",
    ][key] ?? key
  }
  func optionTitle(_ value: String, key: String) -> String {
    if ["from", "to", "target"].contains(key) {
      if let element = document.parsed.elements.first(where: {
        SemanticStructure.value(
          $0.fields["alias"] == nil ? "name" : "alias", of: $0, in: document.parsed) == value
      }) {
        return SemanticStructure.readable(
          SemanticStructure.value("name", of: element, in: document.parsed)) + " (\(value))"
      }
    }
    if key == "left" || key == "right" {
      return [
        "||": "Ровно один", "|o": "Ноль или один", "o|": "Ноль или один", "}o": "Ноль или много",
        "o{": "Ноль или много", "}|": "Один или много", "|{": "Один или много",
      ][value] ?? value
    }
    if key == "line" { return value == "--" ? "Сплошная" : value == ".." ? "Пунктирная" : value }
    if key == "arrow" {
      return [
        "->": "Вызов →", "-->": "Ответ ⇢", "->>": "Асинхронное →", "-->>": "Асинхронный ответ ⇢",
        "<-": "Обратный вызов ←", "<--": "Обратный ответ ⇠", "<->": "Двунаправленная ↔",
      ][value] ?? value
    }
    return value
  }
  func choices(_ key: String, element: Element) -> [String] {
    switch key {
    case "from", "to", "target": return identifiers
    case "arrow": return SequenceArrow.allCases.map(\.rawValue)
    case "left": return Cardinality.allCases.map(\.leftSymbol)
    case "right": return Cardinality.allCases.map(\.rightSymbol)
    case "line":
      return document.parsed.kind == .component
        ? ["-->", "..>", "--", "..", "<--", "<..", "*--", "o--"]
        : RelationshipLine.allCases.map(\.rawValue)
    case "position":
      let target = SemanticStructure.value("target", of: element, in: document.parsed)
      return target.isEmpty
        ? ["left", "right"] : target.contains(",") ? ["over"] : ["left", "right", "over"]
    case "value":
      return SemanticStructure.value("type", of: element, in: document.parsed)
        == "sequenceMessageAlign"
        ? ["left", "center", "right", "direction", "reverseDirection"] : []
    case "type":
      if element.kind == "block" { return BlockType.allCases.map(\.rawValue) }
      if ["component", "interface", "container"].contains(element.kind) {
        return ComponentType.allCases.map(\.rawValue)
      }
      if element.kind == "participant" { return ParticipantType.allCases.map(\.rawValue) }
      if element.kind == "activation" { return ["activate", "deactivate", "destroy"] }
      return []
    default: return []
    }
  }
  var selectedEntity: Element? {
    guard let selected else { return nil }
    if selected.kind == "entity" { return selected }
    return document.parsed.elements.first {
      $0.kind == "entity"
        && $0.fullRange.map { NSLocationInRange(selected.range.location, $0) } == true
    }
  }
  var identifiers: [String] {
    var values = document.parsed.elements.filter {
      ["participant", "entity", "component", "interface", "container"].contains($0.kind)
    }.map {
      SemanticStructure.value(
        $0.fields["alias"] == nil ? "name" : "alias", of: $0, in: document.parsed)
    }
    if document.parsed.kind == .sequence {
      for node in document.parsed.elements where node.kind == "message" {
        for key in ["from", "to"] {
          let value = SemanticStructure.value(key, of: node, in: document.parsed)
          if !value.isEmpty && !values.contains(value) { values.append(value) }
        }
      }
    }
    return values
  }
  func uniqueIdentifier(prefix: String) -> String {
    var number = 1
    while identifiers.contains("\(prefix)\(number)") { number += 1 }
    return "\(prefix)\(number)"
  }
  var messageTemplate: String {
    "\(identifiers.first ?? "A") -> \(identifiers.last ?? "B") : Сообщение"
  }
  func insertScenario(_ text: String, into element: Element) {
    document.edit {
      if element.kind == "branch" {
        return try SemanticOperations.insert(text, intoBranch: element, in: document.parsed)
      }
      if document.selectionFirstBranch {
        return try SemanticOperations.insertIntoFirstBranch(
          text, block: element, in: document.parsed)
      }
      return try ConstructorOperations.insertInside(
        text, element: element, document: document.parsed)
    }
  }
  func add(_ text: String, declaration: Bool = false) {
    document.edit {
      if !declaration, let selected, ["block", "branch"].contains(selected.kind) {
        if selected.kind == "branch" {
          return try SemanticOperations.insert(text, intoBranch: selected, in: document.parsed)
        }
        if document.selectionFirstBranch {
          return try SemanticOperations.insertIntoFirstBranch(
            text, block: selected, in: document.parsed)
        }
        return try ConstructorOperations.insertInside(
          text, element: selected, document: document.parsed)
      }
      return try SourceDocument.insert(text, in: document.source)
    }
  }
}
