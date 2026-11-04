@testable import App
import XCTest

final class ProviderTabFlowLayoutTests: XCTestCase {
    func testRows_isEmptyWithoutTabs() {
        XCTAssertEqual(ProviderTabFlowLayout.rows(for: [], containerWidth: 248, spacing: 6), [])
    }

    func testRows_keepsShortTabsTogetherInOneRow() {
        let rows = ProviderTabFlowLayout.rows(for: [70, 70, 70], containerWidth: 248, spacing: 6)

        XCTAssertEqual(rows, [[0, 1, 2]])
    }

    func testRows_wrapsATabThatDoesNotFit() {
        let rows = ProviderTabFlowLayout.rows(for: [100, 90, 110, 80], containerWidth: 248, spacing: 6)

        XCTAssertEqual(rows, [[0, 1], [2, 3]])
    }

    func testRows_countsTheSpacingBetweenTabs() {
        let fitsExactly = ProviderTabFlowLayout.rows(for: [121, 121], containerWidth: 248, spacing: 6)
        let onePointOver = ProviderTabFlowLayout.rows(for: [121, 122], containerWidth: 248, spacing: 6)

        XCTAssertEqual(fitsExactly, [[0, 1]])
        XCTAssertEqual(onePointOver, [[0], [1]])
    }

    func testRows_keepsATabWiderThanTheRowOnItsOwnRow() {
        let rows = ProviderTabFlowLayout.rows(for: [300, 60], containerWidth: 248, spacing: 6)

        XCTAssertEqual(rows, [[0], [1]])
    }

    func testMaxTabWidth_isHalfTheRowMinusTheSpacing() {
        XCTAssertEqual(ProviderTabFlowLayout.maxTabWidth(containerWidth: 248, spacing: 6), 121)
    }

    func testMaxTabWidth_neverGoesBelowZero() {
        XCTAssertEqual(ProviderTabFlowLayout.maxTabWidth(containerWidth: 0, spacing: 6), 0)
    }

    func testTwoTabsAtTheMaximumWidthShareARow() {
        let maxWidth = ProviderTabFlowLayout.maxTabWidth(containerWidth: 248, spacing: 6)

        let rows = ProviderTabFlowLayout.rows(for: [maxWidth, maxWidth], containerWidth: 248, spacing: 6)

        XCTAssertEqual(rows, [[0, 1]])
    }
}
