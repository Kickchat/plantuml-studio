import AppKit
import ComponentModule
import Foundation
import PlantUMLCore
import Rendering
import StudioDesign
import SwiftUI

/// Exercises the real application process without accessibility permissions or
/// changing the user's saved session. Enabled only by scripts/smoke.sh.
@MainActor enum SmokeTest {
  static func run(workspace: Workspace, directory: URL) async {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for name in ["failure.txt", "result.json"] {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
      }
      workspace.new(.sequence)
      guard let document = workspace.current else { throw failure("No document") }
      try await wait { document.canEdit }
      let initial = document.source
      guard DocumentNavigation.outline(document.parsed).contains(where: { !$0.children.isEmpty }),
        StudioCommands.available(document).contains(where: { $0.id == "participant" })
      else { throw failure("Outline or contextual commands missing") }
      document.searchVisible = true
      document.paletteVisible = true
      try await Task.sleep(for: .milliseconds(200))
      document.paletteVisible = false
      document.searchVisible = false
      guard let message = document.parsed.elements.first(where: { $0.kind == "message" }) else {
        throw failure("No message")
      }
      document.undoManager.removeAllActions()
      document.edit {
        try SourceDocument.changeField(
          "label", of: message, to: "Smoke test edited", in: document.parsed)
      }
      try await wait { document.source != initial && document.canEdit }
      let edited = document.source
      document.undoManager.undo()
      try await wait { document.source == initial && document.canEdit }
      document.undoManager.redo()
      try await wait { document.source == edited && document.canEdit }
      document.url = directory.appendingPathComponent("roundtrip.puml")
      document.save()
      guard !document.dirty, try String(contentsOf: document.url!, encoding: .utf8) == edited else {
        throw failure("Save round-trip failed")
      }
      let beforeTemplate = document.source
      document.edit { try TemplateLibrary.insert(TemplateLibrary.builtins[0], in: document.parsed) }
      try await wait { document.source != beforeTemplate && document.canEdit }
      document.undoManager.undo()
      try await wait { document.source == beforeTemplate && document.canEdit }
      workspace.new(.er)
      guard let er = workspace.current else { throw failure("No ER document") }
      try await wait { er.canEdit }
      let source = er.source
      let outputs = try await Task.detached {
        (try Renderer.render(source), try Renderer.render(source, format: "png"))
      }.value
      try outputs.0.data.write(to: directory.appendingPathComponent("diagram.svg"))
      try outputs.1.data.write(to: directory.appendingPathComponent("diagram.png"))
      try await Task.sleep(for: .milliseconds(500))
      guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView else {
        throw failure("No visible application window")
      }
      func findEditor(_ root: NSView) -> NSTextView? {
        if let editor = root as? NSTextView { return editor }
        return root.subviews.lazy.compactMap { findEditor($0) }.first
      }
      guard let editor = findEditor(view), editor.string == er.source, editor.frame.width > 100,
        editor.frame.height > 50,
        abs(editor.frame.width - (editor.enclosingScrollView?.contentSize.width ?? 0)) < 1
      else { throw failure("Editor layout or document binding failed") }
      if let entity = er.parsed.elements.first(where: { $0.kind == "entity" }),
        let manager = editor.layoutManager, let container = editor.textContainer
      {
        editor.setSelectedRange(NSRange(location: entity.range.location, length: 0))
        manager.ensureLayout(for: container)
        let beforeHeight = manager.usedRect(for: container).height
        editor.perform(NSSelectorFromString("toggleFold"))
        manager.ensureLayout(for: container)
        guard editor.string == er.source, manager.usedRect(for: container).height < beforeHeight
        else { throw failure("Code folding did not collapse layout safely") }
        editor.perform(NSSelectorFromString("toggleFold"))
        manager.ensureLayout(for: container)
      }
      let layout =
        "frame=\(editor.frame) bounds=\(editor.bounds) visible=\(editor.visibleRect) container=\(String(describing:editor.textContainer?.containerSize)) glyphs=\(String(describing:editor.layoutManager?.numberOfGlyphs)) origin=\(editor.textContainerOrigin) clip=\(String(describing:editor.enclosingScrollView?.contentView.frame)) ruler=\(String(describing:editor.enclosingScrollView?.verticalRulerView?.frame))"
      try Data(layout.utf8).write(to: directory.appendingPathComponent("editor-layout.txt"))
      if let bitmap = editor.bitmapImageRepForCachingDisplay(in: editor.bounds) {
        editor.cacheDisplay(in: editor.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
          try png.write(to: directory.appendingPathComponent("editor.png"))
        }
      }
      if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
          try png.write(to: directory.appendingPathComponent("window.png"))
        }
      }
      er.source = er.source.replacingOccurrences(
        of: "  name : text",
        with: "  name : text\n" + (0..<80).map { "  field_\($0) : text" }.joined(separator: "\n"))
      try await wait { er.canEdit && editor.string == er.source }
      try await AppearanceSmoke.run(
        document: er, editor: editor, window: editor.window!, directory: directory)
      guard try document.history.versions(for: document.url!.standardizedFileURL.path).count > 0
      else { throw failure("Saved history missing") }
      workspace.new(.component)
      guard let component = workspace.current else { throw failure("Component document missing") }
      try await wait { component.canEdit }
      guard ComponentModel(component.parsed).nodes.count == 2,
        let relation = component.parsed.elements.first(where: { $0.kind == "componentRelation" })
      else { throw failure("Component model failed") }
      let before = component.source
      component.edit {
        try SourceDocument.changeField(
          "label", of: relation, to: "Smoke component edit", in: component.parsed)
      }
      try await wait { component.source != before && component.canEdit }
      guard
        ComponentContract().compare(before, component.source).changes.contains(where: {
          $0.status == .modified
        })
      else { throw failure("Component structural diff failed") }
      let diffWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1150, height: 800), styleMask: [.titled, .closable],
        backing: .buffered, defer: false)
      diffWindow.contentView = NSHostingView(
        rootView: DiffView(
          comparison: Comparison(
            left: before, right: component.source, leftName: "Before", rightName: "After")))
      diffWindow.makeKeyAndOrderFront(nil)
      try await Task.sleep(for: .seconds(2))
      if let content = diffWindow.contentView,
        let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)
      {
        content.cacheDisplay(in: content.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
          try png.write(to: directory.appendingPathComponent("diff-window.png"))
        }
      }
      diffWindow.orderOut(nil)
      for mode in [ThemeMode.light, .dark] {
        ThemeStore.shared.mode = mode
        try await Task.sleep(for: .milliseconds(350))
        try AppearanceSmoke.capture(
          view, to: directory.appendingPathComponent("component-\(mode.rawValue).png"))
        diffWindow.orderFront(nil)
        try await Task.sleep(for: .milliseconds(150))
        try AppearanceSmoke.capture(
          diffWindow.contentView!, to: directory.appendingPathComponent("diff-\(mode.rawValue).png")
        )
        diffWindow.orderOut(nil)
      }
      ThemeStore.shared.mode = .system
      UserDefaults(suiteName: "PlantUMLStudio.AppearanceSmoke")?.removePersistentDomain(
        forName: "PlantUMLStudio.AppearanceSmoke")
      component.undoManager.undo()
      try await wait { component.source == before && component.canEdit }
      try Data(
        "{\"passed\":true,\"checks\":[\"window\",\"sequence\",\"constructor\",\"undo\",\"redo\",\"save\",\"er\",\"svg\",\"png\",\"outline\",\"palette\",\"search-panel\",\"template-undo\",\"fold-layout\",\"history\",\"component\",\"structural-diff\",\"diff-window\",\"themes\",\"theme-state-preservation\",\"multiwindow-appearance\",\"webkit-theme\"]}"
          .utf8
      ).write(to: directory.appendingPathComponent("result.json"))
      exit(0)
    } catch {
      try? Data(error.localizedDescription.utf8).write(
        to: directory.appendingPathComponent("failure.txt"))
      exit(1)
    }
  }
  static func wait(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(20)
    while !condition() {
      guard Date() < deadline else { throw failure("Application workflow timed out") }
      try await Task.sleep(for: .milliseconds(100))
    }
  }
  static func failure(_ message: String) -> NSError {
    NSError(domain: "SmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
