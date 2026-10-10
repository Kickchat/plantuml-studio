import AppKit
import SwiftUI

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  weak var workspace: Workspace?
  private var smokeStarted = false
  func startSmokeIfRequested() {
    guard !smokeStarted,
      let directory = ProcessInfo.processInfo.environment["PLANTUML_STUDIO_SMOKE_DIR"],
      let workspace
    else { return }
    smokeStarted = true
    Task { await SmokeTest.run(workspace: workspace, directory: URL(fileURLWithPath: directory)) }
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard approveUnsavedDocuments() else { return .terminateCancel }
    workspace?.persist()
    return .terminateNow
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard approveUnsavedDocuments() else { return false }
    workspace?.persist()
    return true
  }
  func approveUnsavedDocuments() -> Bool {
    guard let workspace else { return true }
    var discarded = Set<UUID>()
    for document in workspace.documents where document.dirty {
      let alert = NSAlert()
      alert.messageText = "Сохранить изменения в \(document.name)?"
      alert.addButton(withTitle: "Сохранить")
      alert.addButton(withTitle: "Отмена")
      alert.addButton(withTitle: "Не сохранять")
      switch alert.runModal() {
      case .alertFirstButtonReturn:
        document.save()
        if document.dirty { return false }
      case .alertSecondButtonReturn: return false
      default: discarded.insert(document.id)
      }
    }
    workspace.documents.removeAll { discarded.contains($0.id) }
    if let selected = workspace.selected, discarded.contains(selected) {
      workspace.selected = workspace.documents.first?.id
    }
    return true
  }
}
struct WindowConnection: NSViewRepresentable {
  let delegate: ApplicationDelegate
  let workspace: Workspace
  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ view: NSView, context: Context) {
    delegate.workspace = workspace
    DispatchQueue.main.async {
      view.window?.delegate = delegate
      delegate.startSmokeIfRequested()
    }
  }
}
