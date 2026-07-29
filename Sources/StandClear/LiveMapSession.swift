import Combine
import StandClearCore

enum RouteSelectionMode: Equatable {
    case all
    case custom(Set<String>)
}

@MainActor
final class LiveMapSession: ObservableObject {
    @Published private(set) var allRoutes: Set<String>
    @Published private(set) var routeSelection: RouteSelectionMode = .all
    @Published private(set) var selectedTrainID: TrainRunID?
    @Published private(set) var resetToken = 0

    private var hasInitializedRoutes: Bool

    init(allRoutes: Set<String> = []) {
        let normalized = Set(allRoutes.map(RouteID.normalized))
        self.allRoutes = normalized
        hasInitializedRoutes = !normalized.isEmpty
    }

    var selectedRoutes: Set<String> {
        switch routeSelection {
        case .all: allRoutes
        case let .custom(routes): routes
        }
    }

    var isShowingAllRoutes: Bool {
        routeSelection == .all
    }

    func updateAllRoutes(_ routes: Set<String>) {
        let normalized = Set(routes.map(RouteID.normalized))
        if !hasInitializedRoutes {
            allRoutes = normalized
            hasInitializedRoutes = !normalized.isEmpty
            return
        }

        allRoutes = normalized
        if case let .custom(routes) = routeSelection {
            let reconciled = routes.intersection(normalized)
            routeSelection = reconciled.isEmpty || reconciled == normalized
                ? .all
                : .custom(reconciled)
        }
        clearSelectionIfFiltered()
    }

    func toggleRoute(_ routeID: String) {
        let routeID = RouteID.normalized(routeID)
        guard allRoutes.contains(routeID) else { return }
        switch routeSelection {
        case .all:
            routeSelection = .custom([routeID])
        case var .custom(routes):
            if routes.contains(routeID) {
                routes.remove(routeID)
            } else {
                routes.insert(routeID)
            }
            routeSelection = routes.isEmpty || routes == allRoutes ? .all : .custom(routes)
        }
        clearSelectionIfFiltered()
    }

    func showAllRoutes() {
        routeSelection = .all
        clearSelectionIfFiltered()
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
