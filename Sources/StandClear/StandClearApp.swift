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
            Label(model.menuBarTitle, systemImage: "tram.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
