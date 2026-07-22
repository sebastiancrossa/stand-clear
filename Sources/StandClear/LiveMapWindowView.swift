import StandClearCore
import SwiftUI

struct LiveMapWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var session = LiveMapSession()
    @State private var mapActivity = LiveMapActivitySummary.empty
    @State private var clusterSnapshots: [TrainRenderSnapshot] = []

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
            clusterSnapshots = []
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
                stations: model.mapStations,
                motionPlans: model.mapMotionPlans,
                selectedRoutes: session.selectedRoutes,
                selectedTrainID: session.selectedTrainID,
                unplacedTrainCount: session.selectedRoutes.reduce(0) {
                    $0 + (model.mapUnplacedTrainCountsByRoute[$1] ?? 0)
                },
                userLocation: model.locationService.location,
                resetToken: session.resetToken,
                reduceMotion: reduceMotion,
                now: model.now
            ) { snapshot in
                clusterSnapshots = []
                session.selectTrain(id: snapshot?.id)
            } onSelectCluster: { snapshots in
                session.selectTrain(id: nil)
                clusterSnapshots = snapshots
            } onActivityChange: { summary in
                mapActivity = summary
                if !clusterSnapshots.isEmpty {
                    let selectedClusterIDs = Set(clusterSnapshots.map(\.id))
                    if !summary.clusterTrainIDSets.contains(selectedClusterIDs) {
                        clusterSnapshots = []
                    }
                }
            }
            .ignoresSafeArea()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Live NYC subway map")
            .accessibilityValue(
                "\(mapActivity.visibleTrainCount) visible trains, "
                    + "\(mapActivity.activeTrainCount) active trains"
            )
            .accessibilityHint("Estimated train positions. Use the route controls and train menu to explore.")

            VStack(spacing: 10) {
                mapToolbar(snapshots)
                routeFilters(geometry)
                Spacer(minLength: 12)

                if let selectedSnapshot {
                    trainInspector(selectedSnapshot)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !clusterSnapshots.isEmpty {
                    clusterChooser(clusterSnapshots)
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
                clusterSnapshots = []
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
        let affectedStatuses = model.mapFeedStatuses.filter { status in
            status.state == .failed
                || status.feedTimestamp.map { model.now.timeIntervalSince($0) >= 60 } != false
        }
        return Menu {
            Text(presentation.title)
            if let detail = presentation.detail {
                Text(detail)
            }
            if !affectedStatuses.isEmpty {
                Divider()
                ForEach(affectedStatuses, id: \.self) { status in
                    Text(feedStatusDetail(status))
                }
            }
        } label: {
            HStack(spacing: 8) {
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
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func feedStatusDetail(_ status: RealtimeFeedStatus) -> String {
        let routes = RouteID.sorted(status.routeIDs).map(RouteID.displayLabel).joined(separator: ", ")
        if status.state == .failed {
            return "\(routes): feed unavailable"
        }
        guard let timestamp = status.feedTimestamp else {
            return "\(routes): feed timestamp unavailable"
        }
        return "\(routes): \(Int(model.now.timeIntervalSince(timestamp))) seconds old"
    }

    private func trainPicker(_ snapshots: [TrainRenderSnapshot]) -> some View {
        let visibleSnapshots = snapshots.filter { mapActivity.visibleTrainIDs.contains($0.id) }
        let relevantStatuses = model.mapFeedStatuses.filter {
            !$0.routeIDs.isDisjoint(with: session.selectedRoutes)
        }
        let affectedStatuses = relevantStatuses.filter { status in
            status.state == .failed
                || status.feedTimestamp.map { model.now.timeIntervalSince($0) >= 60 } != false
        }
        let expiredCount = session.selectedRoutes.reduce(0) {
            $0 + (model.mapProjectionCoverage.expiredTrainCountsByRoute[$1] ?? 0)
        }
        let placementGaps = relevantStatuses.filter { status in
            let eligible = model.mapProjectionCoverage.eligibleTrainCountsByFeed[status.feedID] ?? 0
            let placed = model.mapProjectionCoverage.placedTrainCountsByFeed[status.feedID] ?? 0
            return eligible > placed
        }
        return Menu {
            Text("\(mapActivity.activeTrainCount) active across selected lines")
            if mapActivity.clusterCount > 0 {
                Text("\(mapActivity.clusterCount) overlapping group\(mapActivity.clusterCount == 1 ? "" : "s")")
            }
            if mapActivity.unplacedTrainCount > 0 {
                Text("\(mapActivity.unplacedTrainCount) reported run\(mapActivity.unplacedTrainCount == 1 ? "" : "s") unavailable on map")
                let routes = RouteID.sorted(model.mapUnplacedRouteIDs.intersection(session.selectedRoutes))
                if !routes.isEmpty {
                    Text("Affected: \(routes.map(RouteID.displayLabel).joined(separator: ", "))")
                }
            }
            if expiredCount > 0 {
                Text("\(expiredCount) expired run\(expiredCount == 1 ? "" : "s") excluded")
            }
            if !affectedStatuses.isEmpty {
                Divider()
                Text("Realtime feed health")
                ForEach(affectedStatuses, id: \.self) { status in
                    Text(feedStatusDetail(status))
                }
            }
            if !placementGaps.isEmpty {
                Divider()
                Text("Map placement")
                ForEach(placementGaps, id: \.self) { status in
                    Text(feedPlacementDetail(status))
                }
            }
            Divider()
            Text("● Station  ▰ Live train")
            Divider()
            if visibleSnapshots.isEmpty {
                Text("No visible trains")
            } else {
                ForEach(visibleSnapshots) { snapshot in
                    Button {
                        clusterSnapshots = []
                        session.selectTrain(id: snapshot.id)
                    } label: {
                        Text("\(RouteID.displayLabel(snapshot.routeID)) · \(destinationText(snapshot))")
                    }
                }
            }
        } label: {
            Label(
                "\(mapActivity.visibleTrainCount) visible · \(mapActivity.activeTrainCount) active",
                systemImage: "tram.fill"
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(MapToolbarButtonStyle())
        .accessibilityLabel(
            "Choose a visible train, \(mapActivity.visibleTrainCount) visible, "
                + "\(mapActivity.activeTrainCount) active"
        )
    }

    private func feedPlacementDetail(_ status: RealtimeFeedStatus) -> String {
        let routes = RouteID.sorted(status.routeIDs).map(RouteID.displayLabel).joined(separator: ", ")
        let eligible = model.mapProjectionCoverage.eligibleTrainCountsByFeed[status.feedID] ?? 0
        let placed = model.mapProjectionCoverage.placedTrainCountsByFeed[status.feedID] ?? 0
        return "\(routes): \(placed) of \(eligible) runs placed"
    }

    private func routeFilters(_ geometry: TrackGeometryCatalog) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Button {
                    clusterSnapshots = []
                    session.showAllRoutes()
                } label: {
                    Text("All")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(session.isShowingAllRoutes ? Color.black : .secondary)
                        .frame(minHeight: 24)
                        .padding(.horizontal, 8)
                        .background(
                            session.isShowingAllRoutes ? Color.white : Color.black.opacity(0.68),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(session.isShowingAllRoutes ? 0.55 : 0.22), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All subway lines")
                .accessibilityValue(session.isShowingAllRoutes ? "Shown" : "Custom lines shown")
                .accessibilityHint("Shows the full subway system without changing arrival preferences.")

                ForEach(RouteID.sorted(session.allRoutes), id: \.self) { routeID in
                    let selected = session.isRouteVisible(routeID)
                    let style = geometry.style(forRoute: routeID)
                    let background = Color(hexString: style.backgroundHex)
                    let foreground = Color(hexString: style.foregroundHex)

                    Button {
                        clusterSnapshots = []
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
                    .accessibilityHint(
                        session.isShowingAllRoutes
                            ? "Focuses this route without changing arrival preferences."
                            : "Adds or removes this route without changing arrival preferences."
                    )
                }
            }
            .padding(8)
        }
        .background(.ultraThickMaterial, in: Capsule())
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

    private func clusterChooser(_ snapshots: [TrainRenderSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(snapshots.count) trains at this location")
                    .font(.headline)
                Spacer()
                Button {
                    clusterSnapshots = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close overlapping trains")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(snapshots) { snapshot in
                        Button {
                            clusterSnapshots = []
                            session.selectTrain(id: snapshot.id)
                        } label: {
                            HStack(spacing: 7) {
                                routeBadge(snapshot.routeID)
                                    .scaleEffect(0.72)
                                    .frame(width: 30, height: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(destinationText(snapshot))
                                        .font(.caption.weight(.semibold))
                                    Text(directionText(snapshot.direction))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(15)
        .frame(maxWidth: 700)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(radius: 18)
        .accessibilityElement(children: .contain)
    }

    private func routeBadge(_ routeID: String) -> some View {
        let metadata = model.mapGeometry?.style(forRoute: routeID) ?? RouteStyle.metadata(for: routeID)
        let style = RouteStyle(
            background: Color(hexString: metadata.backgroundHex),
            foreground: Color(hexString: metadata.foregroundHex)
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
