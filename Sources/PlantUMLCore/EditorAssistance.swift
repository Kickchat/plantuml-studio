import Foundation

public enum EditorAssistance {
  public static func completions(prefix: String, in document: ParsedDocument) -> [String] {
    let keywords =
      document.kind == .component
      ? ["component", "interface", "package", "node", "database", "cloud", "frame", "folder", "as"]
      : document.kind == .er
        ? ["entity", "as", "integer", "text", "boolean", "date", "<<PK>>", "<<FK>>"]
        : [
          "participant", "actor", "boundary", "control", "entity", "database", "collections",
          "queue",
          "alt", "else", "opt", "loop", "par", "break", "critical", "group", "end", "activate",
          "deactivate", "destroy", "note", "title", "autonumber",
        ]
    let ns = document.source as NSString
    let names = document.elements.filter {
      ["participant", "entity", "component", "interface", "container"].contains($0.kind)
    }.compactMap { ($0.fields["alias"] ?? $0.fields["name"]).map { ns.substring(with: $0) } }
    return Array(Set(keywords + names)).filter { $0.hasPrefix(prefix) }.sorted()
  }
  public static func newline(after line: String, newline: String = "\n") -> String {
    let indent = String(line.prefix { $0 == " " || $0 == "\t" })
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let type = trimmed.components(separatedBy: .whitespaces).first ?? ""
    if ["alt", "opt", "loop", "par", "break", "critical", "group"].contains(type) {
      return newline + indent + "  " + newline + indent + "end"
    }
    if ["entity", "package", "node", "cloud", "frame", "folder", "component", "database"].contains(
      type) && trimmed.hasSuffix("{")
    {
      return newline + indent + "  " + newline + indent + "}"
    }
    return newline + indent
  }
  public static func foldableBody(of element: Element, in document: ParsedDocument) -> NSRange? {
    guard ["block", "entity", "container"].contains(element.kind), let extent = element.fullRange
    else {
      return nil
    }
    let ns = document.source as NSString
    let first = ns.lineRange(for: element.range)
    var last = NSMaxRange(extent) - 1
    while last > first.location
      && ["\n", "\r"].contains(ns.substring(with: NSRange(location: last, length: 1)))
    { last -= 1 }
    let close = ns.lineRange(for: NSRange(location: last, length: 0))
    let start = NSMaxRange(first)
    return close.location > start ? NSRange(location: start, length: close.location - start) : nil
  }
}
