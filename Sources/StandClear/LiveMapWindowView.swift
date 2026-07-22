import StandClearCore
import SwiftUI

struct LiveMapWindowView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var session = LiveMapSession()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .frame(minWidth: 720, minHeight: 520)
        .preferredColorScheme(.dark)
        .task {
            await model.loadMapGeometry()
            synchronizeSession()
        }
        .onReceive(model.$mapMotionPlans) { _ in
            reconcileSelection(at: model.now)
        }
        .onReceive(model.$now) { date in
            reconcileSelection(at: date)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isMapGeometryLoading || (model.mapGeometry == nil && model.mapGeometryError == nil) {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading subway map…")
                    .foregroundStyle(.secondary)
            }
        } else if let error = model.mapGeometryError {
            VStack(spacing: 16) {
                Image(systemName: "map.fill")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Couldn’t load the subway map")
                    .font(.title2.weight(.semibold))
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task {
                        await model.loadMapGeometry()
                        synchronizeSession()
                    }
                }
            }
            .padding(32)
        } else if let geometry = model.mapGeometry {
            VStack(spacing: 16) {
                Image(systemName: "map.fill")
                    .font(.system(size: 42, weight: .light))
                Text("Live subway map ready")
                    .font(.title2.weight(.semibold))
                Text("\(geometry.resource.paths.count) track shapes · \(model.mapMotionPlans.count) active train plans")
                    .foregroundStyle(.secondary)
                if let timestamp = model.mapLatestFeedTimestamp {
                    Text("MTA feed updated \(timestamp, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reset Map") { session.requestReset() }
                    .accessibilityHint("Returns the live map to the full subway system.")
            }
            .padding(32)
        }
    }

    private func synchronizeSession() {
        let routes = Set(model.mapGeometry?.resource.routes.map(\.id) ?? [])
        session.updateAllRoutes(routes)
        reconcileSelection(at: model.now)
    }

    private func reconcileSelection(at date: Date) {
        let trainRoutes = Dictionary(
            uniqueKeysWithValues: model.mapMotionPlans.compactMap { plan in
                plan.render(at: date).map { ($0.id, $0.routeID) }
            }
        )
        session.reconcile(trainRoutes: trainRoutes)
    }
}
