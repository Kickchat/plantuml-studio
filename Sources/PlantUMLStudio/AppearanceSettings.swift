import StudioDesign
import SwiftUI

struct StudioStyle: ViewModifier {
  func body(content: Content) -> some View {
    content.tint(DesignToken.accent.color).accentColor(DesignToken.accent.color)
      .foregroundStyle(DesignToken.primaryText.color).controlSize(.small)
      .background(DesignToken.background.color)
  }
}
struct AppearanceSettings: View {
  @ObservedObject var theme: ThemeStore
  var body: some View {
    Form {
      Section("Appearance") {
        Picker("Theme", selection: $theme.mode) {
          ForEach(ThemeMode.allCases) { mode in Text(mode.title).tag(mode) }
        }.pickerStyle(.segmented)
        Text("System следует оформлению macOS. Выбранная тема применяется ко всем окнам сразу.")
          .font(.caption).foregroundStyle(DesignToken.secondaryText.color)
      }
      Section("PlantUML Studio") {
        HStack(spacing: DesignMetrics.spacing) {
          Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(
            DesignToken.accent.color)
          VStack(alignment: .leading, spacing: 4) {
            Text("Graphite & Emerald").font(.headline)
            Text("Светлая и тёмная палитры").font(.caption).foregroundStyle(DesignToken.secondaryText.color)
          }
          Spacer()
          ForEach([DesignToken.background, .surface, .accent, .selection], id: \.self) { token in
            RoundedRectangle(cornerRadius: 6).fill(token.color).frame(width: 28, height: 28)
              .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignToken.border.color))
          }
        }.padding(.vertical, 8)
        Text("Оформление диаграмм определяется .puml и не меняется вместе с интерфейсом.")
          .font(.caption).foregroundStyle(DesignToken.secondaryText.color)
      }
    }.formStyle(.grouped).frame(width: 540, height: 300).modifier(StudioStyle())
  }
}
struct PanelHeader<Actions: View>: View {
  let title: String
  let icon: String
  @ViewBuilder var actions: () -> Actions
  var body: some View {
    HStack(spacing: DesignMetrics.spacing) {
      Image(systemName: icon).foregroundStyle(DesignToken.secondaryText.color)
      Text(title).font(.system(size: 12, weight: .semibold))
      Spacer()
      actions()
    }.padding(.horizontal, DesignMetrics.panelPadding).frame(height: DesignMetrics.toolbarHeight)
      .background(DesignToken.elevatedSurface.color)
      .overlay(alignment: .bottom) { Rectangle().fill(DesignToken.border.color).frame(height: 1) }
  }
}
