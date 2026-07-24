import CoreLocation
import StandClearCore
import SwiftUI

struct StandClearMenuView: View {
    @EnvironmentObject private var model: AppModel
    let mapWindowCoordinator: LiveMapWindowCoordinator

    var body: some View {
        let metrics = MenuLayoutMetrics(density: model.interfaceDensity)

        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                MenuHeaderView()
                Divider()
                    .overlay(Color.white.opacity(0.12))
                    .frame(height: metrics.dividerThickness)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                    .overlay(Color.white.opacity(0.12))
                    .frame(height: metrics.dividerThickness)
                MenuFooterView(mapWindowCoordinator: mapWindowCoordinator)
            }
        }
        .frame(width: metrics.frameWidth, height: metrics.frameHeight)
        .environment(\.menuLayoutMetrics, metrics)
        .preferredColorScheme(.dark)
        .task { model.start() }
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
        model.isShowingSettings && !model.hasConfiguredSelection
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: metrics.headerItemSpacing)

            if model.isShowingSettings {
                if !isOnboarding {
                    Button {
                        model.isShowingSettings = false
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
                Button {
                    model.isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: metrics.headerTitleFontSize, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Settings")
                .accessibilityLabel("Open Settings")
            }
        }
        .padding(.horizontal, metrics.headerHorizontalPadding)
        .padding(.vertical, metrics.headerVerticalPadding)
        .frame(height: metrics.headerHeight)
    }

    private var title: String {
        if model.isShowingSettings {
            return isOnboarding ? "SET UP STAND CLEAR" : "SETTINGS"
        }
        return model.nearestStation?.name.uppercased() ?? "STAND CLEAR"
    }

    private var subtitle: String {
        if model.isShowingSettings {
            return "APPEARANCE & SERVICE"
        }
        if let distance = model.distanceToStation {
            return "NEAREST STATION · \(distanceText(distance))"
        }
        return "LIVE NYC SUBWAY ARRIVALS"
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        let feet = meters * 3.28084
        if feet < 1_000 {
            return "\(Int(feet.rounded())) FT"
        }
        return String(format: "%.1f MI", meters / 1_609.344)
    }
}

private struct MenuFooterView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics
    @Environment(\.openWindow) private var openWindow

    let mapWindowCoordinator: LiveMapWindowCoordinator

    var body: some View {
        HStack(spacing: metrics.footerItemSpacing) {
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Updating")
                    .font(.system(size: metrics.footerFontSize))
                    .foregroundStyle(.secondary)
            } else if let updated = model.lastUpdated {
                Text("Updated \(updated, style: .relative)")
                    .font(.system(size: metrics.footerFontSize))
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting for MTA")
                    .font(.system(size: metrics.footerFontSize))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                mapWindowCoordinator.present {
                    openWindow(id: "live-map")
                }
            } label: {
                Image(systemName: "map")
            }
            .buttonStyle(.plain)
            .help("Open Live Map")
            .accessibilityLabel("Open Live Map")

            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .accessibilityLabel("Refresh arrivals")

            if let pinnedService = model.pinnedService {
                Button {
                    model.clearPin()
                } label: {
                    Image(systemName: "pin.slash")
                }
                .buttonStyle(.plain)
                .help("Unpin \(pinnedService.displayName)")
                .accessibilityLabel("Unpin \(pinnedService.accessibilityName)")
            }

            Button("Quit") { model.quit() }
                .buttonStyle(.plain)
                .font(.system(size: metrics.footerFontSize))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, metrics.footerHorizontalPadding)
        .frame(height: metrics.footerHeight)
    }
}

private struct ArrivalListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let warning = model.feedWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(
                            size: metrics.settingsBodyFontSize,
                            weight: .semibold
                        ))
                        .foregroundStyle(Color(hex: 0xFCCC0A))
                        .padding(.horizontal, metrics.sectionHorizontalPadding)
                        .padding(.vertical, metrics.sectionSpacing)
                }

                if model.displayedArrivals.isEmpty, !model.isRefreshing {
                    VStack(spacing: metrics.emptyStateSpacing) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(
                                size: metrics.emptyStateIconFontSize,
                                weight: .light
                            ))
                            .foregroundStyle(.secondary)
                        Text("No selected trains right now")
                            .font(.system(
                                size: metrics.emptyStateTitleFontSize,
                                weight: .semibold,
                                design: .rounded
                            ))
                        Text("Try another direction or line, or refresh the MTA feed.")
                            .font(.system(size: metrics.emptyStateBodyFontSize))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: metrics.frameWidth - (metrics.settingsContentPadding * 2))
                        DensityAwareActionButton(title: "Open Settings") {
                            model.isShowingSettings = true
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(
                        minHeight: metrics.emptyStateTopPadding == 0
                            ? metrics.menuContentHeight
                            : 0
                    )
                    .padding(.top, metrics.emptyStateTopPadding)
                    .padding(.horizontal, metrics.settingsContentPadding)
                } else {
                    ForEach(TravelDirection.allCases, id: \.self) { direction in
                        let arrivals = model.displayedArrivals.filter { $0.direction == direction }
                        if !arrivals.isEmpty {
                            Text(direction.title)
                                .font(.system(
                                    size: metrics.directionHeaderFontSize,
                                    weight: .bold,
                                    design: .rounded
                                ))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.top, metrics.sectionTopPadding)
                                .padding(.bottom, metrics.sectionBottomPadding)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: metrics.directionHeaderHeight,
                                    maxHeight: metrics.directionHeaderHeight,
                                    alignment: .leading
                                )
                                .padding(.horizontal, metrics.sectionHorizontalPadding)

                            ForEach(arrivals) { arrival in
                                ArrivalRow(arrival: arrival, now: model.now)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ArrivalRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics

    let arrival: Arrival
    let now: Date

    private var displayedETA: String {
        model.showsMinutesAndSeconds
            ? arrival.etaMinutesSecondsText(relativeTo: now)
            : arrival.etaText(relativeTo: now)
    }

    private var isPinned: Bool {
        model.pinnedService == PinnedService(
            routeID: arrival.routeID,
            direction: arrival.direction
        )
    }

    var body: some View {
        HStack(spacing: metrics.arrivalRowItemSpacing) {
            RouteBullet(
                routeID: arrival.routeID,
                size: metrics.arrivalRouteBulletSize,
                isSelected: true
            )
                .accessibilityHidden(true)

            Text(arrival.direction.arrow)
                .font(.system(
                    size: metrics.arrivalDirectionArrowFontSize,
                    weight: .light,
                    design: .rounded
                ))
                .frame(width: metrics.arrivalDirectionArrowColumnWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: metrics.arrivalTextSpacing) {
                Text(arrival.destination.uppercased())
                    .font(.system(
                        size: metrics.arrivalDestinationFontSize,
                        weight: .bold,
                        design: .rounded
                    ))
                    .lineLimit(model.interfaceDensity == .compact ? 1 : 2)
                    .truncationMode(.tail)
                    .help(arrival.destination)
                Text("REAL-TIME ARRIVAL")
                    .font(.system(
                        size: metrics.arrivalStatusFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(arrival.routeID) train \(arrival.direction.rawValue) to \(arrival.destination)"
            )

            Button {
                model.togglePin(routeID: arrival.routeID, direction: arrival.direction)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: metrics.arrivalPinFontSize, weight: .semibold))
                    .frame(
                        width: metrics.arrivalPinWidth,
                        height: metrics.arrivalPinHeight
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isPinned ? Color.white : Color.secondary)
            .help(isPinned ? "Unpin this service" : "Pin this service to the menu bar")
            .accessibilityLabel(
                "\(isPinned ? "Unpin" : "Pin") "
                    + "\(RouteID.displayLabel(arrival.routeID)) train "
                    + "\(arrival.direction.accessibilityName)"
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
        .clipped()
    }
}

private extension PinnedService {
    var displayName: String {
        "\(RouteID.displayLabel(routeID)) \(direction.arrow)"
    }

    var accessibilityName: String {
        "\(RouteID.displayLabel(routeID)) train \(direction.accessibilityName)"
    }
}

private extension TravelDirection {
    var accessibilityName: String {
        switch self {
        case .northbound: "uptown"
        case .southbound: "downtown"
        case .unknown: "unknown direction"
        }
    }
}

struct RouteBullet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let routeID: String
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        let style = RouteStyle.style(for: routeID)
        ZStack {
            if RouteID.isExpress(routeID) {
                RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .fill(style.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                            .stroke(Color.white.opacity(isSelected ? 0 : 0.28), lineWidth: 1)
                    }
                    .frame(width: size * 0.72, height: size * 0.72)
                    .rotationEffect(.degrees(45))
            } else {
                Circle()
                    .fill(style.background)
                    .overlay {
                        Circle().stroke(Color.white.opacity(isSelected ? 0 : 0.28), lineWidth: 1)
                    }
            }

            Text(RouteID.displayLabel(routeID))
                .font(.system(size: size * (RouteID.displayLabel(routeID).count > 1 ? 0.36 : 0.53), weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .foregroundStyle(style.foreground)
        }
            .frame(width: size, height: size)
            .opacity(isSelected ? 1 : 0.24)
            .scaleEffect(isSelected ? 1 : 0.9)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isSelected)
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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .frame(maxWidth: metrics.statusMaxWidth)

            if let actionTitle, let action {
                DensityAwareActionButton(title: actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(metrics.statusContentPadding)
    }
}

private struct DensityAwareActionButton: View {
    @Environment(\.menuLayoutMetrics) private var metrics

    let title: String
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if metrics.statusUsesProminentActions {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .tint(.white)
        }
    }
}
