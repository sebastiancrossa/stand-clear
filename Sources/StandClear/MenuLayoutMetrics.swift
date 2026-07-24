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
    let emptyStateTopPadding: CGFloat

    let statusSpacing: CGFloat
    let statusIconFontSize: CGFloat
    let statusTitleFontSize: CGFloat
    let statusBodyFontSize: CGFloat
    let statusContentPadding: CGFloat
    let statusMaxWidth: CGFloat
    let statusUsesProminentActions: Bool

    init(density: InterfaceDensity) {
        switch density {
        case .standard:
            self = Self(
                frameWidth: 420,
                frameHeight: 610,
                dividerThickness: 1,
                headerHeight: 62,
                headerHorizontalPadding: 18,
                headerVerticalPadding: 14,
                headerItemSpacing: 12,
                headerTitleFontSize: 15,
                headerSubtitleFontSize: 10,
                footerHeight: 44,
                footerHorizontalPadding: 18,
                footerItemSpacing: 12,
                footerFontSize: 12,
                sectionHorizontalPadding: 18,
                sectionTopPadding: 18,
                sectionBottomPadding: 6,
                sectionSpacing: 12,
                directionHeaderHeight: 38,
                directionHeaderFontSize: 11,
                arrivalRowHeight: 72,
                arrivalRowHorizontalPadding: 18,
                arrivalRowVerticalPadding: 12,
                arrivalRowItemSpacing: 12,
                arrivalTextSpacing: 4,
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
                settingsCTAFontSize: 16,
                emptyStateSpacing: 12,
                emptyStateIconFontSize: 30,
                emptyStateTitleFontSize: 13,
                emptyStateBodyFontSize: 13,
                emptyStateTopPadding: 110,
                statusSpacing: 16,
                statusIconFontSize: 34,
                statusTitleFontSize: 20,
                statusBodyFontSize: 13,
                statusContentPadding: 32,
                statusMaxWidth: 300,
                statusUsesProminentActions: true
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
                sectionHorizontalPadding: 12,
                sectionTopPadding: 8,
                sectionBottomPadding: 4,
                sectionSpacing: 8,
                directionHeaderHeight: 28,
                directionHeaderFontSize: 10,
                arrivalRowHeight: 44,
                arrivalRowHorizontalPadding: 12,
                arrivalRowVerticalPadding: 4,
                arrivalRowItemSpacing: 8,
                arrivalTextSpacing: 2,
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
                settingsCTAFontSize: 13,
                emptyStateSpacing: 8,
                emptyStateIconFontSize: 26,
                emptyStateTitleFontSize: 15,
                emptyStateBodyFontSize: 11,
                emptyStateTopPadding: 0,
                statusSpacing: 8,
                statusIconFontSize: 28,
                statusTitleFontSize: 15,
                statusBodyFontSize: 11,
                statusContentPadding: 14,
                statusMaxWidth: 312,
                statusUsesProminentActions: false
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
        arrivalTextSpacing: CGFloat,
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
        settingsCTAFontSize: CGFloat,
        emptyStateSpacing: CGFloat,
        emptyStateIconFontSize: CGFloat,
        emptyStateTitleFontSize: CGFloat,
        emptyStateBodyFontSize: CGFloat,
        emptyStateTopPadding: CGFloat,
        statusSpacing: CGFloat,
        statusIconFontSize: CGFloat,
        statusTitleFontSize: CGFloat,
        statusBodyFontSize: CGFloat,
        statusContentPadding: CGFloat,
        statusMaxWidth: CGFloat,
        statusUsesProminentActions: Bool
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
        self.arrivalTextSpacing = arrivalTextSpacing
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
        self.emptyStateSpacing = emptyStateSpacing
        self.emptyStateIconFontSize = emptyStateIconFontSize
        self.emptyStateTitleFontSize = emptyStateTitleFontSize
        self.emptyStateBodyFontSize = emptyStateBodyFontSize
        self.emptyStateTopPadding = emptyStateTopPadding
        self.statusSpacing = statusSpacing
        self.statusIconFontSize = statusIconFontSize
        self.statusTitleFontSize = statusTitleFontSize
        self.statusBodyFontSize = statusBodyFontSize
        self.statusContentPadding = statusContentPadding
        self.statusMaxWidth = statusMaxWidth
        self.statusUsesProminentActions = statusUsesProminentActions
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
    static let defaultValue = MenuLayoutMetrics(density: .standard)
}

extension EnvironmentValues {
    var menuLayoutMetrics: MenuLayoutMetrics {
        get { self[MenuLayoutMetricsKey.self] }
        set { self[MenuLayoutMetricsKey.self] = newValue }
    }
}
