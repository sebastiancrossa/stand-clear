import SwiftUI

struct MenuLayoutMetrics: Equatable {
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let dividerThickness: CGFloat

    let headerHeight: CGFloat
    let headerHorizontalPadding: CGFloat
    let headerVerticalPadding: CGFloat
    let headerItemSpacing: CGFloat
    let headerTitleFontSize: CGFloat
    let headerSubtitleFontSize: CGFloat

    let footerHeight: CGFloat
    let footerHorizontalPadding: CGFloat
    let footerItemSpacing: CGFloat
    let footerFontSize: CGFloat

    let sectionHorizontalPadding: CGFloat
    let sectionTopPadding: CGFloat
    let sectionBottomPadding: CGFloat
    let sectionSpacing: CGFloat
    let directionBarHeight: CGFloat
    let directionBarFontSize: CGFloat
    let directionBarArrowFontSize: CGFloat

    let arrivalRowHeight: CGFloat
    let arrivalRowHorizontalPadding: CGFloat
    let arrivalRowVerticalPadding: CGFloat
    let arrivalRowItemSpacing: CGFloat
    let arrivalTextSpacing: CGFloat
    let arrivalRouteBulletSize: CGFloat
    let arrivalDestinationFontSize: CGFloat
    let arrivalStatusFontSize: CGFloat
    let arrivalPinFontSize: CGFloat
    let arrivalPinWidth: CGFloat
    let arrivalPinHeight: CGFloat
    let arrivalETAFontSize: CGFloat
    let arrivalETAMinWidth: CGFloat
    let arrivalETAHeight: CGFloat

    let settingsContentPadding: CGFloat
    let settingsItemSpacing: CGFloat
    let settingsBodyFontSize: CGFloat

    let settingsGroupSpacing: CGFloat
    let settingsGroupLabelFontSize: CGFloat
    let settingsGroupLabelTracking: CGFloat
    let settingsGroupLabelSpacing: CGFloat
    let settingsFootnoteFontSize: CGFloat
    let settingsFootnoteSpacing: CGFloat

    let settingsControlHeight: CGFloat
    let settingsControlCornerRadius: CGFloat
    let settingsControlInset: CGFloat
    let settingsSegmentFontSize: CGFloat
    let settingsSegmentHorizontalPadding: CGFloat
    let settingsFocusRingWidth: CGFloat
    let settingsFocusRingInset: CGFloat

    let settingsRouteBulletSize: CGFloat
    let settingsRouteRowSpacing: CGFloat
    let settingsRouteItemSpacing: CGFloat
    let settingsRouteGroupSpacing: CGFloat
    let settingsRouteBadgeSize: CGFloat
    let settingsRouteBadgeFontSize: CGFloat
    let settingsCTAHeight: CGFloat
    let settingsCTAFontSize: CGFloat

    let alertBannerHeight: CGFloat
    let alertBannerFontSize: CGFloat
    let alertCardSpacing: CGFloat
    let alertCardPadding: CGFloat
    let alertCardCornerRadius: CGFloat
    let alertCardTextSpacing: CGFloat
    let alertCardTypeFontSize: CGFloat
    let alertCardBodyFontSize: CGFloat
    let alertCardMetaFontSize: CGFloat
    let alertCardBulletSize: CGFloat
    let alertPeriodPadding: CGFloat
    let alertPeriodCornerRadius: CGFloat

    let emptyStateSpacing: CGFloat
    let emptyStateIconFontSize: CGFloat
    let emptyStateTitleFontSize: CGFloat
    let emptyStateBodyFontSize: CGFloat

    let statusSpacing: CGFloat
    let statusIconFontSize: CGFloat
    let statusTitleFontSize: CGFloat
    let statusBodyFontSize: CGFloat
    let statusContentPadding: CGFloat
    let statusMaxWidth: CGFloat

    init() {
        frameWidth = 340
        frameHeight = 480
        dividerThickness = 1
        headerHeight = 50
        headerHorizontalPadding = 12
        headerVerticalPadding = 9
        headerItemSpacing = 8
        headerTitleFontSize = 13
        headerSubtitleFontSize = 8
        footerHeight = 36
        footerHorizontalPadding = 12
        footerItemSpacing = 8
        footerFontSize = 10
        sectionHorizontalPadding = 12
        sectionTopPadding = 8
        sectionBottomPadding = 4
        sectionSpacing = 8
        directionBarHeight = 28
        directionBarFontSize = 10
        directionBarArrowFontSize = 11
        arrivalRowHeight = 44
        arrivalRowHorizontalPadding = 12
        arrivalRowVerticalPadding = 4
        arrivalRowItemSpacing = 8
        arrivalTextSpacing = 2
        arrivalRouteBulletSize = 32
        arrivalDestinationFontSize = 11
        arrivalStatusFontSize = 8
        arrivalPinFontSize = 12
        arrivalPinWidth = 26
        arrivalPinHeight = 36
        arrivalETAFontSize = 18
        arrivalETAMinWidth = 62
        arrivalETAHeight = 36
        settingsContentPadding = 14
        settingsItemSpacing = 8
        settingsBodyFontSize = 11
        settingsGroupSpacing = 20
        settingsGroupLabelFontSize = 9
        settingsGroupLabelTracking = 0.7
        settingsGroupLabelSpacing = 7
        settingsFootnoteFontSize = 10
        settingsFootnoteSpacing = 11
        settingsControlHeight = 26
        settingsControlCornerRadius = 8
        settingsControlInset = 2
        settingsSegmentFontSize = 11
        settingsSegmentHorizontalPadding = 10
        settingsFocusRingWidth = 2
        settingsFocusRingInset = 3
        settingsRouteBulletSize = 30
        settingsRouteRowSpacing = 10
        settingsRouteItemSpacing = 6
        settingsRouteGroupSpacing = 14
        settingsRouteBadgeSize = 12
        settingsRouteBadgeFontSize = 9
        settingsCTAHeight = 40
        settingsCTAFontSize = 13
        alertBannerHeight = 26
        alertBannerFontSize = 10
        alertCardSpacing = 8
        alertCardPadding = 10
        alertCardCornerRadius = 8
        alertCardTextSpacing = 6
        alertCardTypeFontSize = 9
        alertCardBodyFontSize = 11
        alertCardMetaFontSize = 10
        alertCardBulletSize = 15
        alertPeriodPadding = 6
        alertPeriodCornerRadius = 6
        emptyStateSpacing = 8
        emptyStateIconFontSize = 26
        emptyStateTitleFontSize = 15
        emptyStateBodyFontSize = 11
        statusSpacing = 8
        statusIconFontSize = 28
        statusTitleFontSize = 15
        statusBodyFontSize = 11
        statusContentPadding = 14
        statusMaxWidth = 312
    }

    var normalArrivalContentHeight: CGFloat {
        menuContentHeight - directionBarHeight
    }

    var menuContentHeight: CGFloat {
        frameHeight - headerHeight - footerHeight - (dividerThickness * 2)
    }

    var normalArrivalCapacity: Int {
        max(0, Int(normalArrivalContentHeight / arrivalRowHeight))
    }

    /// The board with a collapsed service alert banner above the direction bar. The
    /// eight-row floor is a no-warning, no-alert guarantee, so this is deliberately a
    /// separate figure rather than a change to `normalArrivalContentHeight`.
    var alertedArrivalContentHeight: CGFloat {
        normalArrivalContentHeight - alertBannerHeight
    }

    var alertedArrivalCapacity: Int {
        max(0, Int(alertedArrivalContentHeight / arrivalRowHeight))
    }
}

private struct MenuLayoutMetricsKey: EnvironmentKey {
    static let defaultValue = MenuLayoutMetrics()
}

extension EnvironmentValues {
    var menuLayoutMetrics: MenuLayoutMetrics {
        get { self[MenuLayoutMetricsKey.self] }
        set { self[MenuLayoutMetricsKey.self] = newValue }
    }
}
