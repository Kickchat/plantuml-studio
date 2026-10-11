import AppKit
import PlantUMLCore
import StudioDesign
import SwiftUI

struct HistoryView: View {
  @ObservedObject var document: StudioDocument
  @Environment(\.dismiss) private var dismiss
  @State private var versions: [SavedVersion] = []
  @State private var comparison: Comparison?
  @State private var failure = ""
  @AppStorage("studio.history.count") private var count = 30
  @AppStorage("studio.history.mb") private var megabytes = 20
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("История сохранений").font(.title2)
        Spacer()
        Button("Закрыть") { dismiss() }
      }
      HStack {
        Stepper("Версий: \(count)", value: $count, in: 1...200)
        Stepper("МБ на файл: \(megabytes)", value: $megabytes, in: 1...200)
      }
      Text("Лимиты применяются при следующем сохранении. История независима от Undo.").font(
        .caption
      ).foregroundStyle(DesignToken.secondaryText.color)
      List(versions.reversed()) { version in
        HStack {
          Text(version.date, format: .dateTime.year().month().day().hour().minute().second())
          Text("\(version.source.utf8.count) байт").foregroundStyle(DesignToken.secondaryText.color)
          Spacer()
          Button("Сравнить") {
            comparison = Comparison(
              left: version.source, right: document.source,
              leftName: "Версия \(version.date.formatted())", rightName: "Текущий документ")
          }
          Button("Открыть копию") {
            NotificationCenter.default.post(name: .studioOpenHistory, object: version.source)
          }
          Button("Восстановить") { restore(version) }
        }
      }.scrollContentBackground(.hidden).background(DesignToken.surface.color).frame(height: 300)
      if !failure.isEmpty { Text(failure).foregroundStyle(DesignToken.error.color) }
      if document.url == nil { Text("История начинается после сохранения файла на диск.") }
    }.padding(20).frame(width: 800).modifier(StudioStyle()).onAppear { load() }.sheet(
      item: $comparison
    ) {
      DiffView(comparison: $0)
    }
  }
  func load() {
    guard let url = document.url else { return }
    do { versions = try document.history.versions(for: url.standardizedFileURL.path) } catch {
      failure = error.localizedDescription
    }
  }
  func restore(_ version: SavedVersion) {
    let alert = NSAlert()
    alert.messageText = "Восстановить выбранную версию?"
    alert.informativeText =
      "Текущий текст будет заменён. Изменение можно отменить; файл на диске изменится после сохранения."
    alert.addButton(withTitle: "Восстановить")
    alert.addButton(withTitle: "Отмена")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    document.source = version.source
    dismiss()
  }
}
extension Notification.Name {
  static let studioOpenHistory = Notification.Name("studio.openHistory")
}
