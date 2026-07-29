import AppKit
import CoreText
import QuartzCore
import StandClearCore

/// Layer-backed train markers drawn above MapKit. Positions update every display-link
/// frame; marker artwork is rasterized once into a small image cache.
final class TrainMarkerView: NSView {
    private struct MarkerImageKey: Hashable {
        let kind: Kind
        let routeID: String
        let routes: [String]
        let countLabel: String
        let selected: Bool
        let dashed: Bool
        let indicator: LiveMapTrainMarkerIndicator
        let showsRouteGlyph: Bool
        let radiusPoints: CGFloat
        let backgroundHex: String
        let foregroundHex: String

        enum Kind: Hashable {
            case single
            case cluster
        }
    }

    private struct MarkerLayers {
        let container: CALayer
        let body: CALayer
        let arrow: CALayer?
        let fadeBody: CALayer?
    }

    private var markerLayersByID: [String: MarkerLayers] = [:]
    private var imageCache: [MarkerImageKey: CGImage] = [:]
    private var arrowImage: CGImage?
    private var colorsByRouteID: [String: NSColor] = [:]
    private var textColorsByRouteID: [String: NSColor] = [:]
    private var tier: LiveMapMarkerTier = .overview
    private var selectedTrainID: TrainRunID?
    private var reduceMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(
        colorsByRouteID: [String: NSColor],
        textColorsByRouteID: [String: NSColor]
    ) {
        self.colorsByRouteID = colorsByRouteID
        self.textColorsByRouteID = textColorsByRouteID
    }

    func updatePresentation(
        tier: LiveMapMarkerTier,
        selectedTrainID: TrainRunID?,
        reduceMotion: Bool
    ) {
        self.tier = tier
        self.selectedTrainID = selectedTrainID
        self.reduceMotion = reduceMotion
    }

    /// Rebuilds marker layers for the current group structure. Call from the throttled
    /// structural pass; frame animation only moves positions via `updatePositions`.
    func syncGroups(_ groups: [LiveMapTrainGroup]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        var nextIDs = Set<String>()
        for group in groups {
            let id = markerID(for: group)
            nextIDs.insert(id)
            let layers = markerLayersByID[id] ?? makeLayers(for: group)
            markerLayersByID[id] = layers
            if layers.container.superlayer == nil {
                layer?.addSublayer(layers.container)
            }
            applyAppearance(group: group, layers: layers)
            layers.container.position = group.point
            layers.container.opacity = Float(groupOpacity(for: group))
        }

        for (id, layers) in markerLayersByID where !nextIDs.contains(id) {
            layers.container.removeFromSuperlayer()
            markerLayersByID.removeValue(forKey: id)
        }
    }

    /// Cheap per-frame position update. `positionsByID` maps marker IDs to view points,
    /// optional headings, and optional topology crossfade progress/old points.
    func updatePositions(_ positions: [String: MarkerPosition]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for (id, position) in positions {
            guard let layers = markerLayersByID[id] else { continue }
            layers.container.position = position.point
            if let heading = position.headingDegrees, let arrow = layers.arrow {
                arrow.isHidden = false
                // MapKit/Core Animation y-down view: rotate so 0° points up the screen.
                let radians = CGFloat(heading * .pi / 180)
                arrow.setAffineTransform(CGAffineTransform(rotationAngle: radians))
            } else {
                layers.arrow?.isHidden = true
            }
            if let fadeBody = layers.fadeBody,
               let oldPoint = position.previousPoint,
               position.topologyProgress < 1,
               !reduceMotion
            {
                fadeBody.isHidden = false
                fadeBody.opacity = Float(1 - position.topologyProgress)
                layers.body.opacity = Float(position.topologyProgress)
                // Fade body is in container space; offset from current anchor to old point.
                fadeBody.position = CGPoint(
                    x: oldPoint.x - position.point.x,
                    y: oldPoint.y - position.point.y
                )
            } else {
                layers.fadeBody?.isHidden = true
                layers.body.opacity = 1
                layers.body.position = .zero
            }
        }
    }

    struct MarkerPosition {
        let point: CGPoint
        let headingDegrees: Double?
        let previousPoint: CGPoint?
        let topologyProgress: Double
    }

    static func markerID(for group: LiveMapTrainGroup) -> String {
        if group.isCluster {
            let runIDs = group.snapshots.map { snapshot in
                [
                    snapshot.id.feedID,
                    snapshot.id.routeID,
                    snapshot.id.tripID,
                    snapshot.id.serviceDate,
                    snapshot.id.startTime,
                ].joined(separator: ":")
            }.sorted().joined(separator: "|")
            return "cluster:\(runIDs)"
        }
        guard let snapshot = group.snapshots.first else { return "empty" }
        return "train:\(snapshot.id.feedID):\(snapshot.id.routeID):\(snapshot.id.tripID):\(snapshot.id.serviceDate):\(snapshot.id.startTime)"
    }

    private func markerID(for group: LiveMapTrainGroup) -> String {
        Self.markerID(for: group)
    }

    private func groupOpacity(for group: LiveMapTrainGroup) -> Double {
        guard let snapshot = group.snapshots.first else { return 0 }
        return LiveMapPresentation.markerPresentation(for: snapshot, tier: tier).opacity
    }

    private func makeLayers(for group: LiveMapTrainGroup) -> MarkerLayers {
        let container = CALayer()
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        container.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        let body = CALayer()
        body.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        body.contentsScale = container.contentsScale
        container.addSublayer(body)

        let fadeBody: CALayer?
        let arrow: CALayer?
        if group.isCluster {
            fadeBody = nil
            arrow = nil
        } else {
            let fade = CALayer()
            fade.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            fade.contentsScale = container.contentsScale
            fade.isHidden = true
            container.insertSublayer(fade, below: body)
            fadeBody = fade

            let arrowLayer = CALayer()
            arrowLayer.anchorPoint = CGPoint(x: 0.5, y: 1)
            arrowLayer.contentsScale = container.contentsScale
            arrowLayer.contents = directionArrowImage()
            arrowLayer.bounds = CGRect(x: 0, y: 0, width: 14, height: 12)
            arrowLayer.isHidden = true
            container.addSublayer(arrowLayer)
            arrow = arrowLayer
        }

        return MarkerLayers(container: container, body: body, arrow: arrow, fadeBody: fadeBody)
    }

    private func applyAppearance(group: LiveMapTrainGroup, layers: MarkerLayers) {
        let scale = layers.container.contentsScale
        layers.container.contentsScale = scale
        layers.body.contentsScale = scale
        layers.fadeBody?.contentsScale = scale
        layers.arrow?.contentsScale = scale

        if group.isCluster {
            let routes = RouteID.sorted(Set(group.snapshots.map(\.routeID)))
            let count = group.snapshots.count
            let radius = LiveMapPresentation.clusterRadiusPoints(count: count)
            let selected = selectedTrainID.map { id in
                group.snapshots.contains { $0.id == id }
            } ?? false
            let primaryRoute = routes.first ?? ""
            let key = MarkerImageKey(
                kind: .cluster,
                routeID: primaryRoute,
                routes: routes,
                countLabel: LiveMapPresentation.clusterCountLabel(count),
                selected: selected,
                dashed: false,
                indicator: .none,
                showsRouteGlyph: false,
                radiusPoints: radius,
                backgroundHex: backgroundHex(for: primaryRoute),
                foregroundHex: foregroundHex(for: primaryRoute)
            )
            let image = cachedImage(for: key) {
                renderClusterImage(
                    routes: routes,
                    countLabel: key.countLabel,
                    radiusPoints: radius,
                    selected: selected,
                    scale: scale
                )
            }
            let size = CGFloat(image.width) / scale
            layers.body.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            layers.body.position = .zero
            layers.body.contents = image
            layers.arrow?.isHidden = true
            layers.fadeBody?.isHidden = true
            return
        }

        guard let snapshot = group.snapshots.first else { return }
        let presentation = LiveMapPresentation.markerPresentation(for: snapshot, tier: tier)
        let selected = snapshot.id == selectedTrainID
        let key = MarkerImageKey(
            kind: .single,
            routeID: snapshot.routeID,
            routes: [snapshot.routeID],
            countLabel: "",
            selected: selected,
            dashed: presentation.usesDashedRing,
            indicator: presentation.indicator,
            showsRouteGlyph: presentation.showsRouteGlyph,
            radiusPoints: presentation.markerRadiusPoints,
            backgroundHex: backgroundHex(for: snapshot.routeID),
            foregroundHex: foregroundHex(for: snapshot.routeID)
        )
        let image = cachedImage(for: key) {
            renderSingleImage(
                routeID: snapshot.routeID,
                radiusPoints: presentation.markerRadiusPoints,
                selected: selected,
                dashed: presentation.usesDashedRing,
                indicator: presentation.indicator,
                showsRouteGlyph: presentation.showsRouteGlyph,
                scale: scale
            )
        }
        let size = CGFloat(image.width) / scale
        layers.body.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        layers.body.position = .zero
        layers.body.contents = image
        layers.fadeBody?.bounds = layers.body.bounds
        layers.fadeBody?.contents = image

        if presentation.showsDirectionArrow, let arrow = layers.arrow {
            let clearance = presentation.markerRadiusPoints + (selected ? 7 : 4)
            arrow.position = CGPoint(x: 0, y: -clearance)
            arrow.isHidden = false
        } else {
            layers.arrow?.isHidden = true
        }
    }

    private func backgroundHex(for routeID: String) -> String {
        RouteColor.backgroundHex(for: routeID)
    }

    private func foregroundHex(for routeID: String) -> String {
        RouteColor.textHex(for: routeID)
    }

    private func routeColor(_ routeID: String) -> NSColor {
        colorsByRouteID[routeID] ?? NSColor(hexString: RouteColor.backgroundHex(for: routeID))
    }

    private func textColor(_ routeID: String) -> NSColor {
        textColorsByRouteID[routeID] ?? NSColor(hexString: RouteColor.textHex(for: routeID))
    }

    private func cachedImage(for key: MarkerImageKey, create: () -> CGImage) -> CGImage {
        if let cached = imageCache[key] { return cached }
        if imageCache.count >= 256 {
            imageCache.removeAll(keepingCapacity: true)
        }
        let image = create()
        imageCache[key] = image
        return image
    }

    private func directionArrowImage() -> CGImage {
        if let arrowImage { return arrowImage }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let width: CGFloat = 14
        let height: CGFloat = 12
        let size = CGSize(width: width * scale, height: height * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            preconditionFailure("Unable to create arrow image context")
        }
        context.scaleBy(x: scale, y: scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: width / 2, y: height - 1))
        path.addLine(to: CGPoint(x: width / 2, y: 1))
        path.move(to: CGPoint(x: 2, y: 5))
        path.addLine(to: CGPoint(x: width / 2, y: 1))
        path.addLine(to: CGPoint(x: width - 2, y: 5))
        context.addPath(path)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(3.5)
        context.strokePath()
        context.addPath(path)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.96).cgColor)
        context.setLineWidth(1.75)
        context.strokePath()
        guard let image = context.makeImage() else {
            preconditionFailure("Unable to create arrow image")
        }
        arrowImage = image
        return image
    }

    private func renderSingleImage(
        routeID: String,
        radiusPoints: CGFloat,
        selected: Bool,
        dashed: Bool,
        indicator: LiveMapTrainMarkerIndicator,
        showsRouteGlyph: Bool,
        scale: CGFloat
    ) -> CGImage {
        let padding: CGFloat = selected ? 8 : (dashed ? 6 : 4)
        let indicatorExtra: CGFloat = indicator == .none ? 0 : 10
        let diameter = radiusPoints * 2
        let canvas = diameter + padding * 2 + indicatorExtra
        let size = CGSize(width: canvas * scale, height: canvas * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            preconditionFailure("Unable to create marker image context")
        }
        context.scaleBy(x: scale, y: scale)
        // Draw in flipped coordinates so Core Text matches AppKit.
        context.translateBy(x: 0, y: canvas)
        context.scaleBy(x: 1, y: -1)

        let center = CGPoint(x: canvas / 2 - indicatorExtra / 2, y: canvas / 2)
        let markerRect = CGRect(
            x: center.x - radiusPoints,
            y: center.y - radiusPoints,
            width: diameter,
            height: diameter
        )
        if selected {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.88).cgColor)
            context.setLineWidth(2.5)
            context.strokeEllipse(in: markerRect.insetBy(dx: -4, dy: -4))
        }
        context.setFillColor(routeColor(routeID).cgColor)
        context.fillEllipse(in: markerRect)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.88).cgColor)
        context.setLineWidth(radiusPoints <= 4 ? 1 : 2)
        context.strokeEllipse(in: markerRect)

        if dashed {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [2.5, 2.5])
            context.strokeEllipse(in: markerRect.insetBy(dx: -2.5, dy: -2.5))
            context.setLineDash(phase: 0, lengths: [])
        }

        if showsRouteGlyph {
            drawCenteredText(
                RouteID.displayLabel(routeID),
                font: NSFont.systemFont(ofSize: max(7, radiusPoints * 0.95), weight: .bold),
                color: textColor(routeID),
                at: center,
                in: context
            )
        }

        if indicator != .none {
            let indicatorColor: NSColor = indicator == .stalled
                ? .systemYellow
                : NSColor.white.withAlphaComponent(0.78)
            context.setStrokeColor(indicatorColor.cgColor)
            context.setLineWidth(2)
            let x1 = center.x + radiusPoints + 3
            let x2 = center.x + radiusPoints + 6
            context.move(to: CGPoint(x: x1, y: center.y - 3))
            context.addLine(to: CGPoint(x: x1, y: center.y + 3))
            context.move(to: CGPoint(x: x2, y: center.y - 3))
            context.addLine(to: CGPoint(x: x2, y: center.y + 3))
            context.strokePath()
        }

        guard let image = context.makeImage() else {
            preconditionFailure("Unable to create marker image")
        }
        return image
    }

    private func renderClusterImage(
        routes: [String],
        countLabel: String,
        radiusPoints: CGFloat,
        selected: Bool,
        scale: CGFloat
    ) -> CGImage {
        let padding: CGFloat = selected ? 8 : 5
        let diameter = radiusPoints * 2
        let canvas = diameter + padding * 2
        let size = CGSize(width: canvas * scale, height: canvas * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            preconditionFailure("Unable to create cluster image context")
        }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: canvas)
        context.scaleBy(x: 1, y: -1)

        let center = CGPoint(x: canvas / 2, y: canvas / 2)
        let rect = CGRect(
            x: center.x - radiusPoints,
            y: center.y - radiusPoints,
            width: diameter,
            height: diameter
        )
        if selected {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.88).cgColor)
            context.setLineWidth(2.5)
            context.strokeEllipse(in: rect.insetBy(dx: -4, dy: -4))
        }
        let fillColor = routes.count == 1
            ? routeColor(routes[0])
            : NSColor.black.withAlphaComponent(0.9)
        context.setFillColor(fillColor.cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(routes.count == 1 ? 2.5 : 5)
        context.strokeEllipse(in: rect)

        if routes.count > 1 {
            for (index, route) in routes.enumerated() {
                let start = CGFloat(index) / CGFloat(routes.count) * 2 * .pi - (.pi / 2)
                let end = CGFloat(index + 1) / CGFloat(routes.count) * 2 * .pi - (.pi / 2)
                context.setStrokeColor(routeColor(route).cgColor)
                context.setLineWidth(3)
                context.addArc(
                    center: center,
                    radius: radiusPoints,
                    startAngle: start,
                    endAngle: end,
                    clockwise: false
                )
                context.strokePath()
            }
        }

        let labelColor = routes.count == 1 ? textColor(routes[0]) : NSColor.white
        drawCenteredText(
            countLabel,
            font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            color: labelColor,
            at: center,
            in: context
        )

        guard let image = context.makeImage() else {
            preconditionFailure("Unable to create cluster image")
        }
        return image
    }

    private func drawCenteredText(
        _ text: String,
        font: NSFont,
        color: NSColor,
        at point: CGPoint,
        in context: CGContext
    ) {
        let displayColor = color.usingColorSpace(.deviceRGB) ?? color
        let coreTextFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): coreTextFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): displayColor.cgColor,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributedText)
        let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
        context.saveGState()
        defer { context.restoreGState() }
        // Context is already y-flipped for AppKit; flip locally for Core Text.
        context.translateBy(x: point.x, y: point.y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, context)
    }
}

extension NSColor {
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
