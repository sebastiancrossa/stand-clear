import Foundation
@testable import StandClearCore
import XCTest

final class ServiceAlertTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.responses = [:]
        super.tearDown()
    }

    // MARK: - Decoding

    func testDecodingReadsMercuryFieldsAndResolvesStationsFromStops() throws {
        let alerts = try MTAAlertsClient.decodeAlerts(
            from: Data(Self.feedJSON.utf8),
            catalog: fixtureCatalog()
        )

        let delay = try XCTUnwrap(alerts.first { $0.id == "alert:delay" })
        XCTAssertEqual(delay.alertType, "Delays")
        XCTAssertEqual(delay.headerText, "Uptown [D] trains are delayed at Bay Pkwy.")
        XCTAssertEqual(delay.routeIDs, ["D"])
        // "A1N" is a platform stop; the catalog folds it up to its parent station.
        XCTAssertEqual(delay.stationIDs, ["A1"])
        XCTAssertEqual(delay.createdAt, Date(timeIntervalSince1970: 1_785_068_688))
        XCTAssertEqual(delay.updatedAt, Date(timeIntervalSince1970: 1_785_079_124))
        XCTAssertNil(delay.humanReadableActivePeriod)
    }

    func testDecodingPrefersPlainEnglishOverTheHTMLTranslation() throws {
        let alerts = try MTAAlertsClient.decodeAlerts(
            from: Data(Self.feedJSON.utf8),
            catalog: fixtureCatalog()
        )

        let skipped = try XCTUnwrap(alerts.first { $0.id == "alert:skipped" })
        XCTAssertEqual(skipped.headerText, "In the Bronx, [D] skips 170 St in both directions")
        XCTAssertEqual(skipped.descriptionText, "Use nearby 167 St instead.")
        XCTAssertEqual(
            skipped.humanReadableActivePeriod,
            "Jul 26, Sunday, 12:30 PM to 4:30 PM"
        )
    }

    func testDecodingDropsAlertsThatNameNoRoute() throws {
        let alerts = try MTAAlertsClient.decodeAlerts(
            from: Data(Self.feedJSON.utf8),
            catalog: fixtureCatalog()
        )

        XCTAssertFalse(alerts.contains { $0.id == "alert:routeless" })
    }

    func testFetchAlertsRejectsANonSuccessResponse() async throws {
        MockURLProtocol.responses = [
            MTAAlertsClient.feedURL: MockURLProtocol.Response(status: 500, data: Data()),
        ]
        let client = MTAAlertsClient(session: MockURLProtocol.session())

        do {
            _ = try await client.fetchAlerts(catalog: fixtureCatalog(), now: Date())
            XCTFail("Expected an invalid response error")
        } catch MTAAlertFeedError.invalidResponse {
            // Expected.
        }
    }

    func testFetchAlertsReturnsDecodedAlerts() async throws {
        MockURLProtocol.responses = [
            MTAAlertsClient.feedURL: MockURLProtocol.Response(
                status: 200,
                data: Data(Self.feedJSON.utf8)
            ),
        ]
        let client = MTAAlertsClient(session: MockURLProtocol.session())
        let fetchedAt = Date(timeIntervalSince1970: 1_785_079_200)

        let snapshot = try await client.fetchAlerts(catalog: fixtureCatalog(), now: fetchedAt)

        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.alerts.count, 4)
    }

    // MARK: - Active periods

    func testAlertIsActiveOnlyInsideItsPeriod() {
        let alert = makeAlert(
            id: "a",
            routeIDs: ["D"],
            periods: [
                ServiceAlertPeriod(
                    start: Date(timeIntervalSince1970: 100),
                    end: Date(timeIntervalSince1970: 200)
                ),
            ]
        )

        XCTAssertFalse(alert.isActive(at: Date(timeIntervalSince1970: 99)))
        XCTAssertTrue(alert.isActive(at: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(alert.isActive(at: Date(timeIntervalSince1970: 200)))
        XCTAssertFalse(alert.isActive(at: Date(timeIntervalSince1970: 201)))
    }

    func testAlertWithNoEndStaysActiveIndefinitely() {
        let alert = makeAlert(
            id: "a",
            routeIDs: ["D"],
            periods: [ServiceAlertPeriod(start: Date(timeIntervalSince1970: 100), end: nil)]
        )

        XCTAssertFalse(alert.isActive(at: Date(timeIntervalSince1970: 99)))
        XCTAssertTrue(alert.isActive(at: Date(timeIntervalSince1970: 10_000_000)))
    }

    func testAlertWithNoDeclaredPeriodIsAlwaysActive() {
        let alert = makeAlert(id: "a", routeIDs: ["D"], periods: [])

        XCTAssertTrue(alert.isActive(at: Date(timeIntervalSince1970: 0)))
    }

    // MARK: - Board filtering

    func testBoardKeepsAnActiveAlertMatchingRouteAndStation() {
        let alert = makeAlert(id: "a", routeIDs: ["D"], stationIDs: ["A1"], periods: [.always])

        let matches = AlertBoard.alerts(
            from: [alert],
            atAny: ["A1"],
            selectedRoutes: ["D"],
            now: .now
        )

        XCTAssertEqual(matches.map(\.id), ["a"])
    }

    func testBoardKeepsARouteOnlyAlertAtAnyStation() {
        let alert = makeAlert(id: "a", routeIDs: ["D"], stationIDs: [], periods: [.always])

        let matches = AlertBoard.alerts(
            from: [alert],
            atAny: ["Z9"],
            selectedRoutes: ["D"],
            now: .now
        )

        XCTAssertEqual(matches.map(\.id), ["a"])
    }

    func testBoardKeepsAServiceAffectingAlertOnASelectedRouteAtADifferentStation() {
        let alert = makeAlert(id: "a", routeIDs: ["D"], stationIDs: ["B2"], periods: [.always])

        let matches = AlertBoard.alerts(
            from: [alert],
            atAny: ["A1"],
            selectedRoutes: ["D"],
            now: .now
        )

        XCTAssertEqual(matches.map(\.id), ["a"])
    }

    func testBoardSortsStationLocalAlertsAboveDistantOnesRegardlessOfSeverity() {
        let distantDelay = makeAlert(
            id: "delay",
            alertType: "Delays",
            routeIDs: ["D"],
            stationIDs: ["B2"],
            periods: [.always]
        )
        let localPlanned = makeAlert(
            id: "planned",
            alertType: "Planned - Stops Skipped",
            routeIDs: ["D"],
            stationIDs: ["A1"],
            periods: [.always]
        )

        let matches = AlertBoard.alerts(
            from: [distantDelay, localPlanned],
            atAny: ["A1"],
            selectedRoutes: ["D"],
            now: .now
        )

        XCTAssertEqual(matches.map(\.id), ["planned", "delay"])
    }

    func testBoardDropsADistantInformationalAlert() {
        let alert = makeAlert(
            id: "boarding",
            alertType: "Boarding Change",
            routeIDs: ["D"],
            stationIDs: ["B2"],
            periods: [.always]
        )

        let matches = AlertBoard.alerts(
            from: [alert],
            atAny: ["A1"],
            selectedRoutes: ["D"],
            now: .now
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testBoardKeepsALocalInformationalAlert() {
        let alert = makeAlert(
            id: "boarding",
            alertType: "Boarding Change",
            routeIDs: ["D"],
            stationIDs: ["A1"],
            periods: [.always]
        )

        let matches = AlertBoard.alerts(
            from: [alert],
            atAny: ["A1"],
            selectedRoutes: ["D"],
            now: .now
        )

        XCTAssertEqual(matches.map(\.id), ["boarding"])
    }

    func testBoardDropsAnAlertOnAnUnselectedRoute() {
        let alert = makeAlert(id: "a", routeIDs: ["D"], stationIDs: ["A1"], periods: [.always])

        let matches = AlertBoard.alerts(
            from: [alert],
            atAny: ["A1"],
            selectedRoutes: ["Q"],
            now: .now
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testBoardDropsAnAlertThatIsNotRunningYet() {
        let alert = makeAlert(
            id: "a",
            routeIDs: ["D"],
            stationIDs: ["A1"],
            periods: [
                ServiceAlertPeriod(
                    start: Date(timeIntervalSince1970: 5_000),
                    end: Date(timeIntervalSince1970: 6_000)
                ),
            ]
        )

        let matches = AlertBoard.alerts(
            from: [alert],
            atAny: ["A1"],
            selectedRoutes: ["D"],
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertTrue(matches.isEmpty)
    }

    // MARK: - Line-wide badge routes

    func testAlertedRouteIDsIncludeAlertsAtDistantStations() {
        let alert = makeAlert(
            id: "a",
            routeIDs: ["D"],
            stationIDs: ["B2"],
            periods: [.always]
        )

        let routes = AlertBoard.alertedRouteIDs(from: [alert], now: .now)

        XCTAssertEqual(routes, ["D"])
    }

    func testAlertedRouteIDsExcludeOutOfPeriodAlerts() {
        let alert = makeAlert(
            id: "a",
            routeIDs: ["D"],
            stationIDs: ["A1"],
            periods: [
                ServiceAlertPeriod(
                    start: Date(timeIntervalSince1970: 5_000),
                    end: Date(timeIntervalSince1970: 6_000)
                ),
            ]
        )

        let routes = AlertBoard.alertedRouteIDs(
            from: [alert],
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertTrue(routes.isEmpty)
    }

    func testAlertedRouteIDsExcludeInformationalAlertTypes() {
        let boarding = makeAlert(
            id: "boarding",
            alertType: "Boarding Change",
            routeIDs: ["SI"],
            stationIDs: ["S11"],
            periods: [.always]
        )
        let notice = makeAlert(
            id: "notice",
            alertType: "Station Notice",
            routeIDs: ["E", "F"],
            stationIDs: ["F12"],
            periods: [.always]
        )
        let delay = makeAlert(
            id: "delay",
            alertType: "Delays",
            routeIDs: ["Q"],
            stationIDs: ["R16"],
            periods: [.always]
        )

        let routes = AlertBoard.alertedRouteIDs(
            from: [boarding, notice, delay],
            now: .now
        )

        XCTAssertEqual(routes, ["Q"])
    }

    /// The feed lists a route and a stop as two separate informed entities, so matching
    /// has to run against the alert's union of each rather than entity by entity.
    func testBoardMatchesWhenRouteAndStopArriveAsSeparateEntities() throws {
        let alerts = try MTAAlertsClient.decodeAlerts(
            from: Data(Self.feedJSON.utf8),
            catalog: fixtureCatalog()
        )

        let matches = AlertBoard.alerts(
            from: alerts,
            atAny: ["A1"],
            selectedRoutes: ["D"],
            now: Date(timeIntervalSince1970: 1_785_079_200)
        )

        XCTAssertEqual(matches.map(\.id), ["alert:delay"])
    }

    func testBoardMatchesAnyStationInATransferComplex() throws {
        let catalog = fixtureCatalog()
        let alerts = try MTAAlertsClient.decodeAlerts(
            from: Data(Self.feedJSON.utf8),
            catalog: catalog
        )

        // A1 and B2 are joined by the fixture's transfer row, so an alert filed against
        // one of them belongs on the board while standing at the other.
        let matches = AlertBoard.alerts(
            from: alerts,
            atAny: catalog.relatedStations(to: "A1"),
            selectedRoutes: ["Q"],
            now: Date(timeIntervalSince1970: 1_785_079_200)
        )

        XCTAssertEqual(matches.map(\.id), ["alert:transfer"])
    }

    func testBoardReturnsNothingWithoutASelection() {
        let alert = makeAlert(id: "a", routeIDs: ["D"], stationIDs: ["A1"], periods: [.always])

        XCTAssertTrue(
            AlertBoard.alerts(from: [alert], atAny: ["A1"], selectedRoutes: [], now: .now).isEmpty
        )
    }

    func testBoardSortsDisruptionsAboveRoutinePlannedWork() {
        let planned = makeAlert(
            id: "planned",
            alertType: "Planned - Stops Skipped",
            routeIDs: ["D"],
            periods: [.always],
            updatedAt: Date(timeIntervalSince1970: 9_000)
        )
        let delay = makeAlert(
            id: "delay",
            alertType: "Delays",
            routeIDs: ["D"],
            periods: [.always],
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        let matches = AlertBoard.alerts(
            from: [planned, delay],
            atAny: ["A1"],
            selectedRoutes: ["D"],
            now: .now
        )

        XCTAssertEqual(matches.map(\.id), ["delay", "planned"])
    }

    func testBoardBreaksSeverityTiesWithTheMostRecentUpdate() {
        let older = makeAlert(
            id: "older",
            routeIDs: ["D"],
            periods: [.always],
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = makeAlert(
            id: "newer",
            routeIDs: ["D"],
            periods: [.always],
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let matches = AlertBoard.alerts(
            from: [older, newer],
            atAny: ["A1"],
            selectedRoutes: ["D"],
            now: .now
        )

        XCTAssertEqual(matches.map(\.id), ["newer", "older"])
    }

    // MARK: - Bracket tokens

    func testRunsSplitRouteTokensOutOfProse() {
        let runs = AlertText.runs("Uptown [D] trains are delayed.")

        XCTAssertEqual(runs, [.text("Uptown "), .route("D"), .text(" trains are delayed.")])
    }

    func testRunsResolveExpressTokensDirectly() {
        XCTAssertEqual(AlertText.runs("[6X] express"), [.route("6X"), .text(" express")])
    }

    /// The feed writes display labels rather than route IDs, so "SIR" and "S" have to
    /// come back as SI and GS.
    func testRunsResolveDisplayLabelsAndAliases() {
        XCTAssertEqual(AlertText.routeID(forToken: "SIR"), "SI")
        XCTAssertEqual(AlertText.routeID(forToken: "S"), "GS")
        XCTAssertEqual(AlertText.routeID(forToken: "SR"), "H")
        XCTAssertEqual(AlertText.routeID(forToken: "SF"), "FS")
        XCTAssertEqual(AlertText.routeID(forToken: "d"), "D")
    }

    func testUnknownTokensStayInTheProse() {
        XCTAssertNil(AlertText.routeID(forToken: "QQQ"))
        XCTAssertEqual(AlertText.runs("No [QQQ] service"), [.text("No [QQQ] service")])
    }

    func testUnclosedBracketIsLeftAlone() {
        XCTAssertEqual(AlertText.runs("Watch the [D gap"), [.text("Watch the [D gap")])
    }

    func testTextWithoutTokensIsASingleRun() {
        XCTAssertEqual(AlertText.runs("Service is normal."), [.text("Service is normal.")])
    }

    func testAdjacentTokensBothResolve() {
        XCTAssertEqual(AlertText.runs("[E][F]"), [.route("E"), .route("F")])
    }

    // MARK: - Timeline

    func testOpenEndedAlertTimelineIsOngoingAndKeepsALaterUpdate() throws {
        let alerts = try MTAAlertsClient.decodeAlerts(
            from: Data(Self.feedJSON.utf8),
            catalog: fixtureCatalog()
        )
        let delay = try XCTUnwrap(alerts.first { $0.id == "alert:delay" })
        let now = Date(timeIntervalSince1970: 1_785_079_200)

        let timeline = try XCTUnwrap(delay.timeline(at: now))

        XCTAssertEqual(timeline.onset, .ongoing)
        XCTAssertEqual(timeline.startedAt, Date(timeIntervalSince1970: 1_785_068_688))
        XCTAssertEqual(timeline.updatedAt, Date(timeIntervalSince1970: 1_785_079_124))
    }

    func testScheduledWindowTimelineIsReported() throws {
        let alerts = try MTAAlertsClient.decodeAlerts(
            from: Data(Self.feedJSON.utf8),
            catalog: fixtureCatalog()
        )
        let skipped = try XCTUnwrap(alerts.first { $0.id == "alert:skipped" })
        // Inside the Jul 26 12:30–4:30 PM window.
        let now = Date(timeIntervalSince1970: 1_785_085_000)

        let timeline = try XCTUnwrap(skipped.timeline(at: now))

        XCTAssertEqual(timeline.onset, .reported)
        XCTAssertEqual(timeline.startedAt, Date(timeIntervalSince1970: 1_785_000_000))
        XCTAssertEqual(timeline.updatedAt, Date(timeIntervalSince1970: 1_785_079_000))
    }

    func testTimelineDropsAnUnchangedUpdate() {
        let created = Date(timeIntervalSince1970: 1_000)
        let alert = ServiceAlert(
            id: "a",
            alertType: "Delays",
            headerText: "Header",
            routeIDs: ["D"],
            activePeriods: [ServiceAlertPeriod(start: created, end: nil)],
            createdAt: created,
            updatedAt: created
        )

        let timeline = alert.timeline(at: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(timeline?.onset, .ongoing)
        XCTAssertEqual(timeline?.startedAt, created)
        XCTAssertNil(timeline?.updatedAt)
    }

    func testTimelineIsNilWhenCreatedAtIsMissing() throws {
        let alerts = try MTAAlertsClient.decodeAlerts(
            from: Data(Self.feedJSON.utf8),
            catalog: fixtureCatalog()
        )
        let transfer = try XCTUnwrap(alerts.first { $0.id == "alert:transfer" })

        XCTAssertNil(transfer.createdAt)
        XCTAssertNil(transfer.timeline(at: Date(timeIntervalSince1970: 1_785_079_200)))
    }

    // MARK: - Timestamp formatting

    func testTimestampTextUsesTodayEarlierThisWeekAndBeyondBuckets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")

        // Sunday Jul 26, 2026 15:08 UTC
        let now = Date(timeIntervalSince1970: 1_785_078_480)
        let today = Date(timeIntervalSince1970: 1_785_067_440) // 12:04 PM same day
        let earlierThisWeek = Date(timeIntervalSince1970: 1_784_936_400) // Fri 11:40 PM
        let beyond = Date(timeIntervalSince1970: 1_784_289_600) // Jul 17

        XCTAssertEqual(
            ServiceAlertTimestamp.text(for: today, relativeTo: now, calendar: calendar),
            "12:04 PM"
        )
        XCTAssertEqual(
            ServiceAlertTimestamp.text(for: earlierThisWeek, relativeTo: now, calendar: calendar),
            "Fri 11:40 PM"
        )
        XCTAssertEqual(
            ServiceAlertTimestamp.text(for: beyond, relativeTo: now, calendar: calendar),
            "Jul 17"
        )
    }

    func testAgeTextUsesSecondsMinutesHoursAndDays() {
        let now = Date(timeIntervalSince1970: 100_000)

        XCTAssertEqual(
            ServiceAlertTimestamp.ageText(
                for: Date(timeIntervalSince1970: 99_995),
                relativeTo: now
            ),
            "5 seconds ago"
        )
        XCTAssertEqual(
            ServiceAlertTimestamp.ageText(
                for: Date(timeIntervalSince1970: 99_940),
                relativeTo: now
            ),
            "1 minute ago"
        )
        XCTAssertEqual(
            ServiceAlertTimestamp.ageText(
                for: Date(timeIntervalSince1970: 89_200),
                relativeTo: now
            ),
            "3 hours ago"
        )
        XCTAssertEqual(
            ServiceAlertTimestamp.ageText(
                for: Date(timeIntervalSince1970: 100_000 - 9 * 24 * 3_600),
                relativeTo: now
            ),
            "9 days ago"
        )
    }

    // MARK: - Fixtures

    private func fixtureCatalog() -> StationCatalog {
        // swiftlint:disable:next force_try
        try! StationCatalog(
            csv: """
            stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station
            A1,Bay Pkwy,40.0000,-73.0000,1,
            A1N,Bay Pkwy,40.0000,-73.0000,,A1
            B2,Ninth Av,41.0000,-74.0000,1,
            C3,Union St,42.0000,-75.0000,1,
            """,
            transfersCSV: """
            from_stop_id,to_stop_id,transfer_type,min_transfer_time
            A1,B2,2,180
            """
        )
    }

    private func makeAlert(
        id: String,
        alertType: String = "Planned - Stops Skipped",
        routeIDs: Set<String>,
        stationIDs: Set<String> = ["A1"],
        periods: [ServiceAlertPeriod],
        updatedAt: Date? = nil
    ) -> ServiceAlert {
        ServiceAlert(
            id: id,
            alertType: alertType,
            headerText: "Header",
            routeIDs: routeIDs,
            stationIDs: stationIDs,
            activePeriods: periods,
            updatedAt: updatedAt
        )
    }

    /// Shaped after the real `camsys/subway-alerts.json` payload, including the dotted
    /// Mercury extension keys and the paired en / en-html translations.
    private static let feedJSON = """
    {
      "header": { "gtfs_realtime_version": "2.0", "timestamp": 1785079135 },
      "entity": [
        {
          "id": "alert:delay",
          "alert": {
            "active_period": [{ "start": 1785079124 }],
            "informed_entity": [
              { "agency_id": "MTASBWY", "route_id": "D" },
              { "agency_id": "MTASBWY", "stop_id": "A1N" }
            ],
            "header_text": {
              "translation": [
                { "text": "Uptown [D] trains are delayed at Bay Pkwy.", "language": "en" },
                { "text": "<p>Uptown [D] trains are delayed.</p>", "language": "en-html" }
              ]
            },
            "transit_realtime.mercury_alert": {
              "created_at": 1785068688,
              "updated_at": 1785079124,
              "alert_type": "Delays"
            }
          }
        },
        {
          "id": "alert:skipped",
          "alert": {
            "active_period": [{ "start": 1785083400, "end": 1785097800 }],
            "informed_entity": [
              { "agency_id": "MTASBWY", "route_id": "D", "stop_id": "C3" }
            ],
            "header_text": {
              "translation": [
                { "text": "In the Bronx, [D] skips 170 St in both directions", "language": "en" },
                { "text": "<p>In the Bronx, [D] skips 170 St</p>", "language": "en-html" }
              ]
            },
            "description_text": {
              "translation": [
                { "text": "Use nearby 167 St instead.", "language": "en" },
                { "text": "<p>Use nearby 167 St instead.</p>", "language": "en-html" }
              ]
            },
            "transit_realtime.mercury_alert": {
              "created_at": 1785000000,
              "updated_at": 1785079000,
              "alert_type": "Planned - Stops Skipped",
              "human_readable_active_period": {
                "translation": [
                  { "text": "Jul 26, Sunday, 12:30 PM to 4:30 PM", "language": "en" }
                ]
              }
            }
          }
        },
        {
          "id": "alert:transfer",
          "alert": {
            "active_period": [{ "start": 1785079000 }],
            "informed_entity": [
              { "agency_id": "MTASBWY", "route_id": "Q", "stop_id": "B2" }
            ],
            "header_text": {
              "translation": [
                { "text": "[Q] trains board from the uptown platform", "language": "en" }
              ]
            },
            "transit_realtime.mercury_alert": { "alert_type": "Boarding Change" }
          }
        },
        {
          "id": "alert:routeless",
          "alert": {
            "active_period": [{ "start": 1785079000 }],
            "informed_entity": [{ "agency_id": "MTASBWY", "stop_id": "C3" }],
            "header_text": {
              "translation": [{ "text": "Elevator out of service", "language": "en" }]
            },
            "transit_realtime.mercury_alert": { "alert_type": "Elevator" }
          }
        },
        {
          "id": "alert:always",
          "alert": {
            "informed_entity": [{ "agency_id": "MTASBWY", "route_id": "L", "stop_id": "C3" }],
            "header_text": {
              "translation": [{ "text": "[L] runs on a Sunday schedule", "language": "en" }]
            },
            "transit_realtime.mercury_alert": { "alert_type": "Special Schedule" }
          }
        }
      ]
    }
    """
}

private extension ServiceAlertPeriod {
    static let always = ServiceAlertPeriod(start: nil, end: nil)
}
