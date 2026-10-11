import Foundation
import StudioDesign
import XCTest

final class DesignTests: XCTestCase {
  func testReadablePaletteInBothThemes() {
    for dark in [false, true] {
      for background in [
        DesignToken.background, .surface, .elevatedSurface, .selection, .activeLine, .diffAdded,
        .diffRemoved,
      ] {
        XCTAssertGreaterThanOrEqual(
          DesignToken.primaryText.value(dark: dark).contrast(with: background.value(dark: dark)),
          4.5)
      }
      for foreground in [
        DesignToken.secondaryText, .accent, .error, .warning, .success, .keyword, .participant,
        .message, .string, .comment,
      ] {
        for background in [DesignToken.surface, .background, .elevatedSurface] {
          XCTAssertGreaterThanOrEqual(
            foreground.value(dark: dark).contrast(with: background.value(dark: dark)), 4.5,
            "\(foreground) / \(background) / dark=\(dark)")
        }
      }
    }
  }
  func testSystemResolutionAndCSS() {
    XCTAssertFalse(ThemeMode.system.resolved(systemDark: false))
    XCTAssertTrue(ThemeMode.system.resolved(systemDark: true))
    XCTAssertFalse(ThemeMode.light.resolved(systemDark: true))
    XCTAssertTrue(ThemeMode.dark.resolved(systemDark: false))
    XCTAssertEqual(DesignToken.background.value(dark: true).css, "#172332")
  }
  @MainActor func testPersistedPreferenceAndFallback() async {
    let suite = "AppearanceTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = ThemeStore(defaults: defaults, applyToApplication: false)
    XCTAssertEqual(first.mode, .system)
    first.mode = .dark
    XCTAssertEqual(ThemeStore(defaults: defaults, applyToApplication: false).mode, .dark)
    first.mode = .light
    XCTAssertEqual(ThemeStore(defaults: defaults, applyToApplication: false).mode, .light)
    defaults.set("future-invalid-value", forKey: ThemeStore.preferenceKey)
    XCTAssertEqual(ThemeStore(defaults: defaults, applyToApplication: false).mode, .system)
  }
}
