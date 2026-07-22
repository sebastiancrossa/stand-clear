@testable import StandClearCore
import XCTest

final class TrainProjectionEngineTests: XCTestCase {
    func testPredepartureTrainIsHiddenAndExcludedFromEligibleCoverage() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let observation = train(
            tripID: "083000_Q..N16R",
            stops: [stop("AN", sequence: 1, departure: now.addingTimeInterval(120))],
            feedTimestamp: now,
            hasActiveEvidence: false
        )

        let plans = engine.update(observations: [observation], at: now)

        XCTAssertTrue(plans.isEmpty)
        XCTAssertEqual(engine.coverage.eligibleObservationCount, 0)
        XCTAssertEqual(engine.coverage.predepartureObservationCount, 1)
        XCTAssertEqual(engine.coverage.predepartureTrainCountsByRoute, ["Q": 1])
        XCTAssertEqual(engine.coverage.predepartureTrainCountsByFeed, ["gtfs-nqrw": 1])
        XCTAssertEqual(
            engine.coverage.predepartureTrainCountsByFeedAndRoute,
            ["gtfs-nqrw": ["Q": 1]]
        )
    }

    func testTripUpdateOnlyFutureNextStopIsActiveRatherThanPredeparture() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let observation = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", sequence: 2, arrival: now.addingTimeInterval(120))],
            feedTimestamp: now,
            hasActiveEvidence: false
        )

        let plan = try XCTUnwrap(engine.update(observations: [observation], at: now).first)
        let rendered = try XCTUnwrap(plan.render(at: now))

        XCTAssertEqual(engine.coverage.predepartureObservationCount, 0)
        XCTAssertEqual(engine.coverage.eligibleObservationCount, 1)
        XCTAssertEqual(rendered.movementState, .unknown)
    }

    func testMissingVehicleStatusWithStopSequenceIsInTransitWhileDataIsLive() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let vehicle = TrainVehicleObservation(
            entityID: "vehicle",
            stopID: "BN",
            stopSequence: 2,
            status: nil,
            timestamp: now
        )
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let observation = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: now.addingTimeInterval(100))],
            feedTimestamp: now,
            vehicle: vehicle
        )

        let rendered = try XCTUnwrap(
            engine.update(observations: [observation], at: now).first?.render(at: now.addingTimeInterval(10))
        )

        XCTAssertEqual(rendered.health, .live)
        XCTAssertEqual(rendered.movementState, .inTransit)
        XCTAssertGreaterThan(rendered.velocityMetersPerSecond, 0)
    }

    func testInTransitTimelineArrivesDwellsAndContinuesToFollowingStop() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let vehicle = TrainVehicleObservation(
            entityID: "vehicle",
            stopID: "BN",
            stopSequence: 2,
            status: .inTransitTo,
            timestamp: now
        )
        let observation = train(
            tripID: "083000_Q..N16R",
            stops: [
                stop(
                    "BN",
                    arrival: now.addingTimeInterval(20),
                    departure: now.addingTimeInterval(40)
                ),
                stop("CN", arrival: now.addingTimeInterval(120)),
            ],
            feedTimestamp: now,
            vehicle: vehicle
        )
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let plan = try XCTUnwrap(engine.update(observations: [observation], at: now).first)

        let approaching = try XCTUnwrap(plan.render(at: now.addingTimeInterval(10)))
        XCTAssertEqual(approaching.movementState, .inTransit)
        XCTAssertLessThan(approaching.position.distanceMeters, 1_000)
        XCTAssertGreaterThan(approaching.velocityMetersPerSecond, 0)
        XCTAssertEqual(approaching.nextStopID, "BN")

        let dwelling = try XCTUnwrap(plan.render(at: now.addingTimeInterval(30)))
        XCTAssertEqual(dwelling.movementState, .atStation)
        XCTAssertEqual(dwelling.position.distanceMeters, 1_000, accuracy: 0.001)
        XCTAssertEqual(dwelling.velocityMetersPerSecond, 0)
        XCTAssertEqual(dwelling.nextStopID, "BN")

        let continuing = try XCTUnwrap(plan.render(at: now.addingTimeInterval(50)))
        XCTAssertEqual(continuing.movementState, .inTransit)
        XCTAssertGreaterThan(continuing.position.distanceMeters, 1_000)
        XCTAssertLessThan(continuing.position.distanceMeters, 2_000)
        XCTAssertGreaterThan(continuing.velocityMetersPerSecond, 0)
        XCTAssertEqual(continuing.nextStopID, "CN")
        XCTAssertEqual(continuing.nextArrivalTime, now.addingTimeInterval(120))
    }

    func testPreviouslyActiveTrainDoesNotRevertToPredepartureWhenVehicleFieldsDisappear() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let activeVehicle = TrainVehicleObservation(
            entityID: "vehicle",
            stopID: "BN",
            stopSequence: 2,
            status: .inTransitTo,
            timestamp: start
        )
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let active = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: start.addingTimeInterval(100))],
            feedTimestamp: start,
            vehicle: activeVehicle
        )
        let initialPlan = try XCTUnwrap(engine.update(observations: [active], at: start).first)
        let refresh = start.addingTimeInterval(30)
        let beforeRefresh = try XCTUnwrap(initialPlan.render(at: refresh))
        let incomplete = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: start.addingTimeInterval(100))],
            feedTimestamp: refresh,
            vehicle: nil,
            hasActiveEvidence: false
        )

        let retainedPlan = try XCTUnwrap(engine.update(observations: [incomplete], at: refresh).first)
        let immediatelyAfter = try XCTUnwrap(retainedPlan.render(at: refresh))
        let later = try XCTUnwrap(retainedPlan.render(at: refresh.addingTimeInterval(10)))

        XCTAssertEqual(engine.coverage.predepartureObservationCount, 0)
        XCTAssertEqual(immediatelyAfter.movementState, .unknown)
        XCTAssertEqual(immediatelyAfter.position, beforeRefresh.position)
        XCTAssertEqual(later.position, immediatelyAfter.position)
        XCTAssertEqual(later.velocityMetersPerSecond, 0)
    }

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
        XCTAssertNotNil(rendered.headingDegrees)
        XCTAssertTrue((20...60).contains(try XCTUnwrap(rendered.headingDegrees)))
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

    func testSharedImmediateSegmentResolvesEvenWhenFullShapesDiverge() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let vehicle = TrainVehicleObservation(
            entityID: "vehicle",
            stopID: "BN",
            stopSequence: 2,
            status: .inTransitTo,
            timestamp: now
        )
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let observation = train(
            tripID: "083000_Q..N",
            stops: [stop("BN", arrival: now.addingTimeInterval(100))],
            feedTimestamp: now,
            vehicle: vehicle
        )

        let plan = try XCTUnwrap(engine.update(observations: [observation], at: now).first)
        let rendered = try XCTUnwrap(plan.render(at: now.addingTimeInterval(10)))

        XCTAssertEqual(plan.shapeID, "Q..N16R")
        XCTAssertEqual(rendered.confidence, .medium)
        XCTAssertTrue(rendered.reasons.contains(.localSegmentMatch))
        XCTAssertEqual(rendered.movementState, .inTransit)
        XCTAssertGreaterThan(rendered.velocityMetersPerSecond, 0)
    }

    func testSharedStopIDsWithDivergentImmediateGeometryDoNotResolveLocally() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let vehicle = TrainVehicleObservation(
            entityID: "vehicle",
            stopID: "BN",
            stopSequence: 2,
            status: .inTransitTo,
            timestamp: now
        )
        var engine = TrainProjectionEngine(catalog: try geometryCatalog(includeDivergentSharedSegment: true))
        let observation = train(
            tripID: "083000_Q..N",
            stops: [stop("BN", arrival: now.addingTimeInterval(100))],
            feedTimestamp: now,
            vehicle: vehicle
        )

        let rendered = try XCTUnwrap(engine.update(observations: [observation], at: now).first?.render(at: now))

        XCTAssertEqual(rendered.movementState, .unknown)
        XCTAssertEqual(rendered.velocityMetersPerSecond, 0)
        XCTAssertEqual(rendered.confidence, .low)
        XCTAssertTrue(rendered.reasons.contains(.unmatchedGeometry))
        XCTAssertFalse(rendered.reasons.contains(.localSegmentMatch))
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
        XCTAssertEqual(engine.coverage.eligibleObservationCount, 1)
        XCTAssertEqual(engine.coverage.placedTrainCount, 0)
        XCTAssertEqual(engine.coverage.unplacedRouteIDs, ["Q"])
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

    func testStoppedStatusAtPriorStopMovesTowardAdvancedTripUpdateStop() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let vehicle = TrainVehicleObservation(
            entityID: "vehicle",
            stopID: "AN",
            stopSequence: 1,
            status: .stoppedAt,
            timestamp: now
        )
        let observation = train(
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: now.addingTimeInterval(100))],
            feedTimestamp: now,
            vehicle: vehicle
        )
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())

        let rendered = try XCTUnwrap(
            engine.update(observations: [observation], at: now).first?.render(at: now.addingTimeInterval(10))
        )

        XCTAssertEqual(rendered.movementState, .inTransit)
        XCTAssertGreaterThan(rendered.position.distanceMeters, 0)
        XCTAssertLessThan(rendered.position.distanceMeters, 1_000)
        XCTAssertGreaterThan(rendered.velocityMetersPerSecond, 0)
    }

    func testStoppedStatusUsesVehicleAnchorWhenTripUpdateSkipsIntermediateStops() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let vehicle = TrainVehicleObservation(
            entityID: "vehicle",
            stopID: "AN",
            stopSequence: 1,
            status: .stoppedAt,
            timestamp: now
        )
        let observation = train(
            tripID: "083000_Q..N16R",
            stops: [stop("CN", arrival: now.addingTimeInterval(100))],
            feedTimestamp: now,
            vehicle: vehicle
        )
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())

        let rendered = try XCTUnwrap(
            engine.update(observations: [observation], at: now).first?.render(at: now.addingTimeInterval(10))
        )

        XCTAssertEqual(rendered.movementState, .inTransit)
        XCTAssertGreaterThan(rendered.position.distanceMeters, 0)
        XCTAssertLessThan(rendered.position.distanceMeters, 1_000)
    }

    func testStoppedTrainDwellsThenAdvancesToFollowingStop() throws {
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
                stop("BN", arrival: now, departure: now.addingTimeInterval(20)),
                stop("CN", arrival: now.addingTimeInterval(120)),
            ],
            feedTimestamp: now,
            vehicle: vehicle
        )
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let plan = try XCTUnwrap(engine.update(observations: [observation], at: now).first)

        let dwelling = try XCTUnwrap(plan.render(at: now.addingTimeInterval(10)))
        XCTAssertEqual(dwelling.movementState, .atStation)
        XCTAssertEqual(dwelling.position.distanceMeters, 1_000, accuracy: 0.001)
        XCTAssertEqual(dwelling.velocityMetersPerSecond, 0)
        XCTAssertEqual(dwelling.nextStopID, "BN")

        let departed = try XCTUnwrap(plan.render(at: now.addingTimeInterval(30)))
        XCTAssertEqual(departed.movementState, .inTransit)
        XCTAssertGreaterThan(departed.position.distanceMeters, 1_000)
        XCTAssertLessThan(departed.position.distanceMeters, 2_000)
        XCTAssertGreaterThan(departed.velocityMetersPerSecond, 0)
        XCTAssertEqual(departed.nextStopID, "CN")
        XCTAssertEqual(departed.nextArrivalTime, now.addingTimeInterval(120))
    }

    func testStoppedTrainWithElapsedDepartureStillDwellsBeforeAdvancing() throws {
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
                stop("BN", arrival: now.addingTimeInterval(-20), departure: now.addingTimeInterval(-5)),
                stop("CN", arrival: now.addingTimeInterval(120)),
            ],
            feedTimestamp: now,
            vehicle: vehicle
        )
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let plan = try XCTUnwrap(engine.update(observations: [observation], at: now).first)

        let dwelling = try XCTUnwrap(plan.render(at: now.addingTimeInterval(10)))
        XCTAssertEqual(dwelling.movementState, .atStation)
        XCTAssertEqual(dwelling.position.distanceMeters, 1_000, accuracy: 0.001)
        XCTAssertEqual(dwelling.velocityMetersPerSecond, 0)

        let departed = try XCTUnwrap(plan.render(at: now.addingTimeInterval(30)))
        XCTAssertEqual(departed.movementState, .inTransit)
        XCTAssertGreaterThan(departed.position.distanceMeters, 1_000)
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

    func testCoverageBreaksDownPlacedUnplacedAndExpiredObservationsByFeed() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let placed = train(
            feedID: "feed-a",
            tripID: "083000_Q..N16R",
            stops: [stop("BN", arrival: now.addingTimeInterval(50))],
            feedTimestamp: now
        )
        let unplaced = train(
            feedID: "feed-b",
            tripID: "unknown",
            stops: [stop("ZZZ")],
            feedTimestamp: now
        )
        let expired = train(
            feedID: "feed-b",
            tripID: "expired",
            stops: [stop("BN")],
            feedTimestamp: now.addingTimeInterval(-90)
        )

        _ = engine.update(
            entries: [
                .init(observation: placed, lastValidAt: now),
                .init(observation: unplaced, lastValidAt: now),
                .init(observation: expired, lastValidAt: now.addingTimeInterval(-90)),
            ],
            at: now
        )

        XCTAssertEqual(engine.coverage.eligibleTrainCountsByFeed, ["feed-a": 1, "feed-b": 1])
        XCTAssertEqual(engine.coverage.placedTrainCountsByFeed, ["feed-a": 1])
        XCTAssertEqual(engine.coverage.unplacedTrainCountsByFeed, ["feed-b": 1])
        XCTAssertEqual(
            engine.coverage.eligibleTrainCountsByFeedAndRoute,
            ["feed-a": ["Q": 1], "feed-b": ["Q": 1]]
        )
        XCTAssertEqual(engine.coverage.placedTrainCountsByFeedAndRoute, ["feed-a": ["Q": 1]])
        XCTAssertEqual(engine.coverage.unplacedTrainCountsByFeedAndRoute, ["feed-b": ["Q": 1]])
        XCTAssertEqual(engine.coverage.eligibleTrainCountsByRoute, ["Q": 2])
        XCTAssertEqual(engine.coverage.placedTrainCountsByRoute, ["Q": 1])
        XCTAssertEqual(engine.coverage.expiredTrainCountsByRoute, ["Q": 1])
        XCTAssertEqual(engine.coverage.expiredTrainCountsByFeed, ["feed-b": 1])
        XCTAssertEqual(engine.coverage.expiredObservationCount, 1)
        XCTAssertEqual(engine.coverage.movementStateCounts, [.inTransit: 1])
        XCTAssertEqual(engine.coverage.movementStateCountsByFeed, ["feed-a": [.inTransit: 1]])
        XCTAssertEqual(engine.coverage.projectionReasonCountsByFeed["feed-a"]?[.inferredDeparture], 1)
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

    func testRefreshDoesNotReturnToAStopAlreadyPassedByPriorTimeline() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        var engine = TrainProjectionEngine(catalog: try geometryCatalog())
        let initial = train(
            tripID: "083000_Q..N16R",
            stops: [
                stop("BN", arrival: start.addingTimeInterval(20)),
                stop("CN", arrival: start.addingTimeInterval(120)),
            ],
            feedTimestamp: start
        )
        let initialPlan = try XCTUnwrap(engine.update(observations: [initial], at: start).first)
        let refresh = start.addingTimeInterval(60)
        let before = try XCTUnwrap(initialPlan.render(at: refresh))
        XCTAssertGreaterThan(before.position.distanceMeters, 1_000)

        let repeatedStops = train(
            tripID: "083000_Q..N16R",
            stops: [
                stop("BN", arrival: start.addingTimeInterval(20)),
                stop("CN", arrival: start.addingTimeInterval(120)),
            ],
            feedTimestamp: refresh
        )
        let refreshedPlan = try XCTUnwrap(engine.update(observations: [repeatedStops], at: refresh).first)
        let atRefresh = try XCTUnwrap(refreshedPlan.render(at: refresh))
        let afterRefresh = try XCTUnwrap(refreshedPlan.render(at: refresh.addingTimeInterval(10)))

        XCTAssertEqual(atRefresh.position.distanceMeters, before.position.distanceMeters, accuracy: 0.001)
        XCTAssertEqual(atRefresh.nextStopID, "CN")
        XCTAssertGreaterThanOrEqual(afterRefresh.position.distanceMeters, atRefresh.position.distanceMeters)
        XCTAssertLessThanOrEqual(afterRefresh.position.distanceMeters, 2_000)
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

        XCTAssertEqual(frozen.health, .live)
        XCTAssertEqual(frozen.movementState, .stalled)
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
        XCTAssertEqual(recovered.movementState, .inTransit)
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
        XCTAssertEqual(
            Set(cache.coverageEntries(at: start.addingTimeInterval(120)).map(\.observation.id.tripID)),
            ["a1", "b1"]
        )
        XCTAssertTrue(cache.coverageEntries(at: start.addingTimeInterval(210)).isEmpty)
    }
}

private func geometryCatalog(includeDivergentSharedSegment: Bool = false) throws -> TrackGeometryCatalog {
    var paths = [
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
        TrackPath(
            shapeID: "Q..N16R_ALT",
            routeIDs: ["Q"],
            directionIDs: [0],
            points: [
                TrackPoint(latitude: 40.0, longitude: -74.0, distanceMeters: 0),
                TrackPoint(latitude: 40.05, longitude: -73.95, distanceMeters: 500),
                TrackPoint(latitude: 40.1, longitude: -73.9, distanceMeters: 1_000),
                TrackPoint(latitude: 40.25, longitude: -73.75, distanceMeters: 2_200),
            ],
            anchors: [
                TrackStopAnchor(stopID: "AN", stationID: "A", sequence: 1, pointIndex: 0, distanceMeters: 0, medianDwellSeconds: 20, medianTravelSecondsToNext: 100),
                TrackStopAnchor(stopID: "BN", stationID: "B", sequence: 2, pointIndex: 2, distanceMeters: 1_000, medianDwellSeconds: 20, medianTravelSecondsToNext: 120),
                TrackStopAnchor(stopID: "EN", stationID: "E", sequence: 3, pointIndex: 3, distanceMeters: 2_200, medianDwellSeconds: 20, medianTravelSecondsToNext: nil),
            ]
        ),
    ]
    if includeDivergentSharedSegment {
        paths.append(
            TrackPath(
                shapeID: "Q..N16R_DIVERGENT",
                routeIDs: ["Q"],
                directionIDs: [0],
                points: [
                    TrackPoint(latitude: 40.0, longitude: -74.0, distanceMeters: 0),
                    TrackPoint(latitude: 40.15, longitude: -74.15, distanceMeters: 700),
                    TrackPoint(latitude: 40.1, longitude: -73.9, distanceMeters: 1_400),
                    TrackPoint(latitude: 40.25, longitude: -73.75, distanceMeters: 2_400),
                ],
                anchors: [
                    TrackStopAnchor(stopID: "AN", stationID: "A", sequence: 1, pointIndex: 0, distanceMeters: 0, medianDwellSeconds: 20, medianTravelSecondsToNext: 100),
                    TrackStopAnchor(stopID: "BN", stationID: "B", sequence: 2, pointIndex: 2, distanceMeters: 1_400, medianDwellSeconds: 20, medianTravelSecondsToNext: 120),
                    TrackStopAnchor(stopID: "EN", stationID: "E", sequence: 3, pointIndex: 3, distanceMeters: 2_400, medianDwellSeconds: 20, medianTravelSecondsToNext: nil),
                ]
            )
        )
    }
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
        paths: paths,
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
    vehicle: TrainVehicleObservation? = nil,
    hasActiveEvidence: Bool = true
) -> TrainObservation {
    let resolvedVehicle = vehicle ?? (hasActiveEvidence ? TrainVehicleObservation(
        entityID: "vehicle",
        stopID: stops.first?.stopID,
        stopSequence: stops.first?.stopSequence ?? 1,
        status: .inTransitTo,
        timestamp: feedTimestamp
    ) : nil)
    return TrainObservation(
        id: TrainRunID(feedID: feedID, routeID: "Q", tripID: tripID, serviceDate: "20270115", startTime: "08:30:00"),
        entityIDs: ["entity"],
        directionID: 0,
        nyctDirection: .northbound,
        destination: "C",
        isAssigned: true,
        nyctTrainID: "Q 0830",
        feedTimestamp: feedTimestamp,
        tripUpdateTimestamp: feedTimestamp,
        stops: stops,
        vehicle: resolvedVehicle
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
    sequence: Int? = nil,
    arrival: Date? = nil,
    departure: Date? = nil,
    scheduledTrack: String? = nil,
    actualTrack: String? = nil
) -> TrainStopObservation {
    TrainStopObservation(
        stopID: id,
        stopSequence: sequence,
        arrivalTime: arrival,
        departureTime: departure,
        isSkipped: false,
        scheduledTrack: scheduledTrack,
        actualTrack: actualTrack
    )
}
