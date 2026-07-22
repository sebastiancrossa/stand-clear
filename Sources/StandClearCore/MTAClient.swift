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

    private static let feedIDs = [
        "gtfs", "gtfs-ace", "gtfs-bdfm", "gtfs-g",
        "gtfs-jz", "gtfs-l", "gtfs-nqrw", "gtfs-si",
    ]

    private static let routeIDsByFeedIndex: [Set<String>] = [
        ["1", "2", "3", "4", "5", "5X", "6", "6X", "7", "7X", "GS"],
        ["A", "C", "E", "H"],
        ["B", "D", "F", "FX", "M", "FS"],
        ["G"],
        ["J", "Z"],
        ["L"],
        ["N", "Q", "R", "W"],
        ["SI"],
    ]

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchSystemSnapshot(
        catalog: StationCatalog,
        now: Date = Date()
    ) async throws -> SystemFeedSnapshot {
        let session = session
        let results = await withTaskGroup(of: FeedFetchResult.self) { group in
            for (index, url) in Self.feedURLs.enumerated() {
                group.addTask {
                    do {
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 12
                        request.setValue("StandClear/1.0", forHTTPHeaderField: "User-Agent")
                        let (data, response) = try await session.data(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            throw MTAFeedError.invalidResponse
                        }
                        return FeedFetchResult(
                            index: index,
                            feed: try GTFSRealtimeParser.parse(data: data)
                        )
                    } catch {
                        return FeedFetchResult(index: index, feed: nil)
                    }
                }
            }

            var collected: [FeedFetchResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected.sorted { $0.index < $1.index }
        }

        guard results.contains(where: { $0.feed != nil }) else {
            throw MTAFeedError.allFeedsFailed
        }

        let statuses = results.map { result in
            RealtimeFeedStatus(
                feedID: Self.feedID(at: result.index),
                routeIDs: Self.routeIDs(at: result.index),
                state: result.feed == nil ? .failed : .succeeded,
                feedTimestamp: result.feed?.timestamp,
                deletedEntityIDs: Set(
                    result.feed?.entities.compactMap { entity in
                        entity.isDeleted ? entity.id : nil
                    } ?? []
                )
            )
        }

        let successfulFeeds = results.compactMap { result -> (Int, ParsedRealtimeFeed)? in
            result.feed.map { (result.index, $0) }
        }
        let arrivals = makeArrivals(
            trips: successfulFeeds.flatMap { $0.1.tripUpdates },
            catalog: catalog,
            now: now
        )
        let trains = successfulFeeds.flatMap { index, feed in
            makeTrainObservations(
                feed: feed,
                feedID: Self.feedID(at: index),
                catalog: catalog
            )
        }

        return SystemFeedSnapshot(
            arrivals: arrivals,
            trains: trains.sorted {
                if $0.routeID != $1.routeID { return $0.routeID < $1.routeID }
                if $0.id.serviceDate != $1.id.serviceDate { return $0.id.serviceDate < $1.id.serviceDate }
                if $0.id.startTime != $1.id.startTime { return $0.id.startTime < $1.id.startTime }
                return $0.id.tripID < $1.id.tripID
            },
            fetchedAt: now,
            feedStatuses: statuses
        )
    }

    public func fetchArrivals(
        catalog: StationCatalog,
        now: Date = Date()
    ) async throws -> FeedSnapshot {
        let snapshot = try await fetchSystemSnapshot(catalog: catalog, now: now)
        return FeedSnapshot(
            arrivals: snapshot.arrivals,
            fetchedAt: snapshot.fetchedAt,
            failedFeedCount: snapshot.failedFeedCount,
            failedRouteIDs: snapshot.failedRouteIDs
        )
    }

    private func makeArrivals(
        trips: [RealtimeTrip],
        catalog: StationCatalog,
        now: Date
    ) -> [Arrival] {
        let horizon = now.addingTimeInterval(2 * 60 * 60)
        var uniqueArrivals: [String: Arrival] = [:]

        for trip in trips {
            let destination = destination(for: trip.stops, catalog: catalog)

            for stop in trip.stops where !stop.isSkipped {
                guard
                    let time = stop.time,
                    time >= now.addingTimeInterval(-60),
                    time <= horizon,
                    let stationID = catalog.stationID(forStopID: stop.stopID)
                else { continue }

                let direction = Self.direction(forStopID: stop.stopID)
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

        return uniqueArrivals.values.sorted { $0.arrivalTime < $1.arrivalTime }
    }

    private func makeTrainObservations(
        feed: ParsedRealtimeFeed,
        feedID: String,
        catalog: StationCatalog
    ) -> [TrainObservation] {
        let activeEntities = feed.entities.filter { !$0.isDeleted }
        let tripEntities = activeEntities.compactMap { entity -> TripEntity? in
            entity.tripUpdate.map { TripEntity(entityID: entity.id, trip: $0) }
        }
        let vehicleEntities = activeEntities.compactMap { entity -> VehicleEntity? in
            entity.vehiclePosition.map { VehicleEntity(entityID: entity.id, vehicle: $0) }
        }

        var vehiclesByKey: [RunMatchKey: VehicleEntity] = [:]
        for entity in vehicleEntities {
            vehiclesByKey[RunMatchKey(vehicle: entity.vehicle)] = entity
        }

        let tripKeysByTripID = Dictionary(grouping: tripEntities, by: { $0.trip.tripID })
        var consumedVehicleKeys: Set<RunMatchKey> = []
        var observations: [TrainObservation] = []

        for tripEntity in tripEntities {
            let key = RunMatchKey(trip: tripEntity.trip)
            var vehicleEntity = vehiclesByKey[key]
            var matchedVehicleKey = key
            if vehicleEntity == nil,
               tripKeysByTripID[tripEntity.trip.tripID]?.count == 1,
               let fallback = vehiclesByKey.first(where: { $0.key.tripID == tripEntity.trip.tripID })
            {
                matchedVehicleKey = fallback.key
                vehicleEntity = fallback.value
            }
            if vehicleEntity != nil {
                consumedVehicleKeys.insert(matchedVehicleKey)
            }

            guard tripEntity.trip.isAssigned == true || vehicleEntity != nil else { continue }
            observations.append(
                makeTrainObservation(
                    feedID: feedID,
                    feedTimestamp: feed.timestamp,
                    tripEntity: tripEntity,
                    vehicleEntity: vehicleEntity,
                    catalog: catalog
                )
            )
        }

        for vehicleEntity in vehicleEntities {
            let key = RunMatchKey(vehicle: vehicleEntity.vehicle)
            guard !consumedVehicleKeys.contains(key) else { continue }
            observations.append(
                makeTrainObservation(
                    feedID: feedID,
                    feedTimestamp: feed.timestamp,
                    tripEntity: nil,
                    vehicleEntity: vehicleEntity,
                    catalog: catalog
                )
            )
        }

        return observations
    }

    private func makeTrainObservation(
        feedID: String,
        feedTimestamp: Date?,
        tripEntity: TripEntity?,
        vehicleEntity: VehicleEntity?,
        catalog: StationCatalog
    ) -> TrainObservation {
        let trip = tripEntity?.trip
        let vehicle = vehicleEntity?.vehicle
        let routeID = RouteID.normalized(trip?.routeID.nonEmpty ?? vehicle?.routeID.nonEmpty ?? "")
        let tripID = trip?.tripID ?? vehicle?.tripID ?? ""
        let serviceDate = trip?.startDate.nonEmpty ?? vehicle?.startDate.nonEmpty ?? ""
        let startTime = trip?.startTime.nonEmpty ?? vehicle?.startTime.nonEmpty ?? ""
        let stops = trip?.stops.map { stop in
            TrainStopObservation(
                stopID: stop.stopID,
                stopSequence: stop.stopSequence,
                arrivalTime: stop.arrivalTime,
                departureTime: stop.departureTime,
                isSkipped: stop.isSkipped,
                scheduledTrack: stop.scheduledTrack,
                actualTrack: stop.actualTrack
            )
        } ?? []
        let vehicleObservation = vehicleEntity.map { entity in
            TrainVehicleObservation(
                entityID: entity.entityID,
                stopID: entity.vehicle.stopID,
                stopSequence: entity.vehicle.stopSequence,
                status: entity.vehicle.status.map(Self.vehicleStatus),
                timestamp: entity.vehicle.timestamp
            )
        }

        return TrainObservation(
            id: TrainRunID(
                feedID: feedID,
                routeID: routeID,
                tripID: tripID,
                serviceDate: serviceDate,
                startTime: startTime
            ),
            entityIDs: [tripEntity?.entityID, vehicleEntity?.entityID].compactMap { $0 },
            routeID: routeID,
            directionID: trip?.directionID ?? vehicle?.directionID,
            nyctDirection: trip?.nyctDirection ?? vehicle?.nyctDirection,
            destination: destination(for: trip?.stops ?? [], catalog: catalog),
            isAssigned: trip?.isAssigned ?? vehicle?.isAssigned ?? false,
            nyctTrainID: trip?.nyctTrainID?.nonEmpty ?? vehicle?.nyctTrainID?.nonEmpty,
            feedTimestamp: feedTimestamp,
            tripUpdateTimestamp: trip?.timestamp,
            stops: stops,
            vehicle: vehicleObservation
        )
    }

    private func destination(for stops: [RealtimeStopEvent], catalog: StationCatalog) -> String {
        stops.reversed().lazy.compactMap { stop in
            catalog.stationName(forStopID: stop.stopID)
        }.first ?? "Unknown destination"
    }

    private static func direction(forStopID stopID: String) -> TravelDirection {
        if stopID.hasSuffix("N") { return .northbound }
        if stopID.hasSuffix("S") { return .southbound }
        return .unknown
    }

    private static func vehicleStatus(
        _ status: RealtimeVehiclePosition.Status
    ) -> TrainVehicleStatus {
        switch status {
        case .incomingAt: .incomingAt
        case .stoppedAt: .stoppedAt
        case .inTransitTo: .inTransitTo
        }
    }

    private static func feedID(at index: Int) -> String {
        feedIDs.indices.contains(index) ? feedIDs[index] : "feed-\(index)"
    }

    private static func routeIDs(at index: Int) -> Set<String> {
        routeIDsByFeedIndex.indices.contains(index) ? routeIDsByFeedIndex[index] : []
    }
}

private struct FeedFetchResult: Sendable {
    let index: Int
    let feed: ParsedRealtimeFeed?
}

private struct TripEntity {
    let entityID: String
    let trip: RealtimeTrip
}

private struct VehicleEntity {
    let entityID: String
    let vehicle: RealtimeVehiclePosition
}

private struct RunMatchKey: Hashable {
    let tripID: String
    let serviceDate: String
    let startTime: String

    init(trip: RealtimeTrip) {
        tripID = trip.tripID
        serviceDate = trip.startDate
        startTime = trip.startTime
    }

    init(vehicle: RealtimeVehiclePosition) {
        tripID = vehicle.tripID
        serviceDate = vehicle.startDate
        startTime = vehicle.startTime
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
