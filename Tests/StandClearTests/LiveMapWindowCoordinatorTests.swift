@testable import StandClear
import XCTest

@MainActor
final class LiveMapWindowCoordinatorTests: XCTestCase {
    func testPresentingAnExistingMapActivatesTheAppAndRaisesItsWindow() {
        var events: [String] = []
        let window = MapWindowSpy(onRaise: { events.append("raise") })
        let coordinator = LiveMapWindowCoordinator(
            activateApplication: { events.append("activate") },
            scheduleOnMain: { _ in }
        )
        coordinator.register(window)

        coordinator.present {
            events.append("open")
        }

        XCTAssertEqual(events, ["open", "activate", "raise"])
    }
}

@MainActor
private final class MapWindowSpy: LiveMapWindowPresenting {
    var isMiniaturized = false
    private let onRaise: () -> Void

    init(onRaise: @escaping () -> Void) {
        self.onRaise = onRaise
    }

    func restoreFromMiniaturization() {}

    func bringToFront() {
        onRaise()
    }
}
