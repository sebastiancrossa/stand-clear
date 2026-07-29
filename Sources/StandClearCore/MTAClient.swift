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
    /// How far ahead of `now` a stop event may sit and still become an arrival.
    /// The board shows at most eight arrivals per station, so a half-hour window
    /// is ample and avoids retaining every stop event across the whole system.
    public static let arrivalHorizon: TimeInterval = 30 * 60

    /// Maximum number of MTA feeds fetched and parsed at once. Keeps peak
    /// protobuf memory bounded regardless of how many feeds a refresh needs.
    public static let maxConcurrentFeeds = 3

    fileprivate struct FeedDescriptor: Sendable {
        let id: String
        let url: URL
        let routeIDs: Set<String>
    }

    private static let feeds: [FeedDescriptor] = [
        feed("gtfs", "nyct%2Fgtfs", ["1", "2", "3", "4", "5", "5X", "6", "6X", "7", "7X", "GS"]),
        feed("gtfs-ace", "nyct%2Fgtfs-ace", ["A", "C", "E", "H"]),
        feed("gtfs-bdfm", "nyct%2Fgtfs-bdfm", ["B", "D", "F", "FX", "M", "FS"]),
        feed("gtfs-g", "nyct%2Fgtfs-g", ["G"]),
        feed("gtfs-jz", "nyct%2Fgtfs-jz", ["J", "Z"]),
        feed("gtfs-l", "nyct%2Fgtfs-l", ["L"]),
        feed("gtfs-nqrw", "nyct%2Fgtfs-nqrw", ["N", "Q", "R", "W"]),
        feed("gtfs-si", "nyct%2Fgtfs-si", ["SI"]),
    ]

    public static let feedURLs = feeds.map(\.url)

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches the feeds needed for `routeIDs`. Pass `nil` (or an empty set) to
    /// fetch every feed. When `includeTrains` is false, trip/vehicle observations
    /// used only by the Live Map are not built, so the board path stays lean.
    public func fetchSystemSnapshot(
        catalog: StationCatalog,
        now: Date = Date(),
        routeIDs: Set<String>? = nil,
        includeTrains: Bool = true
    ) async throws -> SystemFeedSnapshot {
        let normalizedRoutes = routeIDs.map { Set($0.map(RouteID.normalized)) }
        let descriptors: [FeedDescriptor]
        if let normalizedRoutes {
            if normalizedRoutes.isEmpty {
                descriptors = []
            } else {
                descriptors = Self.feeds.filter { !$0.routeIDs.isDisjoint(with: normalizedRoutes) }
            }
        } else {
            descriptors = Self.feeds
        }

        if descriptors.isEmpty {
            return SystemFeedSnapshot(
                arrivals: [],
                trains: [],
                fetchedAt: now,
                feedStatuses: []
            )
        }

        let session = session
        let includeTrains = includeTrains
        let maxConcurrent = Self.maxConcurrentFeeds
        let routeFilter = normalizedRoutes.flatMap { $0.isEmpty ? nil : $0 }
        let results = await withTaskGroup(of: FeedDerivedResult.self) { group in
            var nextIndex = 0
            var collected: [FeedDerivedResult] = []
            collected.reserveCapacity(descriptors.count)

            func enqueue(_ index: Int) {
                let descriptor = descriptors[index]
                group.addTask {
                    await Self.fetchAndConvert(
                        descriptor: descriptor,
                        index: index,
                        session: session,
                        catalog: catalog,
                        now: now,
                        includeTrains: includeTrains,
                        routeIDs: routeFilter
                    )
                }
            }

            while nextIndex < min(maxConcurrent, descriptors.count) {
                enqueue(nextIndex)
                nextIndex += 1
            }

            while let result = await group.next() {
                collected.append(result)
                if nextIndex < descriptors.count {
                    enqueue(nextIndex)
                    nextIndex += 1
                }
            }

            return collected.sorted { $0.index < $1.index }
        }

        guard results.contains(where: { $0.succeeded }) else {
            throw MTAFeedError.allFeedsFailed
        }

        let statuses = results.map(\.status)
        let arrivals = results.flatMap(\.arrivals).sorted { $0.arrivalTime < $1.arrivalTime }
        let trains = results.flatMap(\.trains).sorted {
            if $0.routeID != $1.routeID { return $0.routeID < $1.routeID }
            if $0.id.serviceDate != $1.id.serviceDate { return $0.id.serviceDate < $1.id.serviceDate }
            if $0.id.startTime != $1.id.startTime { return $0.id.startTime < $1.id.startTime }
            return $0.id.tripID < $1.id.tripID
        }

        return SystemFeedSnapshot(
            arrivals: arrivals,
            trains: trains,
            fetchedAt: now,
            feedStatuses: statuses
        )
    }

    public func fetchArrivals(
        catalog: StationCatalog,
        now: Date = Date(),
        routeIDs: Set<String>? = nil
    ) async throws -> FeedSnapshot {
        let snapshot = try await fetchSystemSnapshot(
            catalog: catalog,
            now: now,
            routeIDs: routeIDs,
            includeTrains: false
        )
        return FeedSnapshot(
            arrivals: snapshot.arrivals,
            fetchedAt: snapshot.fetchedAt,
            failedFeedCount: snapshot.failedFeedCount,
            failedRouteIDs: snapshot.failedRouteIDs
        )
    }

    private static func fetchAndConvert(
        descriptor: FeedDescriptor,
        index: Int,
        session: URLSession,
        catalog: StationCatalog,
        now: Date,
        includeTrains: Bool,
        routeIDs: Set<String>?
    ) async -> FeedDerivedResult {
        do {
            var request = URLRequest(url: descriptor.url)
            request.timeoutInterval = 12
            request.setValue("StandClear/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw MTAFeedError.invalidResponse
            }
            // Parse and convert inside this task so the protobuf graph dies
            // before the next feed result is collected by the parent.
            let feed = try GTFSRealtimeParser.parse(data: data)
            let arrivals = makeArrivals(
                trips: feed.tripUpdates,
                catalog: catalog,
                now: now,
                routeIDs: routeIDs
            )
            let trains = includeTrains
                ? makeTrainObservations(feed: feed, feedID: descriptor.id, catalog: catalog)
                : []
            let status = RealtimeFeedStatus(
                feedID: descriptor.id,
                routeIDs: descriptor.routeIDs,
                state: .succeeded,
                feedTimestamp: feed.timestamp,
                deletedEntityIDs: Set(
                    feed.entities.compactMap { entity in
                        entity.isDeleted ? entity.id : nil
                    }
                )
            )
            return FeedDerivedResult(
                index: index,
                succeeded: true,
                status: status,
                arrivals: arrivals,
                trains: trains
            )
        } catch {
            return FeedDerivedResult(
                index: index,
                succeeded: false,
                status: RealtimeFeedStatus(
                    feedID: descriptor.id,
                    routeIDs: descriptor.routeIDs,
                    state: .failed,
                    feedTimestamp: nil,
                    deletedEntityIDs: []
                ),
                arrivals: [],
                trains: []
            )
        }
    }

    private static func makeArrivals(
        trips: [RealtimeTrip],
        catalog: StationCatalog,
        now: Date,
        routeIDs: Set<String>?
    ) -> [Arrival] {
        let horizon = now.addingTimeInterval(arrivalHorizon)
        var uniqueArrivals: [String: Arrival] = [:]

        for trip in trips {
            let normalizedRoute = RouteID.normalized(trip.routeID)
            if let routeIDs, !routeIDs.contains(normalizedRoute) {
                continue
            }
            let destination = destination(for: trip.stops, catalog: catalog)

            for stop in trip.stops where !stop.isSkipped {
                guard
                    let time = stop.time,
                    time >= now.addingTimeInterval(-60),
                    time <= horizon,
                    let stationID = catalog.stationID(forStopID: stop.stopID)
                else { continue }

                let direction = direction(forStopID: stop.stopID)
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

        return Array(uniqueArrivals.values)
    }

    private static func makeTrainObservations(
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
        var vehicleFallbackByTripID: [String: (RunMatchKey, VehicleEntity)] = [:]
        for entity in vehicleEntities {
            let key = RunMatchKey(vehicle: entity.vehicle)
            vehiclesByKey[key] = entity
            if vehicleFallbackByTripID[key.tripID] == nil {
                vehicleFallbackByTripID[key.tripID] = (key, entity)
            }
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
               let fallback = vehicleFallbackByTripID[tripEntity.trip.tripID]
            {
                matchedVehicleKey = fallback.0
                vehicleEntity = fallback.1
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

    private static func makeTrainObservation(
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
                status: entity.vehicle.status,
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

    private static func destination(for stops: [RealtimeStopEvent], catalog: StationCatalog) -> String {
        stops.reversed().lazy.compactMap { stop in
            catalog.stationName(forStopID: stop.stopID)
        }.first ?? "Unknown destination"
    }

    private static func direction(forStopID stopID: String) -> TravelDirection {
        if stopID.hasSuffix("N") { return .northbound }
        if stopID.hasSuffix("S") { return .southbound }
        return .unknown
    }

    private static func feed(_ id: String, _ path: String, _ routeIDs: Set<String>) -> FeedDescriptor {
        FeedDescriptor(
            id: id,
            url: URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/\(path)")!,
            routeIDs: routeIDs
        )
    }
}

private struct FeedDerivedResult: Sendable {
    let index: Int
    let succeeded: Bool
    let status: RealtimeFeedStatus
    let arrivals: [Arrival]
    let trains: [TrainObservation]
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
