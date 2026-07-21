import SwiftUI

@main
struct SubwayBarApp: App {
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        Task { @MainActor in model.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            SubwayMenuView()
                .environmentObject(model)
        } label: {
            Label(model.menuBarTitle, systemImage: "tram.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
