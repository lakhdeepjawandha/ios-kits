import XCTest
import SwiftUI
import DesignSystem
import PaywallKit
@testable import SettingsKit

// MARK: - Section / row model

final class SettingsModelTests: XCTestCase {

    func testSectionStoresHeaderFooterAndRows() {
        let section = SettingsSection(header: "About", footer: "Footer", rows: [
            SettingsRow(title: "A") { Text("A") },
            SettingsRow(title: "B") { Text("B") },
        ])
        XCTAssertEqual(section.header, "About")
        XCTAssertEqual(section.footer, "Footer")
        XCTAssertEqual(section.rows.count, 2)
        XCTAssertEqual(section.rows.map(\.title), ["A", "B"])
    }

    func testSectionDefaultsHaveNoHeaderOrFooter() {
        let section = SettingsSection(rows: [SettingsRow { Text("x") }])
        XCTAssertNil(section.header)
        XCTAssertNil(section.footer)
    }

    func testRowsHaveDistinctIdentity() {
        let a = SettingsRow { Text("a") }
        let b = SettingsRow { Text("b") }
        XCTAssertNotEqual(a.id, b.id)
    }

    func testRowBuilderFlattensExpressions() {
        let section = SettingsSection(header: "H") {
            SettingsRow(title: "1") { Text("1") }
            SettingsRow(title: "2") { Text("2") }
        }
        XCTAssertEqual(section.rows.map(\.title), ["1", "2"])
    }

    func testRowBuilderSupportsConditionalsAndLoops() {
        let includeExtra = false
        let section = SettingsSection {
            SettingsRow(title: "first") { Text("first") }
            if includeExtra {
                SettingsRow(title: "extra") { Text("extra") }
            }
            for index in 0..<3 {
                SettingsRow(title: "loop-\(index)") { Text("\(index)") }
            }
        }
        XCTAssertEqual(section.rows.map(\.title), ["first", "loop-0", "loop-1", "loop-2"])
    }

    func testSectionBuilderFlattensAndCounts() {
        let showDebug = true
        let sections: [SettingsSection] = SettingsSectionBuilderHarness.build {
            SettingsSection(header: "One") { SettingsRow { Text("a") } }
            if showDebug {
                SettingsSection(header: "Debug") { SettingsRow { Text("d") } }
            }
        }
        XCTAssertEqual(sections.map(\.header), ["One", "Debug"])
    }
}

/// Exercises ``SettingsSectionBuilder`` directly (the screen consumes it via its initializer).
private enum SettingsSectionBuilderHarness {
    static func build(@SettingsSectionBuilder _ sections: () -> [SettingsSection]) -> [SettingsSection] {
        sections()
    }
}

// MARK: - LinkRow mailto modeling

final class LinkRowMailtoTests: XCTestCase {

    func testMailtoBare() throws {
        let url = try XCTUnwrap(LinkRow.mailtoURL(email: "support@example.com"))
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertEqual(url.absoluteString, "mailto:support@example.com")
    }

    func testMailtoWithSubject() throws {
        let url = try XCTUnwrap(LinkRow.mailtoURL(email: "a@b.com", subject: "Need help"))
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:a@b.com?"))
        XCTAssertTrue(url.absoluteString.contains("subject=Need%20help"))
    }

    func testMailtoWithSubjectAndBody() throws {
        let url = try XCTUnwrap(LinkRow.mailtoURL(email: "a@b.com", subject: "Hi", body: "Line one"))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "subject" }?.value, "Hi")
        XCTAssertEqual(query.first { $0.name == "body" }?.value, "Line one")
    }
}

// MARK: - AppInfoFooter formatting

final class AppInfoFooterTests: XCTestCase {

    func testSummaryWithAppName() {
        let summary = AppInfoFooter.summary(appName: "My App", version: "1.2.3", build: "42",
                                            bundleID: "com.example.app")
        XCTAssertEqual(summary, "My App · Version 1.2.3 (42)\ncom.example.app")
    }

    func testSummaryWithoutAppName() {
        let summary = AppInfoFooter.summary(appName: nil, version: "2.0.0", build: "7",
                                            bundleID: "com.example.other")
        XCTAssertEqual(summary, "Version 2.0.0 (7)\ncom.example.other")
    }

    func testSummaryTreatsEmptyAppNameAsAbsent() {
        let summary = AppInfoFooter.summary(appName: "", version: "1.0", build: "1",
                                            bundleID: "id")
        XCTAssertEqual(summary, "Version 1.0 (1)\nid")
    }
}

// MARK: - View construction smoke tests

final class SettingsKitViewBuildTests: XCTestCase {

    @MainActor func testRowsAndScreenBuild() {
        let themeManager = ThemeManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let subscriptions = SubscriptionManager(productIDs: ["pro.yearly"])
        let isOn = Binding.constant(true)

        _ = ThemePickerRow(manager: themeManager).body
        _ = ToggleRow("Toggle", systemImage: "bell", isOn: isOn).body
        _ = ButtonRow("Button", role: .destructive) {}.body
        _ = NavigationLinkRow("Link") { Text("dest") }.body
        _ = ManageSubscriptionRow(manager: subscriptions).body
        _ = LinkRow("Privacy", url: URL(string: "https://example.com")!).body
        _ = LinkRow("Mail", email: "a@b.com", subject: "Hi").body
        _ = AppInfoFooter(appName: "Demo").body

        let screen = SettingsScreen {
            SettingsSection(header: "Appearance") {
                SettingsRow { ThemePickerRow(manager: themeManager) }
            }
            SettingsSection {
                SettingsRow { AppInfoFooter() }
            }
        }
        _ = screen.body
    }
}
