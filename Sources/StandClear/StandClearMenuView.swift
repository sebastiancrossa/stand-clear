import CoreLocation
import StandClearCore
import SwiftUI

struct StandClearMenuView: View {
    @EnvironmentObject private var model: AppModel
    let settingsWindowCoordinator: LiveMapWindowCoordinator

    var body: some View {
        let metrics = MenuLayoutMetrics()

        ZStack {
            MenuTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                MenuHeaderView()
                MenuDivider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MenuDivider()
                MenuFooterView(
                    settingsWindowCoordinator: settingsWindowCoordinator
                )
            }
        }
        .frame(width: metrics.frameWidth, height: metrics.frameHeight)
        .environment(\.menuLayoutMetrics, metrics)
        // The board's default ink, so an unstyled label or SF Symbol lands on white
        // rather than on `.primary` — which is black on a Mac in Light Mode.
        .foregroundStyle(MenuTheme.primaryText)
        .forcesDarkAppearance()
        .task { model.start() }
        .onAppear { model.setMenuPopoverActive(true) }
        .onDisappear {
            model.setMenuPopoverActive(false)
            model.collapseExpandedStation()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isShowingSettings {
            StandClearSettingsView()
        } else if let error = model.startupError {
            StatusView(
                symbol: "exclamationmark.triangle.fill",
                title: "Couldn’t start Stand Clear",
                message: error,
                actionTitle: nil,
                action: nil
            )
        } else {
            switch model.locationService.authorizationStatus {
            case .denied, .restricted:
                StatusView(
                    symbol: "location.slash.fill",
                    title: "Location is off",
                    message: "Allow location access so Stand Clear can find the station closest to you. Your coordinates stay on this Mac.",
                    actionTitle: "Open Location Settings",
                    action: model.openLocationSettings
                )
            default:
                if model.nearestStation == nil {
                    StatusView(
                        symbol: "location.fill",
                        title: "Finding your station",
                        message: "Stand Clear is waiting for a location fix and loading the latest MTA arrivals.",
                        actionTitle: "Try Again",
                        action: model.locationService.requestLocation
                    )
                } else {
                    ArrivalListView()
                }
            }
        }
    }
}

private struct MenuHeaderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics

    private var isOnboarding: Bool {
        model.isOnboarding
    }

    var body: some View {
        HStack(spacing: metrics.headerItemSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(
                        size: metrics.headerTitleFontSize,
                        weight: .bold,
                        design: .rounded
                    ))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(
                        size: metrics.headerSubtitleFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(MenuTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: metrics.headerItemSpacing)

            if model.isShowingSettings {
                if !isOnboarding {
                    Button {
                        model.closeSettings()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: metrics.headerTitleFontSize, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close Settings")
                    .accessibilityLabel("Close Settings")
                    .keyboardShortcut(.cancelAction)
                }
            } else if model.hasConfiguredSelection {
                HStack(spacing: metrics.headerItemSpacing / 2) {
                    if model.nearestStation != nil {
                        Button {
                            model.requestManualRefresh()
                        } label: {
                            Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .font(.system(size: metrics.headerTitleFontSize, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isRefreshing)
                        .help(refreshHelp)
                        .accessibilityLabel("Refresh arrivals")
                        .accessibilityValue(refreshAccessibilityValue)
                        .keyboardShortcut("r", modifiers: .command)
                    }

                    Button {
                        model.openSettings(section: .service)
                    } label: {
                        Image(systemName: "tram.fill")
                            .font(.system(size: metrics.headerTitleFontSize, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Choose lines & direction")
                    .accessibilityLabel("Choose lines and direction")
                }
            }
        }
        .padding(.horizontal, metrics.headerHorizontalPadding)
        .padding(.vertical, metrics.headerVerticalPadding)
        .frame(height: metrics.headerHeight)
    }

    private var refreshHelp: String {
        if let lastUpdated = model.lastUpdated {
            return "Refresh MTA arrivals. Last updated \(lastUpdated.formatted(date: .omitted, time: .shortened))."
        }
        return "Refresh MTA arrivals."
    }

    private var refreshAccessibilityValue: String {
        if model.isRefreshing {
            return "Refreshing"
        }
        if let lastUpdated = model.lastUpdated {
            return "Last updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
        }
        return "Not updated yet"
    }

    private var title: String {
        if model.isShowingSettings {
            return isOnboarding ? "SET UP STAND CLEAR" : "SETTINGS"
        }
        return "STAND CLEAR"
    }

    private var subtitle: String {
        if model.isShowingSettings {
            return "SERVICE"
        }
        if model.nearestStation != nil {
            if let lastUpdated = model.lastUpdated {
                return "UPDATED \(lastUpdated.formatted(date: .omitted, time: .shortened))"
            }
            return "NEARBY STATIONS"
        }
        return "LIVE NYC SUBWAY ARRIVALS"
    }
}

private struct MenuFooterView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics
    @Environment(\.openWindow) private var openWindow

    let settingsWindowCoordinator: LiveMapWindowCoordinator

    var body: some View {
        HStack(spacing: metrics.footerItemSpacing) {
            Button {
                settingsWindowCoordinator.present {
                    openWindow(id: "app-settings")
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .help("Open app Settings")
            .accessibilityLabel("Open app Settings")

            if model.isPinned, let direction = model.selectedDirection {
                Button {
                    model.clearPin()
                } label: {
                    Image(systemName: "pin.slash")
                }
                .buttonStyle(.plain)
                .help("Unpin \(pinnedSummary(for: direction))")
                .accessibilityLabel("Unpin \(pinnedAccessibilitySummary(for: direction))")
            }

            Spacer()

            if model.hasPendingUpdate {
                Button {
                    settingsWindowCoordinator.present {
                        openWindow(id: "app-settings")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(MenuTheme.accent)
                            .frame(width: 6, height: 6)
                        Text("Update")
                            .font(.system(size: metrics.footerFontSize))
                            .foregroundStyle(MenuTheme.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                .help("A new version is available")
                .accessibilityLabel("Update available")
            }

            Button("Quit") { model.quit() }
                .buttonStyle(.plain)
                .font(.system(size: metrics.footerFontSize))
                .foregroundStyle(MenuTheme.secondaryText)
        }
        .padding(.horizontal, metrics.footerHorizontalPadding)
        .frame(height: metrics.footerHeight)
    }

    private func pinnedSummary(for direction: TravelDirection) -> String {
        let arrow = model.currentVocabulary.glyph(for: direction)
        guard let arrival = model.pinnedArrival else { return arrow }
        return "\(RouteID.displayLabel(arrival.routeID)) \(arrow)"
    }

    private func pinnedAccessibilitySummary(for direction: TravelDirection) -> String {
        let name = model.currentVocabulary.accessibilityName(for: direction)
        guard let arrival = model.pinnedArrival else { return "\(name) trains" }
        return "\(RouteID.displayLabel(arrival.routeID)) train \(name)"
    }
}

private struct ArrivalListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics

    private var sections: [StationSection] {
        model.stationSections
    }

    private var isBoardEmpty: Bool {
        sections.isEmpty && !model.isRefreshing
    }

    private var allSectionsHaveNoArrivals: Bool {
        !sections.isEmpty && sections.allSatisfy(\.arrivals.isEmpty)
    }

    /// The board has nothing to show *and* we know why. This is the case the alert
    /// surface exists for, so the alerts stay open and the generic advice below them
    /// gives way to the real reason.
    private var alertsExplainEmptyBoard: Bool {
        (isBoardEmpty || allSectionsHaveNoArrivals) && model.hasAlertAtNearestStation
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let warning = model.feedWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(
                            size: metrics.settingsBodyFontSize,
                            weight: .semibold
                        ))
                        .foregroundStyle(MenuTheme.caution)
                        .padding(.horizontal, metrics.sectionHorizontalPadding)
                        .padding(.vertical, metrics.sectionSpacing)
                }

                if !model.activeAlerts.isEmpty {
                    ServiceAlertSection(
                        alerts: model.activeAlerts,
                        now: model.now,
                        isCollapsible: !alertsExplainEmptyBoard
                    )
                }

                DirectionBar()

                if isBoardEmpty {
                    emptyState
                } else {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        StationSectionView(
                            section: section,
                            isNearest: index == 0,
                            now: model.now
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: metrics.emptyStateSpacing) {
            Image(systemName: alertsExplainEmptyBoard
                ? "exclamationmark.triangle.fill"
                : "clock.badge.questionmark")
                .font(.system(
                    size: metrics.emptyStateIconFontSize,
                    weight: .light
                ))
                .foregroundStyle(alertsExplainEmptyBoard ? MenuTheme.caution : MenuTheme.secondaryText)
            Text("No selected trains right now")
                .font(.system(
                    size: metrics.emptyStateTitleFontSize,
                    weight: .semibold,
                    design: .rounded
                ))
            Text(emptyStateMessage)
                .font(.system(size: metrics.emptyStateBodyFontSize))
                .multilineTextAlignment(.center)
                .foregroundStyle(MenuTheme.secondaryText)
                .frame(maxWidth: metrics.frameWidth - (metrics.settingsContentPadding * 2))

            // Sending the rider to Settings is good advice for an empty board with no
            // explanation, and actively wrong when a suspension is the reason.
            if !alertsExplainEmptyBoard {
                MenuActionButton(title: "Open Settings") {
                    model.openSettings(section: .service)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: alertsExplainEmptyBoard ? 0 : metrics.normalArrivalContentHeight)
        .padding(.horizontal, metrics.settingsContentPadding)
        .padding(.vertical, alertsExplainEmptyBoard ? metrics.settingsContentPadding : 0)
    }

    private var emptyStateMessage: String {
        alertsExplainEmptyBoard
            ? "The service alert above explains why."
            : "Switch direction above, change your lines, or refresh the MTA feed."
    }
}

private struct StationSectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let section: StationSection
    let isNearest: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StationSectionHeader(
                section: section,
                isNearest: isNearest
            ) {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                    model.toggleStationExpanded(section.id)
                }
            }

            if section.arrivals.isEmpty {
                EmptyStationArrivalsRow()
            } else {
                ForEach(section.arrivals) { arrival in
                    ArrivalRow(
                        arrival: arrival,
                        stationID: section.id,
                        now: now
                    )
                }
            }
        }
    }
}

private struct StationSectionHeader: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics

    let section: StationSection
    let isNearest: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.arrivalRowItemSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.station.name.uppercased())
                        .font(.system(
                            size: metrics.directionBarFontSize,
                            weight: .bold,
                            design: .rounded
                        ))
                        .foregroundStyle(MenuTheme.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(
                            size: metrics.arrivalStatusFontSize,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .foregroundStyle(MenuTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: metrics.directionBarFontSize, weight: .semibold))
                    .foregroundStyle(MenuTheme.secondaryText)
                    .rotationEffect(.degrees(section.isExpanded ? 180 : 0))
            }
            .padding(.horizontal, metrics.sectionHorizontalPadding)
            .padding(.top, metrics.sectionTopPadding)
            .padding(.bottom, metrics.sectionBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(
            section.isExpanded
                ? "Collapse to show fewer arrivals"
                : "Expand to show more arrivals"
        )
    }

    private var subtitle: String {
        let distance = distanceText(section.distance)
        let walk = walkText
        let detail = walk.map { "\(distance) · \($0)" } ?? distance
        return isNearest ? "NEAREST STATION · \(detail)" : detail
    }

    private var accessibilityLabel: String {
        let distance = distanceText(section.distance)
        let walk = walkText.map { ", \($0.lowercased())" } ?? ""
        if isNearest {
            return "\(section.station.name), nearest station, \(distance)\(walk)"
        }
        return "\(section.station.name), \(distance)\(walk)"
    }

    private var walkText: String? {
        guard model.reachabilityEnabled,
              let seconds = model.walkSeconds(forStationID: section.id)
        else { return nil }
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        return "\(minutes) MIN WALK"
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        let feet = meters * 3.28084
        if feet < 1_000 {
            return "\(Int(feet.rounded())) FT"
        }
        return String(format: "%.1f MI", meters / 1_609.344)
    }
}

private struct EmptyStationArrivalsRow: View {
    @Environment(\.menuLayoutMetrics) private var metrics

    var body: some View {
        Text("No upcoming trains")
            .font(.system(
                size: metrics.arrivalStatusFontSize,
                weight: .semibold,
                design: .rounded
            ))
            .foregroundStyle(MenuTheme.secondaryText)
            .padding(.horizontal, metrics.arrivalRowHorizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: metrics.arrivalRowHeight / 2,
                alignment: .leading
            )
            .accessibilityLabel("No upcoming trains")
    }
}

/// The board shows one direction at a time, so the row that used to separate
/// direction groups is now the control that switches between them. The swap and the
/// pin are sibling buttons: a Button nested inside another Button's label does not
/// work on macOS.
///
/// A pin covers every selected route in the current direction, not a single arrival,
/// so it lives here rather than on a row — and it follows a swap instead of clearing.
private struct DirectionBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics
    @State private var isHoveringSwap = false

    private var otherDirection: TravelDirection? {
        guard let direction = model.selectedDirection else { return nil }
        return TravelDirection.selectableCases.first { $0 != direction }
    }

    var body: some View {
        if let direction = model.selectedDirection {
            HStack(spacing: 0) {
                swapButton(for: direction)
                pinButton(for: direction)
            }
            .padding(.top, metrics.sectionTopPadding)
            .padding(.bottom, metrics.sectionBottomPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: metrics.directionBarHeight,
                maxHeight: metrics.directionBarHeight
            )
            .padding(.horizontal, metrics.sectionHorizontalPadding)
        }
    }

    private func swapButton(for direction: TravelDirection) -> some View {
        let vocabulary = model.currentVocabulary
        return Button {
            model.swapDirection()
        } label: {
            HStack(spacing: metrics.arrivalRowItemSpacing / 2) {
                Text(vocabulary.glyph(for: direction))
                    .font(.system(size: metrics.directionBarArrowFontSize, weight: .semibold))
                Text(vocabulary.title(for: direction))
                    .font(.system(
                        size: metrics.directionBarFontSize,
                        weight: .bold,
                        design: .rounded
                    ))
                    .lineLimit(1)
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: metrics.directionBarFontSize, weight: .semibold))
                    .opacity(isHoveringSwap ? 1 : 0)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHoveringSwap ? MenuTheme.primaryText : MenuTheme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringSwap = $0 }
        .disabled(otherDirection == nil)
        .help(swapHelp)
        .accessibilityLabel("Showing \(vocabulary.accessibilityName(for: direction)) trains")
        .accessibilityHint(swapHelp)
    }

    private func pinButton(for direction: TravelDirection) -> some View {
        let name = model.currentVocabulary.accessibilityName(for: direction)
        return Button {
            model.togglePin()
        } label: {
            Image(systemName: model.isPinned ? "pin.fill" : "pin")
                .font(.system(size: metrics.arrivalPinFontSize, weight: .semibold))
                .frame(width: metrics.arrivalPinWidth, height: metrics.arrivalPinHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.isPinned ? MenuTheme.primaryText : MenuTheme.secondaryText)
        .help(
            model.isPinned
                ? "Unpin \(name) trains"
                : "Pin \(name) trains to the menu bar"
        )
        .accessibilityLabel("\(model.isPinned ? "Unpin" : "Pin") \(name) trains")
    }

    private var swapHelp: String {
        guard let otherDirection else { return "" }
        let name = model.currentVocabulary.accessibilityName(for: otherDirection)
        return "Switch to \(name) trains"
    }
}

private struct ArrivalRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics

    let arrival: Arrival
    let stationID: String
    let now: Date

    private var displayedETA: String {
        model.showsMinutesAndSeconds
            ? arrival.etaMinutesSecondsText(relativeTo: now)
            : arrival.etaText(relativeTo: now)
    }

    private var reachability: Reachability? {
        model.reachability(for: arrival, atStationID: stationID)
    }

    private var statusLabel: String {
        switch reachability {
        case .leaveNow:
            return "LEAVE NOW"
        case .tooLate:
            return "TOO LATE"
        case .comfortable, .none:
            return "REAL-TIME ARRIVAL"
        }
    }

    private var rowOpacity: Double {
        reachability == .tooLate ? MenuTheme.tooLateOpacity : 1
    }

    private var etaColor: Color {
        switch reachability {
        case .leaveNow:
            return MenuTheme.leaveNow
        case .tooLate:
            return MenuTheme.tertiaryText
        case .comfortable, .none:
            return MenuTheme.primaryText
        }
    }

    var body: some View {
        HStack(spacing: metrics.arrivalRowItemSpacing) {
            RouteBullet(
                routeID: arrival.routeID,
                size: metrics.arrivalRouteBulletSize,
                isSelected: true
            )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: metrics.arrivalTextSpacing) {
                Text(arrival.destination.uppercased())
                    .font(.system(
                        size: metrics.arrivalDestinationFontSize,
                        weight: .bold,
                        design: .rounded
                    ))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(arrival.destination)
                Text(statusLabel)
                    .font(.system(
                        size: metrics.arrivalStatusFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(reachability == .leaveNow ? MenuTheme.leaveNow : MenuTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(arrival.routeID) train \(arrival.direction.rawValue) to \(arrival.destination)"
            )

            Button {
                model.toggleArrivalTimeDisplay()
            } label: {
                Text(displayedETA)
                    .font(.system(
                        size: metrics.arrivalETAFontSize,
                        weight: .regular,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .foregroundStyle(etaColor)
                    .lineLimit(1)
                    .frame(
                        minWidth: metrics.arrivalETAMinWidth,
                        minHeight: metrics.arrivalETAHeight,
                        alignment: .trailing
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.showsMinutesAndSeconds ? "Show whole minutes" : "Show minutes and seconds")
            .accessibilityLabel("Arrival time")
            .accessibilityValue(displayedETA)
            .accessibilityHint(
                model.showsMinutesAndSeconds
                    ? "Click to show all arrival times in whole minutes."
                    : "Click to show all arrival times in minutes and seconds."
            )
        }
        .padding(.horizontal, metrics.arrivalRowHorizontalPadding)
        .padding(.vertical, metrics.arrivalRowVerticalPadding)
        .frame(height: metrics.arrivalRowHeight)
        .background(reachability == .leaveNow ? MenuTheme.leaveNowHighlight : Color.clear)
        .opacity(rowOpacity)
        .clipped()
    }
}

struct RouteBullet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let routeID: String
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        let style = RouteStyle.style(for: routeID)

        // On the board every bullet is selected and reads as solid MTA colour. In the
        // LINES grid an unselected line has to read as off at a glance without going
        // invisible on black, so it empties out to a ring in its own colour and keeps
        // the letter in white. Dimming the whole bullet instead loses the darker
        // routes entirely, and merely draining the colour looks like a third state.
        ZStack {
            if RouteID.isExpress(routeID) {
                RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .fill(fill(style))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                            .strokeBorder(stroke(style), lineWidth: size * 0.06)
                    }
                    .frame(width: size * 0.72, height: size * 0.72)
                    .rotationEffect(.degrees(45))
            } else {
                Circle()
                    .fill(fill(style))
                    .overlay {
                        Circle().strokeBorder(stroke(style), lineWidth: size * 0.06)
                    }
            }

            Text(RouteID.displayLabel(routeID))
                .font(.system(size: size * (RouteID.displayLabel(routeID).count > 1 ? 0.36 : 0.53), weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .foregroundStyle(isSelected ? style.foreground : MenuTheme.primaryText.opacity(0.85))
        }
            .frame(width: size, height: size)
            .scaleEffect(isSelected ? 1 : 0.94)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isSelected)
    }

    private func fill(_ style: RouteStyle) -> Color {
        isSelected ? style.background : style.background.opacity(0.18)
    }

    private func stroke(_ style: RouteStyle) -> Color {
        isSelected ? .clear : style.background.opacity(0.9)
    }
}

private struct StatusView: View {
    @Environment(\.menuLayoutMetrics) private var metrics

    let symbol: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: metrics.statusSpacing) {
            Image(systemName: symbol)
                .font(.system(size: metrics.statusIconFontSize, weight: .light))
                .foregroundStyle(MenuTheme.secondaryText)
            Text(title)
                .font(.system(
                    size: metrics.statusTitleFontSize,
                    weight: .bold,
                    design: .rounded
                ))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: metrics.statusBodyFontSize))
                .multilineTextAlignment(.center)
                .foregroundStyle(MenuTheme.secondaryText)
                .frame(maxWidth: metrics.statusMaxWidth)

            if let actionTitle, let action {
                MenuActionButton(title: actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(metrics.statusContentPadding)
    }
}

private struct MenuActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .tint(MenuTheme.controlSelected)
    }
}
