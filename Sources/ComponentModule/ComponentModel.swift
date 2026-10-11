import Foundation
import PlantUMLCore

public enum ComponentType: String, CaseIterable, Sendable {
  case component, interface, package, node, database, cloud, frame, folder
}
public struct ComponentNode: Sendable {
  public let element: Element
  public let type: ComponentType
  public let name: String
  public let alias: String?
  public let parent: Int?
}
public struct ComponentRelationship: Sendable {
  public let element: Element
  public let from: String
  public let to: String
  public let line: String
  public let label: String
}
public struct ComponentModel: Sendable {
  public let nodes: [ComponentNode]
  public let relationships: [ComponentRelationship]
  public init(_ document: ParsedDocument) {
    let ns = document.source as NSString
    func value(_ key: String, _ element: Element) -> String? {
      element.fields[key].map { ns.substring(with: $0) }
    }
    nodes = document.elements.compactMap { element in
      guard ["component", "interface", "container"].contains(element.kind),
        let name = value("name", element)
      else { return nil }
      let parent = document.elements.filter {
        $0.kind == "container" && $0.id != element.id
          && $0.fullRange.map { NSLocationInRange(element.range.location, $0) } == true
      }.min { ($0.fullRange?.length ?? Int.max) < ($1.fullRange?.length ?? Int.max) }
      return ComponentNode(
        element: element,
        type: ComponentType(rawValue: value("type", element) ?? element.kind) ?? .component,
        name: name, alias: value("alias", element), parent: parent?.id)
    }
    relationships = document.elements.compactMap { element in
      guard element.kind == "componentRelation", let from = value("from", element),
        let to = value("to", element), let line = value("line", element)
      else { return nil }
      return ComponentRelationship(
        element: element, from: from, to: to, line: line, label: value("label", element) ?? "")
    }
  }
}
public enum ComponentOperations {
  public static func move(_ element: Element, into container: Element?, in document: ParsedDocument)
    throws -> String
  {
    guard document.kind == .component, document.canEdit,
      ["component", "interface", "container"].contains(element.kind)
    else { throw SourceError.invalidEdit }
    let range = try ConstructorOperations.span(element, in: document)
    let ns = document.source as NSString
    let fragment = ns.substring(with: range)
    let destination: Int
    if let container {
      guard container.kind == "container", let extent = container.fullRange,
        !NSLocationInRange(container.range.location, range)
      else { throw SourceError.invalidEdit }
      var last = NSMaxRange(extent) - 1
      while last > extent.location
        && ["\n", "\r"].contains(ns.substring(with: NSRange(location: last, length: 1)))
      { last -= 1 }
      destination = ns.lineRange(for: NSRange(location: last, length: 0)).location
    } else {
      destination = ns.lineRange(for: ns.range(of: "@enduml", options: .backwards)).location
    }
    guard !NSLocationInRange(destination, range), destination != range.location else {
      throw SourceError.invalidEdit
    }
    return try SourceDocument.apply(
      [
        TextEdit(range: range, replacement: ""),
        TextEdit(range: NSRange(location: destination, length: 0), replacement: fragment),
      ], to: document.source)
  }
}

public struct ComponentContract: DiagramModuleContract {
  public init() {}
  public var kind: DiagramKind { .component }
  public var declarationKinds: Set<String> { ["component", "interface", "container"] }
  public func identityFields(of element: Element) -> [String] {
    switch element.kind {
    case "component", "interface", "container":
      return [element.fields["alias"] == nil ? "name" : "alias"]
    case "componentRelation": return ["from", "to"]
    default: return element.fields.keys.sorted()
    }
  }
}
