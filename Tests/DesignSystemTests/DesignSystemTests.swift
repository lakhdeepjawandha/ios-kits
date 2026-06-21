import XCTest
import SwiftUI
@testable import DesignSystem

// MARK: - Token tests

final class SpacingTokenTests: XCTestCase {

    func testSpacingOrder() {
        XCTAssertLessThan(DS.Spacing.xs, DS.Spacing.sm)
        XCTAssertLessThan(DS.Spacing.sm, DS.Spacing.md)
        XCTAssertLessThan(DS.Spacing.md, DS.Spacing.lg)
        XCTAssertLessThan(DS.Spacing.lg, DS.Spacing.xl)
    }

    func testSpacingValues() {
        XCTAssertEqual(DS.Spacing.xs, 4)
        XCTAssertEqual(DS.Spacing.sm, 8)
        XCTAssertEqual(DS.Spacing.md, 16)
        XCTAssertEqual(DS.Spacing.lg, 24)
        XCTAssertEqual(DS.Spacing.xl, 40)
    }
}

final class RadiusTokenTests: XCTestCase {

    func testRadiusOrder() {
        XCTAssertLessThan(DS.Radius.sm, DS.Radius.md)
        XCTAssertLessThan(DS.Radius.md, DS.Radius.lg)
        XCTAssertLessThan(DS.Radius.lg, DS.Radius.pill)
    }

    func testRadiusValues() {
        XCTAssertEqual(DS.Radius.sm, 8)
        XCTAssertEqual(DS.Radius.md, 14)
        XCTAssertEqual(DS.Radius.lg, 22)
        XCTAssertGreaterThan(DS.Radius.pill, 999)
    }
}

final class FontSizeTokenTests: XCTestCase {

    func testFontSizeOrder() {
        XCTAssertLessThan(DS.FontSize.overline, DS.FontSize.caption)
        XCTAssertLessThan(DS.FontSize.caption, DS.FontSize.subheadline)
        XCTAssertLessThan(DS.FontSize.subheadline, DS.FontSize.body)
        XCTAssertLessThan(DS.FontSize.body, DS.FontSize.callout)
        XCTAssertLessThan(DS.FontSize.callout, DS.FontSize.title)
        XCTAssertLessThan(DS.FontSize.title, DS.FontSize.title2)
        XCTAssertLessThan(DS.FontSize.title2, DS.FontSize.largeTitle)
        XCTAssertLessThan(DS.FontSize.largeTitle, DS.FontSize.display)
    }

    func testBodyFontSize() {
        XCTAssertEqual(DS.FontSize.body, 17)
    }

    func testCaptionFontSize() {
        XCTAssertEqual(DS.FontSize.caption, 13)
    }

    func testLargeTitleFontSize() {
        XCTAssertEqual(DS.FontSize.largeTitle, 34)
    }
}

final class ShadowTokenTests: XCTestCase {

    func testShadowRadiiOrder() {
        XCTAssertLessThan(DS.Shadow.smRadius, DS.Shadow.mdRadius)
        XCTAssertLessThan(DS.Shadow.mdRadius, DS.Shadow.lgRadius)
    }

    func testShadowYOffsetOrder() {
        XCTAssertLessThan(DS.Shadow.smY, DS.Shadow.mdY)
        XCTAssertLessThan(DS.Shadow.mdY, DS.Shadow.lgY)
    }
}

final class AnimationTokenTests: XCTestCase {

    func testAnimationDurationOrder() {
        XCTAssertLessThan(DS.Animation.fast, DS.Animation.standard)
        XCTAssertLessThan(DS.Animation.standard, DS.Animation.slow)
    }

    func testFastAnimationDuration() {
        XCTAssertEqual(DS.Animation.fast, 0.15, accuracy: 0.001)
    }
}

// MARK: - Theme tests

final class ThemeDefaultsTests: XCTestCase {

    func testDefaultThemeCreation() {
        let theme = Theme()
        // Just ensure all properties are accessible without crashing
        _ = theme.accent
        _ = theme.background
        _ = theme.surface
        _ = theme.textPrimary
        _ = theme.textSecondary
        _ = theme.positive
        _ = theme.negative
        _ = theme.warning
        _ = theme.separator
    }

    func testCustomThemeRoundtrip() {
        let theme = Theme(
            accent: .blue,
            background: .black,
            surface: .gray,
            textPrimary: .white,
            textSecondary: .gray,
            positive: .green,
            negative: .red,
            warning: .orange,
            separator: .gray
        )
        // Verify the struct stores values (colour equality via description)
        XCTAssertEqual(theme.accent.description, Color.blue.description)
        XCTAssertEqual(theme.negative.description, Color.red.description)
    }
}

// MARK: - ThemePreset tests

final class ThemePresetTests: XCTestCase {

    func testAllPresetsHaveDistinctAccents() {
        let navy  = ThemePreset.fintechNavy.theme.accent.description
        let dark  = ThemePreset.traderDark.theme.accent.description
        let gold  = ThemePreset.warmGold.theme.accent.description
        XCTAssertNotEqual(navy, dark)
        XCTAssertNotEqual(dark, gold)
        XCTAssertNotEqual(navy, gold)
    }

    func testEachPresetBuildsWithoutCrash() {
        _ = ThemePreset.fintechNavy.theme
        _ = ThemePreset.traderDark.theme
        _ = ThemePreset.warmGold.theme
    }
}

// MARK: - Component build tests
// These tests verify that each component can be instantiated without crashing.
// SwiftUI View construction is evaluated lazily, so creating the view body is sufficient.

final class ComponentBuildTests: XCTestCase {

    func testPrimaryButtonBuilds() {
        let view = PrimaryButton("Tap me") {}
        _ = view.body
    }

    func testSecondaryButtonBuilds() {
        let view = SecondaryButton("Tap me") {}
        _ = view.body
    }

    func testCardBuilds() {
        let view = Card { Text("Content") }
        _ = view.body
    }

    func testSectionHeaderBuilds() {
        let a = SectionHeader("Title")
        let b = SectionHeader("Title", action: ("See All", {}))
        _ = a.body
        _ = b.body
    }

    func testListRowBuilds() {
        let a = ListRow(title: "Item")
        let b = ListRow(icon: "star", title: "Item", subtitle: "Sub", value: "$1.00", valueColor: .green)
        _ = a.body
        _ = b.body
    }

    func testChipBuilds() {
        let a = Chip("Tag")
        let b = Chip("LIVE", style: .filled, icon: "circle.fill")
        let c = Chip("ETF", style: .outlined)
        _ = a.body; _ = b.body; _ = c.body
    }

    func testMetricCardBuilds() {
        let a = MetricCard(value: "$100", label: "Value")
        let b = MetricCard(value: "10%", label: "Return", delta: "+2%", isPositive: true, icon: "chart.pie")
        _ = a.body; _ = b.body
    }

    func testEmptyStateViewBuilds() {
        let a = EmptyStateView(icon: "tray", title: "Empty", message: "Nothing here.")
        let b = EmptyStateView(icon: "tray", title: "Empty", message: "Nothing here.", cta: ("Add", {}))
        _ = a.body; _ = b.body
    }

    func testShimmerListRowBuilds() {
        let view = ShimmerListRow()
        _ = view.body
    }

    func testShimmerMetricCardBuilds() {
        let view = ShimmerMetricCard()
        _ = view.body
    }

    func testBannerBuilds() {
        let a = Banner("Info message")
        let b = Banner("Success", severity: .success, isDismissible: true)
        let c = Banner("Warning", severity: .warning, action: ("Fix", {}))
        let d = Banner("Error", severity: .error, isDismissible: true)
        _ = a.body; _ = b.body; _ = c.body; _ = d.body
    }

    func testDSSegmentedControlBuilds() {
        var sel = 0
        let binding = Binding(get: { sel }, set: { sel = $0 })
        let view = DSSegmentedControl(selection: binding, segments: ["A", "B", "C"])
        _ = view.body
    }
}

// MARK: - Banner severity tests

final class BannerSeverityTests: XCTestCase {

    func testAllSeveritiesHaveIcons() {
        let severities: [BannerSeverity] = [.info, .success, .warning, .error]
        let theme = Theme()
        for severity in severities {
            XCTAssertFalse(severity.icon.isEmpty, "\(severity) should have an icon")
            _ = severity.foreground(theme)  // must not crash
        }
    }

    func testSeverityIconsAreDistinct() {
        XCTAssertNotEqual(BannerSeverity.info.icon, BannerSeverity.success.icon)
        XCTAssertNotEqual(BannerSeverity.warning.icon, BannerSeverity.error.icon)
    }
}

// MARK: - Chip style tests

final class ChipStyleTests: XCTestCase {

    func testAllChipStylesBuild() {
        _ = Chip("x", style: .filled).body
        _ = Chip("x", style: .outlined).body
        _ = Chip("x", style: .tinted).body
    }
}
