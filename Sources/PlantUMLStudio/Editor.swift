import AppKit
import PlantUMLCore
import SwiftUI

struct CodeEditor: NSViewRepresentable {
  @Binding var text: String
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
      editor.setSelectedRange(range)
      editor.scrollRangeToVisible(range)
    }
    if selectedSourceRange == nil { context.coordinator.lastSelection = nil }
    editor.enclosingScrollView?.verticalRulerView?.needsDisplay = true
  }
  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: CodeEditor
    var lastSelection: NSRange?
    var model: ParsedDocument?
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
      let ns = editor.string as NSString
      layout.removeTemporaryAttribute(
        .underlineStyle, forCharacterRange: NSRange(location: 0, length: ns.length))
      let caret = editor.selectedRange().location
      for element in model.elements where ["block", "entity"].contains(element.kind) {
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
    func highlight(_ editor: NSTextView) {
      model = SourceDocument.parse(editor.string)
      guard let storage = editor.textStorage else { return }
      let range = NSRange(location: 0, length: storage.length)
      storage.beginEditing()
      storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
      for (pattern, color) in [
        (
          #"\b(actor|participant|boundary|control|entity|database|collections|queue|alt|else|opt|loop|par|break|critical|group|end|activate|deactivate|destroy|note|title|autonumber)\b"#,
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
@MainActor final class IndentingTextView: NSTextView {
  override func insertNewline(_ sender: Any?) {
    let source = string as NSString
    let selection = selectedRange()
    let lineRange = source.lineRange(
      for: NSRange(location: min(selection.location, source.length), length: 0))
    let line = source.substring(with: lineRange)
    let indent = String(line.prefix { $0 == " " || $0 == "\t" })
    super.insertNewline(sender)
    if !indent.isEmpty { insertText(indent, replacementRange: selectedRange()) }
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
