import Foundation

public enum DiffStatus: String, Sendable {
  case unchanged, added, removed, modified, moved, ambiguous, textFallback
}
public struct TextDiffRow: Identifiable, Sendable {
  public let id: Int
  public let leftLine: Int?
  public let rightLine: Int?
  public let left: String?
  public let right: String?
  public let status: DiffStatus
}
public struct StructuralChange: Identifiable, Sendable {
  public let id: Int
  public let before: Element?
  public let after: Element?
  public let status: DiffStatus
  public let reason: String
}
public struct DiagramDiffResult: Sendable {
  public let rows: [TextDiffRow]
  public let changes: [StructuralChange]
  public let textOnly: Bool
}
/// Modules retain their own field vocabulary. Matching identities never collapse
/// distinct repeated messages/relations to an arbitrary source range.
public enum DiagramDiff {
  public static func compare(
    _ left: String, _ right: String, mode: DiagramKind? = nil,
    contract: (any DiagramModuleContract)? = nil
  )
    -> DiagramDiffResult
  {
    let a = SourceDocument.parse(left, mode: mode)
    let b = SourceDocument.parse(right, mode: mode)
    let rows = text(left, right)
    guard a.kind == b.kind, a.canEdit, b.canEdit else {
      return DiagramDiffResult(rows: rows, changes: [], textOnly: true)
    }
    func field(_ node: Element, _ key: String, _ doc: ParsedDocument) -> String {
      node.fields[key].map { (doc.source as NSString).substring(with: $0) } ?? ""
    }
    func identity(_ node: Element, _ doc: ParsedDocument) -> String {
      let parents = doc.elements.filter {
        $0.id != node.id && $0.fullRange.map { NSLocationInRange(node.range.location, $0) } == true
      }.sorted { $0.depth < $1.depth }
      let context = parents.map { parent in
        parent.kind + ":" + field(parent, parent.fields["alias"] == nil ? "name" : "alias", doc)
          + ":" + field(parent, "type", doc) + ":" + field(parent, "label", doc)
      }
      let keys: [String]
      switch node.kind {
      case "participant", "entity", "component", "interface", "container":
        keys = [node.fields["alias"] == nil ? "name" : "alias"]
      case "message": keys = ["from", "to"]
      case "relation", "componentRelation": keys = ["from", "to"]
      case "attribute": keys = ["name"]
      case "block": keys = ["type"]
      default: keys = node.fields.keys.sorted()
      }
      return
        ([
          (doc.kind == .component && ["component", "interface", "container"].contains(node.kind))
            ? "componentNode" : node.kind
        ] + context
        + (contract?.identityFields(of: node) ?? keys).map { field(node, $0, doc) }).joined(
          separator: "\u{1f}")
    }
    func semantic(_ node: Element, _ doc: ParsedDocument) -> String {
      node.fields.keys.sorted().map { $0 + "=" + field(node, $0, doc) }.joined(separator: "\u{1f}")
    }
    let leftNodes = a.elements.filter { $0.kind != "unsupported" }
    let rightNodes = b.elements.filter { $0.kind != "unsupported" }
    let leftGroups = Dictionary(grouping: leftNodes, by: { identity($0, a) })
    let rightGroups = Dictionary(grouping: rightNodes, by: { identity($0, b) })
    let matchedKeys = Set(
      leftGroups.keys.filter { leftGroups[$0]?.count == 1 && rightGroups[$0]?.count == 1 })
    let oldOrder = leftNodes.map { identity($0, a) }.filter { matchedKeys.contains($0) }
    let newOrder = rightNodes.map { identity($0, b) }.filter { matchedKeys.contains($0) }
    let oldRanks = Dictionary(
      uniqueKeysWithValues: oldOrder.enumerated().map { ($0.element, $0.offset) })
    let newRanks = Dictionary(
      uniqueKeysWithValues: newOrder.enumerated().map { ($0.element, $0.offset) })
    var changes: [StructuralChange] = []
    func append(_ before: Element?, _ after: Element?, _ status: DiffStatus, _ reason: String) {
      changes.append(
        StructuralChange(
          id: changes.count, before: before, after: after, status: status, reason: reason))
    }
    for key in Set(leftGroups.keys).union(rightGroups.keys).sorted() {
      let old = leftGroups[key] ?? []
      let new = rightGroups[key] ?? []
      if old.count > 1 || new.count > 1 {
        for node in old {
          append(
            node, nil, .ambiguous, "Повторяющаяся структура: точное соответствие не установлено")
        }
        for node in new {
          append(nil, node, .ambiguous, "Повторяющаяся структура: используйте текстовый diff")
        }
      } else if let first = old.first, let second = new.first {
        if semantic(first, a) != semantic(second, b) {
          append(first, second, .modified, "Изменены поля элемента в однозначном контексте")
        } else if oldRanks[key] != newRanks[key] {
          append(first, second, .moved, "Изменён порядок среди сопоставленных элементов")
        }
      } else if let first = old.first {
        append(first, nil, .removed, "Элемент отсутствует в новой версии")
      } else if let second = new.first {
        append(nil, second, .added, "Новый элемент")
      }
    }
    if a.elements.contains(where: { $0.kind == "unsupported" })
      || b.elements.contains(where: { $0.kind == "unsupported" })
    {
      append(nil, nil, .textFallback, "Неизвестные конструкции сравниваются только как текст")
    }
    return DiagramDiffResult(rows: rows, changes: changes, textOnly: false)
  }
  public static func text(_ left: String, _ right: String) -> [TextDiffRow] {
    let a = left.components(separatedBy: "\n")
    let b = right.components(separatedBy: "\n")
    var pairs: [(Int?, Int?)] = []
    // Bound quadratic memory. Large inputs retain an exact text fallback.
    if a.count <= 2000 && b.count <= 2000 {
      let width = b.count + 1
      var table = [Int32](repeating: 0, count: (a.count + 1) * width)
      for i in a.indices.reversed() {
        for j in b.indices.reversed() {
          table[i * width + j] =
            a[i] == b[j]
            ? table[(i + 1) * width + j + 1] + 1
            : max(table[(i + 1) * width + j], table[i * width + j + 1])
        }
      }
      var i = 0
      var j = 0
      while i < a.count || j < b.count {
        if i < a.count && j < b.count && a[i] == b[j] {
          pairs.append((i, j))
          i += 1
          j += 1
        } else if i < a.count
          && (j == b.count || table[(i + 1) * width + j] >= table[i * width + j + 1])
        {
          pairs.append((i, nil))
          i += 1
        } else {
          pairs.append((nil, j))
          j += 1
        }
      }
    } else {
      var prefix = 0
      while prefix < min(a.count, b.count) && a[prefix] == b[prefix] {
        pairs.append((prefix, prefix))
        prefix += 1
      }
      var suffix = 0
      while suffix < min(a.count, b.count) - prefix
        && a[a.count - 1 - suffix] == b[b.count - 1 - suffix]
      { suffix += 1 }
      pairs += (prefix..<(a.count - suffix)).map { ($0, nil) }
      pairs += (prefix..<(b.count - suffix)).map { (nil, $0) }
      pairs += (0..<suffix).map { (a.count - suffix + $0, b.count - suffix + $0) }
    }
    var rows: [TextDiffRow] = []
    var index = 0
    func row(_ i: Int?, _ j: Int?, _ status: DiffStatus) {
      rows.append(
        TextDiffRow(
          id: rows.count, leftLine: i.map { $0 + 1 }, rightLine: j.map { $0 + 1 },
          left: i.map { a[$0] }, right: j.map { b[$0] }, status: status))
    }
    while index < pairs.count {
      if let i = pairs[index].0, let j = pairs[index].1 {
        row(i, j, .unchanged)
        index += 1
        continue
      }
      var removed: [Int] = []
      var added: [Int] = []
      while index < pairs.count && (pairs[index].0 == nil || pairs[index].1 == nil) {
        if let i = pairs[index].0 { removed.append(i) }
        if let j = pairs[index].1 { added.append(j) }
        index += 1
      }
      for k in 0..<max(removed.count, added.count) {
        let i = removed.indices.contains(k) ? removed[k] : nil
        let j = added.indices.contains(k) ? added[k] : nil
        row(i, j, i == nil ? .added : j == nil ? .removed : .modified)
      }
    }
    return rows
  }
}
