import Combine
import StandClearCore

@MainActor
final class LiveMapSession: ObservableObject {
    @Published private(set) var allRoutes: Set<String>
    @Published private(set) var selectedRoutes: Set<String>
    @Published private(set) var selectedTrainID: TrainRunID?
    @Published private(set) var resetToken = 0

    private var hasInitializedRoutes: Bool

    init(allRoutes: Set<String> = []) {
        let normalized = Set(allRoutes.map(RouteID.normalized))
        self.allRoutes = normalized
        selectedRoutes = normalized
        hasInitializedRoutes = !normalized.isEmpty
    }

    var needsRouteRecovery: Bool {
        !allRoutes.isEmpty && selectedRoutes.isEmpty
    }

    func updateAllRoutes(_ routes: Set<String>) {
        let normalized = Set(routes.map(RouteID.normalized))
        if !hasInitializedRoutes {
            allRoutes = normalized
            selectedRoutes = normalized
            hasInitializedRoutes = !normalized.isEmpty
            return
        }

        let addedRoutes = normalized.subtracting(allRoutes)
        allRoutes = normalized
        selectedRoutes.formIntersection(normalized)
        selectedRoutes.formUnion(addedRoutes)
        clearSelectionIfFiltered()
    }

    func toggleRoute(_ routeID: String) {
        let routeID = RouteID.normalized(routeID)
        guard allRoutes.contains(routeID) else { return }
        if selectedRoutes.contains(routeID) {
            selectedRoutes.remove(routeID)
        } else {
            selectedRoutes.insert(routeID)
        }
        clearSelectionIfFiltered()
    }

    func showAllRoutes() {
        selectedRoutes = allRoutes
    }

    func isRouteVisible(_ routeID: String) -> Bool {
        selectedRoutes.contains(RouteID.normalized(routeID))
    }

    func selectTrain(id: TrainRunID?) {
        selectedTrainID = id
        clearSelectionIfFiltered()
    }

    func reconcile(trainIDs: Set<TrainRunID>) {
        guard let selectedTrainID else { return }
        guard trainIDs.contains(selectedTrainID) else {
            clearSelection()
            return
        }
        clearSelectionIfFiltered()
    }

    func requestReset() {
        resetToken &+= 1
        clearSelection()
    }

    private func clearSelectionIfFiltered() {
        guard let selectedTrainID else { return }
        if !selectedRoutes.contains(selectedTrainID.routeID) {
            clearSelection()
        }
    }

    private func clearSelection() {
        selectedTrainID = nil
    }
}
