import AppKit
import StudioDesign

@MainActor enum EditorColors {
  static func apply(to editor: NSTextView) {
    let clip = editor.enclosingScrollView?.contentView
    let origin = clip?.bounds.origin
    let dark = editor.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    func color(_ token: DesignToken) -> NSColor { token.value(dark: dark).color }
    editor.backgroundColor = color(.surface)
    editor.textColor = color(.primaryText)
    editor.insertionPointColor = color(.accent)
    editor.selectedTextAttributes = [
      .backgroundColor: color(.selection),
      .foregroundColor: color(.primaryText),
    ]
    guard let storage = editor.textStorage else { return }
    let range = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    storage.addAttribute(.foregroundColor, value: color(.primaryText), range: range)
    for (regex, token) in patterns {
      for match in regex.matches(in: editor.string, range: range) {
        storage.addAttribute(.foregroundColor, value: color(token), range: match.range)
      }
    }
    storage.endEditing()
    if let container = editor.textContainer {
      editor.layoutManager?.ensureLayout(for: container)
    }
    if let origin { clip?.setBoundsOrigin(origin) }
    editor.needsDisplay = true
    editor.enclosingScrollView?.verticalRulerView?.needsDisplay = true
  }
  private static let patterns: [(NSRegularExpression, DesignToken)] = [
    (
      #"@startuml|@enduml|\b(alt|else|opt|loop|par|break|critical|group|end|activate|deactivate|destroy|note|title|autonumber)\b"#,
      .keyword
    ),
    (
      #"\b(actor|participant|boundary|control|component|interface|package|node|cloud|frame|folder|entity|database|collections|queue)\b"#,
      .participant
    ),
    (#"-->>|->>|-->|->|<<--|<<-|<--|<-|<->|->x|o->|->o|\.\.>"#, DesignToken.message),
    (#""[^"\r\n]*"|<<[^>\r\n]+>>"#, DesignToken.string),
    (#"(?m)^[ \t]*'.*$|/\'[\s\S]*?\'/"#, DesignToken.comment),
  ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
}
