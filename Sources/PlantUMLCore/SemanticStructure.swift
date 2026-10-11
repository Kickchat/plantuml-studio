import Foundation

/// A presentation of existing parser nodes, never a second source parser.
public struct SemanticNode: Identifiable, Sendable {
  public let element: Element
  public let title: String
  public let subtitle: String
  public let icon: String
  public let color: String?
  public let children: [SemanticNode]
  public let initialBranch: Bool
  public var implicitIdentifier: String? = nil
  public var id: String {
    if let implicitIdentifier { return "implicit-" + implicitIdentifier }
    return initialBranch ? "first-\(element.id)" : "element-\(element.id)"
  }
}
public struct SemanticSection: Identifiable, Sendable {
  public let id: String
  public let title: String
  public let nodes: [SemanticNode]
}
public enum SemanticStructure {
  public static func value(_ key: String, of element: Element, in document: ParsedDocument)
    -> String
  {
    guard let range = element.fields[key], range.location >= 0, range.length >= 0,
      range.location <= (document.source as NSString).length,
      range.length <= (document.source as NSString).length - range.location
    else { return "" }
    return (document.source as NSString).substring(with: range)
  }
  public static func readable(_ text: String) -> String {
    var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
      text = String(text.dropFirst().dropLast())
    }
    return text.replacingOccurrences(of: "\\n", with: "\n")
  }
  public static func isSetting(_ element: Element) -> Bool {
    ["title", "autonumber", "diagramSetting"].contains(element.kind)
      || (element.kind == "unsupported"
        && [
          "skinparam", "<style>", "hide footbox", "show footbox", "!theme", "header", "footer",
          "caption", "scale",
        ].contains(where: { element.text.trimmingCharacters(in: .whitespaces).hasPrefix($0) }))
  }
  public static func sections(_ document: ParsedDocument, query: String = "") -> [SemanticSection] {
    let declarations: Set<String> =
      document.kind == .sequence
      ? ["participant"]
      : document.kind == .er ? ["entity"] : ["component", "interface", "container"]
    let relations: Set<String> = ["relation", "componentRelation"]
    let roots = DocumentNavigation.outline(document)
    var objects = roots.filter { declarations.contains($0.element.kind) }.map {
      node($0, in: document)
    }
    if document.kind == .sequence {
      var known = Set(
        objects.map {
          value($0.element.fields["alias"] == nil ? "name" : "alias", of: $0.element, in: document)
        })
      for message in document.elements where message.kind == "message" {
        for key in ["from", "to"] {
          let identifier = value(key, of: message, in: document)
          if !identifier.isEmpty && known.insert(identifier).inserted {
            var implicit = SemanticNode(
              element: message, title: readable(identifier), subtitle: "Participant · неявный",
              icon: "person.crop.square", color: nil, children: [], initialBranch: false)
            implicit.implicitIdentifier = identifier
            objects.append(implicit)
          }
        }
      }
    }
    let links = roots.filter { relations.contains($0.element.kind) }.map { node($0, in: document) }
    let scenario = roots.filter {
      !declarations.contains($0.element.kind) && !relations.contains($0.element.kind)
        && !isSetting($0.element)
    }.map { node($0, in: document) }
    let settings = roots.filter { isSetting($0.element) }.map { node($0, in: document) }
    var sections = [
      SemanticSection(
        id: "objects",
        title: document.kind == .sequence
          ? "Участники" : document.kind == .er ? "Сущности" : "Компоненты", nodes: objects)
    ]
    if document.kind == .sequence {
      sections.append(SemanticSection(id: "scenario", title: "Сценарий", nodes: scenario))
    } else {
      sections.append(SemanticSection(id: "relations", title: "Связи", nodes: links))
      if !scenario.isEmpty {
        sections.append(SemanticSection(id: "other", title: "Другие конструкции", nodes: scenario))
      }
    }
    sections.append(SemanticSection(id: "settings", title: "Настройки диаграммы", nodes: settings))
    guard !query.isEmpty else { return sections }
    func filter(_ node: SemanticNode) -> SemanticNode? {
      let identities =
        node.implicitIdentifier
        ?? ["alias", "from", "to", "target"].map {
          value($0, of: node.element, in: document)
        }.joined(separator: " ")
      if (node.title + " " + node.subtitle + " " + identities).localizedCaseInsensitiveContains(
        query)
      {
        return node
      }
      let children = node.children.compactMap(filter)
      guard !children.isEmpty else { return nil }
      var filtered = SemanticNode(
        element: node.element, title: node.title, subtitle: node.subtitle, icon: node.icon,
        color: node.color, children: children, initialBranch: node.initialBranch)
      filtered.implicitIdentifier = node.implicitIdentifier
      return filtered
    }
    return sections.map {
      SemanticSection(id: $0.id, title: $0.title, nodes: $0.nodes.compactMap(filter))
    }.filter { !$0.nodes.isEmpty }
  }
  public static func node(_ outline: OutlineNode, in document: ParsedDocument) -> SemanticNode {
    let element = outline.element
    func field(_ key: String) -> String { readable(value(key, of: element, in: document)) }
    func name(_ identifier: String) -> String {
      let match = document.elements.first {
        ["participant", "entity", "component", "interface", "container"].contains($0.kind)
          && readable(value($0.fields["alias"] == nil ? "name" : "alias", of: $0, in: document))
            == identifier
      }
      return match.map { readable(value("name", of: $0, in: document)) } ?? identifier
    }
    var title = field("label")
    var subtitle = ""
    var icon = "square"
    var children = outline.children.filter { !isSetting($0.element) }.map { node($0, in: document) }
    switch element.kind {
    case "participant":
      title = field("name")
      subtitle = field("type").capitalized
      icon =
        [
          "actor": "person", "boundary": "rectangle.and.arrow.up.right.and.arrow.down.left",
          "control": "gearshape", "database": "externaldrive", "queue": "tray.full",
          "collections": "square.stack", "entity": "square.on.square",
        ][field("type")] ?? "person.crop.square"
    case "entity", "component", "interface", "container":
      title = field("name")
      subtitle = element.kind == "entity" ? "Сущность" : field("type").capitalized
      icon = element.kind == "container" ? "folder" : "square.stack.3d.up"
    case "message":
      if title.isEmpty { title = "Сообщение без подписи" }
      let reverse = field("arrow").contains("<") && !field("arrow").contains(">")
      subtitle =
        name(field(reverse ? "to" : "from"))
        + (field("arrow").contains("<") && field("arrow").contains(">") ? " ↔ " : " → ")
        + name(field(reverse ? "from" : "to"))
      icon = reverse ? "arrow.left" : "arrow.right"
    case "block":
      title = field("type").uppercased() + (title.isEmpty ? "" : ": " + title)
      icon = "rectangle.3.group"
      if ["alt", "par"].contains(field("type")),
        outline.children.contains(where: { $0.element.kind == "branch" })
      {
        var groups: [SemanticNode] = []
        var branch = element
        var first = true
        var members: [SemanticNode] = []
        func append() {
          groups.append(
            SemanticNode(
              element: branch,
              title: "Ветка: "
                + (readable(value("label", of: branch, in: document)).isEmpty
                  ? "Без условия" : readable(value("label", of: branch, in: document))),
              subtitle: "", icon: "arrow.triangle.branch", color: nil, children: members,
              initialBranch: first))
        }
        for (child, semantic) in zip(outline.children.filter { !isSetting($0.element) }, children) {
          if child.element.kind == "branch" {
            append()
            branch = child.element
            first = false
            members = []
          } else if !isSetting(child.element) {
            members.append(semantic)
          }
        }
        append()
        children = groups
      }
    case "branch":
      title = "Ветка: " + (title.isEmpty ? "Без условия" : title)
      icon = "arrow.triangle.branch"
    case "attribute":
      title = field("name") + (field("datatype").isEmpty ? "" : " · " + field("datatype"))
      if !field("stereotype").isEmpty {
        title +=
          " · "
          + field("stereotype").replacingOccurrences(of: "<<", with: "").replacingOccurrences(
            of: ">>", with: "")
      }
      subtitle = element.fields["mandatory"] == nil ? "" : "Обязательное поле"
      icon = "list.bullet.indent"
    case "relation", "componentRelation":
      let label = title
      func cardinality(_ symbol: String) -> String {
        ["||": "1", "|o": "0…1", "o|": "0…1", "}o": "0…N", "o{": "0…N", "}|": "1…N", "|{": "1…N"][
          symbol] ?? symbol
      }
      title = name(field("from")) + " → " + name(field("to"))
      subtitle =
        element.kind == "relation"
        ? cardinality(field("left")) + " : " + cardinality(field("right")) : ""
      if !label.isEmpty { subtitle += (subtitle.isEmpty ? "" : " · ") + label }
      icon = "point.3.connected.trianglepath.dotted"
    case "note":
      if title.isEmpty { title = "Заметка" }
      subtitle = "Заметка" + (field("target").isEmpty ? "" : " · " + name(field("target")))
      icon = "note.text"
    case "divider", "separator":
      if title.isEmpty { title = "Разделитель" }
      icon = "minus"
    case "delay":
      if title.isEmpty { title = "Задержка" }
      icon = "clock"
    case "activation":
      title =
        ["activate": "Активация", "deactivate": "Деактивация", "destroy": "Завершение"][
          field("type")] ?? "Активация"
      subtitle = name(field("target"))
      icon = "bolt"
    case "title":
      title = "Название диаграммы"
      subtitle = field("label")
      icon = "textformat"
    case "autonumber":
      title = "Автонумерация"
      subtitle = field("options").isEmpty ? "Включена" : "Настроена в коде"
      icon = "list.number"
    case "diagramSetting":
      title =
        [
          "backgroundColor": "Фон диаграммы", "defaultFontName": "Шрифт",
          "defaultFontSize": "Размер шрифта", "sequenceMessageAlign": "Выравнивание сообщений",
        ][field("type")] ?? "Оформление"
      subtitle = field("value")
      icon = "paintbrush"
    default:
      if isSetting(element) { children = [] }
      title = isSetting(element) ? "Дополнительная настройка" : "Конструкция в коде"
      subtitle = "Сохраняется без изменений"
      icon = "curlybraces"
    }
    return SemanticNode(
      element: element, title: title, subtitle: subtitle, icon: icon,
      color: field("color").isEmpty ? nil : field("color"), children: children, initialBranch: false
    )
  }
}
