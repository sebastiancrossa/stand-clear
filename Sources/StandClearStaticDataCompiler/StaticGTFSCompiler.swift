import Foundation
import StandClearCore

public struct StaticGTFSInput: Sendable {
    public let routesCSV: String
    public let tripsCSV: String
    public let stopTimesCSV: String
    public let stopsCSV: String
    public let transfersCSV: String
    public let shapesCSV: String
    public let feedInfoCSV: String?

    public init(
        routesCSV: String,
        tripsCSV: String,
        stopTimesCSV: String,
        stopsCSV: String,
        transfersCSV: String,
        shapesCSV: String,
        feedInfoCSV: String? = nil
    ) {
        self.routesCSV = routesCSV
        self.tripsCSV = tripsCSV
        self.stopTimesCSV = stopTimesCSV
        self.stopsCSV = stopsCSV
        self.transfersCSV = transfersCSV
        self.shapesCSV = shapesCSV
        self.feedInfoCSV = feedInfoCSV
    }
}

public enum StaticGTFSCompilerError: LocalizedError, Equatable {
    case invalidCSV(file: String, missingColumns: [String])
    case noRoutes
    case noPaths
    case routesWithoutGeometry([String])

    public var errorDescription: String? {
        switch self {
        case let .invalidCSV(file, columns): "\(file) is missing required columns: \(columns.joined(separator: ", "))."
        case .noRoutes: "The static feed did not contain any routes."
        case .noPaths: "The static feed did not contain any usable track paths."
        case let .routesWithoutGeometry(routes): "Routes have no usable geometry: \(routes.joined(separator: ", "))."
        }
    }
}

public struct StaticGTFSCompiler: Sendable {
    public init() {}

    public func compile(_ input: StaticGTFSInput) throws -> SubwayGeometryResource {
        let routeRows = try CSVTable(input.routesCSV, file: "routes.txt", required: [
            "route_id", "route_short_name", "route_long_name", "route_color", "route_text_color",
        ])
        let routes = routeRows.rows.compactMap { row -> RouteGeometryMetadata? in
            guard let id = row["route_id"], !id.isEmpty else { return nil }
            return RouteGeometryMetadata(
                id: id,
                shortName: row["route_short_name"] ?? id,
                longName: row["route_long_name"] ?? "",
                colorHex: normalizedHex(row["route_color"], fallback: RouteColor.backgroundHex(for: id)),
                textColorHex: normalizedHex(row["route_text_color"], fallback: RouteColor.textHex(for: id)),
                sortOrder: Int(row["route_sort_order"] ?? "") ?? Int.max
            )
        }.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.id < rhs.id : lhs.sortOrder < rhs.sortOrder
        }
        guard !routes.isEmpty else { throw StaticGTFSCompilerError.noRoutes }

        let stopRows = try CSVTable(input.stopsCSV, file: "stops.txt", required: [
            "stop_id", "stop_lat", "stop_lon", "parent_station",
        ])
        var stops: [String: Stop] = [:]
        for row in stopRows.rows {
            guard
                let id = row["stop_id"],
                let latitude = Double(row["stop_lat"] ?? ""),
                let longitude = Double(row["stop_lon"] ?? "")
            else { continue }
            stops[id] = Stop(
                stationID: (row["parent_station"]?.isEmpty == false ? row["parent_station"] : id) ?? id,
                latitude: latitude,
                longitude: longitude
            )
        }

        let tripRows = try CSVTable(input.tripsCSV, file: "trips.txt", required: [
            "route_id", "trip_id", "direction_id", "shape_id",
        ])
        var trips: [String: Trip] = [:]
        for row in tripRows.rows {
            guard
                let routeID = row["route_id"], !routeID.isEmpty,
                let tripID = row["trip_id"], !tripID.isEmpty,
                let shapeID = row["shape_id"], !shapeID.isEmpty
            else { continue }
            trips[tripID] = Trip(
                id: tripID,
                routeID: RouteID.normalized(routeID),
                directionID: Int(row["direction_id"] ?? "") ?? -1,
                shapeID: shapeID
            )
        }

        let timeRows = try CSVTable(input.stopTimesCSV, file: "stop_times.txt", required: [
            "trip_id", "stop_id", "arrival_time", "departure_time", "stop_sequence",
        ])
        var timesByTrip: [String: [StopTime]] = [:]
        for row in timeRows.rows {
            guard
                let tripID = row["trip_id"], trips[tripID] != nil,
                let stopID = row["stop_id"], let stop = stops[stopID],
                let sequence = Int(row["stop_sequence"] ?? "")
            else { continue }
            timesByTrip[tripID, default: []].append(
                StopTime(
                    stopID: stopID,
                    stationID: stop.stationID,
                    sequence: sequence,
                    arrival: parseTime(row["arrival_time"]),
                    departure: parseTime(row["departure_time"])
                )
            )
        }
        for tripID in timesByTrip.keys {
            timesByTrip[tripID]?.sort { $0.sequence < $1.sequence }
        }

        let shapeRows = try CSVTable(input.shapesCSV, file: "shapes.txt", required: [
            "shape_id", "shape_pt_sequence", "shape_pt_lat", "shape_pt_lon",
        ])
        var rawPointsByShape: [String: [RawPoint]] = [:]
        for row in shapeRows.rows {
            guard
                let shapeID = row["shape_id"],
                let sequence = Int(row["shape_pt_sequence"] ?? ""),
                let latitude = Double(row["shape_pt_lat"] ?? ""),
                let longitude = Double(row["shape_pt_lon"] ?? "")
            else { continue }
            rawPointsByShape[shapeID, default: []].append(
                RawPoint(sequence: sequence, latitude: latitude, longitude: longitude)
            )
        }

        let tripsByShape = Dictionary(grouping: trips.values, by: \.shapeID)
        var paths: [TrackPath] = []
        var warnings: [String] = []
        for shapeID in tripsByShape.keys.sorted() {
            guard var rawPoints = rawPointsByShape[shapeID], rawPoints.count >= 2 else {
                warnings.append("Quarantined \(shapeID): fewer than two shape points")
                continue
            }
            rawPoints.sort { $0.sequence < $1.sequence }
            let points = cumulativePoints(rawPoints)
            guard let pathLength = points.last?.distanceMeters, pathLength > 50 else {
                warnings.append("Quarantined \(shapeID): path is shorter than 50 meters")
                continue
            }
            let shapeTrips = tripsByShape[shapeID] ?? []
            let candidateSequences = shapeTrips.compactMap { trip -> [StopTime]? in
                guard let stopTimes = timesByTrip[trip.id], !stopTimes.isEmpty else { return nil }
                return stopTimes
            }
            guard let representative = representativeSequence(candidateSequences) else {
                warnings.append("Quarantined \(shapeID): no ordered stops")
                continue
            }
            let anchors = projectAnchors(
                representative,
                allSequences: candidateSequences,
                points: points,
                stops: stops
            )
            guard anchors.count == representative.count else {
                warnings.append("Quarantined \(shapeID): one or more stops could not be projected")
                continue
            }
            paths.append(
                TrackPath(
                    shapeID: shapeID,
                    routeIDs: Set(shapeTrips.map(\.routeID)).sorted(),
                    directionIDs: Set(shapeTrips.map(\.directionID)).sorted(),
                    points: points,
                    anchors: anchors
                )
            )
        }
        guard !paths.isEmpty else { throw StaticGTFSCompilerError.noPaths }

        let routesWithPaths = Set(paths.flatMap(\.routeIDs))
        let missingRoutes = routes.map(\.id).filter { !routesWithPaths.contains($0) }.sorted()
        guard missingRoutes.isEmpty else {
            throw StaticGTFSCompilerError.routesWithoutGeometry(missingRoutes)
        }

        return SubwayGeometryResource(
            feedVersion: feedVersion(input.feedInfoCSV),
            routes: routes,
            paths: paths,
            corridors: makeCorridors(paths),
            transferGroups: try transferGroups(input.transfersCSV, stops: stops),
            validationWarnings: warnings.sorted()
        )
    }

    public static func encode(_ resource: SubwayGeometryResource) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(resource)
    }
}

private extension StaticGTFSCompiler {
    struct Stop {
        let stationID: String
        let latitude: Double
        let longitude: Double
    }

    struct Trip {
        let id: String
        let routeID: String
        let directionID: Int
        let shapeID: String
    }

    struct StopTime: Hashable {
        let stopID: String
        let stationID: String
        let sequence: Int
        let arrival: Int?
        let departure: Int?
    }

    struct RawPoint {
        let sequence: Int
        let latitude: Double
        let longitude: Double
    }

    func normalizedHex(_ value: String?, fallback: String) -> String {
        guard let value else { return fallback }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 6, UInt32(normalized, radix: 16) != nil else { return fallback }
        return normalized
    }

    func parseTime(_ value: String?) -> Int? {
        guard let parts = value?.split(separator: ":"), parts.count == 3,
              let hours = Int(parts[0]), let minutes = Int(parts[1]), let seconds = Int(parts[2])
        else { return nil }
        return hours * 3_600 + minutes * 60 + seconds
    }

    func cumulativePoints(_ rawPoints: [RawPoint]) -> [TrackPoint] {
        var distance = 0.0
        var previous: RawPoint?
        return rawPoints.map { point in
            if let previous {
                distance += haversine(
                    latitude1: previous.latitude,
                    longitude1: previous.longitude,
                    latitude2: point.latitude,
                    longitude2: point.longitude
                )
            }
            previous = point
            return TrackPoint(
                latitude: point.latitude,
                longitude: point.longitude,
                distanceMeters: (distance * 10).rounded() / 10
            )
        }
    }

    func representativeSequence(_ candidates: [[StopTime]]) -> [StopTime]? {
        let grouped = Dictionary(grouping: candidates) { sequence in
            sequence.map(\.stationID).joined(separator: "\u{1F}")
        }
        return grouped
            .sorted { lhs, rhs in
                lhs.value.count == rhs.value.count ? lhs.key < rhs.key : lhs.value.count > rhs.value.count
            }
            .first?.value.min { lhs, rhs in
                let lhsKey = lhs.map { "\($0.stopID):\($0.sequence)" }.joined(separator: "\u{1F}")
                let rhsKey = rhs.map { "\($0.stopID):\($0.sequence)" }.joined(separator: "\u{1F}")
                return lhsKey < rhsKey
            }
    }

    func projectAnchors(
        _ sequence: [StopTime],
        allSequences: [[StopTime]],
        points: [TrackPoint],
        stops: [String: Stop]
    ) -> [TrackStopAnchor] {
        var dwellSamplesByStation: [String: [Int]] = [:]
        var travelSamplesByStations: [StationPair: [Int]] = [:]
        for candidate in allSequences {
            var firstIndexByStation: [String: Int] = [:]
            for (index, item) in candidate.enumerated() where firstIndexByStation[item.stationID] == nil {
                firstIndexByStation[item.stationID] = index
                if let arrival = item.arrival, let departure = item.departure, departure >= arrival {
                    dwellSamplesByStation[item.stationID, default: []].append(departure - arrival)
                }
            }
            for (stationID, index) in firstIndexByStation where candidate.indices.contains(index + 1) {
                let current = candidate[index]
                let next = candidate[index + 1]
                guard let departure = current.departure, let arrival = next.arrival, arrival >= departure else { continue }
                travelSamplesByStations[
                    StationPair(from: stationID, to: next.stationID),
                    default: []
                ].append(arrival - departure)
            }
        }

        var minimumPointIndex = 0
        return sequence.enumerated().compactMap { offset, stopTime in
            guard let stop = stops[stopTime.stopID], minimumPointIndex < points.count else { return nil }
            let best = (minimumPointIndex ..< points.count).min { lhs, rhs in
                squaredCoordinateDistance(points[lhs], stop) < squaredCoordinateDistance(points[rhs], stop)
            } ?? minimumPointIndex
            guard haversine(
                latitude1: points[best].latitude,
                longitude1: points[best].longitude,
                latitude2: stop.latitude,
                longitude2: stop.longitude
            ) <= 1_000 else { return nil }
            minimumPointIndex = best

            let nextStationID = sequence.indices.contains(offset + 1) ? sequence[offset + 1].stationID : nil
            let travelSamples = nextStationID.flatMap {
                travelSamplesByStations[StationPair(from: stopTime.stationID, to: $0)]
            } ?? []
            return TrackStopAnchor(
                stopID: stopTime.stopID,
                stationID: stopTime.stationID,
                sequence: stopTime.sequence,
                pointIndex: best,
                distanceMeters: points[best].distanceMeters,
                medianDwellSeconds: median(dwellSamplesByStation[stopTime.stationID] ?? []),
                medianTravelSecondsToNext: median(travelSamples)
            )
        }
    }

    func squaredCoordinateDistance(_ point: TrackPoint, _ stop: Stop) -> Double {
        let latitude = point.latitude - stop.latitude
        let longitude = (point.longitude - stop.longitude) * cos(stop.latitude * .pi / 180)
        return latitude * latitude + longitude * longitude
    }

    func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? Int((Double(sorted[middle - 1]) + Double(sorted[middle])) / 2)
            : sorted[middle]
    }

    func haversine(latitude1: Double, longitude1: Double, latitude2: Double, longitude2: Double) -> Double {
        let radius = 6_371_000.0
        let phi1 = latitude1 * .pi / 180
        let phi2 = latitude2 * .pi / 180
        let deltaPhi = (latitude2 - latitude1) * .pi / 180
        let deltaLambda = (longitude2 - longitude1) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    func makeCorridors(_ paths: [TrackPath]) -> [RenderCorridor] {
        let grouped = Dictionary(grouping: paths) { path in
            path.points.map {
                QuantizedPoint(
                    latitude: Int64(($0.latitude * 1_000_000).rounded()),
                    longitude: Int64(($0.longitude * 1_000_000).rounded())
                )
            }
        }
        return grouped.values.map { matches in
            let shapeIDs = matches.map(\.shapeID).sorted()
            return RenderCorridor(
                id: shapeIDs.joined(separator: "+"),
                shapeIDs: shapeIDs,
                routeIDs: Set(matches.flatMap(\.routeIDs)).sorted()
            )
        }.sorted { $0.id < $1.id }
    }

    func transferGroups(_ csv: String, stops: [String: Stop]) throws -> [StationTransferGroup] {
        let table = try CSVTable(csv, file: "transfers.txt", required: ["from_stop_id", "to_stop_id"])
        var parents = Dictionary(uniqueKeysWithValues: Set(stops.values.map(\.stationID)).map { ($0, $0) })

        func root(_ id: String) -> String {
            var current = id
            while parents[current] != current, let parent = parents[current] { current = parent }
            return current
        }
        for row in table.rows {
            guard let fromID = row["from_stop_id"], let toID = row["to_stop_id"],
                  let from = stops[fromID]?.stationID ?? (parents[fromID] != nil ? fromID : nil),
                  let to = stops[toID]?.stationID ?? (parents[toID] != nil ? toID : nil)
            else { continue }
            let fromRoot = root(from)
            let toRoot = root(to)
            if fromRoot != toRoot { parents[toRoot] = fromRoot }
        }
        let grouped = Dictionary(grouping: parents.keys, by: root)
        return grouped.values
            .map { StationTransferGroup(stationIDs: $0.sorted()) }
            .filter { $0.stationIDs.count > 1 }
            .sorted { ($0.stationIDs.first ?? "") < ($1.stationIDs.first ?? "") }
    }

    func feedVersion(_ csv: String?) -> String? {
        guard let csv, let table = try? CSVTable(csv, file: "feed_info.txt", required: []),
              let first = table.rows.first
        else { return nil }
        let value = first["feed_version"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

private struct StationPair: Hashable {
    let from: String
    let to: String
}

private struct QuantizedPoint: Hashable {
    let latitude: Int64
    let longitude: Int64
}

private struct CSVTable {
    let rows: [[String: String]]

    init(_ csv: String, file: String, required: [String]) throws {
        let lines = csv.split(whereSeparator: \Character.isNewline).map(String.init)
        guard let first = lines.first else {
            throw StaticGTFSCompilerError.invalidCSV(file: file, missingColumns: required)
        }
        let header = Self.parse(first).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let missing = required.filter { !header.contains($0) }
        guard missing.isEmpty else {
            throw StaticGTFSCompilerError.invalidCSV(file: file, missingColumns: missing)
        }
        rows = lines.dropFirst().map { line in
            let values = Self.parse(line)
            return Dictionary(uniqueKeysWithValues: header.enumerated().map { index, column in
                (column, values.indices.contains(index) ? values[index].trimmingCharacters(in: .whitespacesAndNewlines) : "")
            })
        }
    }

    private static func parse(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if quoted, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(field)
        return fields
    }
}
