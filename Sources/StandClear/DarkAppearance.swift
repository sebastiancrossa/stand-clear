import AppKit
import SwiftUI

extension View {
    /// Pins this surface to the dark appearance, whatever the Mac is set to.
    ///
    /// Stand Clear's board is a black arrival sign and every step in `MenuTheme` is a
    /// white overlay chosen for contrast against it. On a Mac in Light Mode the system
    /// palette resolves the other way — `.secondary` text, `Divider`, `Toggle`, the
    /// scroll indicators — so anything left to the system comes back as dark ink and
    /// disappears into the board.
    ///
    /// `preferredColorScheme(.dark)` alone did not cover it. It asks the *hosting
    /// window* to adopt the scheme, and the panel behind `MenuBarExtra` is owned by the
    /// system: it adopts a beat after the first paint, and on a fresh popover it
    /// sometimes never gets asked at all. That timing is why the text vanished
    /// intermittently rather than every time.
    ///
    /// So this pins both halves, and neither one waits on a window:
    ///
    /// - `colorScheme` is written straight into the environment, so SwiftUI resolves
    ///   dynamic colours dark on the very first pass.
    /// - the hosting window is held at `darkAqua`, which is the only thing AppKit-drawn
    ///   chrome reads — switches, steppers, spinners, menus, materials, the title bar.
    ///
    /// The menu bar label deliberately does not use this. The status item sits on the
    /// system's own bar and has to follow whatever that bar is doing.
    func forcesDarkAppearance() -> some View {
        environment(\.colorScheme, .dark)
            .background(DarkAppearancePin())
    }
}

private struct DarkAppearancePin: NSViewRepresentable {
    func makeNSView(context: Context) -> DarkAppearancePinningView {
        DarkAppearancePinningView()
    }

    func updateNSView(_ nsView: DarkAppearancePinningView, context: Context) {
        // SwiftUI rebuilds the popover's window across open/close cycles, so re-pin on
        // every update rather than only when the view first lands in a window.
        nsView.pinWindowAppearance()
    }
}

private final class DarkAppearancePinningView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pinWindowAppearance()
    }

    func pinWindowAppearance() {
        window?.appearance = NSAppearance(named: .darkAqua)
    }

    /// The pin sits in a `background`, which puts a real NSView under the whole
    /// surface. It draws nothing and must not swallow the clicks meant for the board.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
