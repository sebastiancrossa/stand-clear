import Foundation

public enum MTAFeedError: LocalizedError {
    case invalidResponse
    case allFeedsFailed

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The MTA returned an invalid response."
        case .allFeedsFailed: "Live subway data is temporarily unavailable."
        }
    }
}

public struct MTAClient {
    public static let feedURLs = [
        "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
        "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace",
        "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm",
        "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g",
        "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz",
        "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l",
        "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw",
        "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-si",
    ].compactMap(URL.init(string:))

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchArrivals(
        catalog: StationCatalog,
        now: Date = Date()
    ) async throws -> FeedSnapshot {
        let session = session
        let results = await withTaskGroup(of: Result<[RealtimeTrip], Error>.self) { group in
            for url in Self.feedURLs {
                group.addTask {
                    do {
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 12
                        request.setValue("StandClear/1.0", forHTTPHeaderField: "User-Agent")
                        let (data, response) = try await session.data(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            throw MTAFeedError.invalidResponse
                        }
                        return .success(try GTFSRealtimeParser.parse(data: data))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var collected: [Result<[RealtimeTrip], Error>] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        let successfulTrips = results.compactMap { try? $0.get() }
        guard !successfulTrips.isEmpty else {
            throw MTAFeedError.allFeedsFailed
        }

        let horizon = now.addingTimeInterval(2 * 60 * 60)
        var uniqueArrivals: [String: Arrival] = [:]

        for trip in successfulTrips.joined() {
            let destination = trip.stops.reversed().lazy.compactMap { stop in
                catalog.stationName(forStopID: stop.stopID)
            }.first ?? "Unknown destination"

            for stop in trip.stops where !stop.isSkipped {
                guard
                    let time = stop.time,
                    time >= now.addingTimeInterval(-60),
                    time <= horizon,
                    let stationID = catalog.stationID(forStopID: stop.stopID)
                else { continue }

                let direction: TravelDirection
                if stop.stopID.hasSuffix("N") {
                    direction = .northbound
                } else if stop.stopID.hasSuffix("S") {
                    direction = .southbound
                } else {
                    direction = .unknown
                }

                let normalizedRoute = RouteID.normalized(trip.routeID)
                let identifier = "\(trip.tripID)|\(normalizedRoute)|\(stop.stopID)|\(Int(time.timeIntervalSince1970))"
                uniqueArrivals[identifier] = Arrival(
                    id: identifier,
                    routeID: normalizedRoute,
                    stationID: stationID,
                    stopID: stop.stopID,
                    direction: direction,
                    destination: destination,
                    arrivalTime: time
                )
            }
        }

        return FeedSnapshot(
            arrivals: uniqueArrivals.values.sorted { $0.arrivalTime < $1.arrivalTime },
            fetchedAt: now,
            failedFeedCount: results.count - successfulTrips.count
        )
    }
}
