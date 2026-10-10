import Foundation

public enum DiagramKind: String, Sendable { case sequence, er, unknown }
public struct Element: Identifiable, Sendable {
  public var id: Int
  public init(
    kind: String, text: String, range: NSRange, depth: Int, fields: [String: NSRange],
    id: Int? = nil, fullRange: NSRange? = nil
  ) {
    self.fullRange = fullRange
    self.kind = kind
    self.text = text
    self.range = range
    self.depth = depth
    self.fields = fields
    self.id = id ?? range.location
  }
  public let fullRange: NSRange?
  public let kind: String
  public let text: String
  public let range: NSRange
  public let depth: Int
  public let fields: [String: NSRange]
}
public struct ParsedDocument: Sendable {
  public let source: String
  public let kind: DiagramKind
  public let elements: [Element]
  public let diagnostics: [String]
  public var canEdit: Bool { diagnostics.isEmpty && kind != .unknown }
}
public enum SourceError: Error { case staleRange, invalidEdit, unsafeReference }
public struct TextEdit: Sendable {
  public let range: NSRange
  public let replacement: String
  public init(range: NSRange, replacement: String) {
    self.range = range
    self.replacement = replacement
  }
}
public enum SourceDocument {
  public static func apply(_ edits: [TextEdit], to source: String) throws -> String {
    let ns = source as NSString
    let sorted = edits.sorted { $0.range.location < $1.range.location }
    var end = 0
    for edit in sorted {
      guard edit.range.location >= end, edit.range.location >= 0, edit.range.location <= ns.length,
        edit.range.length >= 0, edit.range.length <= ns.length - edit.range.location
      else { throw SourceError.staleRange }
      end = NSMaxRange(edit.range)
    }
    let result = NSMutableString(string: source)
    for edit in sorted.reversed() {
      result.replaceCharacters(in: edit.range, with: edit.replacement)
    }
    return result as String
  }
  public static func parse(_ source: String, mode: DiagramKind? = nil) -> ParsedDocument {
    var elements: [Element] = []
    var diagnostics: [String] = []
    let starts = source.components(separatedBy: "\n").filter {
      $0.trimmingCharacters(in: .whitespaces).hasPrefix("@startuml")
    }.count
    let ends = source.components(separatedBy: "\n").filter {
      $0.trimmingCharacters(in: .whitespacesAndNewlines) == "@enduml"
    }.count
    if starts != 1 || ends != 1 {
      diagnostics.append("Конструктор поддерживает ровно одну диаграмму в документе")
    }
    var offset = 0
    var stack: [String] = []
    var inComment = false
    var opaqueEnd: String?
    var hasER = false
    var hasSequence = false
    var openOffsets: [Int] = []
    var extents: [Int: NSRange] = [:]
    let patterns: [(String, String, [String])] = [
      (
        "participant",
        #"^\s*(actor|participant|boundary|control|entity|database|collections|queue)\s+("[^"]+"|[\p{L}\w]+)(?:\s+as\s+("[^"]+"|[\p{L}\w]+))?(?:\s+(<<[^>]+>>))?(?:\s+(#[\w]+))?(?:\s+order\s+(\d+))?\s*$"#,
        ["type", "name", "alias", "stereotype", "color", "order"]
      ),
      (
        "entity",
        #"^\s*entity\s+("[^"]+"|[\p{L}\w]+)(?:\s+as\s+("[^"]+"|[\p{L}\w]+))?(?:\s+(<<[^>]+>>))?(?:\s+(#[\w]+))?\s*\{\s*$"#,
        ["name", "alias", "stereotype", "color"]
      ),
      (
        "relation",
        #"^\s*([\p{L}\w]+)\s*(\|\||\|o|\}o|\}\|)(--|\.\.)(\|\||o\||o\{|\|\{)\s*([\p{L}\w]+)(?:\s*:\s*(.*))?$"#,
        ["from", "left", "line", "right", "to", "label"]
      ),
      (
        "message",
        #"^\s*("[^"]+"|[\p{L}\w]+)\s*(-->>|->>|-->|->|<<--|<<-|<--|<-|<->|->x|o->|->o)\s*("[^"]+"|[\p{L}\w]+)(?:\s*:\s*(.*))?$"#,
        ["from", "arrow", "to", "label"]
      ),
      ("block", #"^\s*(alt|opt|loop|par|break|critical|group)(?:\s+(.*))?$"#, ["type", "label"]),
      ("branch", #"^\s*else(?:\s+(.*))?$"#, ["label"]),
      (
        "activation", #"^\s*(activate|deactivate|destroy)\s+([\p{L}\w]+)(?:\s+#[\w]+)?\s*$"#,
        ["type", "target"]
      ),
      (
        "note", #"^\s*note\s+(left|right|over)(?:\s+of)?\s*([^:]*):\s*(.*)$"#,
        ["position", "target", "label"]
      ),
      ("title", #"^\s*title\s+(.+)$"#, ["label"]),
      ("autonumber", #"^\s*autonumber(?:\s+(.*))?$"#, ["options"]),
      ("divider", #"^\s*==\s*(.*?)\s*==\s*$"#, ["label"]),
      ("delay", #"^\s*\.\.\.(.*?)\.\.\.\s*$"#, ["label"]),
    ]
    let compiledPatterns = patterns.map { ($0.0, try! NSRegularExpression(pattern: $0.1), $0.2) }
    let attributeRegex = try! NSRegularExpression(
      pattern: #"^\s*(\*)?\s*([^:<>]+?)(?:\s*:\s*([^<]+?))?(?:\s*(<<[^>]+>>))?\s*$"#)
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
      if trim.hasPrefix("'") || trim.isEmpty { continue }
      if let closing = opaqueEnd {
        elements.append(
          Element(
            kind: "unsupported", text: line,
            range: NSRange(location: offset, length: (line as NSString).length), depth: stack.count,
            fields: [:]))
        if trim == closing { opaqueEnd = nil }
        continue
      }
      if trim == "note" || (trim.hasPrefix("note ") && !trim.contains(":")) {
        opaqueEnd = "end note"
        elements.append(
          Element(
            kind: "unsupported", text: line,
            range: NSRange(location: offset, length: (line as NSString).length), depth: stack.count,
            fields: [:]))
        continue
      }
      if trim == "title" {
        opaqueEnd = "end title"
        elements.append(
          Element(
            kind: "unsupported", text: line,
            range: NSRange(location: offset, length: (line as NSString).length), depth: stack.count,
            fields: [:]))
        continue
      }
      if trim == "<style>" {
        opaqueEnd = "</style>"
        elements.append(
          Element(
            kind: "unsupported", text: line,
            range: NSRange(location: offset, length: (line as NSString).length), depth: stack.count,
            fields: [:]))
        continue
      }
      let opaquePairs = [
        ("ref ", "end ref"), ("legend", "endlegend"), ("header", "endheader"),
        ("footer", "endfooter"), ("!procedure", "!endprocedure"), ("!function", "!endfunction"),
      ]
      if let pair = opaquePairs.first(where: { trim.hasPrefix($0.0) }), !trim.contains(":") {
        opaqueEnd = pair.1
        elements.append(
          Element(
            kind: "unsupported", text: line,
            range: NSRange(location: offset, length: (line as NSString).length), depth: stack.count,
            fields: [:]))
        continue
      }
      if trim.hasPrefix("skinparam") && trim.hasSuffix("{") {
        opaqueEnd = "}"
        elements.append(
          Element(
            kind: "unsupported", text: line,
            range: NSRange(location: offset, length: (line as NSString).length), depth: stack.count,
            fields: [:]))
        continue
      }
      if trim == "end" || trim == "}" {
        if stack.isEmpty {
          diagnostics.append("Строка \(elements.count + 1): лишний \(trim)")
        } else if (trim == "}") != (stack.last == "entity") {
          diagnostics.append("Несогласованное закрытие блока")
        } else {
          stack.removeLast()
          let start = openOffsets.removeLast()
          let end = min((source as NSString).length, offset + (raw as NSString).length + 1)
          extents[start] = NSRange(location: start, length: end - start)
        }
        continue
      }
      if stack.last == "entity" {
        let regex = attributeRegex
        var fields: [String: NSRange] = [:]
        let separator = trim.range(of: #"^(--|\.\.|==|__)"#, options: .regularExpression) != nil
        if let m = regex.firstMatch(
          in: line, range: NSRange(location: 0, length: (line as NSString).length)), !separator
        {
          for (i, key) in ["mandatory", "name", "datatype", "stereotype"].enumerated()
          where m.range(at: i + 1).location != NSNotFound {
            let r = m.range(at: i + 1)
            fields[key] = NSRange(location: offset + r.location, length: r.length)
          }
        }
        elements.append(
          Element(
            kind: separator ? "separator" : "attribute", text: line,
            range: NSRange(location: offset, length: (line as NSString).length), depth: stack.count,
            fields: fields))
        continue
      }
      var matched = false
      for (kind, regex, keys) in compiledPatterns {
        guard
          let match = regex.firstMatch(
            in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { continue }
        var fields: [String: NSRange] = [:]
        for (i, key) in keys.enumerated() where match.range(at: i + 1).location != NSNotFound {
          let r = match.range(at: i + 1)
          fields[key] = NSRange(location: offset + r.location, length: r.length)
        }
        if ["participant", "entity"].contains(kind), let alias = fields["alias"],
          let name = fields["name"], (source as NSString).substring(with: alias).hasPrefix("\""),
          !(source as NSString).substring(with: name).hasPrefix("\"")
        {
          fields["name"] = alias
          fields["alias"] = name
        }
        if kind == "branch", !["alt", "par"].contains(stack.last ?? "") {
          diagnostics.append("else допускается здесь только внутри alt/par")
        }
        elements.append(
          Element(
            kind: kind, text: line,
            range: NSRange(location: offset, length: (line as NSString).length), depth: stack.count,
            fields: fields))
        if kind == "entity" {
          hasER = true
          stack.append("entity")
          openOffsets.append(offset)
        }
        if kind == "block" {
          hasSequence = true
          stack.append((line as NSString).substring(with: match.range(at: 1)))
          openOffsets.append(offset)
        }
        if kind == "message" || (kind == "participant" && !trim.hasPrefix("entity ")) {
          hasSequence = true
        }
        if kind == "relation" { hasER = true }
        matched = true
        break
      }
      if !matched && !trim.hasPrefix("@") {
        elements.append(
          Element(
            kind: "unsupported", text: line,
            range: NSRange(location: offset, length: (line as NSString).length), depth: stack.count,
            fields: [:]))
      }
    }
    let multiPatterns: [(String, String, [String])] = [
      (
        "note",
        #"(?m)^[ \t]*note[ \t]+(left|right|over)(?:[ \t]+of)?(?:[ \t]+([^\r\n]*))?\r?\n([\s\S]*?)^[ \t]*end note[ \t]*\r?$"#,
        ["position", "target", "label"]
      ),
      ("title", #"(?m)^[ \t]*title[ \t]*\r?\n([\s\S]*?)^[ \t]*end title[ \t]*\r?$"#, ["label"]),
    ]
    for (kind, pattern, keys) in multiPatterns {
      let regex = try! NSRegularExpression(pattern: pattern)
      for match in regex.matches(
        in: source, range: NSRange(location: 0, length: (source as NSString).length))
      {
        guard
          let start = elements.first(where: {
            $0.range.location == match.range.location && $0.kind == "unsupported"
          })
        else { continue }
        var fields: [String: NSRange] = [:]
        for (index, key) in keys.enumerated()
        where match.range(at: index + 1).location != NSNotFound {
          fields[key] = match.range(at: index + 1)
        }
        elements.removeAll {
          $0.range.location >= match.range.location && $0.range.location < NSMaxRange(match.range)
        }
        elements.append(
          Element(
            kind: kind, text: (source as NSString).substring(with: match.range), range: match.range,
            depth: start.depth, fields: fields))
      }
    }
    elements = elements.map { node in
      Element(
        kind: node.kind, text: node.text, range: node.range, depth: node.depth, fields: node.fields,
        id: node.id, fullRange: extents[node.range.location])
    }
    elements.sort { $0.range.location < $1.range.location }
    if !stack.isEmpty { diagnostics.append("Незакрытые блоки: \(stack.joined(separator: ", "))") }
    if inComment || opaqueEnd != nil { diagnostics.append("Незакрытая многострочная конструкция") }
    if !source.contains("@startuml") || !source.contains("@enduml") {
      diagnostics.append("Нужны @startuml и @enduml")
    }
    return ParsedDocument(
      source: source,
      kind: mode ?? (hasER && !hasSequence ? .er : hasSequence && !hasER ? .sequence : .unknown),
      elements: elements, diagnostics: diagnostics)
  }
  public static func changeField(
    _ key: String, of element: Element, to value: String, in document: ParsedDocument
  ) throws -> String {
    guard document.canEdit, let range = element.fields[key], !value.contains("\n"),
      !value.contains("\r")
    else { throw SourceError.invalidEdit }
    if key == "alias" { throw SourceError.unsafeReference }
    return try apply([TextEdit(range: range, replacement: value)], to: document.source)
  }
  public static func insert(_ text: String, in source: String) throws -> String {
    let range = (source as NSString).range(of: "@enduml", options: .backwards)
    guard range.location != NSNotFound else { throw SourceError.invalidEdit }
    let newline = source.contains("\r\n") ? "\r\n" : "\n"
    return try apply(
      [
        TextEdit(
          range: NSRange(location: (source as NSString).lineRange(for: range).location, length: 0),
          replacement: text.replacingOccurrences(of: "\n", with: newline) + newline)
      ], to: source)
  }
}

extension SourceDocument {
  /// Reconcile identities after a source edit using the unchanged prefix/suffix and
  /// token kind. Offsets remain UTF-16 ranges; identity never substitutes for a range.
  public static func reconcile(_ new: ParsedDocument, with old: ParsedDocument) -> ParsedDocument {
    let before = Array(old.source.utf16)
    let after = Array(new.source.utf16)
    var prefix = 0
    while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < min(before.count, after.count) - prefix,
      before[before.count - suffix - 1] == after[after.count - suffix - 1]
    { suffix += 1 }
    let delta = after.count - before.count
    var used = Set<Int>()
    var next = (old.elements.map(\.id).max() ?? 0) + 1
    let nodes = new.elements.map { node -> Element in
      let previous = old.elements.first { candidate in
        guard !used.contains(candidate.id), candidate.kind == node.kind else { return false }
        if NSMaxRange(candidate.range) <= prefix {
          return candidate.range.location == node.range.location
        }
        if candidate.range.location >= before.count - suffix {
          return candidate.range.location + delta == node.range.location
        }
        return candidate.range.location == node.range.location && candidate.depth == node.depth
      }
      let identity = previous?.id ?? next
      if previous == nil { next += 1 }
      used.insert(identity)
      return Element(
        kind: node.kind, text: node.text, range: node.range, depth: node.depth, fields: node.fields,
        id: identity, fullRange: node.fullRange)
    }
    return ParsedDocument(
      source: new.source, kind: new.kind, elements: nodes, diagnostics: new.diagnostics)
  }
}

extension SourceError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .staleRange: "Документ изменился. Выберите элемент заново."
    case .invalidEdit: "Изменение недопустимо для выбранного элемента или пересекает границу блока."
    case .unsafeReference:
      "Есть ссылки, которые нельзя безопасно изменить. Отредактируйте их в коде. Алиас меняйте отдельно от других свойств."
    }
  }
}
