import StandClearCore
import SwiftUI

struct LiveMapWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var session = LiveMapSession()

    var body: some View {
        return ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .frame(minWidth: 720, minHeight: 520)
        .preferredColorScheme(.dark)
        .task {
            await model.loadMapGeometry()
            synchronizeSession()
        }
        .onReceive(model.$mapGeometry) { _ in
            synchronizeSession()
        }
        .onReceive(model.$mapMotionPlans) { _ in
            reconcileSelection(at: model.now)
        }
        .onReceive(model.$now) { date in
            reconcileSelection(at: date)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isMapGeometryLoading || (model.mapGeometry == nil && model.mapGeometryError == nil) {
            mapLoadingView
        } else if let error = model.mapGeometryError {
            mapErrorView(error)
        } else if let geometry = model.mapGeometry {
            liveMap(geometry)
        }
    }

    private var mapLoadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading subway map…")
                .foregroundStyle(.secondary)
        }
    }

    private func mapErrorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "map.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("Couldn’t load the subway map")
                .font(.title2.weight(.semibold))
            Text(error)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task {
                    await model.loadMapGeometry()
                    synchronizeSession()
                }
            }
        }
        .padding(32)
    }

    private func liveMap(_ geometry: TrackGeometryCatalog) -> some View {
        let snapshots = visibleSnapshots
        let selectedSnapshot = session.selectedTrainID.flatMap { selectedID in
            snapshots.first { $0.id == selectedID }
        }
        return ZStack {
            LiveSubwayMap(
                geometry: geometry,
                motionPlans: model.mapMotionPlans,
                selectedRoutes: session.selectedRoutes,
                selectedTrainID: session.selectedTrainID,
                userLocation: model.locationService.location,
                resetToken: session.resetToken,
                reduceMotion: reduceMotion,
                now: model.now
            ) { snapshot in
                session.selectTrain(id: snapshot?.id)
            }
            .ignoresSafeArea()
            .accessibilityLabel("Live NYC subway map")
            .accessibilityHint("Estimated train positions. Use the route controls and train menu to explore.")

            VStack(spacing: 10) {
                mapToolbar(snapshots)
                routeFilters(geometry)
                Spacer(minLength: 12)

                if session.needsRouteRecovery {
                    routeRecovery
                }

                if let selectedSnapshot {
                    trainInspector(selectedSnapshot)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(14)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: session.selectedTrainID)
    }

    private func mapToolbar(_ snapshots: [TrainRenderSnapshot]) -> some View {
        HStack(spacing: 10) {
            feedStatus
            Spacer(minLength: 10)
            trainPicker(snapshots)
            Button {
                session.requestReset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(MapToolbarButtonStyle())
            .keyboardShortcut("0", modifiers: .command)
            .accessibilityHint("Returns the map to the full subway system, including Staten Island.")
        }
    }

    private var feedStatus: some View {
        let presentation = LiveMapFeedPresentation.make(
            statuses: model.mapFeedStatuses,
            latestTimestamp: model.mapLatestFeedTimestamp,
            now: model.now,
            failureMessage: model.feedWarning
        )
        return HStack(spacing: 8) {
            Circle()
                .fill(feedStatusColor(presentation.state))
                .frame(width: 8, height: 8)
                .overlay {
                    if presentation.state == .waiting {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                if let timestamp = presentation.timestamp {
                    (Text("Updated ") + Text(timestamp, style: .relative))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let detail = presentation.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if presentation.state == .partial
                || presentation.state == .stale
                || presentation.state == .unavailable
            {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                if let detail = presentation.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThickMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func trainPicker(_ snapshots: [TrainRenderSnapshot]) -> some View {
        Menu {
            if snapshots.isEmpty {
                Text("No visible trains")
            } else {
                ForEach(snapshots) { snapshot in
                    Button {
                        session.selectTrain(id: snapshot.id)
                    } label: {
                        Text("\(RouteID.displayLabel(snapshot.routeID)) · \(destinationText(snapshot))")
                    }
                }
            }
        } label: {
            Label("\(snapshots.count) trains", systemImage: "tram.fill")
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(MapToolbarButtonStyle())
        .accessibilityLabel("Choose a train, \(snapshots.count) available")
    }

    private func routeFilters(_ geometry: TrackGeometryCatalog) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(RouteID.sorted(session.allRoutes), id: \.self) { routeID in
                    let selected = session.isRouteVisible(routeID)
                    let metadata = geometry.route(routeID)
                    let background = Color(
                        hexString: metadata?.colorHex ?? RouteColor.backgroundHex(for: routeID)
                    )
                    let foreground = Color(
                        hexString: metadata?.textColorHex ?? RouteColor.textHex(for: routeID)
                    )

                    Button {
                        session.toggleRoute(routeID)
                    } label: {
                        Text(RouteID.displayLabel(routeID))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? foreground : .secondary)
                            .frame(minWidth: 24, minHeight: 24)
                            .padding(.horizontal, 2)
                            .background(selected ? background : Color.black.opacity(0.68), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(selected ? Color.white.opacity(0.45) : Color.white.opacity(0.22), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(RouteID.displayLabel(routeID)) train")
                    .accessibilityValue(selected ? "Shown" : "Hidden")
                    .accessibilityHint("Toggles this route without changing arrival preferences.")
                }
            }
            .padding(8)
        }
        .background(.ultraThickMaterial, in: Capsule())
    }

    private var routeRecovery: some View {
        VStack(spacing: 9) {
            Text("All routes are hidden")
                .font(.headline)
            Text("Choose a route above or restore the full system.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Show all routes") {
                session.showAllRoutes()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
        .padding(16)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 14)
        .accessibilityElement(children: .contain)
    }

    private func trainInspector(_ snapshot: TrainRenderSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            routeBadge(snapshot.routeID)

            VStack(alignment: .leading, spacing: 5) {
                Text(destinationText(snapshot))
                    .font(.headline)
                    .lineLimit(1)
                Text(directionText(snapshot.direction))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let nextStopID = snapshot.nextStopID {
                    HStack(spacing: 4) {
                        Text("Next: \(model.mapStationName(forStopID: nextStopID) ?? nextStopID)")
                        if let arrival = snapshot.nextArrivalTime {
                            Text("· \(etaText(arrival))")
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline.weight(.medium))
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Label(healthText(snapshot.health), systemImage: healthSymbol(snapshot.health))
                    .foregroundStyle(healthColor(snapshot.health))
                Text("\(confidenceText(snapshot.confidence)) confidence")
                if !snapshot.reasons.isEmpty {
                    Text(reasonText(snapshot.reasons))
                        .lineLimit(2)
                }
                (Text("Feed ") + Text(snapshot.feedTimestamp, style: .relative))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                session.selectTrain(id: nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close train details")
        }
        .padding(15)
        .frame(maxWidth: 700)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(radius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trainAccessibilityLabel(snapshot))
    }

    private func routeBadge(_ routeID: String) -> some View {
        let metadata = model.mapGeometry?.route(routeID)
        let style = RouteStyle(
            background: Color(hexString: metadata?.colorHex ?? RouteColor.backgroundHex(for: routeID)),
            foreground: Color(hexString: metadata?.textColorHex ?? RouteColor.textHex(for: routeID))
        )
        return Text(RouteID.displayLabel(routeID))
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(style.foreground)
            .frame(width: 38, height: 38)
            .background(style.background, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
    }

    private var visibleSnapshots: [TrainRenderSnapshot] {
        model.mapMotionPlans
            .compactMap { $0.render(at: model.now) }
            .filter { session.isRouteVisible($0.routeID) }
            .sorted {
                if $0.routeID != $1.routeID { return $0.routeID < $1.routeID }
                return $0.id.tripID < $1.id.tripID
            }
    }

    private func synchronizeSession() {
        let routes = Set(model.mapGeometry?.resource.routes.map(\.id) ?? [])
        session.updateAllRoutes(routes)
        reconcileSelection(at: model.now)
    }

    private func reconcileSelection(at date: Date) {
        let liveTrainIDs = Set(model.mapMotionPlans.lazy.filter {
            $0.dataHealth(at: date) != .expired
        }.map(\.id))
        session.reconcile(trainIDs: liveTrainIDs)
    }

    private func destinationText(_ snapshot: TrainRenderSnapshot) -> String {
        snapshot.destination.isEmpty ? "Destination unavailable" : "To \(snapshot.destination)"
    }

    private func directionText(_ direction: TravelDirection) -> String {
        switch direction {
        case .northbound: "Uptown / northbound"
        case .southbound: "Downtown / southbound"
        case .unknown: "Direction unavailable"
        }
    }

    private func etaText(_ date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(model.now)))
        if seconds < 30 { return "due" }
        return "\(Int(ceil(Double(seconds) / 60))) min"
    }

    private func feedStatusColor(_ state: LiveMapFeedPresentation.State) -> Color {
        switch state {
        case .waiting: .secondary
        case .live: .green
        case .partial, .stale: .yellow
        case .unavailable: .red
        }
    }

    private func healthText(_ health: TrainDataHealth) -> String {
        switch health {
        case .live: "Live estimate"
        case .aging: "Feed aging"
        case .stalled: "Train stalled"
        case .expired: "Expired"
        }
    }

    private func healthSymbol(_ health: TrainDataHealth) -> String {
        switch health {
        case .live: "wave.3.right"
        case .aging: "clock.badge.exclamationmark"
        case .stalled: "pause.circle"
        case .expired: "xmark.circle"
        }
    }

    private func healthColor(_ health: TrainDataHealth) -> Color {
        health == .live ? .green : .yellow
    }

    private func confidenceText(_ confidence: TrainConfidence) -> String {
        switch confidence {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    private func reasonText(_ reasons: Set<TrainProjectionReason>) -> String {
        reasons.sorted { $0.rawValue < $1.rawValue }.map { reason in
            switch reason {
            case .inferredDeparture: "departure inferred"
            case .trackMismatch: "platform changed"
            case .topologyMismatch: "route corrected"
            case .unmatchedGeometry: "station-only estimate"
            }
        }.joined(separator: " · ")
    }

    private func trainAccessibilityLabel(_ snapshot: TrainRenderSnapshot) -> String {
        let nextStop = snapshot.nextStopID
            .flatMap(model.mapStationName(forStopID:))
            .map { ", next stop \($0)" }
            ?? ""
        return "\(RouteID.displayLabel(snapshot.routeID)) train, \(destinationText(snapshot)), "
            + "\(directionText(snapshot.direction))\(nextStop), \(healthText(snapshot.health)), "
            + "\(confidenceText(snapshot.confidence)) confidence"
    }
}

private struct MapToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.ultraThickMaterial, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
