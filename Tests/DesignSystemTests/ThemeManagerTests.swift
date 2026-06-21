import XCTest
import SwiftUI
@testable import DesignSystem

@MainActor
final class ThemeManagerTests: XCTestCase {

    /// A fresh, isolated UserDefaults suite per test so persistence doesn't leak between runs.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString) ?? .standard
    }

    func testDefaultsToProvidedPresetWhenStoreEmpty() {
        let manager = ThemeManager(default: .traderDark, defaults: makeDefaults())
        XCTAssertEqual(manager.preset, .traderDark)
    }

    func testThemeMatchesSelectedPreset() {
        let manager = ThemeManager(default: .warmGold, defaults: makeDefaults())
        XCTAssertEqual(manager.theme.accent.description, ThemePreset.warmGold.theme.accent.description)
    }

    func testSelectPersistsAcrossManagers() {
        let defaults = makeDefaults()
        let key = "DesignSystem.selectedTheme"

        let first = ThemeManager(defaults: defaults, storageKey: key)
        first.select(.traderDark)
        XCTAssertEqual(first.preset, .traderDark)

        // A new manager on the same store should restore the persisted selection.
        let second = ThemeManager(default: .fintechNavy, defaults: defaults, storageKey: key)
        XCTAssertEqual(second.preset, .traderDark)
        XCTAssertEqual(second.theme.accent.description, ThemePreset.traderDark.theme.accent.description)
    }

    func testInvalidStoredValueFallsBackToDefault() {
        let defaults = makeDefaults()
        let key = "DesignSystem.selectedTheme"
        defaults.set("not-a-real-preset", forKey: key)

        let manager = ThemeManager(default: .warmGold, defaults: defaults, storageKey: key)
        XCTAssertEqual(manager.preset, .warmGold)
    }

    func testSelectWritesRawValueToStore() {
        let defaults = makeDefaults()
        let key = "DesignSystem.selectedTheme"

        let manager = ThemeManager(defaults: defaults, storageKey: key)
        manager.select(.warmGold)
        XCTAssertEqual(defaults.string(forKey: key), ThemePreset.warmGold.rawValue)
    }

    func testAvailableThemesCoversAllPresets() {
        let manager = ThemeManager(defaults: makeDefaults())
        XCTAssertEqual(Set(manager.availableThemes), Set(ThemePreset.allCases))
    }

    func testAllPresetRawValuesRoundTrip() {
        for preset in ThemePreset.allCases {
            XCTAssertEqual(ThemePreset(rawValue: preset.rawValue), preset)
        }
    }
}
