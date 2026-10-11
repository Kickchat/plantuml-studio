import PlantUMLCore
import StudioDesign
import SwiftUI

struct SearchBar: View {
  @ObservedObject var document: StudioDocument
  @State private var query = ""
  @State private var replacement = ""
  @State private var caseSensitive = false
  @State private var regex = false
  @State private var index = -1
  @State private var failure = ""
  var options: SearchOptions { SearchOptions(caseSensitive: caseSensitive, regex: regex) }
  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        TextField("Найти", text: $query).onSubmit { navigate(1) }
        Toggle("Aa", isOn: $caseSensitive)
        Toggle(".*", isOn: $regex)
        Button("↑") { navigate(-1) }
        Button("↓") { navigate(1) }
        Text(
          "\((try? SourceSearch.matches(query, in: document.source, options: options).count) ?? 0)")
        Button {
          document.searchVisible = false
        } label: {
          Image(systemName: "xmark")
        }
      }
      HStack {
        TextField("Заменить на", text: $replacement)
        Button("Заменить") { replace(all: false) }
        Button("Все") { replace(all: true) }
      }
      if !failure.isEmpty { Text(failure).foregroundStyle(DesignToken.error.color).font(.caption) }
    }.textFieldStyle(.roundedBorder).padding(DesignMetrics.spacing).background(
      DesignToken.elevatedSurface.color
    )
    .onChange(of: document.source) { index = -1 }
    .onChange(of: query) { index = -1 }
    .onChange(of: regex) { index = -1 }
    .onChange(of: caseSensitive) { index = -1 }
  }
  func navigate(_ step: Int) {
    do {
      let matches = try SourceSearch.matches(query, in: document.source, options: options)
      guard !matches.isEmpty else { return }
      index =
        index < 0
        ? (step > 0 ? 0 : matches.count - 1) : (index + step + matches.count) % matches.count
      document.navigationRange = matches[index]
      failure = ""
    } catch { failure = error.localizedDescription }
  }
  func replace(all: Bool) {
    do {
      if !all && index < 0 { navigate(1) }
      guard all || index >= 0 else { return }
      document.source = try SourceSearch.replace(
        query, with: replacement, in: document.source, options: options, only: all ? nil : index)
      index = -1
      failure = ""
    } catch { failure = error.localizedDescription }
  }
}
