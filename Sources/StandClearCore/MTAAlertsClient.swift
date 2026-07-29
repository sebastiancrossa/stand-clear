import Foundation

public enum MTAAlertFeedError: LocalizedError {
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The MTA returned an invalid service alert response."
        }
    }
}

/// Fetches the MTA subway service alert feed.
///
/// This reads the JSON rather than the protobuf variant on purpose. The standard
/// `effect` and `cause` fields are empty on every alert the MTA publishes, so the only
/// usable categorisation lives in the Mercury extension — and the bundled generated
/// protobuf carries the NYCT extension but not Mercury. The JSON exposes those fields
/// with no code generation, and gzip brings it down to roughly 58 KB on the wire.
public struct MTAAlertsClient {
    public static let feedURL = URL(
        string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fsubway-alerts.json"
    )!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchAlerts(
        catalog: StationCatalog,
        now: Date = Date()
    ) async throws -> ServiceAlertSnapshot {
        var request = URLRequest(url: Self.feedURL)
        request.timeoutInterval = 12
        request.setValue("StandClear/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MTAAlertFeedError.invalidResponse
        }

        return ServiceAlertSnapshot(
            alerts: try Self.decodeAlerts(from: data, catalog: catalog),
            fetchedAt: now
        )
    }

    static func decodeAlerts(from data: Data, catalog: StationCatalog) throws -> [ServiceAlert] {
        // Deliberately no `.convertFromSnakeCase`: it would mangle the dotted Mercury
        // keys, and the resulting alerts would silently lose every type and period.
        let feed = try JSONDecoder().decode(AlertFeed.self, from: data)

        return (feed.entity ?? []).compactMap { entity -> ServiceAlert? in
            guard
                let id = entity.id,
                let alert = entity.alert,
                let headerText = alert.headerText?.englishText
            else { return nil }

            let informedEntities = alert.informedEntity ?? []
            let routeIDs = Set(informedEntities.compactMap(\.routeID).map(RouteID.normalized))
            // An alert we cannot attribute to a route can never match a selection, so it
            // is dropped here rather than carried through the whole pipeline.
            guard !routeIDs.isEmpty else { return nil }

            return ServiceAlert(
                id: id,
                alertType: alert.mercury?.alertType ?? "Service Change",
                headerText: headerText,
                descriptionText: alert.descriptionText?.englishText,
                humanReadableActivePeriod: alert.mercury?.humanReadableActivePeriod?.englishText,
                routeIDs: routeIDs,
                stationIDs: Set(
                    informedEntities
                        .compactMap(\.stopID)
                        .compactMap(catalog.stationID(forStopID:))
                ),
                activePeriods: (alert.activePeriod ?? []).map { period in
                    ServiceAlertPeriod(
                        start: period.start.map(Date.init(secondsSince1970:)),
                        end: period.end.map(Date.init(secondsSince1970:))
                    )
                },
                createdAt: alert.mercury?.createdAt.map(Date.init(secondsSince1970:)),
                updatedAt: alert.mercury?.updatedAt.map(Date.init(secondsSince1970:))
            )
        }
    }
}

// MARK: - Feed payload

private struct AlertFeed: Decodable {
    let entity: [Entity]?
}

private struct Entity: Decodable {
    let id: String?
    let alert: Alert?
}

private struct Alert: Decodable {
    let activePeriod: [Period]?
    let informedEntity: [InformedEntity]?
    let headerText: TranslatedString?
    let descriptionText: TranslatedString?
    let mercury: MercuryAlert?

    enum CodingKeys: String, CodingKey {
        case activePeriod = "active_period"
        case informedEntity = "informed_entity"
        case headerText = "header_text"
        case descriptionText = "description_text"
        case mercury = "transit_realtime.mercury_alert"
    }
}

private struct Period: Decodable {
    let start: Int?
    let end: Int?
}

private struct InformedEntity: Decodable {
    let routeID: String?
    let stopID: String?

    enum CodingKeys: String, CodingKey {
        case routeID = "route_id"
        case stopID = "stop_id"
    }
}

private struct MercuryAlert: Decodable {
    let alertType: String?
    let createdAt: Int?
    let updatedAt: Int?
    let humanReadableActivePeriod: TranslatedString?

    enum CodingKeys: String, CodingKey {
        case alertType = "alert_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case humanReadableActivePeriod = "human_readable_active_period"
    }
}

private struct TranslatedString: Decodable {
    let translation: [Translation]?

    /// The feed ships each string twice, as `en` and as `en-html`. The board renders
    /// route bullets itself, so it wants the plain one.
    var englishText: String? {
        guard let translation, !translation.isEmpty else { return nil }
        if let exact = translation.first(where: { $0.language == "en" })?.text {
            return exact
        }
        if let plain = translation.first(where: { !($0.language ?? "").contains("html") })?.text {
            return plain
        }
        return translation.first?.text
    }
}

private struct Translation: Decodable {
    let text: String?
    let language: String?
}

private extension Date {
    init(secondsSince1970 seconds: Int) {
        self.init(timeIntervalSince1970: TimeInterval(seconds))
    }
}
