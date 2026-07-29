import Foundation

/// One window during which an alert applies.
///
/// Either bound can be missing. The MTA leaves `end` off an alert that is running now
/// with no announced finish — a stalled train, a signal problem — so an absent bound
/// means "open in that direction" rather than "zero-length".
public struct ServiceAlertPeriod: Hashable, Sendable {
    public let start: Date?
    public let end: Date?

    public init(start: Date?, end: Date?) {
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        if let start, date < start { return false }
        if let end, date > end { return false }
        return true
    }
}

/// A single MTA service alert, reduced to the fields the board actually shows.
///
/// The standard GTFS-Realtime `effect` and `cause` fields are never populated on the
/// subway alerts feed, so `alertType` — carried by the MTA's Mercury extension — is the
/// only categorisation available, and `severityRank` is built from it rather than from
/// the enum the spec would suggest.
public struct ServiceAlert: Identifiable, Hashable, Sendable {
    public let id: String
    public let alertType: String
    public let headerText: String
    public let descriptionText: String?
    public let humanReadableActivePeriod: String?
    public let routeIDs: Set<String>
    public let stationIDs: Set<String>
    public let activePeriods: [ServiceAlertPeriod]
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        alertType: String,
        headerText: String,
        descriptionText: String? = nil,
        humanReadableActivePeriod: String? = nil,
        routeIDs: Set<String>,
        stationIDs: Set<String> = [],
        activePeriods: [ServiceAlertPeriod] = [],
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.alertType = alertType
        self.headerText = headerText
        self.descriptionText = descriptionText
        self.humanReadableActivePeriod = humanReadableActivePeriod
        self.routeIDs = Set(routeIDs.map(RouteID.normalized))
        self.stationIDs = stationIDs
        self.activePeriods = activePeriods
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// An alert with no declared period is active for as long as it stays in the feed,
    /// per the GTFS-Realtime spec.
    public func isActive(at date: Date) -> Bool {
        guard !activePeriods.isEmpty else { return true }
        return activePeriods.contains { $0.contains(date) }
    }

    /// Station-facing notices that do not change whether the train runs. The Settings
    /// grid badge means "this line has trouble", so these stay out of it.
    public var isInformational: Bool {
        Self.informationalTypes.contains(alertType)
    }

    /// Whether this alert lands at one of `stationIDs`. An alert that names no station at
    /// all is system-wide for its routes and counts as present at every station.
    public func affectsAnyStation(in stationIDs: Set<String>) -> Bool {
        self.stationIDs.isEmpty || !self.stationIDs.isDisjoint(with: stationIDs)
    }

    /// Lower sorts first. Most of the feed is planned work, so the handful of alerts
    /// that mean "your train is not coming" have to outrank it.
    public var severityRank: Int {
        Self.severityRanks[alertType] ?? Self.defaultSeverityRank
    }

    static let defaultSeverityRank = 3

    private static let informationalTypes: Set<String> = [
        "Boarding Change", "Station Notice", "Elevator", "Escalator",
    ]

    private static let severityRanks: [String: Int] = [
        "Delays": 0,
        "Suspended": 1,
        "Planned - Suspended": 1,
        "Part Suspended": 2,
        "Planned - Part Suspended": 2,
    ]

    /// What the alert card should say about when this alert started and last changed.
    ///
    /// Returns `nil` when the feed never gave us a `created_at`, so the card gains no
    /// empty timestamp line. `updatedAt` is only carried when it is later than
    /// `createdAt` — an unrevised alert reads "Since 12:04 PM" rather than repeating
    /// the same clock time twice.
    public func timeline(at now: Date) -> ServiceAlertTimeline? {
        guard let createdAt else { return nil }

        let onset: ServiceAlertTimeline.Onset
        if activePeriods.isEmpty {
            onset = .ongoing
        } else if let current = activePeriods.first(where: { $0.contains(now) }) {
            onset = current.end == nil ? .ongoing : .reported
        } else {
            // Outside every declared window the board still surfaces the alert only if
            // periods are empty (handled above). Fall back to reported so a caller that
            // asks anyway does not claim the problem is still running.
            onset = .reported
        }

        let revised = updatedAt.flatMap { update in
            update > createdAt ? update : nil
        }

        return ServiceAlertTimeline(onset: onset, startedAt: createdAt, updatedAt: revised)
    }
}

/// The timestamps an alert card shows, already resolved into a wording choice.
public struct ServiceAlertTimeline: Hashable, Sendable {
    public enum Onset: Hashable, Sendable {
        /// The window covering now has no announced finish, so the alert is still running.
        case ongoing
        /// A scheduled window with an end. `created_at` is a publication date, not an onset.
        case reported
    }

    public let onset: Onset
    public let startedAt: Date
    public let updatedAt: Date?

    public init(onset: Onset, startedAt: Date, updatedAt: Date?) {
        self.onset = onset
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    /// Absolute form for the card body: "Since 12:04 PM · Updated 3:08 PM".
    public func displayText(
        relativeTo now: Date,
        calendar: Calendar = .current
    ) -> String {
        let prefix = onset == .ongoing ? "Since" : "Reported"
        var parts = ["\(prefix) \(ServiceAlertTimestamp.text(for: startedAt, relativeTo: now, calendar: calendar))"]
        if let updatedAt {
            parts.append(
                "Updated \(ServiceAlertTimestamp.text(for: updatedAt, relativeTo: now, calendar: calendar))"
            )
        }
        return parts.joined(separator: " · ")
    }

    /// Relative form for help text and VoiceOver: "Reported 3 hours ago. Last updated 4 minutes ago."
    public func accessibilityText(relativeTo now: Date) -> String {
        let prefix = onset == .ongoing ? "Started" : "Reported"
        var parts = ["\(prefix) \(ServiceAlertTimestamp.ageText(for: startedAt, relativeTo: now))"]
        if let updatedAt {
            parts.append(
                "Last updated \(ServiceAlertTimestamp.ageText(for: updatedAt, relativeTo: now))"
            )
        }
        return parts.joined(separator: ". ") + "."
    }
}

/// Formats alert timestamps for the board.
///
/// Absolute text uses `Date.FormatStyle` with the injected calendar's locale and time
/// zone so tests can pin both. Relative age does the interval math directly — the same
/// approach `Arrival.etaText` takes — so it stays testable against an injected `now`.
public enum ServiceAlertTimestamp {
    /// "3:08 PM" today, "Fri 11:40 PM" earlier this week, "Jul 17" beyond it.
    public static func text(
        for date: Date,
        relativeTo now: Date,
        calendar: Calendar = .current
    ) -> String {
        let locale = calendar.locale ?? Locale.current
        let timeZone = calendar.timeZone

        if calendar.isDate(date, inSameDayAs: now) {
            var format = Date.FormatStyle(date: .omitted, time: .shortened)
            format.locale = locale
            format.timeZone = timeZone
            return date.formatted(format)
        }

        let startOfNow = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let dayDistance = calendar.dateComponents(
            [.day],
            from: startOfDate,
            to: startOfNow
        ).day ?? Int.max

        if dayDistance >= 0, dayDistance < 7 {
            var format = Date.FormatStyle()
                .weekday(.abbreviated)
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute()
            format.locale = locale
            format.timeZone = timeZone
            return date.formatted(format)
        }

        var format = Date.FormatStyle()
            .month(.abbreviated)
            .day()
        format.locale = locale
        format.timeZone = timeZone
        return date.formatted(format)
    }

    /// "4 minutes ago", "3 hours ago", "9 days ago".
    public static func ageText(for date: Date, relativeTo now: Date) -> String {
        let seconds = max(0, Int(floor(now.timeIntervalSince(date))))
        if seconds < 60 {
            return seconds == 1 ? "1 second ago" : "\(seconds) seconds ago"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }

        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
}

public struct ServiceAlertSnapshot: Sendable {
    public let alerts: [ServiceAlert]
    public let fetchedAt: Date

    public init(alerts: [ServiceAlert], fetchedAt: Date) {
        self.alerts = alerts
        self.fetchedAt = fetchedAt
    }
}

/// Picks the alerts worth showing, the way `ArrivalBoard` picks arrivals.
public enum AlertBoard {
    /// Alerts that are running right now on one of the selected routes.
    ///
    /// Service-affecting alerts surface for the whole line. Informational notices
    /// (boarding changes, station notices) stay station-gated so a platform change
    /// three boroughs away does not clutter the strip. Alerts that land at one of
    /// `stationIDs` sort first; within that, severity and recency decide.
    ///
    /// A route and a stop usually arrive as two *separate* `informed_entity` elements
    /// rather than one combined entry, so matching is done against the alert's union of
    /// routes and union of stations — never entity by entity. An alert that names no
    /// station at all is system-wide for its routes and always counts as local.
    public static func alerts(
        from allAlerts: [ServiceAlert],
        atAny stationIDs: Set<String>,
        selectedRoutes: Set<String>,
        now: Date = Date()
    ) -> [ServiceAlert] {
        let routes = Set(selectedRoutes.map(RouteID.normalized))
        guard !routes.isEmpty else { return [] }

        return allAlerts
            .filter { alert in
                guard alert.isActive(at: now), !alert.routeIDs.isDisjoint(with: routes) else {
                    return false
                }
                return alert.affectsAnyStation(in: stationIDs) || !alert.isInformational
            }
            .sorted { lhs, rhs in
                let lhsHere = lhs.affectsAnyStation(in: stationIDs)
                let rhsHere = rhs.affectsAnyStation(in: stationIDs)
                if lhsHere != rhsHere { return lhsHere }
                if lhs.severityRank != rhs.severityRank {
                    return lhs.severityRank < rhs.severityRank
                }
                let lhsUpdated = lhs.updatedAt ?? .distantPast
                let rhsUpdated = rhs.updatedAt ?? .distantPast
                if lhsUpdated != rhsUpdated { return lhsUpdated > rhsUpdated }
                return lhs.id < rhs.id
            }
    }

    /// Routes with a service-affecting alert running anywhere on the line. Unlike
    /// `alerts(from:atAny:selectedRoutes:now:)` this is deliberately not station-scoped:
    /// the grid badge answers "is this line in trouble", not "at my platform".
    public static func alertedRouteIDs(
        from allAlerts: [ServiceAlert],
        now: Date = Date()
    ) -> Set<String> {
        allAlerts.reduce(into: Set<String>()) { routeIDs, alert in
            guard alert.isActive(at: now), !alert.isInformational else { return }
            routeIDs.formUnion(alert.routeIDs)
        }
    }
}

/// One piece of an alert's text: either plain words or a route the writer marked up.
public enum AlertTextRun: Hashable, Sendable {
    case text(String)
    case route(String)
}

/// Splits MTA alert prose into text and route runs.
///
/// The MTA writes route references as bracket tokens — "Uptown [D] trains are delayed"
/// — so the raw string is unreadable rendered literally. The tokens hold *display
/// labels* rather than route IDs, which is why `[SIR]` and `[S]` appear and why this
/// resolves through `RouteID.displayLabel` instead of matching IDs alone.
public enum AlertText {
    public static func runs(_ source: String) -> [AlertTextRun] {
        var runs: [AlertTextRun] = []
        var buffer = ""
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]
            if
                character == "[",
                let close = source[index...].firstIndex(of: "]"),
                let routeID = routeID(forToken: String(source[source.index(after: index)..<close]))
            {
                if !buffer.isEmpty {
                    runs.append(.text(buffer))
                    buffer = ""
                }
                runs.append(.route(routeID))
                index = source.index(after: close)
                continue
            }

            // An unresolved token stays in the prose rather than disappearing, so a new
            // MTA abbreviation degrades to "[XYZ]" instead of silently dropping a word.
            buffer.append(character)
            index = source.index(after: index)
        }

        if !buffer.isEmpty {
            runs.append(.text(buffer))
        }
        return runs
    }

    public static func routeID(forToken token: String) -> String? {
        let token = RouteID.normalized(token.trimmingCharacters(in: .whitespaces))
        guard !token.isEmpty else { return nil }
        if knownRouteIDs.contains(token) { return token }
        return routeIDsByDisplayLabel[token]
    }

    private static let knownRouteIDs = Set(RouteID.displayOrder)

    /// Inverse of `RouteID.displayLabel`, which is how "SR", "SF" and "S" get back to
    /// H, FS and GS. Express routes are skipped because `displayLabel` drops their X,
    /// making "6" ambiguous between 6 and 6X — and the feed writes express tokens as
    /// "[6X]" anyway, which the direct ID match above already catches.
    ///
    /// "SIR" is the Staten Island Railway's public name and is not a display label, so
    /// it is aliased explicitly.
    private static let routeIDsByDisplayLabel: [String: String] = {
        var map: [String: String] = [:]
        for routeID in RouteID.displayOrder where !RouteID.isExpress(routeID) {
            map[RouteID.displayLabel(routeID)] = routeID
        }
        map["SIR"] = "SI"
        return map
    }()
}
