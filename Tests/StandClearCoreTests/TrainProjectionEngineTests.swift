@testable import StandClearCore
import XCTest

final class TrainProjectionEngineTests: XCTestCase {
    func testExactShapeSuffixProjectsTrainBetweenStops() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let observation = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: now.addingTimeInterval(50)), stop("CN", arrival: now.addingTimeInterval(150))]
        )

        let plans = engine.update(observations: [observation], at: now)
        let plan = try XCTUnwrap(plans.first)
        let rendered = try XCTUnwrap(plan.render(at: now))

        XCTAssertEqual(plan.shapeID, "Q..N16R")
        XCTAssertEqual(rendered.position.distanceMeters, 500, accuracy: 0.01)
        XCTAssertEqual(rendered.nextStopID, "BN")
        XCTAssertEqual(rendered.confidence, .medium)
        XCTAssertTrue(rendered.reasons.contains(.inferredDeparture))
    }

    func testOrderedStopsSelectUniqueRouteDirectionPathWithoutShapeSuffix() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())

        let plans = engine.update(
            observations: [train(stops: [stop("BN", arrival: now.addingTimeInterval(50)), stop("CN")])],
            at: now
        )

        XCTAssertEqual(plans.first?.shapeID, "Q..N16R")
    }

    func testAmbiguousPathFallsBackOnlyToVerifiedStationAndNeverGuessesLine() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let fallback = train(stops: [stop("BN"), stop("DN")])

        let fallbackPlan = try XCTUnwrap(engine.update(observations: [fallback], at: now).first)
        let rendered = try XCTUnwrap(fallbackPlan.render(at: now))

        XCTAssertEqual(rendered.position.distanceMeters, 1_000)
        XCTAssertEqual(rendered.velocityMetersPerSecond, 0)
        XCTAssertEqual(rendered.confidence, .low)
        XCTAssertTrue(rendered.reasons.contains(.unmatchedGeometry))

        let unmatched = train(tripID: "unknown", stops: [stop("ZZZ")])
        XCTAssertTrue(engine.update(observations: [unmatched], at: now).isEmpty)
    }

    func testStoppedVehiclePinsAtStationAndTrackMismatchLowersConfidence() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let vehicle = TrainVehicleObservation(
            entityID: "vehicle",
            stopID: "BN",
            stopSequence: 2,
            status: .stoppedAt,
            timestamp: now
        )
        let observation = train(
            tripID: "083000_Q..N16R",
            stops: [
                stop(
                    "BN",
                    departure: now.addingTimeInterval(20),
                    scheduledTrack: "1",
                    actualTrack: "2"
                ),
            ],
            vehicle: vehicle
        )
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())

        let rendered = try XCTUnwrap(engine.update(observations: [observation], at: now).first?.render(at: now.addingTimeInterval(10)))

        XCTAssertEqual(rendered.position.distanceMeters, 1_000)
        XCTAssertEqual(rendered.velocityMetersPerSecond, 0)
        XCTAssertEqual(rendered.confidence, .medium)
        XCTAssertTrue(rendered.reasons.contains(.trackMismatch))
    }

    func testFeedAgingFreezesAtSixtySecondsAndExpiresAtNinety() throws {
        let feedTime = Date(timeIntervalSince1970: 10_000)
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let observation = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: feedTime.addingTimeInterval(100))],
            feedTimestamp: feedTime
        )
        let plan = try XCTUnwrap(engine.update(observations: [observation], at: feedTime).first)

        XCTAssertEqual(plan.render(at: feedTime.addingTimeInterval(59))?.health, .live)
        let atSixty = try XCTUnwrap(plan.render(at: feedTime.addingTimeInterval(60)))
        let atEightyNine = try XCTUnwrap(plan.render(at: feedTime.addingTimeInterval(89)))
        XCTAssertEqual(atSixty.health, .aging)
        XCTAssertEqual(atEightyNine.health, .aging)
        XCTAssertEqual(atSixty.position, atEightyNine.position)
        XCTAssertEqual(atEightyNine.velocityMetersPerSecond, 0)
        XCTAssertNil(plan.render(at: feedTime.addingTimeInterval(90)))
    }

    func testRetargetPreservesPositionAndNeverReversesOrOvershoots() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let original = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: start.addingTimeInterval(100))],
            feedTimestamp: start
        )
        let originalPlan = try XCTUnwrap(engine.update(observations: [original], at: start).first)
        let refreshTime = start.addingTimeInterval(30)
        let before = try XCTUnwrap(originalPlan.render(at: refreshTime))
        let revised = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: start.addingTimeInterval(50))],
            feedTimestamp: refreshTime
        )

        let revisedPlan = try XCTUnwrap(engine.update(observations: [revised], at: refreshTime).first)
        let immediatelyAfter = try XCTUnwrap(revisedPlan.render(at: refreshTime))
        let afterArrival = try XCTUnwrap(revisedPlan.render(at: start.addingTimeInterval(55)))

        XCTAssertEqual(immediatelyAfter.position.distanceMeters, before.position.distanceMeters, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(immediatelyAfter.velocityMetersPerSecond, 0)
        XCTAssertEqual(afterArrival.position.distanceMeters, 1_000, accuracy: 0.001)
        XCTAssertEqual(afterArrival.velocityMetersPerSecond, 0)
    }

    func testBranchChangeRebasesWithCrossfadeInsteadOfTravelingBetweenPaths() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let original = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: start.addingTimeInterval(50)), stop("CN")],
            feedTimestamp: start
        )
        let oldPlan = try XCTUnwrap(engine.update(observations: [original], at: start).first)
        let updateTime = start.addingTimeInterval(10)
        let oldPosition = try XCTUnwrap(oldPlan.render(at: updateTime)).position
        let rerouted = train(
            tripID: "083000_Q..N16R",
            stops: [stop("DN", arrival: start.addingTimeInterval(60)), stop("CN")],
            feedTimestamp: updateTime
        )

        let newPlan = try XCTUnwrap(engine.update(observations: [rerouted], at: updateTime).first)
        let rebased = try XCTUnwrap(newPlan.render(at: updateTime))

        XCTAssertEqual(newPlan.shapeID, "Q..N19R")
        XCTAssertEqual(rebased.previousTopologyPosition, oldPosition)
        XCTAssertEqual(rebased.topologyTransitionProgress, 0)
        XCTAssertTrue(rebased.reasons.contains(.topologyMismatch))
        XCTAssertEqual(rebased.confidence, .low)
    }

    func testStalledVehicleFreezesAndFreshMovementRecoversWithoutJump() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let staleVehicle = TrainVehicleObservation(
            entityID: "vehicle",
            stopID: "BN",
            stopSequence: 2,
            status: .inTransitTo,
            timestamp: start.addingTimeInterval(-91)
        )
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let stalledObservation = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: start.addingTimeInterval(100))],
            feedTimestamp: start,
            vehicle: staleVehicle
        )
        let stalledPlan = try XCTUnwrap(engine.update(observations: [stalledObservation], at: start).first)
        let frozen = try XCTUnwrap(stalledPlan.render(at: start))

        XCTAssertEqual(frozen.health, .stalled)
        XCTAssertEqual(frozen.velocityMetersPerSecond, 0)
        XCTAssertEqual(stalledPlan.render(at: start.addingTimeInterval(10))?.position, frozen.position)

        let recoveryTime = start.addingTimeInterval(10)
        let freshVehicle = TrainVehicleObservation(
            entityID: "vehicle",
            stopID: "BN",
            stopSequence: 2,
            status: .inTransitTo,
            timestamp: recoveryTime
        )
        let recoveredObservation = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: start.addingTimeInterval(100))],
            feedTimestamp: recoveryTime,
            vehicle: freshVehicle
        )
        let recoveredPlan = try XCTUnwrap(engine.update(observations: [recoveredObservation], at: recoveryTime).first)
        let recovered = try XCTUnwrap(recoveredPlan.render(at: recoveryTime))

        XCTAssertEqual(recovered.health, .live)
        XCTAssertEqual(recovered.position, frozen.position)
    }
}

final class TrainObservationCacheTests: XCTestCase {
    func testSuccessfulFeedsReplaceTheirGroupWhileFailedFeedsRetainThenExpire() {
        let start = Date(timeIntervalSince1970: 10_000)
        let firstA = train(feedID: "feed-a", tripID: "a1", stops: [stop("BN")], feedTimestamp: start)
        let removedA = train(feedID: "feed-a", tripID: "a2", stops: [stop("BN")], feedTimestamp: start)
        let retainedB = train(feedID: "feed-b", tripID: "b1", stops: [stop("BN")], feedTimestamp: start)
        var cache = TrainObservationCache()

        let initial = cache.merge(
            snapshot(
                trains: [firstA, removedA, retainedB],
                at: start,
                statuses: [status("feed-a", .succeeded, start), status("feed-b", .succeeded, start)]
            ),
            at: start
        )
        XCTAssertEqual(Set(initial.map(\.observation.id.tripID)), ["a1", "a2", "b1"])

        let refresh = start.addingTimeInterval(30)
        let refreshedA = train(feedID: "feed-a", tripID: "a1", stops: [stop("BN")], feedTimestamp: refresh)
        let partial = cache.merge(
            snapshot(
                trains: [refreshedA],
                at: refresh,
                statuses: [status("feed-a", .succeeded, refresh), status("feed-b", .failed, nil)]
            ),
            at: refresh
        )
        XCTAssertEqual(Set(partial.map(\.observation.id.tripID)), ["a1", "b1"])

        let allFailed = cache.merge(
            snapshot(
                trains: [],
                at: start.addingTimeInterval(89),
                statuses: [status("feed-a", .failed, nil), status("feed-b", .failed, nil)]
            ),
            at: start.addingTimeInterval(89)
        )
        XCTAssertEqual(Set(allFailed.map(\.observation.id.tripID)), ["a1", "b1"])

        let expired = cache.merge(
            snapshot(
                trains: [],
                at: start.addingTimeInterval(120),
                statuses: [status("feed-a", .failed, nil), status("feed-b", .failed, nil)]
            ),
            at: start.addingTimeInterval(120)
        )
        XCTAssertTrue(expired.isEmpty)
    }
}

private func geometryCatalog() throws -> TrackGeometryCatalog {
    let resource = SubwayGeometryResource(
        feedVersion: "fixture",
        routes: [
            RouteGeometryMetadata(
                id: "Q",
                shortName: "Q",
                longName: "Broadway Express",
                colorHex: "FCCC0A",
                textColorHex: "000000",
                sortOrder: 1
            ),
        ],
        paths: [
            TrackPath(
                shapeID: "Q..N16R",
                routeIDs: ["Q"],
                directionIDs: [0],
                points: [
                    TrackPoint(latitude: 40.0, longitude: -74.0, distanceMeters: 0),
                    TrackPoint(latitude: 40.1, longitude: -73.9, distanceMeters: 1_000),
                    TrackPoint(latitude: 40.2, longitude: -73.8, distanceMeters: 2_000),
                ],
                anchors: [
                    TrackStopAnchor(stopID: "AN", stationID: "A", sequence: 1, pointIndex: 0, distanceMeters: 0, medianDwellSeconds: 20, medianTravelSecondsToNext: 100),
                    TrackStopAnchor(stopID: "BN", stationID: "B", sequence: 2, pointIndex: 1, distanceMeters: 1_000, medianDwellSeconds: 20, medianTravelSecondsToNext: 100),
                    TrackStopAnchor(stopID: "CN", stationID: "C", sequence: 3, pointIndex: 2, distanceMeters: 2_000, medianDwellSeconds: 20, medianTravelSecondsToNext: nil),
                ]
            ),
            TrackPath(
                shapeID: "Q..N19R",
                routeIDs: ["Q"],
                directionIDs: [0],
                points: [
                    TrackPoint(latitude: 40.0, longitude: -74.0, distanceMeters: 0),
                    TrackPoint(latitude: 40.05, longitude: -73.95, distanceMeters: 800),
                    TrackPoint(latitude: 40.2, longitude: -73.8, distanceMeters: 2_000),
                ],
                anchors: [
                    TrackStopAnchor(stopID: "AN", stationID: "A", sequence: 1, pointIndex: 0, distanceMeters: 0, medianDwellSeconds: 20, medianTravelSecondsToNext: 80),
                    TrackStopAnchor(stopID: "DN", stationID: "D", sequence: 2, pointIndex: 1, distanceMeters: 800, medianDwellSeconds: 20, medianTravelSecondsToNext: 120),
                    TrackStopAnchor(stopID: "CN", stationID: "C", sequence: 3, pointIndex: 2, distanceMeters: 2_000, medianDwellSeconds: 20, medianTravelSecondsToNext: nil),
                ]
            ),
        ],
        corridors: [],
        transferGroups: [],
        validationWarnings: []
    )
    return try TrackGeometryCatalog(data: JSONEncoder().encode(resource))
}

private func train(
    feedID: String = "gtfs-nqrw",
    tripID: String = "trip",
    stops: [TrainStopObservation],
    feedTimestamp: Date = Date(timeIntervalSince1970: 10_000),
    vehicle: TrainVehicleObservation? = nil
) -> TrainObservation {
    TrainObservation(
        id: TrainRunID(feedID: feedID, routeID: "Q", tripID: tripID, serviceDate: "20270115", startTime: "08:30:00"),
        entityIDs: ["entity"],
        routeID: "Q",
        directionID: 0,
        nyctDirection: .northbound,
        destination: "C",
        isAssigned: true,
        nyctTrainID: "Q 0830",
        feedTimestamp: feedTimestamp,
        tripUpdateTimestamp: feedTimestamp,
        stops: stops,
        vehicle: vehicle
    )
}

private func snapshot(
    trains: [TrainObservation],
    at date: Date,
    statuses: [RealtimeFeedStatus]
) -> SystemFeedSnapshot {
    SystemFeedSnapshot(arrivals: [], trains: trains, fetchedAt: date, feedStatuses: statuses)
}

private func status(
    _ feedID: String,
    _ state: RealtimeFeedState,
    _ timestamp: Date?
) -> RealtimeFeedStatus {
    RealtimeFeedStatus(
        feedID: feedID,
        routeIDs: ["Q"],
        state: state,
        feedTimestamp: timestamp
    )
}

private func stop(
    _ id: String,
    arrival: Date? = nil,
    departure: Date? = nil,
    scheduledTrack: String? = nil,
    actualTrack: String? = nil
) -> TrainStopObservation {
    TrainStopObservation(
        stopID: id,
        stopSequence: nil,
        arrivalTime: arrival,
        departureTime: departure,
        isSkipped: false,
        scheduledTrack: scheduledTrack,
        actualTrack: actualTrack
    )
}
