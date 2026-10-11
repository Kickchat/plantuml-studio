import ComponentModule
import PlantUMLCore
import StudioDesign
import SwiftUI

@MainActor final class UserTemplates: ObservableObject {
  @Published var items: [DiagramTemplate] = []
  init() {
    if let data = UserDefaults.standard.data(forKey: "studio.templates.v2"),
      let saved = try? JSONDecoder().decode([DiagramTemplate].self, from: data)
    {
      items = saved
    }
  }
  func persist() {
    if let data = try? JSONEncoder().encode(items) {
      UserDefaults.standard.set(data, forKey: "studio.templates.v2")
    }
  }
}
struct TemplatesView: View {
  @ObservedObject var document: StudioDocument
  @StateObject private var library = UserTemplates()
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var category = "Мои шаблоны"
  @State private var fragment = ""
  @State private var editing: UUID?
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Шаблоны").font(.title2)
        Spacer()
        Button("Закрыть") { dismiss() }
      }
      List {
        ForEach(TemplateLibrary.builtins + ComponentTemplates.builtins + library.items) {
          template in
          if template.kind == document.parsed.kind.rawValue {
            HStack {
              VStack(alignment: .leading) {
                Text(template.name)
                Text(template.category).font(.caption).foregroundStyle(
                  DesignToken.secondaryText.color)
              }
              Spacer()
              Button("Вставить") {
                document.edit { try TemplateLibrary.insert(template, in: document.parsed) }
                dismiss()
              }.disabled(!document.canEdit)
              if library.items.contains(where: { $0.id == template.id }) {
                Button("Изменить") {
                  editing = template.id
                  name = template.name
                  category = template.category
                  fragment = template.fragment
                }
                Button("Удалить") {
                  library.items.removeAll { $0.id == template.id }
                  library.persist()
                }
              }
            }
          }
        }
      }.scrollContentBackground(.hidden).background(DesignToken.surface.color).frame(height: 220)
      HStack {
        TextField("Название", text: $name)
        TextField("Категория", text: $category)
        Button("Из выделения") {
          if let range = document.selectedTextRange ?? document.navigationRange ?? document.parsed
            .elements.first(where: {
              $0.id == document.selection
            })?.fullRange
            ?? document.parsed.elements.first(where: { $0.id == document.selection })?.range
          {
            if range.location >= 0, range.length >= 0,
              range.location <= (document.source as NSString).length,
              range.length <= (document.source as NSString).length - range.location
            {
              fragment = (document.source as NSString).substring(with: range)
            }
          }
        }
      }
      TextEditor(text: $fragment).font(.system(.body, design: .monospaced)).frame(height: 150)
      Button(editing == nil ? "Сохранить шаблон" : "Сохранить изменения") {
        let template = DiagramTemplate(
          id: editing ?? UUID(), name: name, category: category,
          kind: document.parsed.kind.rawValue, fragment: fragment)
        if let index = library.items.firstIndex(where: { $0.id == template.id }) {
          library.items[index] = template
        } else {
          library.items.append(template)
        }
        library.persist()
        editing = nil
        name = ""
        fragment = ""
      }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || fragment.isEmpty)
    }.padding(20).frame(width: 700).modifier(StudioStyle())
  }
}
