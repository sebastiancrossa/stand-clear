import Foundation

extension Bundle {
    static var standClearResources: Bundle {
        guard let resourcesURL = Bundle.main.resourceURL else { return .module }
        return Bundle(
            url: resourcesURL.appendingPathComponent("StandClear_StandClearCore.bundle", isDirectory: true)
        ) ?? .module
    }
}
