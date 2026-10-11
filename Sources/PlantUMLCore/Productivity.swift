import Foundation

public struct OutlineNode: Identifiable, Sendable {
  public let element: Element
  public let children: [OutlineNode]
  public var id: Int { element.id }
  public init(element: Element, children: [OutlineNode]) {
    self.element = element
    self.children = children
  }
}
public enum DocumentNavigation {
  public static func outline(_ document: ParsedDocument) -> [OutlineNode] {
    func nodes(_ elements: [Element]) -> [OutlineNode] {
      var result: [OutlineNode] = []
      var index = 0
      while index < elements.count {
        let element = elements[index]
        index += 1
        var descendants: [Element] = []
        if let extent = element.fullRange {
          while index < elements.count && elements[index].range.location < NSMaxRange(extent) {
            descendants.append(elements[index])
            index += 1
          }
        }
        result.append(OutlineNode(element: element, children: nodes(descendants)))
      }
      return result
    }
    return nodes(document.elements)
  }
  public static func element(at offset: Int, in document: ParsedDocument) -> Element? {
    let matches = document.elements.filter { NSLocationInRange(offset, $0.range) }
    return matches.count == 1 ? matches[0] : nil
  }
  public static func search(_ query: String, in document: ParsedDocument) -> [Element] {
    guard !query.isEmpty else { return document.elements }
    return document.elements.filter { $0.text.localizedCaseInsensitiveContains(query) }
  }
}
public struct SearchOptions: Sendable {
  public var caseSensitive: Bool
  public var regex: Bool
  public init(caseSensitive: Bool = false, regex: Bool = false) {
    self.caseSensitive = caseSensitive
    self.regex = regex
  }
}
public enum SourceSearch {
  public static func matches(_ query: String, in source: String, options: SearchOptions) throws
    -> [NSRange]
  {
    guard !query.isEmpty else { return [] }
    let pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
    let regex = try NSRegularExpression(
      pattern: pattern, options: options.caseSensitive ? [] : [.caseInsensitive])
    return regex.matches(
      in: source, range: NSRange(location: 0, length: (source as NSString).length)
    ).map(\.range)
  }
  public static func replace(
    _ query: String, with replacement: String, in source: String, options: SearchOptions,
    only matchIndex: Int? = nil
  ) throws -> String {
    let pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
    guard !query.isEmpty else { return source }
    let regex = try NSRegularExpression(
      pattern: pattern, options: options.caseSensitive ? [] : [.caseInsensitive])
    let matches = regex.matches(
      in: source, range: NSRange(location: 0, length: (source as NSString).length))
    if let matchIndex, !matches.indices.contains(matchIndex) { throw SourceError.invalidEdit }
    let edits = matches.enumerated().compactMap { index, match -> TextEdit? in
      guard matchIndex == nil || index == matchIndex else { return nil }
      let value =
        options.regex
        ? regex.replacementString(for: match, in: source, offset: 0, template: replacement)
        : replacement
      return TextEdit(range: match.range, replacement: value)
    }
    return try SourceDocument.apply(edits, to: source)
  }
}
public enum QuickOperations {
  public static func insertMessage(
    relativeTo element: Element, before: Bool, text: String, in document: ParsedDocument
  ) throws -> String {
    guard document.canEdit,
      document.elements.contains(where: {
        $0.id == element.id && $0.range == element.range && $0.text == element.text
      }), element.kind == "message", !SourceDocument.hasLineBreak(text)
    else { throw SourceError.invalidEdit }
    let range = try ConstructorOperations.span(element, in: document)
    let indent = String(element.text.prefix { $0 == " " || $0 == "\t" })
    let newline = document.source.contains("\r\n") ? "\r\n" : "\n"
    return try SourceDocument.apply(
      [
        TextEdit(
          range: NSRange(location: before ? range.location : NSMaxRange(range), length: 0),
          replacement: indent + text + newline)
      ], to: document.source)
  }
  public static func reply(to element: Element, in document: ParsedDocument) throws -> String {
    let ns = document.source as NSString
    guard element.kind == "message", let from = element.fields["from"],
      let to = element.fields["to"], let arrow = element.fields["arrow"]
    else { throw SourceError.invalidEdit }
    let reverse =
      ns.substring(with: arrow).contains("<") && !ns.substring(with: arrow).contains(">")
    let sender = ns.substring(with: reverse ? from : to)
    let receiver = ns.substring(with: reverse ? to : from)
    return try insertMessage(
      relativeTo: element, before: false, text: "\(sender) --> \(receiver) : Response", in: document
    )
  }
  public static func duplicate(_ element: Element, in document: ParsedDocument) throws -> String {
    guard document.canEdit,
      document.elements.contains(where: {
        $0.id == element.id && $0.range == element.range && $0.text == element.text
      }), ["message", "block", "entity"].contains(element.kind)
    else { throw SourceError.invalidEdit }
    let range = try ConstructorOperations.span(element, in: document)
    let ns = document.source as NSString
    var fragment = ns.substring(with: range)
    if element.kind == "entity" {
      let identifier = element.fields["alias"] ?? element.fields["name"]
      guard let identifier else { throw SourceError.invalidEdit }
      let old = ns.substring(with: identifier)
      guard old.range(of: #"^[\p{L}_][\p{L}\w]*$"#, options: .regularExpression) != nil else {
        throw SourceError.unsafeReference
      }
      let names = Set(
        document.elements.compactMap {
          ($0.fields["alias"] ?? $0.fields["name"]).map { ns.substring(with: $0) }
        })
      var number = 2
      while names.contains(old + String(number)) { number += 1 }
      fragment = try SourceDocument.apply(
        [
          TextEdit(
            range: NSRange(
              location: identifier.location - range.location, length: identifier.length),
            replacement: old + String(number))
        ], to: fragment)
    }
    let newline = document.source.contains("\r\n") ? "\r\n" : "\n"
    if !(fragment as NSString).hasSuffix("\n") { fragment += newline }
    return try SourceDocument.apply(
      [TextEdit(range: NSRange(location: NSMaxRange(range), length: 0), replacement: fragment)],
      to: document.source)
  }
  public static func wrap(_ elements: [Element], with type: String, in document: ParsedDocument)
    throws -> String
  {
    let sorted = elements.sorted { $0.range.location < $1.range.location }
    guard document.canEdit, ["alt", "opt", "loop"].contains(type), let first = sorted.first,
      let last = sorted.last, sorted.allSatisfy({ $0.kind == "message" && $0.depth == first.depth })
    else { throw SourceError.invalidEdit }
    let end = NSMaxRange(try ConstructorOperations.span(last, in: document))
    let range = NSRange(location: first.range.location, length: end - first.range.location)
    let contained = document.elements.filter {
      $0.range.location >= range.location && $0.range.location < end
    }
    guard contained.map(\.id) == sorted.map(\.id) else { throw SourceError.invalidEdit }
    let ns = document.source as NSString
    let body = ns.substring(with: range)
    let indent = String(first.text.prefix { $0 == " " || $0 == "\t" })
    let newline = document.source.contains("\r\n") ? "\r\n" : "\n"
    // Insert delimiters only. The original body, including comments, stays byte-identical.
    return try SourceDocument.apply(
      [
        TextEdit(
          range: range,
          replacement: indent + type + " condition" + newline + body
            + ((body as NSString).hasSuffix("\n") ? "" : newline) + indent + "end" + newline)
      ], to: document.source)
  }
  public static func addAttributes(_ text: String, to entity: Element, in document: ParsedDocument)
    throws -> String
  {
    guard entity.kind == "entity", !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw SourceError.invalidEdit }
    let candidate = SourceDocument.parse("@startuml\nentity Test {\n" + text + "\n}\n@enduml")
    guard candidate.canEdit,
      candidate.elements.dropFirst().allSatisfy({ ["attribute", "separator"].contains($0.kind) })
    else { throw SourceError.invalidEdit }
    return try ConstructorOperations.insertInside(text, element: entity, document: document)
  }
  public static func format(_ range: NSRange, in document: ParsedDocument) throws -> String {
    guard document.canEdit, range.location >= 0, range.length >= 0,
      range.location <= (document.source as NSString).length,
      range.length <= (document.source as NSString).length - range.location,
      NSMaxRange(range) <= (document.source as NSString).length
    else { throw SourceError.invalidEdit }
    let edits = document.elements.filter {
      $0.range.location >= range.location && NSMaxRange($0.range) <= NSMaxRange(range)
        && $0.kind != "unsupported" && !SourceDocument.hasLineBreak($0.text)
    }.map { node in
      let prefix = String(node.text.prefix { $0 == " " || $0 == "\t" })
      return TextEdit(
        range: NSRange(location: node.range.location, length: (prefix as NSString).length),
        replacement: String(repeating: "  ", count: node.depth))
    }
    return try SourceDocument.apply(edits, to: document.source)
  }
}
