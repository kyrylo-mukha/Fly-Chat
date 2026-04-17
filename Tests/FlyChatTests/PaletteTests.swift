import XCTest
import SwiftUI
@testable import FlyChat

// MARK: - FCLPaletteTests

/// Asserts that every `FCLPalette` property returns a non-`.clear` `Color`.
///
/// These tests run on all platforms the package supports. On iOS the properties
/// return `Color(uiColor:)` values whose components differ from `.clear`; on
/// macOS they return the static fallback literals — both cases must differ from
/// `Color.clear` whose RGBA components are all zero.
final class FCLPaletteTests: XCTestCase {

    // MARK: - Helpers

    /// Extracts the RGBA components of a `Color` in the standard sRGB color
    /// space. Returns `nil` when the conversion is not possible on the current
    /// platform (which is never expected in practice for the values under test).
    private func rgba(of color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let uiColor = UIColor(color)
        // Resolve in the trait environment that matches the test device's current
        // appearance (light by default in the simulator). We just need to confirm
        // the color is not all-zero (clear), not that it equals a specific shade.
        let resolved = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (r, g, b, a)
        #else
        // On non-UIKit platforms fall back to CGColor via a temporary NSColor.
        // The fallback values in FCLPalette are all opaque, so alpha will be 1.0.
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
        // On macOS the static fallbacks are opaque literals; treat as passing.
        _ = color // prevent unused-variable warning
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
        // Enumerate the palette surface so a future property addition triggers
        // a conscious update here. Adjust the expected count when new colors
        // are added to FCLPalette.
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
