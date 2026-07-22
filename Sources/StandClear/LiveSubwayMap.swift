import AppKit
import CoreLocation
import MapKit
import os
import QuartzCore
import StandClearCore
import SwiftUI

struct LiveSubwayMap: NSViewRepresentable {
    let geometry: TrackGeometryCatalog
    let motionPlans: [TrainMotionPlan]
    let selectedRoutes: Set<String>
    let selectedTrainID: TrainRunID?
    let userLocation: CLLocation?
    let resetToken: Int
    let reduceMotion: Bool
    let now: Date
    let onSelectTrain: (TrainRenderSnapshot?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectTrain: onSelectTrain)
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = LiveMapKitView(frame: .zero)
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
            motionPlans: motionPlans,
            selectedRoutes: selectedRoutes,
            selectedTrainID: selectedTrainID,
            userLocation: userLocation,
            reduceMotion: reduceMotion,
            now: now
        )
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onSelectTrain = onSelectTrain
        context.coordinator.update(
            motionPlans: motionPlans,
            selectedRoutes: selectedRoutes,
            selectedTrainID: selectedTrainID,
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

        private weak var mapView: MKMapView?
        private var displayLink: CADisplayLink?
        private var windowVisibilityObservers: [NSKeyValueObservation] = []
        private var windowCloseObserver: NSObjectProtocol?
        private var motionPlans: [TrainMotionPlan] = []
        private var motionPlanRevision = LiveMapMotionRevision(plans: [])
        private var reducedMotionRenderDate: Date?
        private var selectedRoutes: Set<String> = []
        private var selectedTrainID: TrainRunID?
        private var snapshots: [TrainRenderSnapshot] = []
        private var lastResetToken = 0
        private var reduceMotion = false
        private var trackOverlay: TrackNetworkOverlay?
        private weak var trackRenderer: TrackNetworkRenderer?
        private weak var trainRenderer: TrainNetworkRenderer?
        private var userLocationAnnotation: PassiveUserLocationAnnotation?

        init(onSelectTrain: @escaping (TrainRenderSnapshot?) -> Void) {
            self.onSelectTrain = onSelectTrain
        }

        func attach(
            to mapView: MKMapView,
            geometry: TrackGeometryCatalog,
            motionPlans: [TrainMotionPlan],
            selectedRoutes: Set<String>,
            selectedTrainID: TrainRunID?,
            userLocation: CLLocation?,
            reduceMotion: Bool,
            now: Date
        ) {
            self.mapView = mapView
            self.motionPlans = motionPlans
            motionPlanRevision = LiveMapMotionRevision(plans: motionPlans)
            self.selectedRoutes = selectedRoutes
            self.selectedTrainID = selectedTrainID
            self.reduceMotion = reduceMotion
            reducedMotionRenderDate = reduceMotion ? now : nil

            let trackOverlay = TrackNetworkOverlay(catalog: geometry)
            let trainOverlay = TrainNetworkOverlay()
            self.trackOverlay = trackOverlay
            mapView.addOverlay(trackOverlay, level: .aboveRoads)
            mapView.addOverlay(trainOverlay, level: .aboveLabels)

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
            render(at: now)
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.showFullSystem(on: mapView, animated: false)
            }
        }

        func update(
            motionPlans: [TrainMotionPlan],
            selectedRoutes: Set<String>,
            selectedTrainID: TrainRunID?,
            userLocation: CLLocation?,
            resetToken: Int,
            reduceMotion: Bool,
            now: Date
        ) {
            let newRevision = LiveMapMotionRevision(plans: motionPlans)
            let didReceiveNewPlans = newRevision != motionPlanRevision
            let didEnableReduceMotion = reduceMotion && !self.reduceMotion
            self.motionPlans = motionPlans
            motionPlanRevision = newRevision
            self.selectedRoutes = selectedRoutes
            self.selectedTrainID = selectedTrainID
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
            updateUserLocation(userLocation)
            render(at: now)

            if resetToken != lastResetToken, let mapView {
                lastResetToken = resetToken
                showFullSystem(on: mapView, animated: !reduceMotion)
            }
        }

        func detach(from mapView: MKMapView) {
            removeWindowObservers()
            displayLink?.invalidate()
            displayLink = nil
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
            if let overlay = overlay as? TrainNetworkOverlay {
                let renderer = TrainNetworkRenderer(overlay: overlay)
                renderer.snapshots = snapshots
                renderer.selectedTrainID = selectedTrainID
                renderer.reduceMotion = reduceMotion
                renderer.colorsByRouteID = trackOverlay?.colorsByRouteID ?? [:]
                renderer.textColorsByRouteID = trackOverlay?.textColorsByRouteID ?? [:]
                trainRenderer = renderer
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            render(at: Date())
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
            let targets = snapshots.map { snapshot in
                let coordinate = CLLocationCoordinate2D(
                    latitude: snapshot.position.latitude,
                    longitude: snapshot.position.longitude
                )
                return LiveMapHitTarget(snapshot: snapshot, point: mapView.convert(coordinate, toPointTo: mapView))
            }
            let hit = LiveMapPresentation.hitTest(targets, at: clickPoint, radius: 15)
            onSelectTrain(hit)
        }

        private func render(at date: Date) {
            guard let mapView else { return }
            let renderDate = reduceMotion ? (reducedMotionRenderDate ?? date) : date
            let mapRect = mapView.visibleMapRect
            let bounds = GeographicBounds(mapRect: mapRect)
            let rendered = motionPlans.lazy
                .filter { self.selectedRoutes.contains($0.routeID) }
                .compactMap { $0.render(at: renderDate) }
            let nextSnapshots = LiveMapPresentation.visibleSnapshots(
                Array(rendered),
                selectedRoutes: selectedRoutes,
                bounds: bounds
            )
            let needsRedraw = nextSnapshots != snapshots
                || trainRenderer?.selectedTrainID != selectedTrainID
                || trainRenderer?.reduceMotion != reduceMotion
            guard needsRedraw else { return }
            snapshots = nextSnapshots
            trainRenderer?.snapshots = snapshots
            trainRenderer?.selectedTrainID = selectedTrainID
            trainRenderer?.reduceMotion = reduceMotion
            trainRenderer?.setNeedsDisplay(mapRect)
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
                render(at: Date())
            }
        }
    }
}

private final class LiveMapKitView: MKMapView {
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
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

private final class TrainNetworkOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude: 40.72, longitude: -73.94)
    let boundingMapRect = MKMapRect.world
}

private final class TrainNetworkRenderer: MKOverlayRenderer {
    var snapshots: [TrainRenderSnapshot] = []
    var selectedTrainID: TrainRunID?
    var reduceMotion = false
    var colorsByRouteID: [String: NSColor] = [:]
    var textColorsByRouteID: [String: NSColor] = [:]

    private let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.standclear.app",
        category: "LiveMapRenderer"
    )

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let interval = signposter.beginInterval("DrawTrains")
        defer { signposter.endInterval("DrawTrains", interval) }

        for snapshot in snapshots {
            let mapPoint = MKMapPoint(
                CLLocationCoordinate2D(
                    latitude: snapshot.position.latitude,
                    longitude: snapshot.position.longitude
                )
            )
            guard mapRect.insetBy(dx: -32 / Double(zoomScale), dy: -32 / Double(zoomScale)).contains(mapPoint) else {
                continue
            }

            if !reduceMotion,
               let oldPosition = snapshot.previousTopologyPosition,
               snapshot.topologyTransitionProgress < 1
            {
                let oldPoint = point(
                    for: MKMapPoint(
                        CLLocationCoordinate2D(
                            latitude: oldPosition.latitude,
                            longitude: oldPosition.longitude
                        )
                    )
                )
                draw(
                    snapshot,
                    at: oldPoint,
                    alpha: 1 - snapshot.topologyTransitionProgress,
                    zoomScale: zoomScale,
                    in: context
                )
                draw(
                    snapshot,
                    at: point(for: mapPoint),
                    alpha: snapshot.topologyTransitionProgress,
                    zoomScale: zoomScale,
                    in: context
                )
            } else {
                draw(
                    snapshot,
                    at: point(for: mapPoint),
                    alpha: 1,
                    zoomScale: zoomScale,
                    in: context
                )
            }
        }
    }

    private func draw(
        _ snapshot: TrainRenderSnapshot,
        at point: CGPoint,
        alpha: Double,
        zoomScale: MKZoomScale,
        in context: CGContext
    ) {
        let mapUnitsPerPoint = 1 / max(zoomScale, .leastNonzeroMagnitude)
        let isSelected = snapshot.id == selectedTrainID
        let radius: CGFloat = (isSelected ? 11 : 9) * mapUnitsPerPoint
        let markerRect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let healthAlpha: Double = snapshot.health == .live ? 1 : 0.62

        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(alpha * healthAlpha)

        if isSelected {
            context.setFillColor(NSColor.white.withAlphaComponent(0.30).cgColor)
            context.fillEllipse(
                in: markerRect.insetBy(dx: -5 * mapUnitsPerPoint, dy: -5 * mapUnitsPerPoint)
            )
        }

        let routeColor = colorsByRouteID[snapshot.routeID]
            ?? NSColor(hexString: RouteColor.backgroundHex(for: snapshot.routeID))
        context.setFillColor(routeColor.cgColor)
        context.fillEllipse(in: markerRect)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.88).cgColor)
        context.setLineWidth(2.5 * mapUnitsPerPoint)
        context.strokeEllipse(in: markerRect)

        if snapshot.confidence == .low || snapshot.health != .live {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1.5 * mapUnitsPerPoint)
            context.setLineDash(
                phase: 0,
                lengths: [2.5 * mapUnitsPerPoint, 2.5 * mapUnitsPerPoint]
            )
            context.strokeEllipse(
                in: markerRect.insetBy(
                    dx: -2.5 * mapUnitsPerPoint,
                    dy: -2.5 * mapUnitsPerPoint
                )
            )
            context.setLineDash(phase: 0, lengths: [])
        }

        drawRouteGlyph(
            snapshot.routeID,
            centeredAt: point,
            mapUnitsPerPoint: mapUnitsPerPoint,
            in: context
        )

        if snapshot.health == .stalled {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2 * mapUnitsPerPoint)
            context.move(
                to: CGPoint(
                    x: point.x + radius + (3 * mapUnitsPerPoint),
                    y: point.y - (3 * mapUnitsPerPoint)
                )
            )
            context.addLine(
                to: CGPoint(
                    x: point.x + radius + (3 * mapUnitsPerPoint),
                    y: point.y + (3 * mapUnitsPerPoint)
                )
            )
            context.move(
                to: CGPoint(
                    x: point.x + radius + (6 * mapUnitsPerPoint),
                    y: point.y - (3 * mapUnitsPerPoint)
                )
            )
            context.addLine(
                to: CGPoint(
                    x: point.x + radius + (6 * mapUnitsPerPoint),
                    y: point.y + (3 * mapUnitsPerPoint)
                )
            )
            context.strokePath()
        }
    }

    private func drawRouteGlyph(
        _ routeID: String,
        centeredAt point: CGPoint,
        mapUnitsPerPoint: CGFloat,
        in context: CGContext
    ) {
        let label = RouteID.displayLabel(routeID) as NSString
        let font = NSFont.systemFont(ofSize: 9 * mapUnitsPerPoint, weight: .bold)
        let color = textColorsByRouteID[routeID]
            ?? NSColor(hexString: RouteColor.textHex(for: routeID))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let size = label.size(withAttributes: attributes)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        label.draw(
            at: CGPoint(x: point.x - (size.width / 2), y: point.y - (size.height / 2)),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}

private extension NSColor {
    convenience init(hexString: String) {
        let value = UInt32(hexString, radix: 16) ?? 0x808183
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
