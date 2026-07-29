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

        XCTAssertLessThanOrEqual(metrics.directionBarHeight, 28)
        XCTAssertLessThanOrEqual(metrics.arrivalRowHeight, 44)
        XCTAssertGreaterThanOrEqual(metrics.normalArrivalCapacity, 8)
        XCTAssertGreaterThanOrEqual(
            metrics.normalArrivalContentHeight,
            metrics.arrivalRowHeight * 8
        )
    }

    /// The eight-row floor is a no-warning, no-alert guarantee. A collapsed service
    /// alert banner is allowed to cost one row, but no more than one.
    func testMenuMetricsFitSevenArrivalRowsBesideAnAlertBanner() {
        let metrics = MenuLayoutMetrics()

        XCTAssertLessThanOrEqual(metrics.alertBannerHeight, metrics.arrivalRowHeight)
        XCTAssertGreaterThanOrEqual(metrics.alertedArrivalCapacity, 7)
        XCTAssertGreaterThanOrEqual(
            metrics.alertedArrivalContentHeight,
            metrics.arrivalRowHeight * 7
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
            metrics.directionBarArrowFontSize,
            metrics.arrivalDestinationFontSize,
            metrics.arrivalStatusFontSize,
            metrics.arrivalPinHeight,
            metrics.arrivalETAFontSize,
            metrics.settingsControlHeight,
            metrics.settingsGroupSpacing,
            metrics.settingsGroupLabelFontSize,
            metrics.settingsFootnoteFontSize,
            metrics.settingsRouteBulletSize,
            metrics.settingsCTAHeight,
        ]

        for value in sizedMetrics {
            XCTAssertGreaterThan(value, 0)
        }
    }
}
