import CoreLocation
import Foundation

public enum StationCatalogError: LocalizedError {
    case missingBundledStops
    case missingBundledRoutes
    case missingBundledTransfers
    case invalidHeader
    case noStations

    public var errorDescription: String? {
        switch self {
        case .missingBundledStops: "The bundled MTA station list is missing."
        case .missingBundledRoutes: "The bundled MTA station route list is missing."
        case .missingBundledTransfers: "The bundled MTA transfer list is missing."
        case .invalidHeader: "The MTA station list has an unexpected format."
        case .noStations: "The MTA station list did not contain any stations."
        }
    }
}

public struct StationCatalog: Sendable {
    public let stations: [Station]
    private let stationsByID: [String: Station]
    private let parentByStopID: [String: String]
    private let routesByStationID: [String: Set<String>]
    private let relatedStationIDs: [String: Set<String>]

    public init(csv: String, stationRoutesCSV: String? = nil, transfersCSV: String? = nil) throws {
        let lines = csv.split(whereSeparator: \Character.isNewline).map(String.init)
        guard let header = lines.first else {
            throw StationCatalogError.invalidHeader
        }

        let columns = Self.parseCSVRow(header)
        let indices = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($1, $0) })
        guard
            let idIndex = indices["stop_id"],
            let nameIndex = indices["stop_name"],
            let latitudeIndex = indices["stop_lat"],
            let longitudeIndex = indices["stop_lon"],
            let locationTypeIndex = indices["location_type"],
            let parentIndex = indices["parent_station"]
        else {
            throw StationCatalogError.invalidHeader
        }

        var parsedStations: [Station] = []
        var parsedParents: [String: String] = [:]

        for line in lines.dropFirst() {
            let row = Self.parseCSVRow(line)
            let requiredIndex = max(idIndex, nameIndex, latitudeIndex, longitudeIndex, locationTypeIndex, parentIndex)
            guard row.indices.contains(requiredIndex) else { continue }

            let stopID = row[idIndex]
            let parentID = row[parentIndex]
            if !parentID.isEmpty {
                parsedParents[stopID] = parentID
            }

            guard
                row[locationTypeIndex] == "1",
                let latitude = Double(row[latitudeIndex]),
                let longitude = Double(row[longitudeIndex])
            else { continue }

            parsedStations.append(
                Station(
                    id: stopID,
                    name: row[nameIndex],
                    latitude: latitude,
                    longitude: longitude
                )
            )
        }

        guard !parsedStations.isEmpty else {
            throw StationCatalogError.noStations
        }

        stations = parsedStations
        stationsByID = Dictionary(uniqueKeysWithValues: parsedStations.map { ($0.id, $0) })
        parentByStopID = parsedParents

        var parsedRoutes: [String: Set<String>] = [:]
        if let stationRoutesCSV {
            for line in stationRoutesCSV.split(whereSeparator: \Character.isNewline).dropFirst() {
                let values = line.split(separator: ",", maxSplits: 1).map(String.init)
                guard values.count == 2 else { continue }
                parsedRoutes[values[0], default: []].insert(RouteID.normalized(values[1]))
            }
        }
        routesByStationID = parsedRoutes

        var unionParents = Dictionary(uniqueKeysWithValues: parsedStations.map { ($0.id, $0.id) })

        func root(of id: String, in parents: inout [String: String]) -> String {
            var current = id
            while let parent = parents[current], parent != current {
                current = parent
            }
            let root = current
            current = id
            while let parent = parents[current], parent != current {
                parents[current] = root
                current = parent
            }
            return root
        }

        if let transfersCSV {
            for line in transfersCSV.split(whereSeparator: \Character.isNewline).dropFirst() {
                let values = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                guard
                    values.count >= 2,
                    unionParents[values[0]] != nil,
                    unionParents[values[1]] != nil
                else { continue }
                let fromRoot = root(of: values[0], in: &unionParents)
                let toRoot = root(of: values[1], in: &unionParents)
                if fromRoot != toRoot {
                    unionParents[toRoot] = fromRoot
                }
            }
        }

        var groups: [String: Set<String>] = [:]
        for station in parsedStations {
            groups[root(of: station.id, in: &unionParents), default: []].insert(station.id)
        }
        var parsedRelated: [String: Set<String>] = [:]
        for group in groups.values {
            for stationID in group {
                parsedRelated[stationID] = group
            }
        }
        relatedStationIDs = parsedRelated
    }

    public static func bundled() throws -> StationCatalog {
        let dataBundle = packagedResourceBundle() ?? Bundle.module
        guard let stopsURL = dataBundle.url(forResource: "stops", withExtension: "txt") else {
            throw StationCatalogError.missingBundledStops
        }
        guard let routesURL = dataBundle.url(forResource: "station_routes", withExtension: "csv") else {
            throw StationCatalogError.missingBundledRoutes
        }
        guard let transfersURL = dataBundle.url(forResource: "transfers", withExtension: "txt") else {
            throw StationCatalogError.missingBundledTransfers
        }
        return try StationCatalog(
            csv: String(contentsOf: stopsURL, encoding: .utf8),
            stationRoutesCSV: String(contentsOf: routesURL, encoding: .utf8),
            transfersCSV: String(contentsOf: transfersURL, encoding: .utf8)
        )
    }

    private static func packagedResourceBundle() -> Bundle? {
        guard let resourcesURL = Bundle.main.resourceURL else { return nil }
        return Bundle(
            url: resourcesURL.appendingPathComponent("SubwayBar_SubwayBarCore.bundle", isDirectory: true)
        )
    }

    public func station(id: String) -> Station? {
        stationsByID[id]
    }

    public func stationID(forStopID stopID: String) -> String? {
        if stationsByID[stopID] != nil {
            return stopID
        }
        if let parent = parentByStopID[stopID] {
            return parent
        }
        let trimmed = String(stopID.dropLast())
        return stationsByID[trimmed] == nil ? nil : trimmed
    }

    public func stationName(forStopID stopID: String) -> String? {
        guard let id = stationID(forStopID: stopID) else { return nil }
        return stationsByID[id]?.name
    }

    public func relatedStations(to stationID: String) -> Set<String> {
        relatedStationIDs[stationID] ?? [stationID]
    }

    public func routes(serving stationID: String) -> Set<String> {
        relatedStations(to: stationID).reduce(into: Set<String>()) { routes, relatedID in
            routes.formUnion(routesByStationID[relatedID] ?? [])
        }
    }

    public var allRoutes: Set<String> {
        routesByStationID.values.reduce(into: Set<String>()) { routes, stationRoutes in
            routes.formUnion(stationRoutes)
        }
    }

    public func nearest(to location: CLLocation) -> (station: Station, distance: CLLocationDistance)? {
        stations.lazy
            .map { station in (station, station.location.distance(from: location)) }
            .min { $0.1 < $1.1 }
    }

    private static func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var insideQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if insideQuotes, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    index = line.index(after: next)
                    continue
                }
                insideQuotes.toggle()
            } else if character == ",", !insideQuotes {
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
