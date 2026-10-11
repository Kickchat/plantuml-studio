import Foundation

public struct DiagramTemplate: Codable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var category: String
  public var kind: String
  public var fragment: String
  public init(id: UUID = UUID(), name: String, category: String, kind: String, fragment: String) {
    self.id = id
    self.name = name
    self.category = category
    self.kind = kind
    self.fragment = fragment
  }
}
public enum TemplateLibrary {
  public static let builtins: [DiagramTemplate] = [
    .init(
      name: "REST request / response", category: "Sequence", kind: "sequence",
      fragment:
        "participant Client\nparticipant API\nClient -> API : GET /resource\nAPI --> Client : 200 OK"
    ),
    .init(
      name: "Async", category: "Sequence", kind: "sequence",
      fragment: "participant Producer\nparticipant Consumer\nProducer ->> Consumer : Event"),
    .init(
      name: "Error", category: "Sequence", kind: "sequence",
      fragment:
        "participant Client\nparticipant API\nClient -> API : Request\nAPI --> Client : Error"),
    .init(
      name: "Retry", category: "Sequence", kind: "sequence",
      fragment:
        "participant Client\nparticipant API\nloop retry up to 3 times\nClient -> API : Request\nAPI --> Client : Response\nend"
    ),
    .init(
      name: "Timeout", category: "Sequence", kind: "sequence",
      fragment:
        "participant Client\nparticipant API\nClient -> API : Request\n... timeout ...\nAPI --> Client : Timeout"
    ),
    .init(
      name: "Alt", category: "Sequence", kind: "sequence",
      fragment:
        "participant Client\nparticipant API\nalt success\nAPI --> Client : OK\nelse failure\nAPI --> Client : Error\nend"
    ),
    .init(
      name: "Queue", category: "Sequence", kind: "sequence",
      fragment:
        "participant Producer\nqueue Queue\nparticipant Worker\nProducer ->> Queue : Publish\nQueue ->> Worker : Deliver"
    ),
    .init(
      name: "Entity", category: "ER", kind: "er",
      fragment: "entity Item {\n * id : integer <<PK>>\n name : text\n}"),
    .init(
      name: "One to many", category: "ER", kind: "er",
      fragment:
        "entity Parent {\n * id : integer <<PK>>\n}\nentity Child {\n * id : integer <<PK>>\n parent_id : integer <<FK>>\n}\nParent ||--o{ Child : owns"
    ),
    .init(
      name: "Many to many", category: "ER", kind: "er",
      fragment:
        "entity LeftItem {\n * id : integer <<PK>>\n}\nentity RightItem {\n * id : integer <<PK>>\n}\nentity Membership {\n * left_id : integer <<FK>>\n * right_id : integer <<FK>>\n}\nLeftItem ||--o{ Membership\nRightItem ||--o{ Membership"
    ),
    .init(
      name: "Related set", category: "ER", kind: "er",
      fragment:
        "entity Customer {\n * id : integer <<PK>>\n}\nentity Order {\n * id : integer <<PK>>\n customer_id : integer <<FK>>\n}\nentity Line {\n * id : integer <<PK>>\n order_id : integer <<FK>>\n}\nCustomer ||--o{ Order\nOrder ||--o{ Line"
    ),
  ]
  public static func insert(_ template: DiagramTemplate, in document: ParsedDocument) throws
    -> String
  {
    guard document.canEdit, template.kind == document.kind.rawValue else {
      throw SourceError.invalidEdit
    }
    var fragment = SourceDocument.parse(
      "@startuml\n" + template.fragment + "\n@enduml\n", mode: document.kind)
    guard fragment.canEdit else { throw SourceError.invalidEdit }
    let source = document.source as NSString
    var used = Set(
      document.elements.filter {
        ["participant", "entity", "component", "interface", "container"].contains($0.kind)
      }.compactMap {
        ($0.fields["alias"] ?? $0.fields["name"]).map { source.substring(with: $0) }
      })
    // Reserve the entire template namespace before renaming any declaration.
    let original = fragment.source as NSString
    let declarations = fragment.elements.filter {
      ["participant", "entity", "component", "interface", "container"].contains($0.kind)
    }
    let names = declarations.compactMap {
      ($0.fields["alias"] ?? $0.fields["name"]).map { original.substring(with: $0) }
    }
    used.formUnion(names)
    let existing = Set(
      document.elements.filter {
        ["participant", "entity", "component", "interface", "container"].contains($0.kind)
      }.compactMap {
        ($0.fields["alias"] ?? $0.fields["name"]).map { source.substring(with: $0) }
      })
    for name in names where existing.contains(name) {
      var suffix = 2
      while used.contains(name + String(suffix)) { suffix += 1 }
      let replacement = name + String(suffix)
      used.insert(replacement)
      let ns = fragment.source as NSString
      guard
        let element = fragment.elements.first(where: { node in
          guard let range = node.fields["alias"] ?? node.fields["name"] else { return false }
          return ["participant", "entity", "component", "interface", "container"].contains(
            node.kind) && ns.substring(with: range) == name
        })
      else { throw SourceError.invalidEdit }
      fragment = SourceDocument.parse(
        try ConstructorOperations.renameAlias(element, to: replacement, in: fragment),
        mode: document.kind)
    }
    let ns = fragment.source as NSString
    let start = ns.range(of: "\n").location + 1
    let end = ns.range(of: "@enduml", options: .backwards).location
    return try SourceDocument.insert(
      ns.substring(with: NSRange(location: start, length: end - start)), in: document.source)
  }
}
