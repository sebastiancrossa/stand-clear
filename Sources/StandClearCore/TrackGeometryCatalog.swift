import Foundation

public enum TrackGeometryCatalogError: LocalizedError, Equatable {
    case missingBundledGeometry
    case invalidGeometry
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .missingBundledGeometry: "The bundled MTA track geometry is missing."
        case .invalidGeometry: "The bundled MTA track geometry is invalid."
        case let .unsupportedVersion(version): "The bundled MTA track geometry uses unsupported version \(version)."
        }
    }
}

public struct RouteGeometryMetadata: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let shortName: String
    public let longName: String
    public let colorHex: String
    public let textColorHex: String
    public let sortOrder: Int

    public init(
        id: String,
        shortName: String,
        longName: String,
        colorHex: String,
        textColorHex: String,
        sortOrder: Int
    ) {
        self.id = RouteID.normalized(id)
        self.shortName = shortName
        self.longName = longName
        self.colorHex = colorHex.uppercased()
        self.textColorHex = textColorHex.uppercased()
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id = "i", shortName = "s", longName = "n", colorHex = "c", textColorHex = "t", sortOrder = "o"
    }
}

/// The colors and labels used to present a route. These values come from the
/// static MTA feed when it is available and fall back to the legacy line
/// palette only for unknown routes.
public struct RouteStyleMetadata: Equatable, Hashable, Sendable {
    public let backgroundHex: String
    public let foregroundHex: String

    public init(backgroundHex: String, foregroundHex: String) {
        self.backgroundHex = backgroundHex.uppercased()
        self.foregroundHex = foregroundHex.uppercased()
    }
}

/// Resolves route presentation metadata without requiring callers to know
/// whether it came from the MTA static feed or the legacy fallback palette.
public struct RouteStyleResolver: Sendable {
    private let stylesByRouteID: [String: RouteStyleMetadata]

    public init(routes: [RouteGeometryMetadata]) {
        stylesByRouteID = Dictionary(
            uniqueKeysWithValues: routes.map { route in
                (
                    RouteID.normalized(route.id),
                    RouteStyleMetadata(
                        backgroundHex: route.colorHex,
                        foregroundHex: route.textColorHex
                    )
                )
            }
        )
    }

    public init(catalog: TrackGeometryCatalog) {
        self.init(routes: catalog.resource.routes)
    }

    /// Small route-only resource, decoded once for non-map UI such as arrival
    /// badges. Keeping this separate preserves lazy loading of map geometry.
    public static let bundled: RouteStyleResolver = {
        let dataBundle = Bundle.standClearResources
        guard
            let url = dataBundle.url(forResource: "subway_route_styles", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let routes = try? JSONDecoder().decode([RouteGeometryMetadata].self, from: data)
        else {
            return RouteStyleResolver(routes: [])
        }
        return RouteStyleResolver(routes: routes)
    }()

    public func style(for routeID: String) -> RouteStyleMetadata {
        stylesByRouteID[RouteID.normalized(routeID)]
            ?? RouteStyleMetadata(
                backgroundHex: RouteColor.backgroundHex(for: routeID),
                foregroundHex: RouteColor.textHex(for: routeID)
            )
    }
}

public struct TrackPoint: Codable, Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let distanceMeters: Double

    public init(latitude: Double, longitude: Double, distanceMeters: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
    }

    private enum CodingKeys: String, CodingKey {
        case latitude = "a", longitude = "o", distanceMeters = "d"
    }
}

public struct TrackStopAnchor: Codable, Equatable, Hashable, Sendable {
    public let stopID: String
    public let stationID: String
    public let sequence: Int
    public let pointIndex: Int
    public let distanceMeters: Double
    public let medianDwellSeconds: Int?
    public let medianTravelSecondsToNext: Int?

    public init(
        stopID: String,
        stationID: String,
        sequence: Int,
        pointIndex: Int,
        distanceMeters: Double,
        medianDwellSeconds: Int?,
        medianTravelSecondsToNext: Int?
    ) {
        self.stopID = stopID
        self.stationID = stationID
        self.sequence = sequence
        self.pointIndex = pointIndex
        self.distanceMeters = distanceMeters
        self.medianDwellSeconds = medianDwellSeconds
        self.medianTravelSecondsToNext = medianTravelSecondsToNext
    }

    private enum CodingKeys: String, CodingKey {
        case stopID = "i"
        case stationID = "p"
        case sequence = "s"
        case pointIndex = "x"
        case distanceMeters = "d"
        case medianDwellSeconds = "w"
        case medianTravelSecondsToNext = "t"
    }
}

public struct TrackPath: Codable, Equatable, Sendable {
    public let shapeID: String
    public let routeIDs: [String]
    public let directionIDs: [Int]
    public let points: [TrackPoint]
    public let anchors: [TrackStopAnchor]

    public init(
        shapeID: String,
        routeIDs: [String],
        directionIDs: [Int],
        points: [TrackPoint],
        anchors: [TrackStopAnchor]
    ) {
        self.shapeID = shapeID
        self.routeIDs = routeIDs
        self.directionIDs = directionIDs
        self.points = points
        self.anchors = anchors
    }

    private enum CodingKeys: String, CodingKey {
        case shapeID = "i", routeIDs = "r", directionIDs = "n", points = "p", anchors = "a"
    }
}

public struct RenderCorridor: Codable, Equatable, Sendable {
    public let id: String
    public let shapeIDs: [String]
    public let routeIDs: [String]
    /// The directed station-to-station geometry this corridor renders. Keeping
    /// this separate from `TrackPath` lets shared sections be grouped even when
    /// the complete trip shapes have different endpoints.
    public let points: [TrackPoint]

    public init(id: String, shapeIDs: [String], routeIDs: [String], points: [TrackPoint] = []) {
        self.id = id
        self.shapeIDs = shapeIDs
        self.routeIDs = routeIDs
        self.points = points
    }

    private enum CodingKeys: String, CodingKey {
        case id = "i", shapeIDs = "s", routeIDs = "r", points = "p"
    }
}

public struct StationTransferGroup: Codable, Equatable, Sendable {
    public let stationIDs: [String]

    public init(stationIDs: [String]) {
        self.stationIDs = stationIDs
    }

    private enum CodingKeys: String, CodingKey {
        case stationIDs = "s"
    }
}

public struct SubwayGeometryResource: Codable, Equatable, Sendable {
    public static let currentVersion = 3

    public let version: Int
    public let feedVersion: String?
    public let routes: [RouteGeometryMetadata]
    public let paths: [TrackPath]
    public let corridors: [RenderCorridor]
    public let transferGroups: [StationTransferGroup]
    public let validationWarnings: [String]

    public init(
        version: Int = currentVersion,
        feedVersion: String?,
        routes: [RouteGeometryMetadata],
        paths: [TrackPath],
        corridors: [RenderCorridor],
        transferGroups: [StationTransferGroup],
        validationWarnings: [String]
    ) {
        self.version = version
        self.feedVersion = feedVersion
        self.routes = routes
        self.paths = paths
        self.corridors = corridors
        self.transferGroups = transferGroups
        self.validationWarnings = validationWarnings
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case feedVersion = "f"
        case routes = "r"
        case paths = "p"
        case corridors = "c"
        case transferGroups = "t"
        case validationWarnings = "w"
    }
}

public struct TrackGeometryCatalog: Sendable {
    public let resource: SubwayGeometryResource
    private let routesByID: [String: RouteGeometryMetadata]
    private let routeStyleResolver: RouteStyleResolver
    private let pathsByShapeID: [String: TrackPath]
    private let pathsByRouteID: [String: [TrackPath]]

    public init(data: Data) throws {
        let decoded: SubwayGeometryResource
        do {
            decoded = try GeometryBinaryCodec.decode(data)
        } catch {
            throw TrackGeometryCatalogError.invalidGeometry
        }
        guard decoded.version == SubwayGeometryResource.currentVersion else {
            throw TrackGeometryCatalogError.unsupportedVersion(decoded.version)
        }
        guard
            !decoded.routes.isEmpty,
            !decoded.paths.isEmpty,
            Set(decoded.routes.map(\.id)).count == decoded.routes.count,
            Set(decoded.paths.map(\.shapeID)).count == decoded.paths.count,
            decoded.paths.allSatisfy({ path in
                path.points.count >= 2
                    && !path.anchors.isEmpty
                    && Self.isMonotonic(path.points.map(\.distanceMeters))
                    && Self.isMonotonic(path.anchors.map(\.distanceMeters))
            })
        else {
            throw TrackGeometryCatalogError.invalidGeometry
        }
        resource = decoded
        routesByID = Dictionary(uniqueKeysWithValues: decoded.routes.map { ($0.id, $0) })
        routeStyleResolver = RouteStyleResolver(routes: decoded.routes)
        pathsByShapeID = Dictionary(uniqueKeysWithValues: decoded.paths.map { ($0.shapeID, $0) })
        var grouped: [String: [TrackPath]] = [:]
        for path in decoded.paths {
            for routeID in path.routeIDs {
                grouped[RouteID.normalized(routeID), default: []].append(path)
            }
        }
        pathsByRouteID = grouped.mapValues { $0.sorted { $0.shapeID < $1.shapeID } }
    }

    public static func bundled() throws -> TrackGeometryCatalog {
        let dataBundle = Bundle.standClearResources
        guard let url = dataBundle.url(forResource: "subway_geometry", withExtension: "scgm") else {
            throw TrackGeometryCatalogError.missingBundledGeometry
        }
        // mappedIfSafe keeps the file pages clean/file-backed instead of copying
        // the whole payload into dirty MALLOC.
        return try TrackGeometryCatalog(
            data: Data(contentsOf: url, options: [.mappedIfSafe])
        )
    }

    public func route(_ routeID: String) -> RouteGeometryMetadata? {
        routesByID[RouteID.normalized(routeID)]
    }

    public func style(forRoute routeID: String) -> RouteStyleMetadata {
        routeStyleResolver.style(for: routeID)
    }

    public func path(shapeID: String) -> TrackPath? {
        pathsByShapeID[shapeID]
    }

    public func paths(forRoute routeID: String) -> [TrackPath] {
        pathsByRouteID[RouteID.normalized(routeID)] ?? []
    }

    private static func isMonotonic(_ values: [Double]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy(<=)
    }
}

public enum RouteColor {
    public static func backgroundHex(for routeID: String) -> String {
        switch RouteID.baseLine(routeID) {
        case "A", "C", "E", "SI": "0039A6"
        case "B", "D", "F", "M": "FF6319"
        case "G": "6CBE45"
        case "J", "Z": "996633"
        case "N", "Q", "R", "W": "FCCC0A"
        case "1", "2", "3": "EE352E"
        case "4", "5", "6": "00933C"
        case "7": "B933AD"
        default: "808183"
        }
    }

    public static func textHex(for routeID: String) -> String {
        ["N", "Q", "R", "W"].contains(RouteID.baseLine(routeID)) ? "000000" : "FFFFFF"
    }
}
