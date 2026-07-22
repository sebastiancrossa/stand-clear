@testable import StandClearCore
import XCTest

final class LiveFeedTests: XCTestCase {
    func testOfficialMTAFeedsProduceMappedArrivals() async throws {
        guard ProcessInfo.processInfo.environment["STAND_CLEAR_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set STAND_CLEAR_LIVE_TEST=1 to call the live MTA feeds.")
        }

        let catalog = try StationCatalog.bundled()
        let snapshot = try await MTAClient().fetchSystemSnapshot(catalog: catalog)

        XCTAssertGreaterThan(snapshot.arrivals.count, 100)
        XCTAssertEqual(snapshot.failedFeedCount, 0)
        XCTAssertTrue(snapshot.failedRouteIDs.isEmpty)
        XCTAssertTrue(snapshot.arrivals.contains { $0.routeID == "7" })
        XCTAssertTrue(snapshot.arrivals.allSatisfy { catalog.station(id: $0.stationID) != nil })
        XCTAssertFalse(snapshot.trains.isEmpty)
        XCTAssertEqual(Set(snapshot.trains.map(\.id)).count, snapshot.trains.count)
        XCTAssertTrue(snapshot.trains.allSatisfy { $0.isAssigned || $0.vehicle != nil })
        XCTAssertTrue(snapshot.trains.contains { !$0.stops.isEmpty })
        XCTAssertTrue(snapshot.feedStatuses.allSatisfy { $0.feedTimestamp != nil })

        let geometry = try TrackGeometryCatalog.bundled()
        let evaluationDate = snapshot.feedStatuses.compactMap(\.feedTimestamp).max() ?? snapshot.fetchedAt
        var engine = TrainProjectionEngine(catalog: geometry)
        let plans = engine.update(observations: snapshot.trains, at: evaluationDate)
        let rendered = plans.compactMap { $0.render(at: evaluationDate) }
        let plansByID = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        let inTransitEvidence = snapshot.trains.filter { observation in
            guard let vehicle = observation.vehicle,
                  let plan = plansByID[observation.id],
                  !plan.reasons.contains(.unmatchedGeometry)
            else { return false }
            if let vehicleTimestamp = vehicle.timestamp {
                let feedTimestamp = observation.feedTimestamp ?? evaluationDate
                guard feedTimestamp.timeIntervalSince(vehicleTimestamp) <= 90 else { return false }
            }
            switch vehicle.status {
            case .incomingAt, .inTransitTo:
                return true
            case .stoppedAt:
                let nextStopID = observation.stops.first(where: { !$0.isSkipped })?.stopID
                return vehicle.stopID != nil && vehicle.stopID != nextStopID
            case nil:
                return vehicle.stopSequence != nil
            }
        }
        let evidenceCountsByFeed = Dictionary(grouping: inTransitEvidence, by: { $0.id.feedID })
            .mapValues(\.count)

        XCTAssertFalse(rendered.isEmpty)
        XCTAssertTrue(rendered.allSatisfy { $0.movementState != .preDeparture })
        for (feedID, evidenceCount) in evidenceCountsByFeed where evidenceCount >= 3 {
            let projected = engine.coverage.movementStateCountsByFeed[feedID]?[.inTransit] ?? 0
            let evidenceDetails = inTransitEvidence
                .filter { $0.id.feedID == feedID }
                .map { observation in
                    let renderedPlan = plansByID[observation.id]?.render(at: evaluationDate)
                    let vehicle = observation.vehicle
                    let firstStop = observation.stops.first(where: { !$0.isSkipped })
                    let vehicleStopID = vehicle?.stopID ?? "nil"
                    let stopSequence = vehicle?.stopSequence.map(String.init) ?? "nil"
                    let firstStopID = firstStop?.stopID ?? "nil"
                    return "\(observation.routeID)/\(observation.id.tripID) "
                        + "status=\(String(describing: vehicle?.status)) "
                        + "vehicleStop=\(vehicleStopID) "
                        + "sequence=\(stopSequence) "
                        + "firstStop=\(firstStopID) "
                        + "vehicleAge=\(vehicle?.timestamp.map { evaluationDate.timeIntervalSince($0) } ?? -1) "
                        + "projected=\(String(describing: renderedPlan?.movementState)) "
                        + "confidence=\(String(describing: renderedPlan?.confidence)) "
                        + "reasons=\(String(describing: renderedPlan?.reasons))"
                }
                .joined(separator: "\n")
            XCTAssertGreaterThan(
                projected,
                0,
                "Feed \(feedID) had \(evidenceCount) observations with in-transit evidence but no in-transit plans. State counts: \(engine.coverage.movementStateCountsByFeed[feedID] ?? [:]); reasons: \(engine.coverage.projectionReasonCountsByFeed[feedID] ?? [:])\n\(evidenceDetails)"
            )
        }
    }
}
