import SwiftUI

@MainActor final class ShortcutStore: ObservableObject {
  @Published var keys: [String: String] = [:]
  init() {
    keys =
      UserDefaults.standard.dictionary(forKey: "studio.shortcuts.v2") as? [String: String] ?? [:]
  }
  func set(_ key: String, for command: String) {
    let normalized = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count <= 1,
      !keys.contains(where: { $0.key != command && !$0.value.isEmpty && $0.value == normalized })
    else { return }
    keys[command] = normalized
    UserDefaults.standard.set(keys, forKey: "studio.shortcuts.v2")
  }
}
struct ShortcutSettings: View {
  @ObservedObject var store: ShortcutStore
  let commands = [
    ("participant", "Добавить участника"), ("message", "Добавить сообщение"),
    ("block", "Добавить блок"), ("entity", "Добавить сущность"), ("attribute", "Добавить атрибут"),
    ("relation", "Добавить связь"), ("focusEditor", "Фокус редактора"),
    ("focusDiagram", "Фокус диаграммы"), ("focusProperties", "Фокус свойств"),
  ]
  var body: some View {
    Form {
      Text(
        "Пользовательские команды используют ⌘⌥ и одну клавишу. Повторяющиеся клавиши не сохраняются."
      ).font(.caption)
      ForEach(commands, id: \.0) { id, name in
        HStack {
          Text(name)
          Spacer()
          TextField(
            "—", text: Binding(get: { store.keys[id] ?? "" }, set: { store.set($0, for: id) })
          ).frame(width: 45)
        }
      }
    }.padding(20).frame(width: 480)
  }
}
