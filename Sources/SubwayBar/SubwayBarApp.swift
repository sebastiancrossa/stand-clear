import SwiftUI

@main
struct SubwayBarApp: App {
    @StateObject private var model = AppModel()

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

