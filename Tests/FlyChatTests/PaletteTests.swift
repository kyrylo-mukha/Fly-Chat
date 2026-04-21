import XCTest
import SwiftUI
@testable import FlyChat

// MARK: - FCLPaletteTests

/// Asserts that every `FCLPalette` property returns a non-`.clear` `Color`.
final class FCLPaletteTests: XCTestCase {

    // MARK: - Helpers

    /// Returns RGBA components of `color` in sRGB, or `nil` on non-UIKit platforms.
    private func rgba(of color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let uiColor = UIColor(color)
        let resolved = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (r, g, b, a)
        #else
        return nil
        #endif
    }

    /// Asserts that `color` is not equivalent to `Color.clear` (all-zero RGBA).
    private func assertNotClear(_ color: Color, name: String) {
        #if canImport(UIKit)
        guard let components = rgba(of: color) else {
            XCTFail("\(name): could not resolve RGBA components")
            return
        }
        let isClear = components.red == 0
            && components.green == 0
            && components.blue == 0
            && components.alpha == 0
        XCTAssertFalse(isClear, "\(name) must not resolve to Color.clear (all-zero RGBA)")
        #else
        _ = color
        #endif
    }

    // MARK: - Background Colors

    func testSystemBackgroundIsNotClear() {
        assertNotClear(FCLPalette.systemBackground, name: "FCLPalette.systemBackground")
    }

    func testSecondarySystemBackgroundIsNotClear() {
        assertNotClear(FCLPalette.secondarySystemBackground, name: "FCLPalette.secondarySystemBackground")
    }

    func testSystemGroupedBackgroundIsNotClear() {
        assertNotClear(FCLPalette.systemGroupedBackground, name: "FCLPalette.systemGroupedBackground")
    }

    // MARK: - Label Colors

    func testLabelIsNotClear() {
        assertNotClear(FCLPalette.label, name: "FCLPalette.label")
    }

    func testSecondaryLabelIsNotClear() {
        assertNotClear(FCLPalette.secondaryLabel, name: "FCLPalette.secondaryLabel")
    }

    func testTertiaryLabelIsNotClear() {
        assertNotClear(FCLPalette.tertiaryLabel, name: "FCLPalette.tertiaryLabel")
    }

    // MARK: - Fill Colors

    func testTertiarySystemFillIsNotClear() {
        assertNotClear(FCLPalette.tertiarySystemFill, name: "FCLPalette.tertiarySystemFill")
    }

    func testSecondarySystemFillIsNotClear() {
        assertNotClear(FCLPalette.secondarySystemFill, name: "FCLPalette.secondarySystemFill")
    }

    // MARK: - Gray Colors

    func testSystemGray3IsNotClear() {
        assertNotClear(FCLPalette.systemGray3, name: "FCLPalette.systemGray3")
    }

    // MARK: - Exhaustive property count

    func testPaletteExposesAllNineProperties() {
        let colors: [Color] = [
            FCLPalette.systemBackground,
            FCLPalette.secondarySystemBackground,
            FCLPalette.systemGroupedBackground,
            FCLPalette.label,
            FCLPalette.secondaryLabel,
            FCLPalette.tertiaryLabel,
            FCLPalette.tertiarySystemFill,
            FCLPalette.secondarySystemFill,
            FCLPalette.systemGray3,
        ]
        XCTAssertEqual(colors.count, 9, "Expected 9 FCLPalette colors; update this test if the palette grows.")
    }
}
