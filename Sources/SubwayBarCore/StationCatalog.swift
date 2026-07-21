import CoreLocation
import Foundation

public enum StationCatalogError: LocalizedError {
    case missingBundledStops
    case invalidHeader
    case noStations

    public var errorDescription: String? {
        switch self {
        case .missingBundledStops: "The bundled MTA station list is missing."
        case .invalidHeader: "The MTA station list has an unexpected format."
        case .noStations: "The MTA station list did not contain any stations."
        }
    }
}

public struct StationCatalog: Sendable {
    public let stations: [Station]
    private let stationsByID: [String: Station]
    private let parentByStopID: [String: String]

    public init(csv: String) throws {
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
    }

    public static func bundled() throws -> StationCatalog {
        guard let url = Bundle.module.url(forResource: "stops", withExtension: "txt") else {
            throw StationCatalogError.missingBundledStops
        }
        return try StationCatalog(csv: String(contentsOf: url, encoding: .utf8))
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

