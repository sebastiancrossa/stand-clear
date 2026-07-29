import AppKit
import CoreLocation
import MapKit
import QuartzCore
import StandClearCore
import SwiftUI

struct LiveSubwayMap: NSViewRepresentable {
    let geometry: TrackGeometryCatalog
    let stations: [LiveMapStation]
    let motionPlans: [TrainMotionPlan]
    let selectedRoutes: Set<String>
    let selectedTrainID: TrainRunID?
    let unplacedTrainCount: Int
    let userLocation: CLLocation?
    let resetToken: Int
    let reduceMotion: Bool
    let now: Date
    let onSelectTrain: (TrainRenderSnapshot?) -> Void
    let onSelectCluster: ([TrainRenderSnapshot]) -> Void
    let onActivityChange: (LiveMapActivitySummary) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelectTrain: onSelectTrain,
            onSelectCluster: onSelectCluster,
            onActivityChange: onActivityChange
        )
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = LiveMapKitView(frame: .zero)
        mapView.appearance = NSAppearance(named: .darkAqua)
        let configuration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: .muted
        )
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        mapView.preferredConfiguration = configuration
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isPitchEnabled = false
        mapView.delegate = context.coordinator

        context.coordinator.attach(
            to: mapView,
            geometry: geometry,
            stations: stations,
            motionPlans: motionPlans,
            selectedRoutes: selectedRoutes,
            selectedTrainID: selectedTrainID,
            unplacedTrainCount: unplacedTrainCount,
            userLocation: userLocation,
            reduceMotion: reduceMotion,
            now: now
        )
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onSelectTrain = onSelectTrain
        context.coordinator.onSelectCluster = onSelectCluster
        context.coordinator.onActivityChange = onActivityChange
        context.coordinator.update(
            motionPlans: motionPlans,
            selectedRoutes: selectedRoutes,
            selectedTrainID: selectedTrainID,
            unplacedTrainCount: unplacedTrainCount,
            userLocation: userLocation,
            resetToken: resetToken,
            reduceMotion: reduceMotion,
            now: now
        )
    }

    static func dismantleNSView(_ mapView: MKMapView, coordinator: Coordinator) {
        coordinator.detach(from: mapView)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelectTrain: (TrainRenderSnapshot?) -> Void
        var onSelectCluster: ([TrainRenderSnapshot]) -> Void
        var onActivityChange: (LiveMapActivitySummary) -> Void

        private weak var mapView: MKMapView?
        private var displayLink: CADisplayLink?
        private var windowVisibilityObservers: [NSKeyValueObservation] = []
        private var windowCloseObserver: NSObjectProtocol?
        private var motionPlans: [TrainMotionPlan] = []
        private var motionPlanRevision = LiveMapMotionRevision(plans: [])
        private var reducedMotionRenderDate: Date?
        private var selectedRoutes: Set<String> = []
        private var selectedTrainID: TrainRunID?
        private var unplacedTrainCount = 0
        private var trainGroups: [LiveMapTrainGroup] = []
        private var lastActivitySummary = LiveMapActivitySummary.empty
        private var stations: [LiveMapStation] = []
        private var pendingClusterTrainIDs: Set<TrainRunID>?
        private var lastResetToken = 0
        private var reduceMotion = false
        private var trackOverlay: TrackNetworkOverlay?
        private weak var trackRenderer: TrackNetworkRenderer?
        private weak var stationRenderer: StationNetworkRenderer?
        private var markerView: TrainMarkerView?
        private var markerTier: LiveMapMarkerTier = .overview
        private var lastStructuralPass: Date?
        private var structuralForceNeeded = true
        private var userLocationAnnotation: PassiveUserLocationAnnotation?

        init(
            onSelectTrain: @escaping (TrainRenderSnapshot?) -> Void,
            onSelectCluster: @escaping ([TrainRenderSnapshot]) -> Void,
            onActivityChange: @escaping (LiveMapActivitySummary) -> Void
        ) {
            self.onSelectTrain = onSelectTrain
            self.onSelectCluster = onSelectCluster
            self.onActivityChange = onActivityChange
        }

        func attach(
            to mapView: MKMapView,
            geometry: TrackGeometryCatalog,
            stations: [LiveMapStation],
            motionPlans: [TrainMotionPlan],
            selectedRoutes: Set<String>,
            selectedTrainID: TrainRunID?,
            unplacedTrainCount: Int,
            userLocation: CLLocation?,
            reduceMotion: Bool,
            now: Date
        ) {
            self.mapView = mapView
            self.motionPlans = motionPlans
            motionPlanRevision = LiveMapMotionRevision(plans: motionPlans)
            self.selectedRoutes = selectedRoutes
            self.selectedTrainID = selectedTrainID
            self.unplacedTrainCount = unplacedTrainCount
            self.stations = stations
            self.reduceMotion = reduceMotion
            reducedMotionRenderDate = reduceMotion ? now : nil
            structuralForceNeeded = true

            let trackOverlay = TrackNetworkOverlay(catalog: geometry)
            let stationOverlay = StationNetworkOverlay(stations: stations)
            self.trackOverlay = trackOverlay
            mapView.addOverlay(trackOverlay, level: .aboveRoads)
            mapView.addOverlay(stationOverlay, level: .aboveLabels)

            let markers = TrainMarkerView(frame: mapView.bounds)
            markers.autoresizingMask = [.width, .height]
            markers.configure(
                colorsByRouteID: trackOverlay.colorsByRouteID,
                textColorsByRouteID: trackOverlay.textColorsByRouteID
            )
            mapView.addSubview(markers)
            markerView = markers

            let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(didClickMap(_:)))
            clickRecognizer.numberOfClicksRequired = 1
            mapView.addGestureRecognizer(clickRecognizer)

            let displayLink = mapView.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30,
                maximum: 30,
                preferred: 30
            )
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
            observeMapWindow(for: mapView)
            updateDisplayLinkState(renderWhenResumed: false)

            updateUserLocation(userLocation)
            render(at: now, forceStructural: true)
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.showFullSystem(on: mapView, animated: false)
            }
        }

        func update(
            motionPlans: [TrainMotionPlan],
            selectedRoutes: Set<String>,
            selectedTrainID: TrainRunID?,
            unplacedTrainCount: Int,
            userLocation: CLLocation?,
            resetToken: Int,
            reduceMotion: Bool,
            now: Date
        ) {
            let newRevision = LiveMapMotionRevision(plans: motionPlans)
            let didReceiveNewPlans = newRevision != motionPlanRevision
            let didChangeRoutes = selectedRoutes != self.selectedRoutes
            let didEnableReduceMotion = reduceMotion && !self.reduceMotion
            if didReceiveNewPlans || didChangeRoutes {
                pendingClusterTrainIDs = nil
                structuralForceNeeded = true
            }
            if selectedTrainID != self.selectedTrainID {
                structuralForceNeeded = true
            }
            self.motionPlans = motionPlans
            motionPlanRevision = newRevision
            self.selectedRoutes = selectedRoutes
            self.selectedTrainID = selectedTrainID
            self.unplacedTrainCount = unplacedTrainCount
            self.reduceMotion = reduceMotion
            if reduceMotion {
                if LiveMapAnimationPolicy.shouldAdvanceReducedMotionSnapshot(
                    didReceiveNewPlans: didReceiveNewPlans,
                    didEnableReduceMotion: didEnableReduceMotion,
                    hasFrozenSnapshot: reducedMotionRenderDate != nil
                ) {
                    reducedMotionRenderDate = now
                }
            } else {
                reducedMotionRenderDate = nil
            }
            updateDisplayLinkState()
            trackRenderer?.selectedRoutes = selectedRoutes
            stationRenderer?.selectedRoutes = selectedRoutes
            updateUserLocation(userLocation)
            render(
                at: now,
                forceStructural: structuralForceNeeded,
                didReceiveNewPlans: didReceiveNewPlans,
                didChangeRoutes: didChangeRoutes
            )

            if resetToken != lastResetToken, let mapView {
                lastResetToken = resetToken
                pendingClusterTrainIDs = nil
                showFullSystem(on: mapView, animated: !reduceMotion)
            }
        }

        func detach(from mapView: MKMapView) {
            removeWindowObservers()
            displayLink?.invalidate()
            displayLink = nil
            markerView?.removeFromSuperview()
            markerView = nil
            self.mapView = nil
            mapView.delegate = nil
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let overlay = overlay as? TrackNetworkOverlay {
                let renderer = TrackNetworkRenderer(overlay: overlay)
                renderer.selectedRoutes = selectedRoutes
                trackRenderer = renderer
                return renderer
            }
            if let overlay = overlay as? StationNetworkOverlay {
                let renderer = StationNetworkRenderer(overlay: overlay)
                renderer.selectedRoutes = selectedRoutes
                renderer.detail = LiveMapPresentation.stationDetail(
                    longitudeDelta: mapView.region.span.longitudeDelta
                )
                stationRenderer = renderer
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            let nextTier = LiveMapPresentation.markerTier(
                longitudeDelta: mapView.region.span.longitudeDelta
            )
            stationRenderer?.detail = LiveMapPresentation.stationDetail(
                longitudeDelta: mapView.region.span.longitudeDelta
            )
            let didChangeTier = nextTier != markerTier
            if didChangeTier {
                structuralForceNeeded = true
            }
            render(at: Date(), forceStructural: didChangeTier, didChangeTier: didChangeTier)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            render(at: Date(), forceStructural: true)
            guard let pendingClusterTrainIDs else { return }
            self.pendingClusterTrainIDs = nil
            guard let surviving = LiveMapPresentation.survivingCluster(
                trainIDs: pendingClusterTrainIDs,
                groups: trainGroups
            ) else { return }
            onSelectCluster(surviving.snapshots)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard annotation is PassiveUserLocationAnnotation else { return nil }
            let identifier = "passive-user-location"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.frame = NSRect(x: 0, y: 0, width: 18, height: 18)
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.systemBlue.cgColor
            view.layer?.borderColor = NSColor.white.cgColor
            view.layer?.borderWidth = 3
            view.layer?.cornerRadius = 9
            view.toolTip = "Your approximate location"
            view.setAccessibilityLabel("Your approximate location")
            return view
        }

        @objc private func displayLinkDidFire(_ displayLink: CADisplayLink) {
            guard LiveMapAnimationPolicy.shouldRunDisplayLink(
                reduceMotion: reduceMotion,
                isWindowVisible: isMapWindowVisible
            ) else { return }
            render(at: Date())
        }

        private func mapViewDidMoveToWindow() {
            guard let mapView else { return }
            observeMapWindow(for: mapView)
            updateDisplayLinkState()
        }

        private func mapWindowVisibilityDidChange() {
            updateDisplayLinkState()
        }

        private func mapWindowWillClose() {
            displayLink?.isPaused = true
        }

        @objc private func didClickMap(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended, let mapView else { return }
            let clickPoint = recognizer.location(in: mapView)
            let radius = LiveMapPresentation.hitTestRadius(for: markerTier)
            guard let hit = LiveMapPresentation.hitTest(trainGroups, at: clickPoint, radius: radius) else {
                onSelectTrain(nil)
                return
            }
            if hit.isCluster {
                if LiveMapPresentation.clusterSelectionAction(
                    longitudeDelta: mapView.region.span.longitudeDelta
                ) == .zoom {
                    pendingClusterTrainIDs = Set(hit.snapshots.map(\.id))
                    zoom(to: hit, on: mapView)
                } else {
                    onSelectCluster(hit.snapshots)
                }
                return
            }
            onSelectTrain(hit.snapshots.first)
        }

        private func render(
            at date: Date,
            forceStructural: Bool = false,
            didReceiveNewPlans: Bool = false,
            didChangeRoutes: Bool = false,
            didChangeTier: Bool = false
        ) {
            guard let mapView else { return }
            let renderDate = reduceMotion ? (reducedMotionRenderDate ?? date) : date
            let nextTier = LiveMapPresentation.markerTier(
                longitudeDelta: mapView.region.span.longitudeDelta
            )
            let tierChanged = nextTier != markerTier || didChangeTier
            markerTier = nextTier

            let shouldRunStructural = forceStructural
                || structuralForceNeeded
                || LiveMapStructuralPassPolicy.shouldRun(
                    now: date,
                    lastStructuralPass: lastStructuralPass,
                    didReceiveNewPlans: didReceiveNewPlans,
                    didChangeRoutes: didChangeRoutes,
                    didChangeTier: tierChanged
                )

            let activeSnapshots = motionPlans
                .filter { selectedRoutes.contains($0.routeID) }
                .compactMap { $0.render(at: renderDate) }

            if shouldRunStructural {
                runStructuralPass(
                    activeSnapshots: activeSnapshots,
                    at: date,
                    on: mapView
                )
            }

            animateMarkers(activeSnapshots: activeSnapshots, on: mapView)
        }

        private func runStructuralPass(
            activeSnapshots: [TrainRenderSnapshot],
            at date: Date,
            on mapView: MKMapView
        ) {
            let mapRect = mapView.visibleMapRect
            let bounds = GeographicBounds(mapRect: mapRect)
            let nextSnapshots = LiveMapPresentation.visibleSnapshots(
                activeSnapshots,
                selectedRoutes: selectedRoutes,
                bounds: bounds
            )
            let targets = nextSnapshots.map { snapshot in
                LiveMapHitTarget(
                    snapshot: snapshot,
                    point: mapView.convert(
                        CLLocationCoordinate2D(
                            latitude: snapshot.position.latitude,
                            longitude: snapshot.position.longitude
                        ),
                        toPointTo: mapView
                    )
                )
            }
            let nextGroups = LiveMapPresentation.trainGroups(
                targets,
                collisionDistance: LiveMapPresentation.collisionDistance(for: markerTier)
            )
            trainGroups = nextGroups
            lastStructuralPass = date
            structuralForceNeeded = false

            markerView?.updatePresentation(
                tier: markerTier,
                selectedTrainID: selectedTrainID,
                reduceMotion: reduceMotion
            )
            markerView?.syncGroups(nextGroups)

            (mapView as? LiveMapKitView)?.updateAccessibility(
                stations: stations,
                groups: trainGroups,
                selectedRoutes: selectedRoutes
            )
            let activitySummary = LiveMapPresentation.activitySummary(
                activeSnapshots: activeSnapshots,
                visibleGroups: trainGroups,
                unplacedTrainCount: unplacedTrainCount
            )
            if activitySummary != lastActivitySummary {
                lastActivitySummary = activitySummary
                DispatchQueue.main.async { [weak self] in
                    self?.onActivityChange(activitySummary)
                }
            }
        }

        private func animateMarkers(
            activeSnapshots: [TrainRenderSnapshot],
            on mapView: MKMapView
        ) {
            guard let markerView else { return }
            let snapshotsByID = Dictionary(uniqueKeysWithValues: activeSnapshots.map { ($0.id, $0) })
            var positions: [String: TrainMarkerView.MarkerPosition] = [:]

            for group in trainGroups {
                let id = TrainMarkerView.markerID(for: group)
                guard let anchor = group.anchorSnapshot else { continue }
                let liveAnchor = snapshotsByID[anchor.id] ?? anchor
                let point = mapView.convert(
                    CLLocationCoordinate2D(
                        latitude: liveAnchor.position.latitude,
                        longitude: liveAnchor.position.longitude
                    ),
                    toPointTo: mapView
                )
                let previousPoint: CGPoint?
                if let previous = liveAnchor.previousTopologyPosition {
                    previousPoint = mapView.convert(
                        CLLocationCoordinate2D(
                            latitude: previous.latitude,
                            longitude: previous.longitude
                        ),
                        toPointTo: mapView
                    )
                } else {
                    previousPoint = nil
                }
                let presentation = LiveMapPresentation.markerPresentation(
                    for: liveAnchor,
                    tier: markerTier
                )
                positions[id] = TrainMarkerView.MarkerPosition(
                    point: point,
                    headingDegrees: presentation.showsDirectionArrow ? liveAnchor.headingDegrees : nil,
                    previousPoint: previousPoint,
                    topologyProgress: liveAnchor.topologyTransitionProgress
                )
            }

            // Keep hit-test anchors aligned with drawn positions between structural passes.
            trainGroups = trainGroups.map { group in
                let id = TrainMarkerView.markerID(for: group)
                guard let position = positions[id] else { return group }
                return LiveMapTrainGroup(snapshots: group.snapshots, point: position.point)
            }

            markerView.updatePositions(positions)
        }

        private func zoom(to group: LiveMapTrainGroup, on mapView: MKMapView) {
            guard let anchor = group.anchorSnapshot else { return }
            let coordinate = CLLocationCoordinate2D(
                latitude: anchor.position.latitude,
                longitude: anchor.position.longitude
            )
            let span = MKCoordinateSpan(
                latitudeDelta: 0.012,
                longitudeDelta: 0.012
            )
            mapView.setRegion(
                MKCoordinateRegion(center: coordinate, span: span),
                animated: !reduceMotion
            )
        }

        private func showFullSystem(on mapView: MKMapView, animated: Bool) {
            guard let mapRect = trackOverlay?.boundingMapRect, !mapRect.isNull else { return }
            mapView.setVisibleMapRect(
                mapRect,
                edgePadding: NSEdgeInsets(top: 48, left: 48, bottom: 48, right: 48),
                animated: animated
            )
        }

        private func updateUserLocation(_ location: CLLocation?) {
            guard let mapView else { return }
            if let location, let annotation = userLocationAnnotation,
               annotation.coordinate.latitude == location.coordinate.latitude,
               annotation.coordinate.longitude == location.coordinate.longitude
            {
                return
            }
            if let annotation = userLocationAnnotation {
                mapView.removeAnnotation(annotation)
                userLocationAnnotation = nil
            }
            guard let location else { return }
            let annotation = PassiveUserLocationAnnotation(coordinate: location.coordinate)
            userLocationAnnotation = annotation
            mapView.addAnnotation(annotation)
        }

        private var isMapWindowVisible: Bool {
            guard let window = mapView?.window else { return false }
            return window.isVisible
                && !window.isMiniaturized
                && window.occlusionState.contains(.visible)
        }

        private func observeMapWindow(for mapView: MKMapView) {
            removeWindowObservers()
            if let mapView = mapView as? LiveMapKitView {
                mapView.onWindowChange = { [weak self] in
                    self?.mapViewDidMoveToWindow()
                }
            }
            guard let window = mapView.window else { return }
            let visibilityDidChange: @MainActor () -> Void = { [weak self] in
                self?.mapWindowVisibilityDidChange()
            }
            windowVisibilityObservers = [
                window.observe(\.isVisible) { _, _ in Task { @MainActor in visibilityDidChange() } },
                window.observe(\.isMiniaturized) { _, _ in Task { @MainActor in visibilityDidChange() } },
                window.observe(\.occlusionState) { _, _ in Task { @MainActor in visibilityDidChange() } },
            ]
            windowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor [weak self] in self?.mapWindowWillClose() }
            }
        }

        private func removeWindowObservers() {
            windowVisibilityObservers.removeAll()
            if let windowCloseObserver {
                NotificationCenter.default.removeObserver(windowCloseObserver)
                self.windowCloseObserver = nil
            }
        }

        private func updateDisplayLinkState(renderWhenResumed: Bool = true) {
            guard let displayLink else { return }
            let shouldRun = LiveMapAnimationPolicy.shouldRunDisplayLink(
                reduceMotion: reduceMotion,
                isWindowVisible: isMapWindowVisible
            )
            let wasPaused = displayLink.isPaused
            displayLink.isPaused = !shouldRun
            if renderWhenResumed, shouldRun, wasPaused {
                render(at: Date(), forceStructural: true)
            }
        }
    }
}

private final class LiveMapKitView: MKMapView {
    var onWindowChange: (() -> Void)?
    private var liveMapAccessibilityChildren: [NSAccessibilityElement] = []
    private var accessibilityElementsByID: [String: NSAccessibilityElement] = [:]
    private var lastAccessibilityUpdate = Date.distantPast

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }

    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + liveMapAccessibilityChildren
    }

    func updateAccessibility(
        stations: [LiveMapStation],
        groups: [LiveMapTrainGroup],
        selectedRoutes: Set<String>
    ) {
        guard NSWorkspace.shared.isVoiceOverEnabled else {
            liveMapAccessibilityChildren = []
            accessibilityElementsByID = [:]
            return
        }
        let updateDate = Date()
        guard updateDate.timeIntervalSince(lastAccessibilityUpdate) >= 0.5 else { return }
        lastAccessibilityUpdate = updateDate
        let detail = LiveMapPresentation.stationDetail(
            longitudeDelta: region.span.longitudeDelta
        )
        var nextElementsByID: [String: NSAccessibilityElement] = [:]
        let stationElements = LiveMapPresentation.visibleStations(
            stations,
            selectedRoutes: selectedRoutes,
            detail: detail
        ).compactMap { station -> NSAccessibilityElement? in
            let coordinate = CLLocationCoordinate2D(
                latitude: station.latitude,
                longitude: station.longitude
            )
            let point = convert(coordinate, toPointTo: self)
            guard bounds.insetBy(dx: -12, dy: -12).contains(point) else { return nil }
            let id = "station:\(station.id)"
            let element = accessibilityElement(
                id: id,
                label: LiveMapPresentation.stationAccessibilityLabel(station),
                centeredAt: point,
                size: 12
            )
            nextElementsByID[id] = element
            return element
        }
        let trainElements = groups.map { group in
            let runIDs = group.snapshots.map { snapshot in
                let run = snapshot.id
                return [run.feedID, run.routeID, run.tripID, run.serviceDate, run.startTime]
                    .joined(separator: ":")
            }.joined(separator: "|")
            let id = "train:\(runIDs)"
            let element = accessibilityElement(
                id: id,
                label: LiveMapPresentation.trainGroupAccessibilityLabel(group),
                centeredAt: group.point,
                size: group.isCluster ? 28 : 24
            )
            element.setAccessibilityHelp("Use the visible trains menu to inspect this marker.")
            nextElementsByID[id] = element
            return element
        }
        accessibilityElementsByID = nextElementsByID
        liveMapAccessibilityChildren = stationElements + trainElements
    }

    private func accessibilityElement(
        id: String,
        label: String,
        centeredAt point: CGPoint,
        size: CGFloat
    ) -> NSAccessibilityElement {
        let localFrame = NSRect(
            x: point.x - (size / 2),
            y: point.y - (size / 2),
            width: size,
            height: size
        )
        let windowFrame = convert(localFrame, to: nil)
        let screenFrame = window?.convertToScreen(windowFrame) ?? windowFrame
        let element = accessibilityElementsByID[id] ?? NSAccessibilityElement()
        element.setAccessibilityRole(.staticText)
        element.setAccessibilityLabel(label)
        element.setAccessibilityFrame(screenFrame)
        element.setAccessibilityParent(self)
        return element
    }
}

private struct LiveMapMotionRevision: Equatable {
    private struct Entry: Equatable {
        let id: TrainRunID
        let direction: TravelDirection
        let destination: String
        let shapeID: String?
        let nextStopID: String?
        let nextArrivalTime: Date?
        let confidence: TrainConfidence
        let movementState: TrainMovementState
        let reasons: Set<TrainProjectionReason>
        let feedTimestamp: Date
        let vehicleTimestamp: Date?
    }

    private let entries: [Entry]

    init(plans: [TrainMotionPlan]) {
        entries = plans.map {
            Entry(
                id: $0.id,
                direction: $0.direction,
                destination: $0.destination,
                shapeID: $0.shapeID,
                nextStopID: $0.nextStopID,
                nextArrivalTime: $0.nextArrivalTime,
                confidence: $0.confidence,
                movementState: $0.movementState,
                reasons: $0.reasons,
                feedTimestamp: $0.feedTimestamp,
                vehicleTimestamp: $0.vehicleTimestamp
            )
        }
        .sorted { lhs, rhs in
            if lhs.id.feedID != rhs.id.feedID { return lhs.id.feedID < rhs.id.feedID }
            if lhs.id.tripID != rhs.id.tripID { return lhs.id.tripID < rhs.id.tripID }
            return lhs.id.startTime < rhs.id.startTime
        }
    }
}

private extension GeographicBounds {
    init(mapRect: MKMapRect) {
        let northWest = MKMapPoint(x: mapRect.minX, y: mapRect.minY).coordinate
        let southEast = MKMapPoint(x: mapRect.maxX, y: mapRect.maxY).coordinate
        self.init(
            minimumLatitude: min(northWest.latitude, southEast.latitude),
            maximumLatitude: max(northWest.latitude, southEast.latitude),
            minimumLongitude: min(northWest.longitude, southEast.longitude),
            maximumLongitude: max(northWest.longitude, southEast.longitude)
        )
    }
}

private final class PassiveUserLocationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

private final class TrackNetworkOverlay: NSObject, MKOverlay {
    struct Line {
        let points: [MKMapPoint]
        let routeIDs: [String]
        let boundingMapRect: MKMapRect
    }

    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let lines: [Line]
    let colorsByRouteID: [String: NSColor]
    let textColorsByRouteID: [String: NSColor]

    init(catalog: TrackGeometryCatalog) {
        let corridors = catalog.resource.corridors.sorted { $0.id < $1.id }
        let source: [([TrackPoint], [String])] = corridors.compactMap { corridor in
            guard corridor.points.count >= 2 else { return nil }
            return (corridor.points, RouteID.sorted(corridor.routeIDs))
        }
        let resolvedSource = source.isEmpty
            ? catalog.resource.paths.map { ($0.points, RouteID.sorted($0.routeIDs)) }
            : source

        lines = resolvedSource.compactMap { pathPoints, routeIDs in
            let points = pathPoints.map {
                MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
            }
            guard points.count >= 2 else { return nil }
            return Line(
                points: points,
                routeIDs: routeIDs,
                boundingMapRect: Self.boundingRect(for: points)
            )
        }
        boundingMapRect = lines.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        coordinate = MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate
        colorsByRouteID = Dictionary(uniqueKeysWithValues: catalog.resource.routes.map { route in
            (route.id, NSColor(hexString: catalog.style(forRoute: route.id).backgroundHex))
        })
        textColorsByRouteID = Dictionary(uniqueKeysWithValues: catalog.resource.routes.map { route in
            (route.id, NSColor(hexString: catalog.style(forRoute: route.id).foregroundHex))
        })
    }

    private static func boundingRect(for points: [MKMapPoint]) -> MKMapRect {
        points.reduce(MKMapRect.null) { partial, point in
            partial.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
    }
}

private final class TrackNetworkRenderer: MKOverlayRenderer {
    var selectedRoutes: Set<String> = [] {
        didSet {
            if selectedRoutes != oldValue { setNeedsDisplay() }
        }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let network = overlay as? TrackNetworkOverlay else { return }
        let mapUnitsPerPoint = 1 / max(zoomScale, .leastNonzeroMagnitude)
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for line in network.lines where line.boundingMapRect.intersects(mapRect) {
            let routes = line.routeIDs.filter(selectedRoutes.contains)
            guard !routes.isEmpty else { continue }
            let path = CGMutablePath()
            for (index, mapPoint) in line.points.enumerated() {
                let point = point(for: mapPoint)
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }

            let routeWidth: CGFloat = 3.5 * mapUnitsPerPoint
            let routeSpacing: CGFloat = 4 * mapUnitsPerPoint
            context.addPath(path)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.78).cgColor)
            context.setLineWidth(max(7, 4 + CGFloat(routes.count) * 4) * mapUnitsPerPoint)
            context.setLineDash(phase: 0, lengths: [])
            context.strokePath()

            if routes.count == 1, let routeID = routes.first {
                context.addPath(path)
                context.setStrokeColor(color(for: routeID, network: network).cgColor)
                context.setLineWidth(routeWidth)
                context.strokePath()
                continue
            }

            for (index, routeID) in routes.enumerated() {
                let offset = (CGFloat(index) - CGFloat(routes.count - 1) / 2) * routeSpacing
                context.addPath(offsetPath(for: line.points, by: offset))
                context.setStrokeColor(color(for: routeID, network: network).cgColor)
                context.setLineWidth(routeWidth)
                context.strokePath()
            }
        }
    }

    private func offsetPath(for mapPoints: [MKMapPoint], by offset: CGFloat) -> CGPath {
        let points = mapPoints.map(point(for:))
        let path = CGMutablePath()
        for (index, point) in points.enumerated() {
            let previous = points[max(0, index - 1)]
            let next = points[min(points.count - 1, index + 1)]
            let delta = CGPoint(x: next.x - previous.x, y: next.y - previous.y)
            let length = max(hypot(delta.x, delta.y), .leastNonzeroMagnitude)
            let shifted = CGPoint(
                x: point.x - delta.y / length * offset,
                y: point.y + delta.x / length * offset
            )
            index == 0 ? path.move(to: shifted) : path.addLine(to: shifted)
        }
        return path
    }

    private func color(for routeID: String, network: TrackNetworkOverlay) -> NSColor {
        network.colorsByRouteID[routeID] ?? NSColor(hexString: RouteColor.backgroundHex(for: routeID))
    }
}

private final class StationNetworkOverlay: NSObject, MKOverlay {
    struct Item {
        let station: LiveMapStation
        let mapPoint: MKMapPoint
        let boundingMapRect: MKMapRect
    }

    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let items: [Item]

    init(stations: [LiveMapStation]) {
        items = stations.map { station in
            let mapPoint = MKMapPoint(
                CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
            )
            return Item(
                station: station,
                mapPoint: mapPoint,
                boundingMapRect: MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 0, height: 0)
            )
        }
        boundingMapRect = items.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        coordinate = MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate
    }
}

private final class StationNetworkRenderer: MKOverlayRenderer {
    var selectedRoutes: Set<String> = [] {
        didSet {
            if selectedRoutes != oldValue { setNeedsDisplay() }
        }
    }

    var detail: LiveMapStationDetail = .overview {
        didSet {
            if detail != oldValue { setNeedsDisplay() }
        }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let network = overlay as? StationNetworkOverlay else { return }
        let mapUnitsPerPoint = 1 / max(zoomScale, .leastNonzeroMagnitude)
        let expandedRect = mapRect.insetBy(
            dx: -80 * Double(mapUnitsPerPoint),
            dy: -24 * Double(mapUnitsPerPoint)
        )
        let visibleStationIDs = Set(
            LiveMapPresentation.visibleStations(
                network.items.map(\.station),
                selectedRoutes: selectedRoutes,
                detail: detail
            ).map(\.id)
        )
        let visible = network.items.filter { item in
            expandedRect.contains(item.mapPoint)
                && visibleStationIDs.contains(item.station.id)
        }
        var occupiedLabelRects: [CGRect] = []

        context.saveGState()
        defer { context.restoreGState() }

        for item in visible {
            let point = point(for: item.mapPoint)
            let radius: CGFloat = (item.station.isTransfer ? 4.2 : 2.7) * mapUnitsPerPoint
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor)
            context.fillEllipse(in: rect)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.86).cgColor)
            context.setLineWidth((item.station.isTransfer ? 1.5 : 1) * mapUnitsPerPoint)
            context.strokeEllipse(in: rect)

            guard detail == .close else { continue }
            let label = item.station.name as NSString
            let font = NSFont.systemFont(ofSize: 10 * mapUnitsPerPoint, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ]
            let size = label.size(withAttributes: attributes)
            let labelRect = CGRect(
                x: point.x + (6 * mapUnitsPerPoint),
                y: point.y - (size.height / 2),
                width: size.width,
                height: size.height
            ).insetBy(dx: -2 * mapUnitsPerPoint, dy: -1 * mapUnitsPerPoint)
            guard !occupiedLabelRects.contains(where: { $0.intersects(labelRect) }) else { continue }
            occupiedLabelRects.append(labelRect)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            label.draw(
                at: CGPoint(x: labelRect.minX, y: labelRect.minY),
                withAttributes: attributes
            )
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
