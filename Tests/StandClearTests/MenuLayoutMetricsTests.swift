@testable import StandClear
import XCTest

final class MenuLayoutMetricsTests: XCTestCase {
    func testStandardProfilePreservesCurrentMenuSize() {
        let metrics = MenuLayoutMetrics(density: .standard)

        XCTAssertEqual(metrics.frameWidth, 420)
        XCTAssertEqual(metrics.frameHeight, 610)
        XCTAssertEqual(metrics.headerHeight, 62)
        XCTAssertEqual(metrics.arrivalRowHeight, 72)
    }

    func testCompactProfileUsesRequestedMenuSize() {
        let metrics = MenuLayoutMetrics(density: .compact)

        XCTAssertEqual(metrics.frameWidth, 340)
        XCTAssertEqual(metrics.frameHeight, 480)
        XCTAssertEqual(metrics.headerHeight, 50)
        XCTAssertEqual(metrics.footerHeight, 36)
        XCTAssertEqual(metrics.arrivalRouteBulletSize, 32)
        XCTAssertEqual(metrics.arrivalDirectionArrowFontSize, 26)
        XCTAssertEqual(metrics.arrivalDirectionArrowColumnWidth, 24)
        XCTAssertEqual(metrics.arrivalDestinationFontSize, 11)
        XCTAssertEqual(metrics.arrivalStatusFontSize, 8)
        XCTAssertEqual(metrics.arrivalPinHeight, 36)
        XCTAssertEqual(metrics.arrivalETAHeight, 36)
        XCTAssertEqual(metrics.arrivalRowItemSpacing, 8)
        XCTAssertEqual(metrics.arrivalTextSpacing, 2)
        XCTAssertTrue((12 ... 14).contains(metrics.arrivalRowHorizontalPadding))
    }

    func testCompactProfileFitsEightNormalArrivalRows() {
        let metrics = MenuLayoutMetrics(density: .compact)

        XCTAssertLessThanOrEqual(metrics.directionHeaderHeight, 28)
        XCTAssertLessThanOrEqual(metrics.arrivalRowHeight, 44)
        XCTAssertGreaterThanOrEqual(metrics.normalArrivalCapacity, 8)
        XCTAssertGreaterThanOrEqual(
            metrics.normalArrivalContentHeight,
            metrics.arrivalRowHeight * 8
        )
    }

    func testCompactProfileUsesPositiveSmallerDensityMetrics() {
        let standard = MenuLayoutMetrics(density: .standard)
        let compact = MenuLayoutMetrics(density: .compact)

        let pairedMetrics: [(compact: CGFloat, standard: CGFloat)] = [
            (compact.headerHeight, standard.headerHeight),
            (compact.footerHeight, standard.footerHeight),
            (compact.sectionHorizontalPadding, standard.sectionHorizontalPadding),
            (compact.arrivalRowHeight, standard.arrivalRowHeight),
            (compact.arrivalTextSpacing, standard.arrivalTextSpacing),
            (compact.arrivalRouteBulletSize, standard.arrivalRouteBulletSize),
            (compact.arrivalDirectionArrowFontSize, standard.arrivalDirectionArrowFontSize),
            (compact.arrivalDestinationFontSize, standard.arrivalDestinationFontSize),
            (compact.arrivalStatusFontSize, standard.arrivalStatusFontSize),
            (compact.arrivalPinHeight, standard.arrivalPinHeight),
            (compact.arrivalETAFontSize, standard.arrivalETAFontSize),
            (compact.settingsDirectionButtonHeight, standard.settingsDirectionButtonHeight),
            (compact.settingsRouteBulletSize, standard.settingsRouteBulletSize),
            (compact.settingsCTAHeight, standard.settingsCTAHeight),
        ]

        for pair in pairedMetrics {
            XCTAssertGreaterThan(pair.compact, 0)
            XCTAssertLessThan(pair.compact, pair.standard)
        }
    }
}
