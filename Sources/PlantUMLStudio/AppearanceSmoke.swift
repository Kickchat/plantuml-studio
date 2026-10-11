import AppKit
import StudioDesign
import SwiftUI
import WebKit

@MainActor enum AppearanceSmoke {
  static func run(document: StudioDocument, editor: NSTextView, window: NSWindow, directory: URL)
    async throws
  {
    let theme = ThemeStore.shared
    defer {
      window.appearance = nil
      theme.mode = .system
      UserDefaults(suiteName: "PlantUMLStudio.AppearanceSmoke")?.removePersistentDomain(
        forName: "PlantUMLStudio.AppearanceSmoke")
    }
    func webViews(_ root: NSView) -> [WKWebView] {
      (root as? WKWebView).map { [$0] } ?? root.subviews.flatMap(webViews)
    }
    guard let web = window.contentView.flatMap({ webViews($0).first }) else {
      throw SmokeTest.failure("Missing WebKit preview")
    }
    let second = NSWindow(
      contentRect: NSRect(x: 20, y: 20, width: 560, height: 360), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    second.contentView = NSHostingView(rootView: AppearanceSettings(theme: theme))
    second.orderFront(nil)
    defer { second.orderOut(nil) }
    let beforeSource = document.source
    let beforeSVG = document.svg
    let dirty = document.dirty
    let undo = document.undoManager.canUndo
    let redo = document.undoManager.canRedo
    try await Task.sleep(for: .milliseconds(500))
    editor.setSelectedRange(NSRange(location: 12, length: 4))
    let selection = editor.selectedRange()
    let clip = editor.enclosingScrollView!.contentView
    guard clip.frame.minX >= editor.enclosingScrollView!.verticalRulerView!.frame.maxX else {
      throw SmokeTest.failure("Line numbers overlap the code viewport")
    }
    clip.scroll(to: NSPoint(x: 0, y: 40))
    let scroll = clip.bounds.origin
    try Data(
      "editor=\(editor.frame) clipFrame=\(clip.frame) clipBounds=\(clip.bounds) scroll=\(editor.enclosingScrollView!.frame) ruler=\(editor.enclosingScrollView!.verticalRulerView!.frame)"
        .utf8
    ).write(to: directory.appendingPathComponent("editor-layout.txt"))
    try await Task.sleep(for: .milliseconds(150))
    let originalSVG =
      try await web.evaluateJavaScript("document.querySelector('svg').outerHTML") as? String
    for mode in [ThemeMode.system, .light, .dark, .light] {
      theme.mode = mode
      try await Task.sleep(for: .milliseconds(350))
      let dark = theme.effectiveDark
      let mainDark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      let secondDark = second.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      guard mainDark == dark, secondDark == dark else {
        throw SmokeTest.failure("Windows disagree on appearance")
      }
      let css =
        try await web.evaluateJavaScript("getComputedStyle(document.body).backgroundColor")
        as? String
      let rgb = DesignToken.background.value(dark: dark).hex
      guard css == "rgb(\((rgb>>16)&255), \((rgb>>8)&255), \(rgb&255))" else {
        throw SmokeTest.failure("WebKit theme disagrees: \(css ?? "nil")")
      }
      let svg =
        try await web.evaluateJavaScript("document.querySelector('svg').outerHTML") as? String
      guard editor.window === window, web.window === window, svg == originalSVG,
        document.svg == beforeSVG, document.source == beforeSource,
        document.dirty == dirty, document.undoManager.canUndo == undo,
        document.undoManager.canRedo == redo,
        editor.selectedRange() == selection, clip.bounds.origin == scroll
      else {
        throw SmokeTest.failure(
          "Theme changed editor/document/diagram state: mode=\(mode) scroll=\(clip.bounds.origin) expected=\(scroll) selection=\(editor.selectedRange()) expectedSelection=\(selection) source=\(document.source == beforeSource) svg=\(svg == originalSVG) dirty=\(document.dirty == dirty) undo=\(document.undoManager.canUndo == undo) redo=\(document.undoManager.canRedo == redo)"
        )
      }
      let selectedColor = editor.selectedTextAttributes[.backgroundColor] as? NSColor
      guard
        selectedColor.map({ resolved($0, in: window.effectiveAppearance) })
          == resolved(DesignToken.selection.nsColor, in: window.effectiveAppearance)
      else { throw SmokeTest.failure("Editor selection palette disagrees") }
      if mode != .system {
        try capture(
          window.contentView!,
          to: directory.appendingPathComponent("appearance-\(mode.rawValue).png"))
      }
    }
    // Simulate native appearance propagation without modifying the user's OS settings.
    theme.mode = .system
    guard NSApp.appearance == nil else {
      throw SmokeTest.failure("System mode pins the application appearance")
    }
    for name in [NSAppearance.Name.darkAqua, .aqua] {
      // Inject the native application appearance as a stand-in for an OS change.
      // SwiftUI hosts derive their color scheme from the application appearance.
      NSApp.appearance = NSAppearance(named: name)
      try await Task.sleep(for: .milliseconds(350))
      guard theme.mode == .system else {
        throw SmokeTest.failure("Native appearance changed the saved theme preference")
      }
      let rgb = DesignToken.background.value(dark: name == .darkAqua).hex
      let css =
        try await web.evaluateJavaScript("getComputedStyle(document.body).backgroundColor")
        as? String
      guard css == "rgb(\((rgb>>16)&255), \((rgb>>8)&255), \(rgb&255))" else {
        throw SmokeTest.failure(
          "System appearance did not propagate to WKWebView: css=\(css ?? "nil") web=\(web.effectiveAppearance) window=\(window.effectiveAppearance) editor=\(editor.effectiveAppearance)"
        )
      }
      let color = resolved(editor.backgroundColor, in: window.effectiveAppearance)
      guard
        color
          == resolved(
            DesignToken.surface.value(dark: name == .darkAqua).color, in: window.effectiveAppearance
          )
      else {
        throw SmokeTest.failure(
          "Native appearance did not propagate to editor: \(name.rawValue) actual=\(color) expected=\(resolved(DesignToken.surface.value(dark:name == .darkAqua).color,in:window.effectiveAppearance)) editorAppearance=\(editor.effectiveAppearance)"
        )
      }
    }
    NSApp.appearance = nil
    window.appearance = nil
    let restored = ThemeStore(
      defaults: UserDefaults(suiteName: "PlantUMLStudio.AppearanceSmoke")!,
      applyToApplication: false)
    guard restored.mode == .system else {
      throw SmokeTest.failure("Appearance preference was not restored")
    }
    // Verify styling of other primary dialogs in both appearances.
    for mode in [ThemeMode.light, .dark] {
      theme.mode = mode
      let dialogs: [(String, AnyView)] = [
        ("palette", AnyView(CommandPalette(document: document))),
        ("templates", AnyView(TemplatesView(document: document))),
        ("history", AnyView(HistoryView(document: document))),
      ]
      for (name, view) in dialogs {
        second.contentView = NSHostingView(rootView: view)
        second.setContentSize(NSSize(width: name == "palette" ? 560 : 850, height: 580))
        try await Task.sleep(for: .milliseconds(150))
        try capture(
          second.contentView!, to: directory.appendingPathComponent("\(name)-\(mode.rawValue).png"))
      }
    }
  }
  static func resolved(_ color: NSColor, in appearance: NSAppearance) -> NSColor {
    var result = color
    appearance.performAsCurrentDrawingAppearance { result = color.usingColorSpace(.sRGB) ?? color }
    return result
  }
  static func capture(_ view: NSView, to url: URL) throws {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      throw SmokeTest.failure("No screenshot bitmap")
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw SmokeTest.failure("No screenshot data")
    }
    try data.write(to: url)
  }
}
