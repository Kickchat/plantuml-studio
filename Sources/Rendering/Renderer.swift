import CryptoKit
import Darwin
import Foundation

public struct RenderOutput: Sendable {
  public let data: Data
  public let diagnostics: String
}
public final class RenderCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  public init() {}
  public func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }
  public var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }
}

public enum Renderer {
  private static let cache = RenderCache()
  private static let slots = DispatchSemaphore(value: 2)
  public static func runtime() -> URL {
    let bundled = Bundle.main.resourceURL?.appendingPathComponent("Runtime")
    if let bundled,
      FileManager.default.fileExists(
        atPath: bundled.appendingPathComponent("plantuml-1.2025.0.jar").path)
    {
      return bundled
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
      "Runtime")
  }
  public static func render(
    _ source: String, format: String = "svg", cancellation: RenderCancellation? = nil
  ) throws -> RenderOutput {
    if cancellation?.isCancelled == true { throw CancellationError() }
    guard ["svg", "png"].contains(format) else {
      throw NSError(
        domain: "Renderer", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Неподдерживаемый формат экспорта"])
    }
    let key = SHA256.hash(data: Data((format + "\n" + source).utf8)).map {
      String(format: "%02x", $0)
    }.joined()
    if let cached = cache.get(key) { return cached }
    let queueDeadline = Date().addingTimeInterval(15)
    while slots.wait(timeout: .now() + 0.05) != .success {
      if cancellation?.isCancelled == true { throw CancellationError() }
      guard Date() < queueDeadline else {
        throw NSError(
          domain: "Renderer", code: 4,
          userInfo: [NSLocalizedDescriptionKey: "Очередь рендеринга занята"])
      }
    }
    defer { slots.signal() }
    if cancellation?.isCancelled == true { throw CancellationError() }
    let root = runtime()
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: temp) }
    // Files avoid pipe backpressure for large SVGs. Process runs off the main actor.
    let input = temp.appendingPathComponent("input.puml")
    let out = temp.appendingPathComponent("output")
    let err = temp.appendingPathComponent("errors")
    try Data(source.utf8).write(to: input)
    fm.createFile(atPath: out.path, contents: nil)
    fm.createFile(atPath: err.path, contents: nil)
    let process = Process()
    process.executableURL = root.appendingPathComponent("jdk-21.0.6+7-jre/Contents/Home/bin/java")
    process.arguments = [
      "-Xmx256m", "-Djava.awt.headless=true", "-DPLANTUML_SECURITY_PROFILE=SECURE", "-jar",
      root.appendingPathComponent("plantuml-1.2025.0.jar").path, "-Playout=smetana", "-pipe",
      "-t\(format)", "-charset", "UTF-8",
    ]
    process.standardInput = try FileHandle(forReadingFrom: input)
    let output = try FileHandle(forWritingTo: out)
    let errors = try FileHandle(forWritingTo: err)
    defer {
      try? output.close()
      try? errors.close()
      try? (process.standardInput as? FileHandle)?.close()
    }
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let deadline = Date().addingTimeInterval(15)
    while process.isRunning && Date() < deadline {
      if cancellation?.isCancelled == true {
        kill(process.processIdentifier, SIGKILL)
        throw CancellationError()
      }
      Thread.sleep(forTimeInterval: 0.025)
    }
    if process.isRunning {
      kill(process.processIdentifier, SIGKILL)
      throw NSError(
        domain: "Renderer", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Рендеринг превысил 15 секунд"])
    }
    let diagnostics = (try? String(contentsOf: err, encoding: .utf8)) ?? ""
    let data = try Data(contentsOf: out)
    guard process.terminationStatus == 0, !data.isEmpty, !diagnostics.contains("ERROR") else {
      throw NSError(
        domain: "Renderer", code: 2,
        userInfo: [NSLocalizedDescriptionKey: diagnostics.isEmpty ? "Ошибка PlantUML" : diagnostics]
      )
    }
    let result = RenderOutput(data: data, diagnostics: diagnostics)
    cache.set(key, result)
    return result
  }
}

private final class RenderCache: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String: RenderOutput] = [:]
  private var order: [String] = []
  func get(_ key: String) -> RenderOutput? {
    lock.lock()
    defer { lock.unlock() }
    return entries[key]
  }
  func set(_ key: String, _ value: RenderOutput) {
    lock.lock()
    defer { lock.unlock() }
    guard value.data.count <= 16 * 1024 * 1024 else { return }
    if entries[key] == nil { order.append(key) }
    entries[key] = value
    while order.count > 12 || entries.values.reduce(0, { $0 + $1.data.count }) > 32 * 1024 * 1024 {
      entries.removeValue(forKey: order.removeFirst())
    }
  }
}
