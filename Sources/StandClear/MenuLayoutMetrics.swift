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
    let directionHeaderHeight: CGFloat
    let directionHeaderFontSize: CGFloat

    let arrivalRowHeight: CGFloat
    let arrivalRowHorizontalPadding: CGFloat
    let arrivalRowVerticalPadding: CGFloat
    let arrivalRowItemSpacing: CGFloat
    let arrivalTextSpacing: CGFloat
    let arrivalRouteBulletSize: CGFloat
    let arrivalDirectionArrowFontSize: CGFloat
    let arrivalDirectionArrowColumnWidth: CGFloat
    let arrivalDestinationFontSize: CGFloat
    let arrivalStatusFontSize: CGFloat
    let arrivalPinFontSize: CGFloat
    let arrivalPinWidth: CGFloat
    let arrivalPinHeight: CGFloat
    let arrivalETAFontSize: CGFloat
    let arrivalETAMinWidth: CGFloat
    let arrivalETAHeight: CGFloat

    let settingsContentPadding: CGFloat
    let settingsSectionSpacing: CGFloat
    let settingsItemSpacing: CGFloat
    let settingsTitleFontSize: CGFloat
    let settingsBodyFontSize: CGFloat
    let settingsDirectionButtonHeight: CGFloat
    let settingsDirectionArrowFontSize: CGFloat
    let settingsDirectionLabelFontSize: CGFloat
    let settingsRouteBulletSize: CGFloat
    let settingsRouteRowSpacing: CGFloat
    let settingsRouteItemSpacing: CGFloat
    let settingsCTAHeight: CGFloat
    let settingsCTAFontSize: CGFloat

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
        directionHeaderHeight = 28
        directionHeaderFontSize = 10
        arrivalRowHeight = 44
        arrivalRowHorizontalPadding = 12
        arrivalRowVerticalPadding = 4
        arrivalRowItemSpacing = 8
        arrivalTextSpacing = 2
        arrivalRouteBulletSize = 32
        arrivalDirectionArrowFontSize = 26
        arrivalDirectionArrowColumnWidth = 24
        arrivalDestinationFontSize = 11
        arrivalStatusFontSize = 8
        arrivalPinFontSize = 12
        arrivalPinWidth = 26
        arrivalPinHeight = 36
        arrivalETAFontSize = 18
        arrivalETAMinWidth = 62
        arrivalETAHeight = 36
        settingsContentPadding = 14
        settingsSectionSpacing = 14
        settingsItemSpacing = 8
        settingsTitleFontSize = 15
        settingsBodyFontSize = 11
        settingsDirectionButtonHeight = 56
        settingsDirectionArrowFontSize = 20
        settingsDirectionLabelFontSize = 8
        settingsRouteBulletSize = 38
        settingsRouteRowSpacing = 8
        settingsRouteItemSpacing = 10
        settingsCTAHeight = 40
        settingsCTAFontSize = 13
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
        menuContentHeight - directionHeaderHeight
    }

    var menuContentHeight: CGFloat {
        frameHeight - headerHeight - footerHeight - (dividerThickness * 2)
    }

    var normalArrivalCapacity: Int {
        max(0, Int(normalArrivalContentHeight / arrivalRowHeight))
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
