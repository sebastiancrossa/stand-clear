import CoreLocation
import Foundation

/// Walking speed presets. Exposed as named paces rather than raw m/s because riders
/// differ in speed but cannot accurately self-report metres per second.
public enum WalkingPace: String, CaseIterable, Hashable, Sendable {
    case slow
    case average
    case brisk

    /// Approximate NYC pedestrian speeds. Average sits near the local observed mean
    /// (~1.5 m/s), with slow and brisk a step either side.
    public var metersPerSecond: Double {
        switch self {
        case .slow: 1.2
        case .average: 1.5
        case .brisk: 1.8
        }
    }

    public var title: String {
        switch self {
        case .slow: "Slow"
        case .average: "Average"
        case .brisk: "Brisk"
        }
    }
}

/// Whether a rider can still catch an arrival given their walk time to the platform.
public enum Reachability: Equatable, Hashable, Sendable {
    /// ETA is comfortably beyond walk time plus slack.
    case comfortable
    /// ETA is between walk time and walk time plus slack — leave now.
    case leaveNow
    /// ETA is at or under walk time — too late to catch at a normal walk.
    case tooLate

    public var isCatchable: Bool {
        switch self {
        case .comfortable, .leaveNow: true
        case .tooLate: false
        }
    }
}

/// Pure walk-time math: straight-line distance → grid-corrected seconds + platform buffer.
public enum WalkTimeEstimator {
    /// Expected ratio of Manhattan-grid walking distance to straight-line distance,
    /// averaging `|cos θ| + |sin θ|` over all bearings: `4/π`.
    public static let gridCorrection = 4.0 / Double.pi

    public static let defaultPlatformBufferSeconds = 75
    public static let reachabilitySlackSeconds = 60

    public static func estimateSeconds(
        straightLineMeters: CLLocationDistance,
        pace: WalkingPace,
        platformBufferSeconds: Int = defaultPlatformBufferSeconds
    ) -> Int {
        let safeMeters = max(0, straightLineMeters)
        let safeBuffer = max(0, platformBufferSeconds)
        let walkingSeconds = (safeMeters * gridCorrection) / pace.metersPerSecond
        return Int(ceil(walkingSeconds)) + safeBuffer
    }

    /// Prefer a per-station override when present; otherwise estimate from distance.
    public static func resolveSeconds(
        straightLineMeters: CLLocationDistance,
        pace: WalkingPace,
        platformBufferSeconds: Int,
        stationOverrideSeconds: Int?
    ) -> Int {
        if let stationOverrideSeconds {
            return max(0, stationOverrideSeconds)
        }
        return estimateSeconds(
            straightLineMeters: straightLineMeters,
            pace: pace,
            platformBufferSeconds: platformBufferSeconds
        )
    }

    public static func classify(
        etaSeconds: Int,
        walkSeconds: Int,
        slackSeconds: Int = reachabilitySlackSeconds
    ) -> Reachability {
        let safeETA = max(0, etaSeconds)
        let safeWalk = max(0, walkSeconds)
        let safeSlack = max(0, slackSeconds)
        if safeETA <= safeWalk {
            return .tooLate
        }
        if safeETA <= safeWalk + safeSlack {
            return .leaveNow
        }
        return .comfortable
    }

    public static func classify(
        arrivalTime: Date,
        now: Date,
        walkSeconds: Int,
        slackSeconds: Int = reachabilitySlackSeconds
    ) -> Reachability {
        let etaSeconds = max(0, Int(floor(arrivalTime.timeIntervalSince(now))))
        return classify(
            etaSeconds: etaSeconds,
            walkSeconds: walkSeconds,
            slackSeconds: slackSeconds
        )
    }
}
