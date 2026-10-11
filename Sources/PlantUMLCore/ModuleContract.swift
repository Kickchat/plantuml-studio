import Foundation

public protocol DiagramModuleContract: Sendable {
  var kind: DiagramKind { get }
  var declarationKinds: Set<String> { get }
  func recognizes(_ source: String) -> Bool
  func parse(_ source: String) -> ParsedDocument
  func identityFields(of element: Element) -> [String]
  func propertyFields(of element: Element) -> [String]
  func validate(_ document: ParsedDocument) -> [String]
  func rename(_ element: Element, to alias: String, in document: ParsedDocument) throws -> String
  func compare(_ left: String, _ right: String) -> DiagramDiffResult
}
extension DiagramModuleContract {
  public func recognizes(_ source: String) -> Bool { SourceDocument.parse(source).kind == kind }
  public func parse(_ source: String) -> ParsedDocument { SourceDocument.parse(source, mode: kind) }
  public func propertyFields(of element: Element) -> [String] { element.fields.keys.sorted() }
  public func validate(_ document: ParsedDocument) -> [String] {
    document.diagnostics + (document.kind == kind ? [] : ["Другой тип диаграммы"])
  }
  public func rename(_ element: Element, to alias: String, in document: ParsedDocument) throws
    -> String
  { try ConstructorOperations.renameAlias(element, to: alias, in: document) }
  public func compare(_ left: String, _ right: String) -> DiagramDiffResult {
    DiagramDiff.compare(left, right, mode: kind, contract: self)
  }
}
