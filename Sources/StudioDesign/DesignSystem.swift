import AppKit
import SwiftUI

public enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
  case system, light, dark
  public var id: String { rawValue }
  public var title: String { rawValue.capitalized }
  public func resolved(systemDark: Bool) -> Bool {
    self == .dark || (self == .system && systemDark)
  }
}
public struct RGB: Sendable {
  public let hex: UInt32
  public init(_ hex: UInt32) { self.hex = hex }
  public var css: String { String(format: "#%06X", hex) }
  public var color: NSColor {
    NSColor(
      srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255, alpha: 1)
  }
  public var luminance: Double {
    func linear(_ value: UInt32) -> Double {
      let v = Double(value) / 255
      return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear((hex >> 16) & 255) + 0.7152 * linear((hex >> 8) & 255) + 0.0722
      * linear(hex & 255)
  }
  public func contrast(with other: RGB) -> Double {
    (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
  }
}
public enum DesignToken: CaseIterable, Sendable {
  case background, surface, elevatedSurface, primaryText, secondaryText, accent, selection, border,
    error, warning, success
  case activeLine, keyword, participant, message, string, comment, diffAdded, diffRemoved,
    diagramPaper, diagramInk
  public func value(dark: Bool) -> RGB {
    let pair: (UInt32, UInt32)
    switch self {
    case .background: pair = (0xF7F9F8, 0x172332)
    case .surface: pair = (0xFFFFFF, 0x1D2B3A)
    case .elevatedSurface: pair = (0xE9EFED, 0x263645)
    case .primaryText: pair = (0x172332, 0xEDF5F1)
    case .secondaryText: pair = (0x536670, 0xADBDC7)
    case .accent: pair = (0x086B50, 0x73E5BB)
    case .selection: pair = (0xCCE9DE, 0x244F43)
    case .border: pair = (0xCAD6D1, 0x405365)
    case .error: pair = (0xB42332, 0xFF919B)
    case .warning: pair = (0x875000, 0xF0C478)
    case .success: pair = (0x086B50, 0x73E5BB)
    case .activeLine: pair = (0xF0F6F3, 0x233B40)
    case .keyword: pair = (0x713AAA, 0xCBABF5)
    case .participant: pair = (0x1B609E, 0x84C7F6)
    case .message: pair = (0x086B50, 0x73E5BB)
    case .string: pair = (0x885000, 0xE9C17B)
    case .comment: pair = (0x586C63, 0xA2B7AC)
    case .diffAdded: pair = (0xDDEFE4, 0x24483B)
    case .diffRemoved: pair = (0xF8E2E4, 0x502E3A)
    case .diagramPaper: pair = (0xFFFFFF, 0xFFFFFF)
    case .diagramInk: pair = (0x000000, 0x000000)
    }
    return RGB(dark ? pair.1 : pair.0)
  }
  public var nsColor: NSColor {
    NSColor(name: nil) { appearance in
      self.value(dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua).color
    }
  }
  public var color: Color { Color(nsColor: nsColor) }
}
public enum DesignMetrics {
  public static let spacing: CGFloat = 8
  public static let panelPadding: CGFloat = 12
  public static let cornerRadius: CGFloat = 8
  public static let toolbarHeight: CGFloat = 42
}
@MainActor public final class ThemeStore: ObservableObject {
  public static let preferenceKey = "studio.appearance.mode"
  public static let shared = ThemeStore()
  private let defaults: UserDefaults
  private let applyToApplication: Bool
  @Published public var mode: ThemeMode {
    didSet {
      defaults.set(mode.rawValue, forKey: Self.preferenceKey)
      apply()
    }
  }
  public init(defaults: UserDefaults? = nil, applyToApplication: Bool = true) {
    let smoke = ProcessInfo.processInfo.environment["PLANTUML_STUDIO_SMOKE_DIR"] != nil
    self.defaults =
      defaults ?? (smoke ? UserDefaults(suiteName: "PlantUMLStudio.AppearanceSmoke")! : .standard)
    self.applyToApplication = applyToApplication
    mode = ThemeMode(rawValue: self.defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
    apply()
  }
  public var effectiveDark: Bool {
    mode.resolved(
      systemDark: NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        == .darkAqua)
  }
  private func apply() {
    guard applyToApplication else { return }
    switch mode {
    case .system: NSApplication.shared.appearance = nil
    case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
    case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }
  }
}
