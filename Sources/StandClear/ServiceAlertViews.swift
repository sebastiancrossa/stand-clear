import StandClearCore
import SwiftUI

/// The service alert region of the board: a one-line strip that opens into full alert
/// cards.
///
/// Collapsed by default so the eight-row arrival floor survives the common case, but not
/// collapsible when the board has nothing else to show — an empty board with a hidden
/// explanation is the exact failure this whole surface exists to fix.
struct ServiceAlertSection: View {
    @Environment(\.menuLayoutMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let alerts: [ServiceAlert]
    let now: Date
    let isCollapsible: Bool

    @State private var isExpanded = false
    @State private var isHovered = false

    private var showsCards: Bool { isExpanded || !isCollapsible }

    private var summary: String {
        alerts.count == 1 ? "1 service alert" : "\(alerts.count) service alerts"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.alertCardSpacing) {
            if isCollapsible {
                strip
            } else {
                stripLabel
                    .foregroundStyle(MenuTheme.caution)
                    .frame(height: metrics.alertBannerHeight)
            }

            if showsCards {
                VStack(alignment: .leading, spacing: metrics.alertCardSpacing) {
                    ForEach(alerts) { alert in
                        ServiceAlertCard(alert: alert, now: now)
                    }
                }
                .padding(.bottom, metrics.alertCardSpacing)
            }
        }
        .padding(.horizontal, metrics.sectionHorizontalPadding)
        .padding(.top, metrics.sectionTopPadding)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: showsCards)
    }

    private var strip: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: metrics.arrivalRowItemSpacing / 2) {
                stripLabel
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: metrics.alertBannerFontSize, weight: .semibold))
            }
            .foregroundStyle(isHovered ? MenuTheme.primaryText : MenuTheme.caution)
            .frame(height: metrics.alertBannerHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isExpanded ? "Hide service alerts" : "Show service alerts")
        .accessibilityLabel(summary)
        .accessibilityHint(isExpanded ? "Hides alert details." : "Shows alert details.")
    }

    private var stripLabel: some View {
        HStack(spacing: metrics.arrivalRowItemSpacing / 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: metrics.alertBannerFontSize, weight: .semibold))
            Text(summary.uppercased())
                .font(.system(
                    size: metrics.alertBannerFontSize,
                    weight: .bold,
                    design: .rounded
                ))
                .lineLimit(1)
        }
    }
}

/// One alert, laid out the way the MTA lays out its own: who is affected, what changed,
/// when it applies, why, and when we were told.
private struct ServiceAlertCard: View {
    @Environment(\.menuLayoutMetrics) private var metrics

    let alert: ServiceAlert
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.alertCardTextSpacing) {
            HStack(spacing: metrics.settingsRouteItemSpacing / 2) {
                ForEach(RouteID.sorted(alert.routeIDs), id: \.self) { routeID in
                    RouteBullet(
                        routeID: routeID,
                        size: metrics.alertCardBulletSize,
                        isSelected: true
                    )
                }

                Text(alert.alertType.uppercased())
                    .font(.system(
                        size: metrics.alertCardTypeFontSize,
                        weight: .bold,
                        design: .rounded
                    ))
                    .tracking(metrics.settingsGroupLabelTracking)
                    .foregroundStyle(MenuTheme.caution)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(routeAccessibilityLabel)

            AlertRichText(source: alert.headerText, weight: .semibold)

            if let period = alert.humanReadableActivePeriod {
                Text(period)
                    .font(.system(size: metrics.alertCardBodyFontSize, weight: .semibold))
                    .foregroundStyle(MenuTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(metrics.alertPeriodPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(
                            cornerRadius: metrics.alertPeriodCornerRadius,
                            style: .continuous
                        )
                        .strokeBorder(MenuTheme.controlTrackStroke, lineWidth: 1)
                    }
                    .accessibilityLabel("Active period: \(period)")
            }

            if let description = alert.descriptionText, !description.isEmpty {
                AlertRichText(source: description, isSecondary: true)
            }

            if let timeline = alert.timeline(at: now) {
                let accessibility = timeline.accessibilityText(relativeTo: now)
                Text(timeline.displayText(relativeTo: now))
                    .font(.system(size: metrics.alertCardMetaFontSize, weight: .medium))
                    .foregroundStyle(MenuTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(accessibility)
                    .accessibilityLabel(accessibility)
            }
        }
        .padding(metrics.alertCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: metrics.alertCardCornerRadius, style: .continuous)
                .fill(MenuTheme.controlTrack)
        }
    }

    private var routeAccessibilityLabel: String {
        let routes = RouteID.sorted(alert.routeIDs)
            .map { "\(RouteID.displayLabel($0)) train" }
            .joined(separator: ", ")
        return "\(routes). \(alert.alertType)"
    }
}

/// Alert prose with the MTA's `[D]` bracket tokens rendered as real route bullets.
///
/// SwiftUI cannot wrap a mixed run of views and text, but it *can* wrap a `Text` built
/// from concatenated runs — and a `Text` accepts an `Image`. So each route token becomes
/// a rasterised `RouteBullet`, which flows and wraps like a glyph.
private struct AlertRichText: View {
    @Environment(\.menuLayoutMetrics) private var metrics

    let source: String
    var weight: Font.Weight = .regular
    var isSecondary = false

    var body: some View {
        AlertRichText
            .text(
                for: source,
                bulletSize: metrics.alertCardBulletSize,
                fallbackWeight: weight
            )
            .font(.system(size: metrics.alertCardBodyFontSize, weight: weight))
            .foregroundStyle(isSecondary ? MenuTheme.secondaryText : MenuTheme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Self.accessibilityText(for: source))
    }

    @MainActor
    private static func text(
        for source: String,
        bulletSize: CGFloat,
        fallbackWeight: Font.Weight
    ) -> Text {
        AlertText.runs(source).reduce(Text(verbatim: "")) { partial, run in
            switch run {
            case let .text(value):
                return partial + Text(verbatim: value)
            case let .route(routeID):
                guard
                    let image = RouteBulletImageCache.shared.image(
                        routeID: routeID,
                        size: bulletSize
                    )
                else {
                    // Rendering can fail before the app has a screen to measure. A bold
                    // route-coloured letter still reads correctly in the sentence.
                    return partial + Text(RouteID.displayLabel(routeID))
                        .fontWeight(.heavy)
                        .foregroundColor(RouteStyle.style(for: routeID).background)
                }
                return partial + Text(Image(nsImage: image)).baselineOffset(-3)
            }
        }
    }

    /// VoiceOver reads the image runs as nothing, so the spoken string names the trains.
    private static func accessibilityText(for source: String) -> String {
        AlertText.runs(source)
            .map { run in
                switch run {
                case let .text(value): value
                case let .route(routeID): " \(RouteID.displayLabel(routeID)) train "
                }
            }
            .joined()
    }
}

/// Rasterised route bullets, kept for the life of the process.
///
/// There are only a couple of dozen routes and one bullet size on this surface, so the
/// cache fills once and never grows.
@MainActor
private final class RouteBulletImageCache {
    static let shared = RouteBulletImageCache()

    private struct Key: Hashable {
        let routeID: String
        let size: CGFloat
    }

    private var images: [Key: NSImage] = [:]

    func image(routeID: String, size: CGFloat) -> NSImage? {
        let key = Key(routeID: routeID, size: size)
        if let cached = images[key] { return cached }

        let renderer = ImageRenderer(
            content: RouteBullet(routeID: routeID, size: size, isSelected: true)
                .frame(width: size, height: size)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }

        images[key] = image
        return image
    }
}

/// The alert marker on a route bullet in the Settings LINES grid.
struct RouteAlertBadge: View {
    @Environment(\.menuLayoutMetrics) private var metrics

    var body: some View {
        Text("!")
            .font(.system(
                size: metrics.settingsRouteBadgeFontSize,
                weight: .black,
                design: .rounded
            ))
            .foregroundStyle(MenuTheme.selectedText)
            .frame(width: metrics.settingsRouteBadgeSize, height: metrics.settingsRouteBadgeSize)
            .background {
                Circle()
                    .fill(MenuTheme.caution)
                    .overlay {
                        // The board is black and so is the gap between grid bullets, so
                        // the badge needs its own edge to stay legible when it overlaps
                        // a dark route colour.
                        Circle().strokeBorder(MenuTheme.canvas, lineWidth: 1)
                    }
            }
            .accessibilityHidden(true)
    }
}
