import XCTest
import SwiftUI
@testable import FlyChat

@MainActor
final class FCLVisualStyleTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultsDeliverLiquidGlass() {
        XCTAssertEqual(FCLVisualStyleDefaults.style, .liquidGlass)
        XCTAssertNil(FCLVisualStyleDefaults.tint)
        XCTAssertEqual(
            FCLVisualStyleDefaults.reducedTransparencyBackground,
            FCLChatColorToken(red: 0.93, green: 0.94, blue: 0.96)
        )
    }

    // MARK: - Resolver precedence

    func testExplicitOverridesDelegate() {
        let resolved = FCLVisualStyleResolver.resolve(
            explicit: .default,
            delegate: .liquidGlass,
            reduceTransparency: false
        )
        XCTAssertEqual(resolved, .opaque)
    }

    func testDelegateUsedWhenNoExplicit() {
        let resolved = FCLVisualStyleResolver.resolve(
            explicit: nil,
            delegate: .default,
            reduceTransparency: false
        )
        XCTAssertEqual(resolved, .opaque)
    }

    func testDefaultLiquidGlassResolvesToGlassBranch() {
        let resolved = FCLVisualStyleResolver.resolve(
            explicit: nil,
            delegate: FCLVisualStyleDefaults.style,
            reduceTransparency: false
        )
        #if os(iOS)
        if #available(iOS 26, *) {
            XCTAssertEqual(resolved, .liquidGlassNative)
        } else {
            XCTAssertEqual(resolved, .liquidGlassFallback)
        }
        #else
        XCTAssertEqual(resolved, .liquidGlassFallback)
        #endif
    }

    func testSystemStyleResolvesToNativeOrOpaque() {
        let resolved = FCLVisualStyleResolver.resolve(
            explicit: .system,
            delegate: .liquidGlass,
            reduceTransparency: false
        )
        #if os(iOS)
        if #available(iOS 26, *) {
            XCTAssertEqual(resolved, .liquidGlassNative)
        } else {
            XCTAssertEqual(resolved, .opaque)
        }
        #else
        XCTAssertEqual(resolved, .opaque)
        #endif
    }

    func testReduceTransparencyCollapsesToOpaque() {
        let resolved = FCLVisualStyleResolver.resolve(
            explicit: .liquidGlass,
            delegate: .liquidGlass,
            reduceTransparency: true
        )
        XCTAssertEqual(resolved, .opaque)
    }

    // MARK: - Delegate defaults via protocol extensions

    private final class EmptyVisualDelegate: FCLVisualStyleDelegate {}

    func testProtocolExtensionsDeliverLibraryDefaults() {
        let delegate = EmptyVisualDelegate()
        XCTAssertEqual(delegate.style, FCLVisualStyleDefaults.style)
        XCTAssertNil(delegate.tint)
        XCTAssertEqual(
            delegate.reducedTransparencyBackground,
            FCLVisualStyleDefaults.reducedTransparencyBackground
        )
    }

    // MARK: - FCLChatDelegate sub-delegate wiring

    private final class EmptyChatDelegate: FCLChatDelegate {}

    func testChatDelegateReturnsNilVisualStyleByDefault() {
        let delegate = EmptyChatDelegate()
        XCTAssertNil(delegate.visualStyle)
    }

    // MARK: - accessibilityShowButtonShapes rim stroke

    func testGlassButtonEffectiveRimStrokeOffWhenShowButtonShapesFalse() {
        let color = FCLGlassButton<Text>.effectiveRimStroke(
            showButtonShapes: false,
            tint: nil
        )
        XCTAssertNil(color, "No rim stroke should be produced when showButtonShapes is false")
    }

    func testGlassButtonEffectiveRimStrokeOnWhenShowButtonShapesTrue() {
        let color = FCLGlassButton<Text>.effectiveRimStroke(
            showButtonShapes: true,
            tint: nil
        )
        XCTAssertNotNil(color, "A rim stroke color must be produced when showButtonShapes is true")
    }

    func testGlassButtonEffectiveRimStrokeUsesTintWhenProvided() {
        let tint = FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0)
        let withTint = FCLGlassButton<Text>.effectiveRimStroke(
            showButtonShapes: true,
            tint: tint
        )
        let withoutTint = FCLGlassButton<Text>.effectiveRimStroke(
            showButtonShapes: true,
            tint: nil
        )
        XCTAssertNotNil(withTint)
        XCTAssertNotNil(withoutTint)
        // Both are non-nil; tint-based vs primary-based colors differ in value.
        XCTAssertNotEqual(withTint, withoutTint)
    }

    func testGlassIconButtonEffectiveRimStrokeOffWhenShowButtonShapesFalse() {
        let color = FCLGlassIconButton.effectiveRimStroke(
            showButtonShapes: false,
            tint: nil
        )
        XCTAssertNil(color, "No rim stroke should be produced when showButtonShapes is false")
    }

    func testGlassIconButtonEffectiveRimStrokeOnWhenShowButtonShapesTrue() {
        let color = FCLGlassIconButton.effectiveRimStroke(
            showButtonShapes: true,
            tint: nil
        )
        XCTAssertNotNil(color, "A rim stroke color must be produced when showButtonShapes is true")
    }

    func testGlassChipEffectiveRimStrokeOffWhenShowButtonShapesFalse() {
        let color = FCLGlassChip<EmptyView>.effectiveRimStroke(
            showButtonShapes: false,
            tint: nil
        )
        XCTAssertNil(color, "No rim stroke should be produced when showButtonShapes is false")
    }

    func testGlassChipEffectiveRimStrokeOnWhenShowButtonShapesTrue() {
        let color = FCLGlassChip<EmptyView>.effectiveRimStroke(
            showButtonShapes: true,
            tint: nil
        )
        XCTAssertNotNil(color, "A rim stroke color must be produced when showButtonShapes is true")
    }
}
