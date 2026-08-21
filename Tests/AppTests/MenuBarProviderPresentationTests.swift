@testable import App
import AppKit
import Core
import Foundation
import XCTest

final class MenuBarProviderPresentationTests: XCTestCase {
    func testWindowPresentationUsesSelectedProviderGlyphAndFastStatus() throws {
        let resolved = try XCTUnwrap(
            MenuBarProviderPresentation.resolve(
                providerInfo: providerInfo(id: "first", glyph: .sfSymbol("sparkles")),
                providerState: loadedState(for: "first", isBalance: false),
                isFastRefreshActive: true
            )
        )

        XCTAssertEqual(resolved.status, .window(percentage: 20))
        XCTAssertTrue(resolved.isFastRefreshActive)
        XCTAssertEqual(symbolName(for: resolved.glyph), "sparkles")
        XCTAssertTrue(MenuBarProviderPresentation.accessibilityLabel(for: resolved).contains("Fast refresh active"))
    }

    func testBalancePresentationUsesSelectedProviderGlyphWithoutFastStatus() throws {
        let resolved = try XCTUnwrap(
            MenuBarProviderPresentation.resolve(
                providerInfo: providerInfo(id: "balance", glyph: .sfSymbol("dollarsign")),
                providerState: loadedState(for: "balance", isBalance: true),
                isFastRefreshActive: false
            )
        )

        guard case .balance = resolved.status else {
            return XCTFail("Expected balance presentation")
        }
        XCTAssertFalse(resolved.isFastRefreshActive)
        XCTAssertEqual(symbolName(for: resolved.glyph), "dollarsign")
        XCTAssertFalse(MenuBarProviderPresentation.accessibilityLabel(for: resolved).contains("Fast refresh active"))
    }

    func testChangingSelectedProviderChangesTheGlyphWithTheStatus() throws {
        let first = try XCTUnwrap(
            MenuBarProviderPresentation.resolve(
                providerInfo: providerInfo(id: "first", glyph: .sfSymbol("1.circle")),
                providerState: loadedState(for: "first", isBalance: false),
                isFastRefreshActive: false
            )
        )
        let second = try XCTUnwrap(
            MenuBarProviderPresentation.resolve(
                providerInfo: providerInfo(id: "second", glyph: .sfSymbol("2.circle")),
                providerState: loadedState(for: "second", isBalance: true),
                isFastRefreshActive: true
            )
        )

        XCTAssertEqual(symbolName(for: first.glyph), "1.circle")
        XCTAssertEqual(first.status, .window(percentage: 20))
        XCTAssertEqual(symbolName(for: second.glyph), "2.circle")
        guard case .balance = second.status else {
            return XCTFail("Expected balance presentation")
        }
    }

    func testVintageMacPresentationRetainsTheSelectedProviderGlyph() throws {
        let resolved = try XCTUnwrap(
            MenuBarProviderPresentation.resolve(
                providerInfo: providerInfo(id: "vintage", glyph: .sfSymbol("desktopcomputer")),
                providerState: loadedState(for: "vintage", isBalance: false),
                isFastRefreshActive: false
            )
        )

        XCTAssertEqual(symbolName(for: resolved.glyph), "desktopcomputer")
        XCTAssertEqual(QuotaStatusResolver.tier(for: resolved.status), .good)
    }

    func testUnselectedFastProviderDoesNotAddFastStatusToTheSelectedPresentation() throws {
        let resolved = try XCTUnwrap(
            MenuBarProviderPresentation.resolve(
                providerInfo: providerInfo(id: "selected", glyph: .sfSymbol("sparkles")),
                providerState: loadedState(for: "selected", isBalance: false),
                isFastRefreshActive: false
            )
        )

        XCTAssertFalse(resolved.isFastRefreshActive)
        XCTAssertFalse(MenuBarProviderPresentation.accessibilityLabel(for: resolved).contains("Fast refresh active"))
    }

    func testMissingAssetUsesNeutralGlyphFallback() {
        XCTAssertEqual(
            MenuBarProviderGlyphResolver.fallbackSymbolName(
                for: .asset(name: "MissingMenuBarGlyph", bundle: .main)
            ),
            "cpu"
        )
    }

    func testMenuBarGlyphRendersAsABitmapTemplateImage() {
        let image = MenuBarProviderGlyphResolver.menuBarImage(
            for: .sfSymbol("sparkles"),
            isFastRefreshActive: false
        )

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(
            image.size,
            CGSize(
                width: MenuBarProviderGlyphResolver.identityCanvasSide,
                height: MenuBarProviderGlyphResolver.identityCanvasSide
            )
        )
        XCTAssertFalse(image.representations.isEmpty)
    }

    func testFastRefreshOverlapsTheGlyphAtTheTopRight() {
        let image = MenuBarProviderGlyphResolver.menuBarImage(
            for: .sfSymbol("sparkles"),
            isFastRefreshActive: true
        )

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(
            image.size,
            CGSize(
                width: MenuBarProviderGlyphResolver.identityCanvasSide,
                height: MenuBarProviderGlyphResolver.identityCanvasSide
            )
        )
        XCTAssertEqual(
            MenuBarProviderGlyphResolver.menuBarImageSize(isFastRefreshActive: true).width,
            MenuBarProviderGlyphResolver.menuBarImageSize(isFastRefreshActive: false).width
        )
        XCTAssertEqual(
            MenuBarProviderGlyphResolver.glyphRect,
            CGRect(x: 1, y: 1, width: 12, height: 12)
        )
        XCTAssertEqual(
            MenuBarProviderGlyphResolver.fastIndicatorRect,
            CGRect(x: 7, y: 7, width: 7, height: 7)
        )
        XCTAssertTrue(
            MenuBarProviderGlyphResolver.glyphRect.intersects(
                MenuBarProviderGlyphResolver.fastIndicatorRect
            )
        )
        XCTAssertEqual(
            MenuBarProviderGlyphResolver.fastIndicatorClearanceRect,
            CGRect(x: 6, y: 6, width: 8, height: 8)
        )
        XCTAssertFalse(image.representations.isEmpty)
    }

    func testFallbackProviderStateDoesNotCreateProviderPresentation() {
        XCTAssertNil(
            MenuBarProviderPresentation.resolve(
                providerInfo: providerInfo(id: "fallback", glyph: .sfSymbol("sparkles")),
                providerState: loadedState(for: "fallback", isBalance: false, isDisplayable: false),
                isFastRefreshActive: true
            )
        )
    }

    private func providerInfo(id: String, glyph: ProviderGlyph) -> ProviderInfo {
        ProviderInfo(
            id: id,
            displayName: id,
            glyph: glyph,
            description: "Test provider",
            defaultBaseURL: URL(string: "https://example.com")!,
            authShape: .apiKey
        )
    }

    private func loadedState(
        for providerId: String,
        isBalance: Bool,
        isDisplayable: Bool = true
    ) -> ProviderState {
        let lines: [UsageLine] = if !isDisplayable {
            []
        } else if isBalance {
            [UsageLine(label: "Balance", total: 12.34, unit: "USD")]
        } else {
            [UsageLine(label: "Window", percentage: 20)]
        }
        return .loaded(
            ProviderQuota(
                providerId: providerId,
                providerName: providerId,
                headline: "",
                lines: lines,
                lastUpdated: .distantPast
            )
        )
    }

    private func symbolName(for glyph: ProviderGlyph) -> String? {
        guard case let .sfSymbol(name) = glyph else { return nil }
        return name
    }
}
