import CoreLocation
import SubwayBarCore
import SwiftUI

struct SubwayMenuView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.12))
                content
                Divider().overlay(Color.white.opacity(0.12))
                footer
            }
        }
        .frame(width: 420, height: 610)
        .preferredColorScheme(.dark)
        .task { model.start() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.nearestStation?.name.uppercased() ?? "SUBWAYBAR")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)

                if let distance = model.distanceToStation {
                    Text("NEAREST STATION · \(distanceText(distance))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("LIVE NYC SUBWAY ARRIVALS")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if model.nearestStation != nil {
                Button {
                    model.isChoosingLines.toggle()
                } label: {
                    Image(systemName: model.isChoosingLines ? "xmark" : "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isChoosingLines ? "Close line picker" : "Choose lines")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.startupError {
            StatusView(
                symbol: "exclamationmark.triangle.fill",
                title: "Couldn’t start SubwayBar",
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
                    message: "Allow location access so SubwayBar can find the station closest to you. Your coordinates stay on this Mac.",
                    actionTitle: "Open Location Settings",
                    action: model.openLocationSettings
                )
            default:
                if model.nearestStation == nil {
                    StatusView(
                        symbol: "location.fill",
                        title: "Finding your station",
                        message: "SubwayBar is waiting for a location fix and loading the latest MTA arrivals.",
                        actionTitle: "Try Again",
                        action: model.locationService.requestLocation
                    )
                } else if model.isChoosingLines {
                    RoutePickerView()
                } else {
                    ArrivalListView()
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Updating")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let updated = model.lastUpdated {
                Text("Updated \(updated, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting for MTA")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .accessibilityLabel("Refresh arrivals")

            Button("Quit") { model.quit() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        let feet = meters * 3.28084
        if feet < 1_000 {
            return "\(Int(feet.rounded())) FT"
        }
        return String(format: "%.1f MI", meters / 1_609.344)
    }
}

private struct RoutePickerView: View {
    @EnvironmentObject private var model: AppModel

    private let columns = Array(repeating: GridItem(.fixed(58), spacing: 14), count: 4)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("CHOOSE YOUR LINES")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Only selected lines appear on your arrival board.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if model.availableRoutes.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Checking this station’s lines…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 48)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.availableRoutes, id: \.self) { routeID in
                            Button {
                                model.toggleRoute(routeID)
                            } label: {
                                RouteBullet(
                                    routeID: routeID,
                                    size: 54,
                                    isSelected: model.selectedRoutes.contains(routeID)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(routeID) train")
                            .accessibilityValue(model.selectedRoutes.contains(routeID) ? "Selected" : "Not selected")
                        }
                    }
                }

                Button {
                    model.finishChoosingLines()
                } label: {
                    HStack {
                        Text("Show arrivals")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white)
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.selectedRoutes.intersection(model.availableRoutes).isEmpty)
                .opacity(model.selectedRoutes.intersection(model.availableRoutes).isEmpty ? 0.35 : 1)
            }
            .padding(24)
        }
    }
}

private struct ArrivalListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let warning = model.feedWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0xFCCC0A))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }

                if model.displayedArrivals.isEmpty, !model.isRefreshing {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No selected trains right now")
                            .font(.headline)
                        Text("Try another line or refresh the MTA feed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Choose Lines") { model.isChoosingLines = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
                } else {
                    ForEach(TravelDirection.allCases, id: \.self) { direction in
                        let arrivals = model.displayedArrivals.filter { $0.direction == direction }
                        if !arrivals.isEmpty {
                            Text(direction.title)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.top, 18)
                                .padding(.bottom, 6)

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
    let arrival: Arrival
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            RouteBullet(routeID: arrival.routeID, size: 46, isSelected: true)

            Text(arrival.direction.arrow)
                .font(.system(size: 38, weight: .light, design: .rounded))
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(arrival.destination.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Text("REAL-TIME ARRIVAL")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(arrival.etaText(relativeTo: now))
                .font(.system(size: 24, weight: .regular, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(arrival.routeID) train \(arrival.direction.rawValue) to \(arrival.destination), \(arrival.etaText(relativeTo: now))"
        )
    }
}

private struct RouteBullet: View {
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
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
