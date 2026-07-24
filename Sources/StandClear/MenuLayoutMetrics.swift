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

    let outerHorizontalPadding: CGFloat
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

    init(density: InterfaceDensity) {
        switch density {
        case .standard:
            self = Self(
                frameWidth: 420,
                frameHeight: 610,
                dividerThickness: 1,
                headerHeight: 60,
                headerHorizontalPadding: 18,
                headerVerticalPadding: 14,
                headerItemSpacing: 12,
                headerTitleFontSize: 15,
                headerSubtitleFontSize: 10,
                footerHeight: 44,
                footerHorizontalPadding: 18,
                footerItemSpacing: 12,
                footerFontSize: 12,
                outerHorizontalPadding: 18,
                sectionHorizontalPadding: 18,
                sectionTopPadding: 18,
                sectionBottomPadding: 6,
                sectionSpacing: 12,
                directionHeaderHeight: 36,
                directionHeaderFontSize: 11,
                arrivalRowHeight: 70,
                arrivalRowHorizontalPadding: 18,
                arrivalRowVerticalPadding: 12,
                arrivalRowItemSpacing: 12,
                arrivalRouteBulletSize: 46,
                arrivalDirectionArrowFontSize: 38,
                arrivalDirectionArrowColumnWidth: 34,
                arrivalDestinationFontSize: 13,
                arrivalStatusFontSize: 9,
                arrivalPinFontSize: 14,
                arrivalPinWidth: 30,
                arrivalPinHeight: 48,
                arrivalETAFontSize: 24,
                arrivalETAMinWidth: 86,
                arrivalETAHeight: 48,
                settingsContentPadding: 24,
                settingsSectionSpacing: 20,
                settingsItemSpacing: 12,
                settingsTitleFontSize: 18,
                settingsBodyFontSize: 13,
                settingsDirectionButtonHeight: 76,
                settingsDirectionArrowFontSize: 26,
                settingsDirectionLabelFontSize: 9,
                settingsRouteBulletSize: 54,
                settingsRouteRowSpacing: 12,
                settingsRouteItemSpacing: 14,
                settingsCTAHeight: 48,
                settingsCTAFontSize: 16
            )
        case .compact:
            self = Self(
                frameWidth: 340,
                frameHeight: 480,
                dividerThickness: 1,
                headerHeight: 50,
                headerHorizontalPadding: 12,
                headerVerticalPadding: 9,
                headerItemSpacing: 8,
                headerTitleFontSize: 13,
                headerSubtitleFontSize: 8,
                footerHeight: 36,
                footerHorizontalPadding: 12,
                footerItemSpacing: 8,
                footerFontSize: 10,
                outerHorizontalPadding: 12,
                sectionHorizontalPadding: 12,
                sectionTopPadding: 8,
                sectionBottomPadding: 4,
                sectionSpacing: 8,
                directionHeaderHeight: 28,
                directionHeaderFontSize: 10,
                arrivalRowHeight: 44,
                arrivalRowHorizontalPadding: 12,
                arrivalRowVerticalPadding: 6,
                arrivalRowItemSpacing: 8,
                arrivalRouteBulletSize: 32,
                arrivalDirectionArrowFontSize: 26,
                arrivalDirectionArrowColumnWidth: 24,
                arrivalDestinationFontSize: 11,
                arrivalStatusFontSize: 8,
                arrivalPinFontSize: 12,
                arrivalPinWidth: 26,
                arrivalPinHeight: 36,
                arrivalETAFontSize: 18,
                arrivalETAMinWidth: 62,
                arrivalETAHeight: 36,
                settingsContentPadding: 14,
                settingsSectionSpacing: 14,
                settingsItemSpacing: 8,
                settingsTitleFontSize: 15,
                settingsBodyFontSize: 11,
                settingsDirectionButtonHeight: 56,
                settingsDirectionArrowFontSize: 20,
                settingsDirectionLabelFontSize: 8,
                settingsRouteBulletSize: 38,
                settingsRouteRowSpacing: 8,
                settingsRouteItemSpacing: 10,
                settingsCTAHeight: 40,
                settingsCTAFontSize: 13
            )
        }
    }

    private init(
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        dividerThickness: CGFloat,
        headerHeight: CGFloat,
        headerHorizontalPadding: CGFloat,
        headerVerticalPadding: CGFloat,
        headerItemSpacing: CGFloat,
        headerTitleFontSize: CGFloat,
        headerSubtitleFontSize: CGFloat,
        footerHeight: CGFloat,
        footerHorizontalPadding: CGFloat,
        footerItemSpacing: CGFloat,
        footerFontSize: CGFloat,
        outerHorizontalPadding: CGFloat,
        sectionHorizontalPadding: CGFloat,
        sectionTopPadding: CGFloat,
        sectionBottomPadding: CGFloat,
        sectionSpacing: CGFloat,
        directionHeaderHeight: CGFloat,
        directionHeaderFontSize: CGFloat,
        arrivalRowHeight: CGFloat,
        arrivalRowHorizontalPadding: CGFloat,
        arrivalRowVerticalPadding: CGFloat,
        arrivalRowItemSpacing: CGFloat,
        arrivalRouteBulletSize: CGFloat,
        arrivalDirectionArrowFontSize: CGFloat,
        arrivalDirectionArrowColumnWidth: CGFloat,
        arrivalDestinationFontSize: CGFloat,
        arrivalStatusFontSize: CGFloat,
        arrivalPinFontSize: CGFloat,
        arrivalPinWidth: CGFloat,
        arrivalPinHeight: CGFloat,
        arrivalETAFontSize: CGFloat,
        arrivalETAMinWidth: CGFloat,
        arrivalETAHeight: CGFloat,
        settingsContentPadding: CGFloat,
        settingsSectionSpacing: CGFloat,
        settingsItemSpacing: CGFloat,
        settingsTitleFontSize: CGFloat,
        settingsBodyFontSize: CGFloat,
        settingsDirectionButtonHeight: CGFloat,
        settingsDirectionArrowFontSize: CGFloat,
        settingsDirectionLabelFontSize: CGFloat,
        settingsRouteBulletSize: CGFloat,
        settingsRouteRowSpacing: CGFloat,
        settingsRouteItemSpacing: CGFloat,
        settingsCTAHeight: CGFloat,
        settingsCTAFontSize: CGFloat
    ) {
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.dividerThickness = dividerThickness
        self.headerHeight = headerHeight
        self.headerHorizontalPadding = headerHorizontalPadding
        self.headerVerticalPadding = headerVerticalPadding
        self.headerItemSpacing = headerItemSpacing
        self.headerTitleFontSize = headerTitleFontSize
        self.headerSubtitleFontSize = headerSubtitleFontSize
        self.footerHeight = footerHeight
        self.footerHorizontalPadding = footerHorizontalPadding
        self.footerItemSpacing = footerItemSpacing
        self.footerFontSize = footerFontSize
        self.outerHorizontalPadding = outerHorizontalPadding
        self.sectionHorizontalPadding = sectionHorizontalPadding
        self.sectionTopPadding = sectionTopPadding
        self.sectionBottomPadding = sectionBottomPadding
        self.sectionSpacing = sectionSpacing
        self.directionHeaderHeight = directionHeaderHeight
        self.directionHeaderFontSize = directionHeaderFontSize
        self.arrivalRowHeight = arrivalRowHeight
        self.arrivalRowHorizontalPadding = arrivalRowHorizontalPadding
        self.arrivalRowVerticalPadding = arrivalRowVerticalPadding
        self.arrivalRowItemSpacing = arrivalRowItemSpacing
        self.arrivalRouteBulletSize = arrivalRouteBulletSize
        self.arrivalDirectionArrowFontSize = arrivalDirectionArrowFontSize
        self.arrivalDirectionArrowColumnWidth = arrivalDirectionArrowColumnWidth
        self.arrivalDestinationFontSize = arrivalDestinationFontSize
        self.arrivalStatusFontSize = arrivalStatusFontSize
        self.arrivalPinFontSize = arrivalPinFontSize
        self.arrivalPinWidth = arrivalPinWidth
        self.arrivalPinHeight = arrivalPinHeight
        self.arrivalETAFontSize = arrivalETAFontSize
        self.arrivalETAMinWidth = arrivalETAMinWidth
        self.arrivalETAHeight = arrivalETAHeight
        self.settingsContentPadding = settingsContentPadding
        self.settingsSectionSpacing = settingsSectionSpacing
        self.settingsItemSpacing = settingsItemSpacing
        self.settingsTitleFontSize = settingsTitleFontSize
        self.settingsBodyFontSize = settingsBodyFontSize
        self.settingsDirectionButtonHeight = settingsDirectionButtonHeight
        self.settingsDirectionArrowFontSize = settingsDirectionArrowFontSize
        self.settingsDirectionLabelFontSize = settingsDirectionLabelFontSize
        self.settingsRouteBulletSize = settingsRouteBulletSize
        self.settingsRouteRowSpacing = settingsRouteRowSpacing
        self.settingsRouteItemSpacing = settingsRouteItemSpacing
        self.settingsCTAHeight = settingsCTAHeight
        self.settingsCTAFontSize = settingsCTAFontSize
    }

    var normalArrivalContentHeight: CGFloat {
        frameHeight
            - headerHeight
            - footerHeight
            - (dividerThickness * 2)
            - directionHeaderHeight
    }

    var normalArrivalCapacity: Int {
        max(0, Int(normalArrivalContentHeight / arrivalRowHeight))
    }
}

private struct MenuLayoutMetricsKey: EnvironmentKey {
    static let defaultValue = MenuLayoutMetrics(density: .standard)
}

extension EnvironmentValues {
    var menuLayoutMetrics: MenuLayoutMetrics {
        get { self[MenuLayoutMetricsKey.self] }
        set { self[MenuLayoutMetricsKey.self] = newValue }
    }
}
