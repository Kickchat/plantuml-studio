import Foundation

public enum ConstructorOperations {
  public static func renameAlias(_ element: Element, to alias: String, in document: ParsedDocument)
    throws -> String
  {
    guard document.canEdit, let range = element.fields["alias"] ?? element.fields["name"],
      alias.range(of: #"^[\p{L}_][\p{L}\w]*$"#, options: .regularExpression) != nil
    else { throw SourceError.invalidEdit }
    let ns = document.source as NSString
    let previous = ns.substring(with: range)
    guard previous.first != "\"" else { throw SourceError.unsafeReference }
    let token = try NSRegularExpression(
      pattern: "(?<![\\p{L}\\w])" + NSRegularExpression.escapedPattern(for: previous)
        + "(?![\\p{L}\\w])")
    // Unsupported statements may reference this alias. Refuse rather than guessing.
    for node in document.elements where node.kind == "unsupported" || node.kind == "note" {
      if token.firstMatch(
        in: node.text, range: NSRange(location: 0, length: (node.text as NSString).length)) != nil
      {
        throw SourceError.unsafeReference
      }
    }
    for node in document.elements
    where node.id != element.id
      && ["entity", "participant", "component", "interface", "container"].contains(node.kind)
    {
      for key in ["name", "alias"] {
        if let r = node.fields[key], ns.substring(with: r) == alias {
          throw SourceError.invalidEdit
        }
      }
    }
    var edits = [TextEdit(range: range, replacement: alias)]
    for node in document.elements {
      for key in ["from", "to", "target"] {
        if let r = node.fields[key], ns.substring(with: r) == previous {
          edits.append(TextEdit(range: r, replacement: alias))
        }
      }
    }
    return try SourceDocument.apply(edits, to: document.source)
  }
  public static func span(_ element: Element, in document: ParsedDocument) throws -> NSRange {
    let ns = document.source as NSString
    var end = NSMaxRange(element.range)
    if element.kind == "block" || element.kind == "entity" || element.kind == "container" {
      guard let fullRange = element.fullRange else { throw SourceError.invalidEdit }
      return fullRange
    }
    if end < ns.length && ns.substring(with: NSRange(location: end, length: 1)) == "\r" { end += 1 }
    if end < ns.length && ns.substring(with: NSRange(location: end, length: 1)) == "\n" { end += 1 }
    return NSRange(location: element.range.location, length: end - element.range.location)
  }
  public static func delete(_ element: Element, in document: ParsedDocument) throws -> String {
    guard document.canEdit, element.kind != "unsupported", element.kind != "branch" else {
      throw SourceError.invalidEdit
    }
    if element.kind == "container", let extent = element.fullRange {
      for child in document.elements
      where child.id != element.id && NSLocationInRange(child.range.location, extent)
        && ["component", "interface", "container"].contains(child.kind)
      {
        _ = try delete(child, in: document)
      }
    }
    if ["participant", "entity", "component", "interface", "container"].contains(element.kind) {
      let ns = document.source as NSString
      let identifier = element.fields["alias"] ?? element.fields["name"]
      guard let identifier else { throw SourceError.invalidEdit }
      let name = ns.substring(with: identifier)
      let token = try NSRegularExpression(
        pattern: "(?<![\\p{L}\\w])" + NSRegularExpression.escapedPattern(for: name)
          + "(?![\\p{L}\\w])")
      let deletedRange = try span(element, in: document)
      for other in document.elements
      where other.id != element.id
        && !(other.range.location >= deletedRange.location
          && NSMaxRange(other.range) <= NSMaxRange(deletedRange))
      {
        if token.firstMatch(
          in: other.text, range: NSRange(location: 0, length: (other.text as NSString).length))
          != nil
        {
          throw SourceError.unsafeReference
        }
      }
    }
    return try SourceDocument.apply(
      [TextEdit(range: try span(element, in: document), replacement: "")], to: document.source)
  }
  public static func insertInside(_ text: String, element: Element, document: ParsedDocument) throws
    -> String
  {
    guard document.canEdit, ["block", "entity", "container"].contains(element.kind) else {
      throw SourceError.invalidEdit
    }
    let ns = document.source as NSString
    let range = try span(element, in: document)
    var last = NSMaxRange(range) - 1
    while last > range.location,
      ["\r", "\n"].contains(ns.substring(with: NSRange(location: last, length: 1)))
    { last -= 1 }
    let closing = ns.lineRange(for: NSRange(location: last, length: 0))
    let newline = document.source.contains("\r\n") ? "\r\n" : "\n"
    let indentation = String(element.text.prefix { $0 == " " || $0 == "\t" }) + "  "
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
    let insertion =
      normalized.components(separatedBy: "\n").map { indentation + $0 }.joined(separator: newline)
      + newline
    return try SourceDocument.apply(
      [TextEdit(range: NSRange(location: closing.location, length: 0), replacement: insertion)],
      to: document.source)
  }
}

extension ConstructorOperations {
  public static func move(_ element: Element, up: Bool, in document: ParsedDocument) throws
    -> String
  {
    guard document.canEdit, !["branch", "unsupported", "activation"].contains(element.kind) else {
      throw SourceError.invalidEdit
    }
    let range = try span(element, in: document)
    let ns = document.source as NSString
    let candidates = document.elements.filter {
      $0.depth == element.depth && $0.id != element.id
        && (up ? NSMaxRange($0.range) <= range.location : $0.range.location >= NSMaxRange(range))
    }
    guard let other = up ? candidates.last : candidates.first, other.kind != "unsupported",
      other.kind != "branch", other.kind != "activation"
    else { throw SourceError.invalidEdit }
    let otherRange = try span(other, in: document)
    let first = up ? otherRange : range
    let second = up ? range : otherRange
    // Only whitespace may be crossed. This prevents moving across end/else, comments,
    // unknown statements, or another parent's closing delimiter.
    guard NSMaxRange(first) <= second.location else { throw SourceError.invalidEdit }
    let between = ns.substring(
      with: NSRange(location: NSMaxRange(first), length: second.location - NSMaxRange(first)))
    guard between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SourceError.invalidEdit
    }
    let replacement = ns.substring(with: second) + between + ns.substring(with: first)
    return try SourceDocument.apply(
      [
        TextEdit(
          range: NSRange(location: first.location, length: NSMaxRange(second) - first.location),
          replacement: replacement)
      ], to: document.source)
  }
}

extension ConstructorOperations {
  public static func setAttributeMandatory(
    _ element: Element, enabled: Bool, in document: ParsedDocument
  ) throws -> String {
    guard document.canEdit, element.kind == "attribute", let name = element.fields["name"] else {
      throw SourceError.invalidEdit
    }
    if let marker = element.fields["mandatory"] {
      return enabled
        ? document.source
        : try SourceDocument.apply([TextEdit(range: marker, replacement: "")], to: document.source)
    }
    return enabled
      ? try SourceDocument.apply(
        [TextEdit(range: NSRange(location: name.location, length: 0), replacement: "* ")],
        to: document.source) : document.source
  }
  public static func setAttributeKey(_ element: Element, enabled: Bool, in document: ParsedDocument)
    throws -> String
  {
    guard document.canEdit, element.kind == "attribute" else { throw SourceError.invalidEdit }
    if let stereotype = element.fields["stereotype"] {
      let current = (document.source as NSString).substring(with: stereotype)
      guard current == "<<PK>>" else { throw SourceError.unsafeReference }
      return enabled
        ? document.source
        : try SourceDocument.apply(
          [TextEdit(range: stereotype, replacement: "")], to: document.source)
    }
    return enabled
      ? try SourceDocument.apply(
        [
          TextEdit(
            range: NSRange(location: NSMaxRange(element.range), length: 0), replacement: " <<PK>>")
        ], to: document.source) : document.source
  }
}
