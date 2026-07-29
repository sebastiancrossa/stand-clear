import AppKit
import StandClearCore
import SwiftUI

/// The app Settings window: a sidebar of panes beside a scrolling column of grouped
/// setting rows.
///
/// The panes are the same four the popover footer has always opened — General, Menu Bar,
/// Walk Time, About — but they are navigated rather than tabbed. A segmented control
/// across the top has to shrink every title to fit one line, which is why it stops
/// working at four panes and why nothing shipping on macOS uses it for preferences any
/// more; a sidebar names each pane in full, carries a glyph, and has room for a fifth.
///
/// Each setting is a row rather than a bare control: glyph, name, one sentence of what
/// it does, and the control on the trailing edge. That shape is what lets a toggle say
/// what it toggles without a paragraph underneath it, and it keeps every row in a card
/// the same height whether its control is a switch, a button, or a pop-up.
struct AppSettingsWindowView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedPane: AppSettingsTab = .general
    @State private var launchAtLoginError: String?

    private static let twitterURL = URL(string: "https://x.com/sebcrossa")!
    private static let githubURL = URL(string: "https://github.com/sebastiancrossa/stand-clear")!
    private static let mtaFeedsURL = URL(string: "https://www.mta.info/developers")!

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 660, idealWidth: 780, minHeight: 460, idealHeight: 580)
        // This window is standard macOS chrome rather than the black board, so it has
        // no colours of its own to fix — pinning the appearance is what keeps it the
        // same window the popover opens on a Mac in either mode.
        .forcesDarkAppearance()
    }

    // MARK: Chrome

    /// Selection arrives from `List` as an optional because a click on the empty space
    /// below the last row clears it. A pane is always showing, so that clear is dropped
    /// rather than mirrored into state the detail column would have to handle.
    private var paneSelection: Binding<AppSettingsTab?> {
        Binding(
            get: { selectedPane },
            set: { newValue in newValue.map { selectedPane = $0 } }
        )
    }

    private var sidebar: some View {
        List(selection: paneSelection) {
            ForEach(AppSettingsTab.allCases) { pane in
                Label {
                    Text(pane.title)
                        .font(.system(size: SettingsMetrics.sidebarRowFontSize, weight: .medium))
                } icon: {
                    Image(systemName: pane.symbol)
                }
                .tag(pane)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(
            min: SettingsMetrics.sidebarMinWidth,
            ideal: SettingsMetrics.sidebarIdealWidth,
            max: SettingsMetrics.sidebarMaxWidth
        )
        .accessibilityLabel("Settings panes")
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                    switch selectedPane {
                    case .general:
                        generalPane
                    case .menuBar:
                        menuBarPane
                    case .walkTime:
                        walkTimePane
                    case .about:
                        aboutPane
                    }
                }
                .padding(.horizontal, SettingsMetrics.paneHorizontalPadding)
                .padding(.top, SettingsMetrics.paneTopPadding)
                .padding(.bottom, SettingsMetrics.paneBottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.headerSpacing) {
            Text(selectedPane.title)
                .font(.system(size: SettingsMetrics.headerTitleFontSize, weight: .semibold))

            Text(selectedPane.caption)
                .font(.system(size: SettingsMetrics.headerCaptionFontSize))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, SettingsMetrics.headerHorizontalPadding)
        .padding(.top, SettingsMetrics.headerTopPadding)
        .padding(.bottom, SettingsMetrics.headerBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: General

    @ViewBuilder
    private var generalPane: some View {
        SettingsCard {
            SettingsRow(
                symbol: "power",
                title: "Open at Login",
                subtitle: "Start Stand Clear in the menu bar when you log in to this Mac.",
                note: launchAtLoginError.map { SettingsRowNote(text: $0, tone: .warning) }
            ) {
                Toggle(
                    "Open at Login",
                    isOn: Binding(
                        get: { model.isLaunchAtLoginEnabled },
                        set: { enabled in
                            launchAtLoginError = model.setLaunchAtLoginEnabled(enabled)
                        }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }

            SettingsRow(
                symbol: "location",
                title: "Location Access",
                subtitle: "Coordinates stay on this Mac. Stand Clear only uses them to find nearby stations.",
                note: locationNote
            ) {
                Button("Open System Settings") {
                    model.openLocationSettings()
                }
            }
        }

        SettingsCard {
            SettingsRow(
                symbol: "figure.walk.motion",
                title: "Walk-Time Reachability",
                subtitle: "Dim trains you cannot catch and highlight the ones you need to leave for now."
            ) {
                Toggle(
                    "Walk-Time Reachability",
                    isOn: Binding(
                        get: { model.reachabilityEnabled },
                        set: model.setReachabilityEnabled
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }

        SettingsCard {
            SettingsRow(
                symbol: "arrow.down.circle",
                title: "Updates",
                subtitle: "Version \(appVersion)",
                note: updateNote
            ) {
                Button(updateActionTitle) {
                    model.checkForSoftwareUpdates()
                }
                .disabled(!model.softwareUpdater.canCheckForUpdates)
            }

            SettingsRow(
                symbol: "arrow.triangle.2.circlepath",
                title: "Automatic Updates",
                subtitle: "Check for new versions in the background. Installing stays your call."
            ) {
                Toggle(
                    "Automatic Updates",
                    isOn: Binding(
                        get: { model.isAutomaticUpdateChecksEnabled },
                        set: model.setAutomaticUpdateChecksEnabled
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
        .task {
            model.refreshSoftwareUpdateInformation()
        }
    }

    // MARK: Menu Bar

    /// Everything below the display mode describes the countdown, so none of it means
    /// anything while the menu bar is showing the icon alone.
    private var showsCountdown: Bool {
        model.menuBarDisplayMode != .iconOnly
    }

    private var countdownRequiredNote: SettingsRowNote? {
        showsCountdown ? nil : SettingsRowNote(text: "Needs a countdown in the menu bar.")
    }

    @ViewBuilder
    private var menuBarPane: some View {
        SettingsCard {
            SettingsRow(
                symbol: "menubar.rectangle",
                title: "Display",
                subtitle: "What the menu bar shows once you pin a direction."
            ) {
                Picker(
                    "Display",
                    selection: Binding(
                        get: { model.menuBarDisplayMode },
                        set: model.setMenuBarDisplayMode
                    )
                ) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRow(
                symbol: "paintpalette",
                title: "Route Color",
                subtitle: "Mark the countdown with a dot in the pinned line's color.",
                note: countdownRequiredNote,
                isEnabled: showsCountdown
            ) {
                Toggle(
                    "Route Color",
                    isOn: Binding(
                        get: { model.menuBarShowRouteColor },
                        set: model.setMenuBarShowRouteColor
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!showsCountdown)
            }

            SettingsRow(
                symbol: "eye.slash",
                title: "Hide When Idle",
                subtitle: "Fall back to the icon alone when there is no catchable train.",
                note: countdownRequiredNote,
                isEnabled: showsCountdown
            ) {
                Toggle(
                    "Hide When Idle",
                    isOn: Binding(
                        get: { model.menuBarHideWhenIdle },
                        set: model.setMenuBarHideWhenIdle
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!showsCountdown)
            }

            SettingsRow(
                symbol: "bolt.fill",
                title: "Leave-Now Highlight",
                subtitle: "Turn the countdown amber while the train is still catchable on foot.",
                note: model.reachabilityEnabled
                    ? nil
                    : SettingsRowNote(text: "Needs Walk-Time Reachability, in General."),
                isEnabled: model.reachabilityEnabled
            ) {
                Toggle(
                    "Leave-Now Highlight",
                    isOn: Binding(
                        get: { model.menuBarUrgencyEnabled },
                        set: model.setMenuBarUrgencyEnabled
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!model.reachabilityEnabled)
            }
        }
    }

    // MARK: Walk Time

    @ViewBuilder
    private var walkTimePane: some View {
        SettingsCard {
            SettingsRow(
                symbol: "figure.walk",
                title: "Walking Pace",
                subtitle: "Applied to street-grid distance to estimate time to the station."
            ) {
                Picker(
                    "Walking Pace",
                    selection: Binding(
                        get: { model.walkingPace },
                        set: model.setWalkingPace
                    )
                ) {
                    ForEach(WalkingPace.allCases, id: \.self) { pace in
                        Text(pace.title).tag(pace)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            SettingsRow(
                symbol: "timer",
                title: "Platform Buffer",
                subtitle: "Extra time for stairs, escalators, and reaching the platform."
            ) {
                Stepper(
                    value: Binding(
                        get: { model.platformBufferSeconds },
                        set: model.setPlatformBufferSeconds
                    ),
                    in: 0...600,
                    step: 15
                ) {
                    Text("\(model.platformBufferSeconds) sec")
                        .font(.system(size: SettingsMetrics.rowTitleFontSize))
                        .monospacedDigit()
                }
            }
        }

        SettingsCard(
            title: "Station Overrides",
            footnote: "An override replaces the estimate for that station outright — use it where the walk is longer than the map suggests."
        ) {
            if model.nearbyStations.isEmpty {
                SettingsRow(
                    symbol: "mappin.slash",
                    title: "No Stations Yet",
                    subtitle: "Nearby stations appear here once location is available."
                )
            } else {
                for nearby in model.nearbyStations {
                    SettingsCardRow(id: nearby.id) {
                        StationWalkOverrideRow(
                            stationName: nearby.station.name,
                            estimatedSeconds: WalkTimeEstimator.estimateSeconds(
                                straightLineMeters: nearby.distance,
                                pace: model.walkingPace,
                                platformBufferSeconds: model.platformBufferSeconds
                            ),
                            overrideSeconds: model.stationWalkOverrides[nearby.id],
                            onChange: { value in
                                model.setStationWalkOverride(stationID: nearby.id, seconds: value)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: About

    @ViewBuilder
    private var aboutPane: some View {
        SettingsCard {
            SettingsCardRow {
                identityRow
            }

            SettingsCardRow {
                creatorRow
            }

            SettingsLinkRow(
                symbol: "chevron.left.forwardslash.chevron.right",
                title: "GitHub",
                subtitle: "Source, releases, and issues.",
                destination: Self.githubURL
            )
        }

        SettingsCard(title: "Data") {
            SettingsLinkRow(
                symbol: "antenna.radiowaves.left.and.right",
                title: "MTA Realtime Feeds",
                subtitle: "Arrival times and service alerts come from the Metropolitan Transportation Authority's public GTFS-Realtime feeds. Stand Clear is not affiliated with the MTA.",
                destination: Self.mtaFeedsURL
            )

            SettingsRow(
                symbol: "lock.shield",
                title: "On-Device Location",
                subtitle: "Location is processed on this Mac to find nearby stations. Coordinates are never uploaded."
            )
        }
    }

    private var identityRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Stand Clear")
                    .font(.system(size: 17, weight: .semibold))

                Text("Version \(appVersion)")
                    .font(.system(size: SettingsMetrics.rowSubtitleFontSize))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Live subway arrivals for nearby NYC stations, from your menu bar.")
                    .font(.system(size: SettingsMetrics.rowSubtitleFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsMetrics.rowHorizontalPadding)
        .padding(.vertical, 16)
    }

    private var creatorRow: some View {
        SettingsRowLayout(
            symbol: "heart.fill",
            tint: RouteStyle.style(for: "1").background
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Made in NYC by ")
                Link("@sebcrossa", destination: Self.twitterURL)
            }
            .font(.system(size: SettingsMetrics.rowTitleFontSize, weight: .semibold))
            .tint(.accentColor)
        } trailing: {
            EmptyView()
        }
    }

    // MARK: Status

    private var locationNote: SettingsRowNote? {
        switch model.locationService.authorizationStatus {
        case .authorizedAlways:
            return SettingsRowNote(text: "Allowed")
        case .denied, .restricted:
            return SettingsRowNote(
                text: "Off — Stand Clear cannot find nearby stations until you allow access.",
                tone: .warning
            )
        case .notDetermined:
            return SettingsRowNote(text: "Not decided yet")
        @unknown default:
            return SettingsRowNote(text: "Unknown")
        }
    }

    private var updateNote: SettingsRowNote? {
        switch model.softwareUpdater.state {
        case .idle:
            return SettingsRowNote(text: "Not checked yet")
        case .checking:
            return SettingsRowNote(text: "Checking…")
        case .upToDate:
            if let lastCheckDate = model.softwareUpdater.lastCheckDate {
                let checked = Self.relativeCheckFormatter.localizedString(
                    for: lastCheckDate,
                    relativeTo: Date()
                )
                return SettingsRowNote(text: "Up to date — checked \(checked)")
            }
            return SettingsRowNote(text: "Up to date")
        case let .available(version):
            return SettingsRowNote(text: "Version \(version) is available", tone: .accent)
        case let .failed(message):
            return SettingsRowNote(text: "Couldn't check for updates. \(message)", tone: .warning)
        }
    }

    private var updateActionTitle: String {
        if case .available = model.softwareUpdater.state {
            return "Install Update"
        }
        return "Check Now"
    }

    private static let relativeCheckFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (short?, build?):
            return "\(short) (\(build))"
        case let (short?, nil):
            return short
        default:
            return "0.1.0"
        }
    }
}

/// One nearby station's walk time: the estimate, or a number the rider sets themselves.
///
/// The stepper sits in the text column rather than beside the switch. A row that ends in
/// a stepper *and* a switch gives the pointer two similar-looking targets a few points
/// apart, and the stepper only exists while the switch is on — so it belongs under the
/// station's name, where its appearing does not move the switch.
private struct StationWalkOverrideRow: View {
    let stationName: String
    let estimatedSeconds: Int
    let overrideSeconds: Int?
    let onChange: (Int?) -> Void

    @State private var usesOverride = false
    @State private var minutes = 5

    var body: some View {
        SettingsRowLayout(symbol: "mappin.and.ellipse") {
            VStack(alignment: .leading, spacing: SettingsMetrics.rowTextSpacing) {
                Text(stationName)
                    .font(.system(size: SettingsMetrics.rowTitleFontSize, weight: .semibold))
                    .lineLimit(1)

                if usesOverride {
                    Stepper(
                        value: Binding(
                            get: { minutes },
                            set: { newValue in
                                minutes = newValue
                                onChange(newValue * 60)
                            }
                        ),
                        in: 1...30
                    ) {
                        Text("\(minutes) min walk")
                            .font(.system(size: SettingsMetrics.rowSubtitleFontSize))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .controlSize(.small)
                } else {
                    Text("Estimated \(formattedDuration(estimatedSeconds))")
                        .font(.system(size: SettingsMetrics.rowSubtitleFontSize))
                        .foregroundStyle(.secondary)
                }
            }
        } trailing: {
            Toggle(
                "Override walk time for \(stationName)",
                isOn: Binding(
                    get: { usesOverride },
                    set: { enabled in
                        usesOverride = enabled
                        onChange(enabled ? minutes * 60 : nil)
                    }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .onAppear {
            if let overrideSeconds {
                usesOverride = true
                minutes = max(1, Int((Double(overrideSeconds) / 60.0).rounded()))
            }
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        return "\(minutes) min"
    }
}
