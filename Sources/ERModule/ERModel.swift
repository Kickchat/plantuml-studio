import Foundation
import PlantUMLCore

public enum Cardinality: String, CaseIterable, Sendable {
  case exactlyOne, zeroOrOne, zeroOrMany, oneOrMany
  public var leftSymbol: String {
    switch self {
    case .exactlyOne: "||"
    case .zeroOrOne: "|o"
    case .zeroOrMany: "}o"
    case .oneOrMany: "}|"
    }
  }
  public var rightSymbol: String {
    switch self {
    case .exactlyOne: "||"
    case .zeroOrOne: "o|"
    case .zeroOrMany: "o{"
    case .oneOrMany: "|{"
    }
  }
}
public enum RelationshipLine: String, CaseIterable, Sendable {
  case solid = "--"
  case dotted = ".."
}
public struct EREntity: Sendable {
  public let element: Element
  public let name: String
  public let alias: String?
  public let attributes: [Element]
}
public struct ERRelationship: Sendable {
  public let element: Element
  public let source: String
  public let destination: String
  public let left: Cardinality
  public let right: Cardinality
  public let line: RelationshipLine
  public let label: String
}
public struct ERModel: Sendable {
  public let entities: [EREntity]
  public let relationships: [ERRelationship]
  public init(_ document: ParsedDocument) {
    let ns = document.source as NSString
    func field(_ key: String, _ element: Element) -> String? {
      element.fields[key].map { ns.substring(with: $0) }
    }
    entities = document.elements.compactMap { element in
      guard element.kind == "entity", let name = field("name", element),
        let extent = element.fullRange
      else { return nil }
      let attributes = document.elements.filter {
        ["attribute", "separator"].contains($0.kind) && $0.range.location > element.range.location
          && $0.range.location < NSMaxRange(extent)
      }
      return EREntity(
        element: element, name: name, alias: field("alias", element), attributes: attributes)
    }
    relationships = document.elements.compactMap { element in
      guard element.kind == "relation", let source = field("from", element),
        let destination = field("to", element),
        let left = Cardinality.allCases.first(where: { $0.leftSymbol == field("left", element) }),
        let right = Cardinality.allCases.first(where: { $0.rightSymbol == field("right", element) }
        ), let line = field("line", element).flatMap(RelationshipLine.init(rawValue:))
      else { return nil }
      return ERRelationship(
        element: element, source: source, destination: destination, left: left, right: right,
        line: line, label: field("label", element) ?? "")
    }
  }
}
