import AppKit
import ERModule
import PlantUMLCore
import Rendering
import SequenceModule
import SwiftUI
import WebKit

let sequenceTemplate =
  "@startuml\ntitle Authentication\nactor User\nparticipant API\nUser -> API : Sign in\nactivate API\nalt Success\n  API --> User : Welcome\nelse Invalid credentials\n  API --> User : Try again\nend\ndeactivate API\n@enduml\n"
let erTemplate =
  "@startuml\n!pragma layout smetana\nentity \"User\" as User {\n  * id : integer <<PK>>\n  --\n  name : text\n}\nentity \"Session\" as Session {\n  * id : integer <<PK>>\n  --\n  user_id : integer <<FK>>\n}\nUser ||--o{ Session : owns\n@enduml\n"

@main struct PlantUMLStudioApp: App {
  @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
  @StateObject private var workspace = Workspace()
  @StateObject private var shortcuts = ShortcutStore()
  var body: some Scene {
    WindowGroup("PlantUML Studio") {
      VStack(spacing: 0) {
        ScrollView(.horizontal) {
          HStack(spacing: 4) {
            ForEach(workspace.documents) { doc in
              TabButton(
                document: doc, active: workspace.selected == doc.id,
                select: { workspace.selected = doc.id }, close: { workspace.close(doc) })
            }
            Menu {
              Button("Sequence") { workspace.new(.sequence) }
              Button("ER Diagram") { workspace.new(.er) }
            } label: {
              Image(systemName: "plus")
            }
          }.padding(8)
        }
        Divider()
        if let document = workspace.current {
          DocumentView(document: document).id(document.id)
        } else {
          ContentUnavailableView("Откройте диаграмму", systemImage: "doc.text")
        }
      }.frame(minWidth: 1000, minHeight: 650).background(Color(nsColor: .windowBackgroundColor))
        .background(WindowConnection(delegate: delegate, workspace: workspace)).onReceive(
          NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
        ) { _ in workspace.persist() }
    }.commands {
      CommandMenu("Конструктор") {
        if let doc = workspace.current {
          ForEach(StudioCommands.available(doc).filter { shortcuts.keys[$0.id]?.isEmpty == false })
          { command in
            Button(command.name, action: command.action).keyboardShortcut(
              KeyEquivalent(Character(shortcuts.keys[command.id]!)), modifiers: [.command, .option])
          }
        }
      }
      CommandGroup(replacing: .newItem) {
        Button("Новая Sequence") { workspace.new(.sequence) }.keyboardShortcut("n")
        Button("Новая ER") { workspace.new(.er) }.keyboardShortcut(
          "n", modifiers: [.command, .shift])
        Button("Открыть…") { workspace.open() }.keyboardShortcut("o")
      }
      CommandGroup(replacing: .undoRedo) {
        Button("Отменить") { workspace.current?.undoManager.undo() }.keyboardShortcut("z")
        Button("Повторить") { workspace.current?.undoManager.redo() }.keyboardShortcut(
          "z", modifiers: [.command, .shift])
      }
      CommandMenu("Навигация") {
        Button("Палитра команд…") { workspace.current?.paletteVisible = true }.keyboardShortcut(
          "p", modifiers: [.command, .shift])
        Button("Найти…") { workspace.current?.searchVisible = true }.keyboardShortcut("f")
        Button("Заменить…") { workspace.current?.searchVisible = true }.keyboardShortcut(
          "f", modifiers: [.command, .option])
        Button("Увеличить") {
          if let doc = workspace.current { doc.zoom = min(3, max(0.2, doc.zoom) + 0.1) }
        }.keyboardShortcut("+")
        Button("Уменьшить") {
          if let doc = workspace.current { doc.zoom = max(0.2, doc.zoom - 0.1) }
        }.keyboardShortcut("-")
        Button("Масштаб 100%") { workspace.current?.zoom = 1 }.keyboardShortcut("0")
      }
      CommandGroup(replacing: .saveItem) {
        Button("Сохранить") { workspace.current?.save() }.keyboardShortcut("s")
        Button("Сохранить как…") { workspace.current?.save(asNew: true) }.keyboardShortcut(
          "s", modifiers: [.command, .shift])
        Button("Экспорт SVG…") { workspace.current?.export("svg") }
        Button("Экспорт PNG…") { workspace.current?.export("png") }
      }
    }
    Settings { ShortcutSettings(store: shortcuts) }
  }
}
struct TabButton: View {
  @ObservedObject var document: StudioDocument
  let active: Bool
  let select: () -> Void
  let close: () -> Void
  var body: some View {
    HStack {
      Button(document.name + (document.dirty ? " •" : ""), action: select).buttonStyle(.plain)
      Button(action: close) { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain)
    }.padding(8).background(active ? Color.accentColor.opacity(0.12) : Color.clear).clipShape(
      RoundedRectangle(cornerRadius: 6))
  }
}
