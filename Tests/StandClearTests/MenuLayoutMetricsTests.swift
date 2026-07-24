@testable import StandClear
import XCTest

final class MenuLayoutMetricsTests: XCTestCase {
    func testMenuMetricsUseExpectedMenuSize() {
        let metrics = MenuLayoutMetrics()

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

    func testMenuMetricsFitEightNormalArrivalRows() {
        let metrics = MenuLayoutMetrics()

        XCTAssertLessThanOrEqual(metrics.directionHeaderHeight, 28)
        XCTAssertLessThanOrEqual(metrics.arrivalRowHeight, 44)
        XCTAssertGreaterThanOrEqual(metrics.normalArrivalCapacity, 8)
        XCTAssertGreaterThanOrEqual(
            metrics.normalArrivalContentHeight,
            metrics.arrivalRowHeight * 8
        )
    }

    func testMenuMetricsAreAllPositive() {
        let metrics = MenuLayoutMetrics()

        let sizedMetrics: [CGFloat] = [
            metrics.headerHeight,
            metrics.footerHeight,
            metrics.sectionHorizontalPadding,
            metrics.arrivalRowHeight,
            metrics.arrivalTextSpacing,
            metrics.arrivalRouteBulletSize,
            metrics.arrivalDirectionArrowFontSize,
            metrics.arrivalDestinationFontSize,
            metrics.arrivalStatusFontSize,
            metrics.arrivalPinHeight,
            metrics.arrivalETAFontSize,
            metrics.settingsDirectionButtonHeight,
            metrics.settingsRouteBulletSize,
            metrics.settingsCTAHeight,
        ]

        for value in sizedMetrics {
            XCTAssertGreaterThan(value, 0)
        }
    }
}
