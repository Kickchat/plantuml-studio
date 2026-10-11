import Foundation

public enum SyntaxHints {
  public static func hint(for element: Element, in document: ParsedDocument) -> String {
    switch element.kind {
    case "message": return "from -> to : label · --> reply · ->> async"
    case "participant": return "participant \"Name\" as Alias #Color"
    case "block": return "alt / opt / loop condition … end"
    case "entity": return "entity \"Name\" as Alias { … }"
    case "attribute": return "* mandatory_name : type <<PK>> / <<FK>>"
    case "relation": return "Parent ||--o{ Child : label"
    case "component", "interface", "container":
      return "component / interface / package \"Name\" as Alias #Color · { … } for containers"
    case "componentRelation": return "from --> to : label · ..> dotted · o-- aggregation"
    case "note": return "note right of Alias : text"
    default: return "Unknown syntax is preserved; edit its original text."
    }
  }
}
