import Foundation
import PlantUMLCore

public enum ParticipantType: String, CaseIterable, Sendable {
  case actor, participant, boundary, control, entity, database, collections, queue
}
public enum SequenceArrow: String, CaseIterable, Sendable {
  case call = "->"
  case response = "-->"
  case asynchronous = "->>"
  case asynchronousResponse = "-->>"
  case reverse = "<-"
  case reverseResponse = "<--"
  case reverseAsync = "<<-"
  case reverseAsyncResponse = "<<--"
  case bidirectional = "<->"
  case lost = "->x"
  case origin = "o->"
  case destination = "->o"
}
public enum BlockType: String, CaseIterable, Sendable {
  case alt, opt, loop, par, `break`, critical, group
}
public struct Participant: Sendable {
  public let element: Element
  public let type: ParticipantType
  public let name: String
  public let alias: String?
}
public struct SequenceMessage: Sendable {
  public let element: Element
  public let sender: String
  public let receiver: String
  public let arrow: SequenceArrow
  public let label: String
}
public struct SequenceModel: Sendable {
  public let participants: [Participant]
  public let messages: [SequenceMessage]
  public init(_ document: ParsedDocument) {
    let ns = document.source as NSString
    func field(_ key: String, _ element: Element) -> String? {
      element.fields[key].map { ns.substring(with: $0) }
    }
    participants = document.elements.compactMap { element in
      guard element.kind == "participant",
        let type = field("type", element).flatMap(ParticipantType.init(rawValue:)),
        let name = field("name", element)
      else { return nil }
      return Participant(element: element, type: type, name: name, alias: field("alias", element))
    }
    messages = document.elements.compactMap { element in
      guard element.kind == "message", let sender = field("from", element),
        let receiver = field("to", element),
        let arrow = field("arrow", element).flatMap(SequenceArrow.init(rawValue:))
      else { return nil }
      return SequenceMessage(
        element: element, sender: sender, receiver: receiver, arrow: arrow,
        label: field("label", element) ?? "")
    }
  }
}

public struct SequenceContract: DiagramModuleContract {
  public init() {}
  public var kind: DiagramKind { .sequence }
  public var declarationKinds: Set<String> { ["participant"] }
  public func identityFields(of element: Element) -> [String] {
    switch element.kind {
    case "participant": return [element.fields["alias"] == nil ? "name" : "alias"]
    case "message": return ["from", "to"]
    case "block": return ["type"]
    default: return element.fields.keys.sorted()
    }
  }
}
