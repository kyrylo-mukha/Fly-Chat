import XCTest
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
}
