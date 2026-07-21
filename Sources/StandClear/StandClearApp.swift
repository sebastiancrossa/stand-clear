import SwiftUI

@main
struct StandClearApp: App {
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        Task { @MainActor in model.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            StandClearMenuView()
                .environmentObject(model)
        } label: {
            Group {
                switch model.menuBarPresentation.content {
                case .icon:
                    Image(systemName: "tram.fill")
                case let .text(text):
                    Text(text)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel(model.menuBarPresentation.accessibilityLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
