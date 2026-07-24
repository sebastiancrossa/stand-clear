import StandClearCore
import SwiftUI

struct StandClearSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.menuLayoutMetrics) private var metrics

    private var isOnboarding: Bool {
        model.isOnboarding
    }

    private var compactLayout: Binding<Bool> {
        Binding(
            get: { model.interfaceDensity == .compact },
            set: { model.setInterfaceDensity($0 ? .compact : .standard) }
        )
    }

    private var arrivalTimeMode: Binding<ArrivalTimeDisplayMode> {
        Binding(
            get: { model.arrivalTimeDisplayMode },
            set: model.setArrivalTimeDisplayMode
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.settingsSectionSpacing) {
                appearanceSection
                Divider().overlay(Color.white.opacity(0.12))
                serviceSection

                if isOnboarding {
                    onboardingAction
                }
            }
            .padding(metrics.settingsContentPadding)
        }
        .scrollIndicators(.visible)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: metrics.settingsItemSpacing) {
            sectionHeading("APPEARANCE")

            Toggle(isOn: compactLayout) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compact layout")
                        .font(.system(
                            size: metrics.settingsBodyFontSize,
                            weight: .semibold,
                            design: .rounded
                        ))
                    Text("Show more arrivals in a smaller menu.")
                        .font(.system(size: metrics.settingsBodyFontSize))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .accessibilityHint("Changes the menu size and spacing immediately.")

            VStack(alignment: .leading, spacing: metrics.settingsItemSpacing / 2) {
                Text("ARRIVAL TIMES")
                    .font(.system(
                        size: metrics.settingsBodyFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))

                Picker("Arrival time format", selection: arrivalTimeMode) {
                    Text("Whole minutes").tag(ArrivalTimeDisplayMode.wholeMinutes)
                    Text("Min & sec").tag(ArrivalTimeDisplayMode.minutesAndSeconds)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel("Arrival time format")
                .accessibilityHint("Changes every arrival time immediately.")
            }
        }
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: metrics.settingsItemSpacing) {
            sectionHeading("SERVICE")

            Text("Choose the directions and subway lines shown on your arrival board.")
                .font(.system(size: metrics.settingsBodyFontSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: metrics.settingsItemSpacing) {
                ForEach(TravelDirection.selectableCases, id: \.self) { direction in
                    let canToggle = model.canToggleDirection(direction)
                    SettingsDirectionButton(
                        direction: direction,
                        isSelected: model.selectedDirections.contains(direction),
                        canToggle: canToggle
                    ) {
                        model.toggleDirection(direction)
                    }
                }
            }

            if let startupError = model.startupError {
                Label {
                    Text(startupError)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: metrics.settingsBodyFontSize))
                .foregroundStyle(Color(hex: 0xFCCC0A))
                .accessibilityLabel("Stand Clear could not start. \(startupError)")
            } else if model.availableRoutes.isEmpty {
                HStack(spacing: metrics.settingsItemSpacing) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Loading subway lines…")
                        .font(.system(size: metrics.settingsBodyFontSize))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, metrics.settingsSectionSpacing)
            } else {
                VStack(alignment: .leading, spacing: metrics.settingsRouteRowSpacing) {
                    ForEach(
                        Array(RouteID.grouped(model.availableRoutes).enumerated()),
                        id: \.offset
                    ) { _, routes in
                        HStack(spacing: metrics.settingsRouteItemSpacing) {
                            ForEach(routes, id: \.self) { routeID in
                                let isSelected = model.selectedRoutes.contains(routeID)
                                let canToggle = model.canToggleRoute(routeID)
                                Button {
                                    model.toggleRoute(routeID)
                                } label: {
                                    RouteBullet(
                                        routeID: routeID,
                                        size: metrics.settingsRouteBulletSize,
                                        isSelected: isSelected
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(!canToggle)
                                .help(
                                    canToggle
                                        ? "\(isSelected ? "Hide" : "Show") the \(RouteID.displayLabel(routeID)) train."
                                        : "At least one subway line must remain selected."
                                )
                                .accessibilityLabel("\(RouteID.displayLabel(routeID)) train")
                                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                                .accessibilityHint(
                                    canToggle
                                        ? "Toggles this subway line."
                                        : "At least one subway line must remain selected."
                                )
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var onboardingAction: some View {
        Button {
            model.finishChoosingLines()
        } label: {
            HStack {
                Text("Show arrivals")
                Image(systemName: "arrow.right")
            }
            .font(.system(
                size: metrics.settingsCTAFontSize,
                weight: .bold,
                design: .rounded
            ))
            .frame(maxWidth: .infinity)
            .frame(height: metrics.settingsCTAHeight)
            .background(Color.white)
            .foregroundStyle(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!model.hasUsableSelection)
        .opacity(model.hasUsableSelection ? 1 : 0.35)
        .keyboardShortcut(.defaultAction)
        .accessibilityHint("Select at least one direction and one line to continue.")
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(
                size: metrics.settingsTitleFontSize,
                weight: .bold,
                design: .rounded
            ))
    }
}

private struct SettingsDirectionButton: View {
    @Environment(\.menuLayoutMetrics) private var metrics

    let direction: TravelDirection
    let isSelected: Bool
    let canToggle: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: metrics.settingsItemSpacing / 2) {
                Image(systemName: direction == .northbound ? "arrow.up" : "arrow.down")
                    .font(.system(
                        size: metrics.settingsDirectionArrowFontSize,
                        weight: .light
                    ))
                Text(direction.pickerTitle)
                    .font(.system(
                        size: metrics.settingsDirectionLabelFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.settingsDirectionButtonHeight)
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
            .background(Color.white.opacity(isSelected ? 0.1 : 0.025))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(isSelected ? 0.7 : 0.12))
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
        .help(
            canToggle
                ? "\(isSelected ? "Hide" : "Show") \(direction.pickerTitle.lowercased()) trains."
                : "At least one direction must remain selected."
        )
        .accessibilityLabel(direction.pickerTitle.capitalized)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(
            canToggle
                ? "Toggles this direction."
                : "At least one direction must remain selected."
        )
    }
}
