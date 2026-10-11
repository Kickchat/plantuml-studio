import PlantUMLCore
import StudioDesign
import SwiftUI

private struct AttributeDraft: Identifiable {
  let id = UUID()
  var name = ""
  var datatype = "text"
  var mandatory = false
  var primaryKey = false
}

struct AttributeBatchEditor: View {
  @ObservedObject var document: StudioDocument
  let entity: Element
  @Environment(\.dismiss) private var dismiss
  @State private var drafts = [AttributeDraft()]
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Новые атрибуты").font(.headline)
      ScrollView {
        VStack(spacing: 8) {
          ForEach($drafts) { $draft in
            HStack {
              TextField("Название", text: $draft.name)
              TextField("Тип данных", text: $draft.datatype)
              Toggle("Обязательный", isOn: $draft.mandatory)
              Toggle("PK", isOn: $draft.primaryKey)
              Button {
                drafts.removeAll { $0.id == draft.id }
              } label: {
                Image(systemName: "minus.circle")
              }
            }
          }
        }
      }.frame(height: 200)
      Button("Ещё атрибут") { drafts.append(AttributeDraft()) }
      Text("PK — визуальная метка, без ограничений БД.").font(.caption).foregroundStyle(
        DesignToken.secondaryText.color)
      if !error.isEmpty { Text(error).font(.caption).foregroundStyle(DesignToken.error.color) }
      HStack {
        Spacer()
        Button("Отмена") { dismiss() }
        Button("Добавить") { apply() }.disabled(!document.canEdit || drafts.isEmpty)
      }
    }.textFieldStyle(.roundedBorder).padding(20).frame(width: 650).modifier(StudioStyle())
  }
  func apply() {
    do {
      guard
        drafts.allSatisfy({ draft in
          !SourceDocument.hasLineBreak(draft.name) && !SourceDocument.hasLineBreak(draft.datatype)
            && draft.name.range(of: #"^[\p{L}_][\p{L}\w]*$"#, options: .regularExpression) != nil
            && !draft.datatype.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.datatype.rangeOfCharacter(from: CharacterSet(charactersIn: "{}<>:")) == nil
        })
      else { throw SourceError.invalidEdit }
      let text = drafts.map {
        ($0.mandatory ? "* " : "") + $0.name + " : " + $0.datatype
          + ($0.primaryKey ? " <<PK>>" : "")
      }.joined(separator: "\n")
      let proposed = try QuickOperations.addAttributes(text, to: entity, in: document.parsed)
      document.edit { proposed }
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
