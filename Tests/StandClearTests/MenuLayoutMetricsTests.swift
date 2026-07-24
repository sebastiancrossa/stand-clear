@testable import StandClear
import XCTest

final class MenuLayoutMetricsTests: XCTestCase {
    func testStandardProfilePreservesCurrentMenuSize() {
        let metrics = MenuLayoutMetrics(density: .standard)

        XCTAssertEqual(metrics.frameWidth, 420)
        XCTAssertEqual(metrics.frameHeight, 610)
    }

    func testCompactProfileUsesRequestedMenuSize() {
        let metrics = MenuLayoutMetrics(density: .compact)

        XCTAssertEqual(metrics.frameWidth, 340)
        XCTAssertEqual(metrics.frameHeight, 480)
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
            (compact.outerHorizontalPadding, standard.outerHorizontalPadding),
            (compact.arrivalRowHeight, standard.arrivalRowHeight),
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
