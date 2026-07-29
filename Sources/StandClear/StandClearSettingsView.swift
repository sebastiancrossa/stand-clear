import StandClearCore
import SwiftUI

struct StandClearSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics

    private var isOnboarding: Bool {
        model.isOnboarding
    }

    /// The control is driven by an optional so that onboarding, which starts with no
    /// direction chosen, can render a track with no segment selected.
    private var direction: Binding<TravelDirection?> {
        Binding(
            get: { model.selectedDirection },
            set: { newValue in newValue.map(model.selectDirection) }
        )
    }

    var body: some View {
        if isOnboarding {
            // Setup is the Service pane plus a way out of it. Every preference that
            // does not gate the first board — the ETA format, opening at login — lives
            // in app Settings, so a first-run rider answers the two questions the board
            // cannot be drawn without and nothing else.
            //
            // The call to action is pinned rather than placed after the groups: the
            // line grid is taller than the popover, and a "Show arrivals" button that
            // only appears once the rider scrolls past every subway line is a dead end
            // on the one screen that must not have one.
            VStack(spacing: 0) {
                pane {
                    directionGroup
                    linesGroup
                }

                MenuDivider()

                onboardingAction
                    .padding(metrics.settingsContentPadding)
            }
        } else {
            pane {
                directionGroup
                linesGroup
            }
        }
    }

    private func pane(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.settingsGroupSpacing) {
                content()
            }
            .padding(metrics.settingsContentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }

    private var directionGroup: some View {
        SettingsGroup(label: "DIRECTION") {
            SettingsSegmentedControl(
                label: "Direction",
                segments: TravelDirection.selectableCases.map { direction in
                    let vocabulary = model.currentVocabulary
                    return .init(
                        value: Optional(direction),
                        title: vocabulary.title(for: direction),
                        glyph: vocabulary.glyph(for: direction),
                        help: "Show \(vocabulary.accessibilityName(for: direction)) trains.",
                        accessibilityTitle: vocabulary.accessibilityName(for: direction).capitalized
                    )
                },
                selection: direction
            )
        }
    }

    @ViewBuilder
    private var linesGroup: some View {
        if let startupError = model.startupError {
            SettingsGroup(label: "LINES") {
                Label {
                    Text(startupError)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: metrics.settingsBodyFontSize))
                .foregroundStyle(MenuTheme.caution)
                .accessibilityLabel("Stand Clear could not start. \(startupError)")
            }
        } else if model.availableRoutes.isEmpty {
            SettingsGroup(label: "LINES") {
                HStack(spacing: metrics.settingsItemSpacing) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(MenuTheme.primaryText)
                    Text("Loading subway lines…")
                        .font(.system(size: metrics.settingsBodyFontSize))
                        .foregroundStyle(MenuTheme.secondaryText)
                }
                .frame(height: metrics.settingsRouteBulletSize)
            }
        } else {
            SettingsGroup(label: "LINES", footnote: linesFootnote) {
                WrappingHStack(
                    itemSpacing: metrics.settingsRouteGroupSpacing,
                    lineSpacing: metrics.settingsRouteRowSpacing
                ) {
                    ForEach(
                        Array(RouteID.grouped(model.availableRoutes).enumerated()),
                        id: \.offset
                    ) { _, routes in
                        HStack(spacing: metrics.settingsRouteItemSpacing) {
                            ForEach(routes, id: \.self) { routeID in
                                SettingsRouteToggle(
                                    routeID: routeID,
                                    isSelected: model.selectedRoutes.contains(routeID),
                                    canToggle: model.canToggleRoute(routeID),
                                    hasAlert: model.alertedRouteIDs.contains(routeID)
                                ) {
                                    model.toggleRoute(routeID)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var linesFootnote: String {
        let selected = model.selectedRoutes.intersection(model.availableRoutes).count
        guard selected > 0 else { return "Pick at least one line to continue." }
        return "\(selected) of \(model.availableRoutes.count) lines shown on the board."
    }

    private var onboardingAction: some View {
        SettingsPrimaryButton(
            title: "Show arrivals",
            symbol: "arrow.right",
            isEnabled: model.hasUsableSelection,
            action: model.finishChoosingLines
        )
        .keyboardShortcut(.defaultAction)
        .accessibilityHint("Select a direction and at least one line to continue.")
    }
}

/// One route bullet in the LINES grid.
///
/// `RouteBullet` already carries the selected and unselected treatment; this adds the
/// pointer-over step it cannot know about, so an unselected line lifts toward its full
/// colour before the user commits to the click.
private struct SettingsRouteToggle: View {
    @Environment(\.menuLayoutMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let routeID: String
    let isSelected: Bool
    let canToggle: Bool
    let hasAlert: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var help: String {
        let base = canToggle
            ? "\(isSelected ? "Hide" : "Show") the \(RouteID.displayLabel(routeID)) train."
            : "At least one subway line must remain selected."
        return hasAlert ? "\(base) Service alert on this line." : base
    }

    var body: some View {
        Button(action: action) {
            RouteBullet(
                routeID: routeID,
                size: metrics.settingsRouteBulletSize,
                isSelected: isSelected
            )
            .opacity(!isSelected && isHovered ? 0.72 : 1)
            .overlay(alignment: .topTrailing) {
                if hasAlert {
                    RouteAlertBadge()
                        .offset(x: metrics.settingsRouteBadgeSize / 3, y: -metrics.settingsRouteBadgeSize / 3)
                }
            }
            .scaleEffect(canToggle && isHovered ? 1.06 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .help(help)
        .accessibilityLabel("\(RouteID.displayLabel(routeID)) train")
        .accessibilityValue(
            [
                isSelected ? "Selected" : "Not selected",
                hasAlert ? "Service alert" : nil,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(
            canToggle
                ? "Toggles this subway line."
                : "At least one subway line must remain selected."
        )
    }
}
