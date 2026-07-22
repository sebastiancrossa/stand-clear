@testable import StandClear
import StandClearCore
import XCTest

@MainActor
final class LiveMapSessionTests: XCTestCase {
    func testStartsWithEveryRouteAndFiltersWithoutPersistedArrivalState() {
        let session = LiveMapSession(allRoutes: ["N", "Q", "R"])

        XCTAssertEqual(session.selectedRoutes, ["N", "Q", "R"])

        session.toggleRoute("q")

        XCTAssertEqual(session.selectedRoutes, ["N", "R"])
        XCTAssertFalse(session.isRouteVisible("Q"))
    }

    func testShowAllRecoversFromZeroSelectedRoutes() {
        let session = LiveMapSession(allRoutes: ["N", "Q"])
        session.toggleRoute("N")
        session.toggleRoute("Q")

        XCTAssertTrue(session.selectedRoutes.isEmpty)
        XCTAssertTrue(session.needsRouteRecovery)

        session.showAllRoutes()

        XCTAssertEqual(session.selectedRoutes, ["N", "Q"])
        XCTAssertFalse(session.needsRouteRecovery)
    }

    func testSelectionPersistsWhileAvailableAndClearsWhenFilteredOrExpired() {
        let q = makeRunID(route: "Q")
        let n = makeRunID(route: "N")
        let session = LiveMapSession(allRoutes: ["N", "Q"])

        session.selectTrain(id: q)
        session.reconcile(trainIDs: [q, n])
        XCTAssertEqual(session.selectedTrainID, q)

        session.toggleRoute("Q")
        XCTAssertNil(session.selectedTrainID)

        session.showAllRoutes()
        session.selectTrain(id: n)
        session.reconcile(trainIDs: [q])
        XCTAssertNil(session.selectedTrainID)
    }

    func testResetActionAdvancesTokenAndClearsSelection() {
        let q = makeRunID(route: "Q")
        let session = LiveMapSession(allRoutes: ["Q"])
        session.selectTrain(id: q)
        let initialToken = session.resetToken

        session.requestReset()

        XCTAssertEqual(session.resetToken, initialToken + 1)
        XCTAssertNil(session.selectedTrainID)
    }

    private func makeRunID(route: String) -> TrainRunID {
        TrainRunID(
            feedID: "test",
            routeID: route,
            tripID: "trip-\(route)",
            serviceDate: "20260722",
            startTime: "12:00:00"
        )
    }
}
