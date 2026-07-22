@testable import StandClear
import StandClearCore
import XCTest

@MainActor
final class LiveMapSessionTests: XCTestCase {
    func testFirstRouteClickFocusesThatRouteFromTheAllRoutesOverview() {
        let session = LiveMapSession(allRoutes: ["N", "Q", "R"])

        XCTAssertEqual(session.selectedRoutes, ["N", "Q", "R"])
        XCTAssertTrue(session.isShowingAllRoutes)

        session.toggleRoute("q")

        XCTAssertEqual(session.selectedRoutes, ["Q"])
        XCTAssertFalse(session.isShowingAllRoutes)
        XCTAssertTrue(session.isRouteVisible("Q"))
    }

    func testCustomRouteClicksAggregateAndRemovingTheLastRouteReturnsToAll() {
        let session = LiveMapSession(allRoutes: ["N", "Q", "R"])

        session.toggleRoute("Q")
        session.toggleRoute("N")
        XCTAssertEqual(session.selectedRoutes, ["N", "Q"])

        session.toggleRoute("Q")
        XCTAssertEqual(session.selectedRoutes, ["N"])

        session.toggleRoute("N")
        XCTAssertTrue(session.isShowingAllRoutes)
        XCTAssertEqual(session.selectedRoutes, ["N", "Q", "R"])
    }

    func testAddingEveryRouteNormalizesBackToAllMode() {
        let session = LiveMapSession(allRoutes: ["A", "Q"])

        session.toggleRoute("A")
        session.toggleRoute("Q")

        XCTAssertTrue(session.isShowingAllRoutes)
        XCTAssertEqual(session.selectedRoutes, ["A", "Q"])
    }

    func testShowAllRestoresOverviewFromCustomSelection() {
        let session = LiveMapSession(allRoutes: ["N", "Q"])
        session.toggleRoute("N")

        XCTAssertEqual(session.selectedRoutes, ["N"])

        session.showAllRoutes()

        XCTAssertEqual(session.selectedRoutes, ["N", "Q"])
        XCTAssertTrue(session.isShowingAllRoutes)
    }

    func testRouteCatalogUpdatesExpandAllModeButPreserveCustomFocus() {
        let overview = LiveMapSession(allRoutes: ["N", "Q"])
        overview.updateAllRoutes(["N", "Q", "R"])
        XCTAssertEqual(overview.selectedRoutes, ["N", "Q", "R"])

        let focused = LiveMapSession(allRoutes: ["N", "Q"])
        focused.toggleRoute("Q")
        focused.updateAllRoutes(["N", "Q", "R"])
        XCTAssertEqual(focused.selectedRoutes, ["Q"])
        XCTAssertFalse(focused.isShowingAllRoutes)
    }

    func testSelectionPersistsWhileAvailableAndClearsWhenFilteredOrExpired() {
        let q = makeRunID(route: "Q")
        let n = makeRunID(route: "N")
        let session = LiveMapSession(allRoutes: ["N", "Q"])

        session.selectTrain(id: q)
        session.reconcile(trainIDs: [q, n])
        XCTAssertEqual(session.selectedTrainID, q)

        session.toggleRoute("N")
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
