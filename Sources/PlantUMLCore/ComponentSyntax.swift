import Foundation

/// Ranged component grammar. Typed semantics and operations live in ComponentModule.
enum ComponentSyntax {
  static let types = "component|interface|package|node|database|cloud|frame|folder"
  static func recognizes(_ source: String) -> Bool {
    var inComment = false
    var opaque: String?
    for raw in source.components(separatedBy: "\n") {
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if inComment {
        if line.contains("'/") { inComment = false }
        continue
      }
      if line.hasPrefix("/'") {
        inComment = !line.contains("'/")
        continue
      }
      if line.isEmpty || line.hasPrefix("'") { continue }
      if let closing = opaque {
        if line == closing { opaque = nil }
        continue
      }
      if (line.hasPrefix("note ") && !line.contains(":")) || line == "note" {
        opaque = "end note"
        continue
      }
      if ["title", "legend", "header", "footer"].contains(line) {
        opaque = "end " + line
        continue
      }
      if line == "<style>" {
        opaque = "</style>"
        continue
      }
      if line.hasPrefix("skinparam ") && line.hasSuffix("{") {
        opaque = "}"
        continue
      }
      if line.hasPrefix("!procedure") {
        opaque = "!endprocedure"
        continue
      }
      if line.hasPrefix("!function") {
        opaque = "!endfunction"
        continue
      }
      if line.range(
        of: #"^(component|interface|package|node|cloud|frame|folder)\s"#,
        options: .regularExpression) != nil
        || line.range(of: #"^\[[^\]\r\n]+\]"#, options: .regularExpression) != nil
      {
        return true
      }
    }
    return false
  }
  static func parse(_ source: String) -> ParsedDocument {
    let declaration = try! NSRegularExpression(
      pattern: "^\\s*(" + types
        + ")\\s+(\"[^\"]+\"|[\\p{L}_][\\p{L}\\w.]*)(?:\\s+as\\s+(\"[^\"]+\"|[\\p{L}_][\\p{L}\\w.]*))?(?:\\s+(<<[^>]+>>))?(?:\\s+(#[\\w]+))?\\s*(\\{)?\\s*$"
    )
    let bracket = try! NSRegularExpression(
      pattern:
        #"^\s*\[([^\]]+)\](?:\s+as\s+([\p{L}_][\p{L}\w.]*))?(?:\s+(<<[^>]+>>))?(?:\s+(#[\w]+))?\s*$"#
    )
    let interface = try! NSRegularExpression(
      pattern: #"^\s*\(\)\s+("[^"]+"|[\p{L}_][\p{L}\w.]*)(?:\s+as\s+([\p{L}_][\p{L}\w.]*))?\s*$"#)
    let relation = try! NSRegularExpression(
      pattern:
        #"^\s*(\[[^\]]+\]|"[^"]+"|[\p{L}_][\p{L}\w.]*)\s*([<o*]?(?:--|\.\.|-)(?:left|right|up|down)?[-.]*[>o*]?)\s*(\[[^\]]+\]|"[^"]+"|[\p{L}_][\p{L}\w.]*)(?:\s*:\s*(.*))?\s*$"#
    )
    let ns = source as NSString
    var elements: [Element] = []
    var diagnostics: [String] = []
    var stack: [Int] = []
    var extents: [Int: NSRange] = [:]
    var offset = 0
    var inComment = false
    var opaque: String?
    var starts = 0
    var ends = 0
    for raw in source.components(separatedBy: "\n") {
      let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
      let trim = line.trimmingCharacters(in: .whitespaces)
      defer { offset += (raw as NSString).length + 1 }
      if inComment {
        if trim.contains("'/") { inComment = false }
        continue
      }
      if trim.hasPrefix("/'") {
        inComment = !trim.contains("'/")
        continue
      }
      if trim.isEmpty || trim.hasPrefix("'") { continue }
      if trim.hasPrefix("@startuml") {
        starts += 1
        continue
      }
      if trim == "@enduml" {
        ends += 1
        continue
      }
      let range = NSRange(location: offset, length: (line as NSString).length)
      if let closing = opaque {
        elements.append(
          Element(kind: "unsupported", text: line, range: range, depth: stack.count, fields: [:]))
        if trim == closing { opaque = nil }
        continue
      }
      if (trim.hasPrefix("note ") && !trim.contains(":")) || trim == "note" || trim == "legend"
        || trim == "title" || trim == "<style>"
        || (trim.hasPrefix("skinparam ") && trim.hasSuffix("{"))
      {
        opaque =
          trim.hasPrefix("note")
          ? "end note"
          : trim == "<style>" ? "</style>" : trim.hasPrefix("skinparam") ? "}" : "end " + trim
        elements.append(
          Element(kind: "unsupported", text: line, range: range, depth: stack.count, fields: [:]))
        continue
      }
      if trim == "}" {
        if let start = stack.popLast() {
          extents[start] = NSRange(
            location: start, length: min(ns.length, offset + (raw as NSString).length + 1) - start)
        } else {
          diagnostics.append("Лишнее закрытие контейнера")
        }
        continue
      }
      var fields: [String: NSRange] = [:]
      var kind = "unsupported"
      var opens = false
      for (regex, keys, nodeKind) in [
        (declaration, ["type", "name", "alias", "stereotype", "color", "open"], "component"),
        (bracket, ["name", "alias", "stereotype", "color"], "component"),
        (interface, ["name", "alias"], "interface"),
        (relation, ["from", "line", "to", "label"], "componentRelation"),
      ] {
        guard
          let match = regex.firstMatch(
            in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { continue }
        for (index, key) in keys.enumerated()
        where match.range(at: index + 1).location != NSNotFound {
          let local = match.range(at: index + 1)
          fields[key] = NSRange(location: offset + local.location, length: local.length)
        }
        if nodeKind == "componentRelation" {
          for key in ["from", "to"] {
            if let range = fields[key] {
              let value = ns.substring(with: range)
              if (value.hasPrefix("[") && value.hasSuffix("]"))
                || (value.hasPrefix("\"") && value.hasSuffix("\""))
              {
                fields[key] = NSRange(location: range.location + 1, length: range.length - 2)
              }
            }
          }
        }
        opens = fields.removeValue(forKey: "open") != nil
        kind = opens ? "container" : nodeKind
        if let type = fields["type"], ns.substring(with: type) == "interface" { kind = "interface" }
        if let alias = fields["alias"], let name = fields["name"],
          ns.substring(with: alias).hasPrefix("\""), !ns.substring(with: name).hasPrefix("\"")
        {
          fields["alias"] = name
          fields["name"] = alias
        }
        break
      }
      if kind == "unsupported"
        && trim.range(of: "^(" + types + ")\\s.*\\{", options: .regularExpression) != nil
      {
        diagnostics.append("Неподдерживаемый заголовок контейнера: правьте код")
      }
      elements.append(
        Element(kind: kind, text: line, range: range, depth: stack.count, fields: fields))
      if opens { stack.append(offset) }
    }
    if starts != 1 || ends != 1 {
      diagnostics.append("Нужна ровно одна диаграмма @startuml / @enduml")
    }
    if !stack.isEmpty || opaque != nil || inComment {
      diagnostics.append("Незакрытая конструкция Component")
    }
    elements = elements.map {
      Element(
        kind: $0.kind, text: $0.text, range: $0.range, depth: $0.depth, fields: $0.fields,
        id: $0.id, fullRange: extents[$0.range.location])
    }
    return ParsedDocument(
      source: source, kind: .component, elements: elements, diagnostics: diagnostics)
  }
}
