import Foundation
import PlantUMLCore
import Rendering

struct Measurement: Codable {
  let lines: Int
  let parseMilliseconds: Double
  let renderMilliseconds: Double
  let operationMilliseconds: Double
  let cachedRenderMilliseconds: Double
}
func measure<T>(_ operation: () throws -> T) rethrows -> (T, Double) {
  let start = ContinuousClock.now
  let value = try operation()
  let elapsed = start.duration(to: .now).components
  return (value, Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
}
var results: [Measurement] = []
for count in [100, 300, 500, 1000] {
  let lines =
    ["@startuml", "participant A", "participant B"]
    + (0..<(count - 4)).map { "A -> B : message \($0)" } + ["@enduml"]
  let source = lines.joined(separator: "\n")
  let (parsed, parseTime) = measure { SourceDocument.parse(source) }
  let (_, renderTime) = try measure { try Renderer.render(source) }
  let (_, operationTime) = try measure {
    try QuickOperations.reply(to: parsed.elements.first { $0.kind == "message" }!, in: parsed)
  }
  let (_, cachedTime) = try measure { try Renderer.render(source) }
  results.append(
    Measurement(
      lines: count, parseMilliseconds: parseTime, renderMilliseconds: renderTime,
      operationMilliseconds: operationTime, cachedRenderMilliseconds: cachedTime))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(data: try encoder.encode(results), encoding: .utf8)!)
