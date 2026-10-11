import AppKit
import PlantUMLCore
import SwiftUI

struct CodeEditor: NSViewRepresentable {
  @Binding var text: String
  var focusRequested = false
  var onFocused: (() -> Void)? = nil
  var onCursor: ((NSRange) -> Void)? = nil
  var diagnosticLine: Int? = nil
  var selectedSourceRange: NSRange? = nil
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = EditorScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    let editor = IndentingTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
    editor.isRichText = false
    editor.allowsUndo = false
    editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.isContinuousSpellCheckingEnabled = false
    editor.isIncrementalSearchingEnabled = true
    editor.usesFindBar = true
    editor.textContainerInset = NSSize(width: 12, height: 12)
    editor.minSize = NSSize(width: 0, height: 0)
    editor.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.autoresizingMask = [.width]
    editor.backgroundColor = .textBackgroundColor
    editor.textColor = .textColor
    editor.textContainer?.widthTracksTextView = true
    editor.textContainer?.containerSize = NSSize(
      width: 500, height: CGFloat.greatestFiniteMagnitude)
    editor.delegate = context.coordinator
    editor.layoutManager?.delegate = editor
    editor.string = text
    scroll.documentView = editor
    let ruler = LineNumberRuler(scrollView: scroll, orientation: .verticalRuler)
    ruler.clientView = editor
    ruler.ruleThickness = 48
    scroll.verticalRulerView = ruler
    scroll.hasVerticalRuler = true
    scroll.rulersVisible = true
    context.coordinator.highlight(editor)
    return scroll
  }
  func updateNSView(_ view: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let editor = view.documentView as? NSTextView else { return }
    if focusRequested {
      editor.window?.makeFirstResponder(editor)
      DispatchQueue.main.async { onFocused?() }
    }
    if editor.string != text,
      editor.shouldChangeText(
        in: NSRange(location: 0, length: (editor.string as NSString).length),
        replacementString: text)
    {
      editor.textStorage?.replaceCharacters(
        in: NSRange(location: 0, length: (editor.string as NSString).length), with: text)
      editor.didChangeText()
      context.coordinator.highlight(editor)
    }
    editor.textStorage?.removeAttribute(
      .backgroundColor, range: NSRange(location: 0, length: (editor.string as NSString).length))
    if let line = diagnosticLine {
      let source = editor.string as NSString
      var offset = 0
      for (index, raw) in editor.string.components(separatedBy: "\n").enumerated() {
        if index == line, offset < source.length {
          editor.textStorage?.addAttribute(
            .backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.15),
            range: NSRange(location: offset, length: (raw as NSString).length))
          break
        }
        offset += (raw as NSString).length + 1
      }
    }
    if let range = selectedSourceRange, range != context.coordinator.lastSelection,
      NSMaxRange(range) <= (editor.string as NSString).length
    {
      context.coordinator.lastSelection = range
      context.coordinator.selectingProgrammatically = true
      editor.setSelectedRange(range)
      context.coordinator.selectingProgrammatically = false
      editor.scrollRangeToVisible(range)
    }
    if selectedSourceRange == nil { context.coordinator.lastSelection = nil }
    editor.enclosingScrollView?.verticalRulerView?.needsDisplay = true
  }
  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: CodeEditor
    var lastSelection: NSRange?
    var model: ParsedDocument?
    var selectingProgrammatically = false
    init(_ parent: CodeEditor) { self.parent = parent }
    func textDidChange(_ notification: Notification) {
      guard let editor = notification.object as? NSTextView else { return }
      parent.text = editor.string
      highlight(editor)
      editor.enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }
    func textViewDidChangeSelection(_ notification: Notification) {
      guard let editor = notification.object as? NSTextView, let layout = editor.layoutManager,
        let model, model.source == editor.string
      else { return }
      if !selectingProgrammatically { parent.onCursor?(editor.selectedRange()) }
      let ns = editor.string as NSString
      layout.removeTemporaryAttribute(
        .underlineStyle, forCharacterRange: NSRange(location: 0, length: ns.length))
      let caret = editor.selectedRange().location
      for element in model.elements where ["block", "entity", "container"].contains(element.kind) {
        guard let extent = element.fullRange else { continue }
        var last = NSMaxRange(extent) - 1
        while last > extent.location,
          ["\n", "\r"].contains(ns.substring(with: NSRange(location: last, length: 1)))
        { last -= 1 }
        let closing = ns.lineRange(for: NSRange(location: last, length: 0))
        if NSLocationInRange(caret, element.range) || NSLocationInRange(caret, closing) {
          for range in [element.range, closing] {
            layout.addTemporaryAttribute(
              .underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range)
          }
          break
        }
      }
    }
    func textView(
      _ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange,
      indexOfSelectedItem index: UnsafeMutablePointer<Int>?
    ) -> [String] {
      guard let model else { return words }
      return EditorAssistance.completions(
        prefix: (textView.string as NSString).substring(with: charRange), in: model)
    }
    func highlight(_ editor: NSTextView) {
      model = SourceDocument.parse(editor.string)
      guard let storage = editor.textStorage else { return }
      let range = NSRange(location: 0, length: storage.length)
      storage.beginEditing()
      storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
      for (pattern, color) in [
        (
          #"\b(actor|participant|boundary|control|component|interface|package|node|cloud|frame|folder|entity|database|collections|queue|alt|else|opt|loop|par|break|critical|group|end|activate|deactivate|destroy|note|title|autonumber)\b"#,
          NSColor.systemPurple
        ), (#"(?m)^\s*'.*$"#, NSColor.secondaryLabelColor),
        (#"@startuml|@enduml|--?>+|<--?"#, NSColor.systemBlue),
      ] {
        let regex = try! NSRegularExpression(pattern: pattern)
        for match in regex.matches(in: editor.string, range: range) {
          storage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
      }
      storage.endEditing()
    }
  }
}

@MainActor final class LineNumberRuler: NSRulerView {
  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard let editor = clientView as? NSTextView, let layout = editor.layoutManager,
      let container = editor.textContainer
    else { return }
    NSColor.windowBackgroundColor.setFill()
    rect.fill()
    let visible = editor.visibleRect
    let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
    let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
    let source = editor.string as NSString
    var index = 0
    var number = 1
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
      .foregroundColor: NSColor.secondaryLabelColor,
    ]
    while index < source.length {
      let range = source.lineRange(for: NSRange(location: index, length: 0))
      if NSMaxRange(range) >= characters.location, range.location <= NSMaxRange(characters) {
        let glyph = layout.glyphIndexForCharacter(at: index)
        let lineRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let y = lineRect.minY + editor.textContainerInset.height - visible.minY
        let label = "\(number)" as NSString
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y), withAttributes: attributes)
      }
      index = NSMaxRange(range)
      number += 1
    }
  }
}
@MainActor final class IndentingTextView: NSTextView, @preconcurrency NSLayoutManagerDelegate {
  private var folded: [NSRange] = []
  override func insertNewline(_ sender: Any?) {
    let source = string as NSString
    let selection = selectedRange()
    let lineRange = source.lineRange(
      for: NSRange(location: min(selection.location, source.length), length: 0))
    let line = source.substring(
      with: NSRange(location: lineRange.location, length: selection.location - lineRange.location))
    let newline = string.contains("\r\n") ? "\r\n" : "\n"
    var insertion = EditorAssistance.newline(after: line, newline: newline)
    let paired = SourceDocument.parse(string).elements.contains {
      $0.range.location == lineRange.location && $0.fullRange != nil
    }
    if paired && insertion.components(separatedBy: newline).count == 3 {
      insertion = newline + String(line.prefix { $0 == " " || $0 == "\t" }) + "  "
    }
    insertText(insertion, replacementRange: selection)
    let parts = insertion.components(separatedBy: newline)
    if parts.count == 3 {
      setSelectedRange(
        NSRange(
          location: selection.location + (newline as NSString).length
            + (parts[1] as NSString).length, length: 0))
    }
  }
  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = super.menu(for: event) ?? NSMenu()
    menu.addItem(.separator())
    for (title, action) in [
      ("Автодополнение", #selector(showCompletion)),
      ("Свернуть / развернуть блок", #selector(toggleFold)),
      ("Форматировать выделение", #selector(formatSelection)),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    return menu
  }
  @objc private func showCompletion() { complete(nil) }
  @objc private func formatSelection() {
    let model = SourceDocument.parse(string)
    guard selectedRange().length > 0,
      let proposed = try? QuickOperations.format(selectedRange(), in: model)
    else { return }
    insertText(
      proposed, replacementRange: NSRange(location: 0, length: (string as NSString).length))
  }
  @objc private func toggleFold() {
    guard let layout = layoutManager else { return }
    let model = SourceDocument.parse(string)
    let caret = selectedRange().location
    guard
      let element = model.elements.filter({
        $0.fullRange.map { NSLocationInRange(caret, $0) } == true
      }).min(by: { ($0.fullRange?.length ?? Int.max) < ($1.fullRange?.length ?? Int.max) }),
      let range = EditorAssistance.foldableBody(of: element, in: model)
    else { return }
    let hiding = !folded.contains(range)
    if hiding { folded.append(range) } else { folded.removeAll { $0 == range } }
    let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    for index in glyphs.location..<NSMaxRange(glyphs) {
      layout.setNotShownAttribute(hiding, forGlyphAt: index)
    }
    layout.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
    needsDisplay = true
  }
  func layoutManager(
    _ layoutManager: NSLayoutManager,
    shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
    lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
    baselineOffset: UnsafeMutablePointer<CGFloat>, in textContainer: NSTextContainer,
    forGlyphRange glyphRange: NSRange
  ) -> Bool {
    let range = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    if folded.contains(where: {
      range.location >= $0.location && NSMaxRange(range) <= NSMaxRange($0)
    }) {
      lineFragmentRect.pointee.size.height = 0.001
      lineFragmentUsedRect.pointee.size.height = 0.001
      baselineOffset.pointee = 0
      return true
    }
    return false
  }
  override func didChangeText() {
    if let layout = layoutManager {
      for index in 0..<layout.numberOfGlyphs {
        layout.setNotShownAttribute(false, forGlyphAt: index)
      }
    }
    folded.removeAll()
    super.didChangeText()
  }

}

@MainActor private final class EditorScrollView: NSScrollView {
  override func tile() {
    super.tile()
    guard let editor = documentView as? NSTextView, contentSize.width > 0 else { return }
    let size = NSSize(
      width: contentSize.width, height: max(contentSize.height, editor.frame.height))
    if editor.frame.size != size { editor.setFrameSize(size) }
    if editor.frame.origin != .zero { editor.setFrameOrigin(.zero) }
    editor.minSize = NSSize(width: contentSize.width, height: contentSize.height)
  }
}
