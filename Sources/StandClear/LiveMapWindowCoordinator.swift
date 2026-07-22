import AppKit
import SwiftUI

@MainActor
protocol LiveMapWindowPresenting: AnyObject {
    var isMiniaturized: Bool { get }
    func restoreFromMiniaturization()
    func bringToFront()
}

extension NSWindow: LiveMapWindowPresenting {
    func restoreFromMiniaturization() {
        deminiaturize(nil)
    }

    func bringToFront() {
        makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class LiveMapWindowCoordinator {
    typealias MainScheduler = (@escaping @MainActor () -> Void) -> Void

    private weak var window: (any LiveMapWindowPresenting)?
    private let activateApplication: @MainActor () -> Void
    private let scheduleOnMain: MainScheduler

    init(
        activateApplication: @escaping @MainActor () -> Void = {
            NSApp.activate()
        },
        scheduleOnMain: @escaping MainScheduler = { action in
            Task { @MainActor in
                await Task.yield()
                action()
            }
        }
    ) {
        self.activateApplication = activateApplication
        self.scheduleOnMain = scheduleOnMain
    }

    func register(_ window: (any LiveMapWindowPresenting)?) {
        self.window = window
    }

    func present(openWindow: () -> Void) {
        openWindow()
        activateAndRaiseWindow()
        scheduleOnMain { [weak self] in
            self?.activateAndRaiseWindow()
        }
    }

    private func activateAndRaiseWindow() {
        activateApplication()
        guard let window else { return }
        if window.isMiniaturized {
            window.restoreFromMiniaturization()
        }
        window.bringToFront()
    }
}

struct LiveMapWindowReader: NSViewRepresentable {
    let onWindowChange: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> LiveMapWindowObservingView {
        let view = LiveMapWindowObservingView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: LiveMapWindowObservingView, context: Context) {
        nsView.onWindowChange = onWindowChange
        nsView.reportWindow()
    }
}

final class LiveMapWindowObservingView: NSView {
    var onWindowChange: (@MainActor (NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindow()
    }

    func reportWindow() {
        onWindowChange?(window)
    }
}
