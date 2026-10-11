import Foundation

public enum SemanticOperations {
  private static func check(_ element: Element, _ document: ParsedDocument) throws {
    try ConstructorOperations.validate(element, in: document)
    guard document.canEdit else { throw SourceError.invalidEdit }
  }
  public static func properties(
    _ values: [String: String], of element: Element, in document: ParsedDocument
  ) throws -> String {
    try check(element, document)
    let ns = document.source as NSString
    var values = values.filter { key, value in
      guard let range = element.fields[key] else { return !value.isEmpty }
      return ns.substring(with: range) != value
    }
    let bracketDeclaration =
      element.kind == "component"
      && element.text.trimmingCharacters(in: .whitespaces).hasPrefix("[")
    if values["name"] != nil, values["alias"] == nil, element.fields["alias"] == nil,
      let name = element.fields["name"],
      ns.substring(with: name).hasPrefix("\"")
        || bracketDeclaration
          && ns.substring(with: name).range(
            of: #"^[\p{L}_][\p{L}\w]*$"#, options: .regularExpression) == nil,
      ["participant", "entity", "component", "interface", "container"].contains(element.kind)
    {
      let identities = Set(
        document.elements.compactMap { node in
          (node.fields["alias"] ?? node.fields["name"]).map { ns.substring(with: $0) }
        })
      var number = 1
      while identities.contains("Object\(number)") { number += 1 }
      values["alias"] = "Object\(number)"
    }
    var source = document.source
    var current = element
    if let alias = values.removeValue(forKey: "alias") {
      source = try ConstructorOperations.renameAlias(element, to: alias, in: document)
      if element.fields["alias"] == nil, let nameRange = element.fields["name"] {
        let oldName = ns.substring(with: nameRange)
        if bracketDeclaration {
          source = try SourceDocument.apply(
            [
              TextEdit(
                range: NSRange(location: nameRange.location, length: (alias as NSString).length),
                replacement: oldName),
              TextEdit(
                range: NSRange(
                  location: nameRange.location + (alias as NSString).length + 1, length: 0),
                replacement: " as " + alias),
            ], to: source)
        } else {
          let displayName = oldName.hasPrefix("\"") ? oldName : "\"" + oldName + "\""
          source = try SourceDocument.apply(
            [
              TextEdit(
                range: NSRange(location: nameRange.location, length: (alias as NSString).length),
                replacement: displayName + " as " + alias)
            ], to: source)
        }
      }
      let updated = SourceDocument.parse(source, mode: document.kind)
      guard
        let node = updated.elements.first(where: {
          $0.range.location == element.range.location && $0.kind == element.kind
        })
      else { throw SourceError.staleRange }
      current = node
    }
    let updated = source as NSString
    var edits: [TextEdit] = []
    if element.kind == "note", let position = values["position"],
      let positionRange = current.fields["position"], let targetRange = current.fields["target"],
      !updated.substring(with: targetRange).trimmingCharacters(in: .whitespaces).isEmpty
    {
      let between = NSRange(
        location: NSMaxRange(positionRange),
        length: targetRange.location - NSMaxRange(positionRange))
      edits.append(TextEdit(range: between, replacement: position == "over" ? " " : " of "))
    }
    for (key, raw) in values {
      let multiline = key == "label" && SourceDocument.hasLineBreak(element.text)
      let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
      guard normalized.range(of: "\r") == nil, !SourceDocument.hasLineBreak(normalized) || multiline
      else {
        throw SourceError.invalidEdit
      }
      if multiline {
        let closing = element.kind == "note" ? "end note" : "end title"
        guard
          !normalized.components(separatedBy: "\n").contains(where: {
            $0.trimmingCharacters(in: .whitespaces) == closing
          })
        else { throw SourceError.invalidEdit }
      }
      var value =
        multiline
        ? normalized.replacingOccurrences(
          of: "\n", with: document.source.contains("\r\n") ? "\r\n" : "\n") : raw
      if key == "name",
        ["participant", "entity", "component", "interface", "container"].contains(element.kind)
      {
        guard !raw.contains("\""), !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
          throw SourceError.invalidEdit
        }
        value = bracketDeclaration ? raw : "\"" + raw + "\""
        if bracketDeclaration && raw.contains("]") { throw SourceError.invalidEdit }
        if current.fields["alias"] == nil, let range = current.fields["name"] {
          let identifier = updated.substring(with: range)
          // Preserve reference identity when a declaration previously used its name as alias.
          if !identifier.hasPrefix("\"") {
            if bracketDeclaration {
              edits.append(
                TextEdit(
                  range: NSRange(location: NSMaxRange(range) + 1, length: 0),
                  replacement: " as " + identifier))
            } else {
              value += " as " + identifier
            }
          } else {
            throw SourceError.unsafeReference
          }
        }
      }
      if let range = current.fields[key] {
        edits.append(TextEdit(range: range, replacement: value))
      } else if key == "label",
        ["message", "relation", "componentRelation", "block", "branch"].contains(current.kind)
      {
        edits.append(
          TextEdit(
            range: NSRange(location: NSMaxRange(current.range), length: 0),
            replacement: (["block", "branch"].contains(current.kind) ? " " : " : ") + value))
      } else if key == "datatype", current.kind == "attribute", let name = current.fields["name"] {
        guard !value.contains(":"), !value.contains("<"), !value.contains(">") else {
          throw SourceError.invalidEdit
        }
        edits.append(
          TextEdit(
            range: NSRange(location: NSMaxRange(name), length: 0), replacement: " : " + value))
      } else if key == "color",
        ["participant", "entity", "component", "interface", "container"].contains(current.kind)
      {
        guard value.range(of: #"^#[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
          throw SourceError.invalidEdit
        }
        let location: Int
        if let order = current.fields["order"] {
          location =
            updated.range(
              of: "order", options: .backwards,
              range: NSRange(
                location: current.range.location, length: order.location - current.range.location)
            ).location
        } else if ["entity", "container"].contains(current.kind) {
          location = updated.range(of: "{", options: .backwards, range: current.range).location
        } else {
          location = NSMaxRange(current.range)
        }
        guard location != NSNotFound else { throw SourceError.invalidEdit }
        edits.append(
          TextEdit(range: NSRange(location: location, length: 0), replacement: " " + value + " "))
      } else {
        throw SourceError.invalidEdit
      }
    }
    return try SourceDocument.apply(edits, to: source)
  }
  public static func dependencies(of element: Element, in document: ParsedDocument) throws
    -> [Element]
  {
    try check(element, document)
    guard ["participant", "entity", "component", "interface", "container"].contains(element.kind),
      let identity = element.fields["alias"] ?? element.fields["name"]
    else { return [] }
    let ns = document.source as NSString
    let name = ns.substring(with: identity)
    let token = try NSRegularExpression(
      pattern: "(?<![\\p{L}\\w])" + NSRegularExpression.escapedPattern(for: name)
        + "(?![\\p{L}\\w])")
    let span = try ConstructorOperations.span(element, in: document)
    return document.elements.filter { node in
      guard node.id != element.id, !NSLocationInRange(node.range.location, span) else {
        return false
      }
      if node.kind == "unsupported" {
        return token.firstMatch(
          in: node.text, range: NSRange(location: 0, length: (node.text as NSString).length)) != nil
      }
      return ["from", "to", "target"].contains { key in
        guard let range = node.fields[key] else { return false }
        let value = ns.substring(with: range)
        return value == name
          || (key == "target"
            && value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
              .contains(name))
      }
    }
  }
  public static func delete(
    _ element: Element, includingDependencies: Bool, in document: ParsedDocument
  ) throws -> String {
    try check(element, document)
    let dependencies = try dependencies(of: element, in: document)
    guard dependencies.isEmpty || includingDependencies else { throw SourceError.unsafeReference }
    if element.kind == "branch" {
      guard
        let block = document.elements.last(where: {
          $0.kind == "block"
            && $0.fullRange.map { NSLocationInRange(element.range.location, $0) } == true
        }), let extent = block.fullRange
      else { throw SourceError.invalidEdit }
      let ns = document.source as NSString
      var last = NSMaxRange(extent) - 1
      while last > extent.location
        && ["\r", "\n"].contains(ns.substring(with: NSRange(location: last, length: 1)))
      { last -= 1 }
      let closing = ns.lineRange(for: NSRange(location: last, length: 0)).location
      let end =
        document.elements.first(where: {
          $0.kind == "branch" && $0.depth == element.depth
            && $0.range.location > element.range.location
            && NSLocationInRange($0.range.location, extent)
        })?.range.location ?? closing
      return try SourceDocument.apply(
        [
          TextEdit(
            range: NSRange(location: element.range.location, length: end - element.range.location),
            replacement: "")
        ], to: document.source)
    }
    guard
      dependencies.allSatisfy({
        ["message", "relation", "componentRelation", "note", "activation"].contains($0.kind)
      }), element.kind != "unsupported", element.kind != "branch"
    else { throw SourceError.unsafeReference }
    if element.kind == "container" {
      return try ConstructorOperations.delete(element, in: document)
    }
    let ranges = try ([element] + dependencies).map {
      try ConstructorOperations.span($0, in: document)
    }
    return try SourceDocument.apply(
      ranges.map { TextEdit(range: $0, replacement: "") }, to: document.source)
  }
  public static func insert(_ text: String, intoBranch branch: Element, in document: ParsedDocument)
    throws -> String
  {
    try check(branch, document)
    guard branch.kind == "branch",
      let block = document.elements.last(where: {
        $0.kind == "block"
          && $0.fullRange.map { NSLocationInRange(branch.range.location, $0) } == true
      }), let extent = block.fullRange
    else { throw SourceError.invalidEdit }
    let next = document.elements.first {
      $0.kind == "branch" && $0.depth == branch.depth && $0.range.location > branch.range.location
        && $0.range.location < NSMaxRange(extent)
    }
    guard let next else {
      return try ConstructorOperations.insertInside(text, element: block, document: document)
    }
    let newline = document.source.contains("\r\n") ? "\r\n" : "\n"
    let indent = String(branch.text.prefix { $0 == " " || $0 == "\t" }) + "  "
    let insertion =
      text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map {
        indent + $0
      }.joined(separator: newline) + newline
    return try SourceDocument.apply(
      [TextEdit(range: NSRange(location: next.range.location, length: 0), replacement: insertion)],
      to: document.source)
  }
  public static func insertIntoFirstBranch(
    _ text: String, block: Element, in document: ParsedDocument
  ) throws -> String {
    try check(block, document)
    guard block.kind == "block", let extent = block.fullRange else { throw SourceError.invalidEdit }
    guard
      let branch = document.elements.first(where: {
        $0.kind == "branch" && $0.depth == block.depth + 1
          && NSLocationInRange($0.range.location, extent)
      })
    else { return try ConstructorOperations.insertInside(text, element: block, document: document) }
    let newline = document.source.contains("\r\n") ? "\r\n" : "\n"
    let indent = String(block.text.prefix { $0 == " " || $0 == "\t" }) + "  "
    let insertion =
      text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map {
        indent + $0
      }.joined(separator: newline) + newline
    return try SourceDocument.apply(
      [
        TextEdit(range: NSRange(location: branch.range.location, length: 0), replacement: insertion)
      ], to: document.source)
  }
  public static func setAutonumber(_ enabled: Bool, in document: ParsedDocument) throws -> String {
    let nodes = document.elements.filter { $0.kind == "autonumber" }
    guard document.canEdit, nodes.count <= 1,
      nodes.allSatisfy({ SemanticStructure.value("options", of: $0, in: document).isEmpty })
    else { throw SourceError.unsafeReference }
    if let node = nodes.first {
      return enabled ? document.source : try ConstructorOperations.delete(node, in: document)
    }
    return enabled ? try insertSetting("autonumber", in: document) : document.source
  }
  public static func insertSetting(_ text: String, in document: ParsedDocument) throws -> String {
    guard document.canEdit, !SourceDocument.hasLineBreak(text) else {
      throw SourceError.invalidEdit
    }
    let ns = document.source as NSString
    let start = ns.range(of: "@startuml")
    guard start.location != NSNotFound else { throw SourceError.invalidEdit }
    let line = ns.lineRange(for: start)
    let newline = document.source.contains("\r\n") ? "\r\n" : "\n"
    return try SourceDocument.apply(
      [
        TextEdit(range: NSRange(location: NSMaxRange(line), length: 0), replacement: text + newline)
      ], to: document.source)
  }
}
