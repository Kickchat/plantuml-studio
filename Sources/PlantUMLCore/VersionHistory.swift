import CryptoKit
import Foundation

public struct SavedVersion: Codable, Identifiable, Sendable {
  public let id: UUID
  public let date: Date
  public let source: String
}
public struct HistoryLimits: Sendable {
  public var count: Int
  public var bytes: Int
  public init(count: Int = 30, bytes: Int = 20 * 1024 * 1024) {
    self.count = max(1, count)
    self.bytes = max(1024, bytes)
  }
}
/// Atomic local history, independently owned by each saved document path.
public struct VersionHistory: Sendable {
  public let directory: URL
  public init(directory: URL) { self.directory = directory }
  private func file(_ key: String) -> URL {
    let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(name + ".json")
  }
  public func versions(for key: String) throws -> [SavedVersion] {
    let target = file(key)
    guard FileManager.default.fileExists(atPath: target.path) else { return [] }
    return try JSONDecoder().decode([SavedVersion].self, from: Data(contentsOf: target))
  }
  @discardableResult public func record(
    _ source: String, for key: String, limits: HistoryLimits = HistoryLimits()
  ) throws -> [SavedVersion] {
    var items = try versions(for: key)
    if items.last?.source != source {
      items.append(SavedVersion(id: UUID(), date: Date(), source: source))
    }
    let encoder = JSONEncoder()
    while items.count > limits.count { items.removeFirst() }
    while !items.isEmpty {
      if try encoder.encode(items).count <= limits.bytes { break }
      items.removeFirst()
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try encoder.encode(items).write(to: file(key), options: .atomic)
    return items
  }
}
