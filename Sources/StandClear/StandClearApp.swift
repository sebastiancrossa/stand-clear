import SwiftUI

@main
struct StandClearApp: App {
    @StateObject private var model: AppModel
    private let mapWindowCoordinator: LiveMapWindowCoordinator
    private let settingsWindowCoordinator: LiveMapWindowCoordinator

    init() {
        CrashReportingService.start()
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        mapWindowCoordinator = LiveMapWindowCoordinator()
        settingsWindowCoordinator = LiveMapWindowCoordinator()
        Task { @MainActor in model.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            StandClearMenuView(
                settingsWindowCoordinator: settingsWindowCoordinator
            )
            .environmentObject(model)
        } label: {
            MenuBarLabelView(presentation: model.menuBarPresentation, showRouteColor: model.menuBarShowRouteColor)
        }
        .menuBarExtraStyle(.window)

        Window("Live Map", id: "live-map") {
            LiveMapWindowView()
                .environmentObject(model)
                .background {
                    LiveMapWindowReader { window in
                        mapWindowCoordinator.register(window)
                    }
                }
        }
        .defaultSize(width: 1_100, height: 760)
        .windowResizability(.contentMinSize)

        Window("Settings", id: "app-settings") {
            AppSettingsWindowView()
                .environmentObject(model)
                .background {
                    LiveMapWindowReader { window in
                        settingsWindowCoordinator.register(window)
                    }
                }
        }
        // The sidebar and the setting rows both want room, and `contentSize` would pin
        // the window to whichever pane is showing — so the minimum comes from the view
        // and the rider keeps the resize handle.
        .defaultSize(width: 780, height: 580)
        .windowResizability(.contentMinSize)
    }
}

private struct MenuBarLabelView: View {
    let presentation: MenuBarPresentation
    let showRouteColor: Bool

    var body: some View {
        Group {
            switch presentation.content {
            case .icon:
                Image(systemName: "tram.fill")
                    .symbolRenderingMode(presentation.isUrgent ? .palette : .monochrome)
                    .foregroundStyle(presentation.isUrgent ? MenuTheme.leaveNow : Color.primary)
            case let .text(text):
                countdownLabel(text)
            case let .iconAndText(text):
                HStack(spacing: 4) {
                    Image(systemName: "tram.fill")
                    countdownLabel(text)
                }
            }
        }
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private func countdownLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            if showRouteColor, let routeID = presentation.routeID {
                Circle()
                    .fill(RouteStyle.style(for: routeID).background)
                    .frame(width: 8, height: 8)
            }
            Text(text)
                .monospacedDigit()
                .foregroundStyle(presentation.isUrgent ? MenuTheme.leaveNow : Color.primary)
                .frame(width: 88, alignment: .leading)
        }
    }
}
