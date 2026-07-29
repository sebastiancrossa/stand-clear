import SwiftUI

/// The menu's colour vocabulary.
///
/// Every surface in the popover is a white overlay on the black arrival board, so the
/// values here are opacities rather than colours. Naming them keeps the same step
/// meaning the same thing everywhere: a divider is always `separator`, a resting
/// control is always `controlTrack`, and a change to one of those steps moves the whole
/// popover at once instead of one call site.
///
/// Text steps are chosen for contrast against `canvas`, not by eye: `secondaryText`
/// ≈ 7.6:1 and `tertiaryText` ≈ 5.3:1, both clearing 4.5:1 for body copy — including
/// the unavailable states, which stay readable rather than fading toward the board.
///
/// Nothing on this surface may reach for a system-relative colour — `.primary`,
/// `.secondary`, `.tertiary`, `Color.accentColor`, `Divider`. The board is black on
/// every Mac, but those resolve to dark ink on a Mac in Light Mode and vanish into it.
/// The steps below are absolute, so the popover renders the same on both.
enum MenuTheme {
    // MARK: Surfaces

    static let canvas = Color.black

    /// Resting fill for a segmented track or any control well.
    static let controlTrack = Color.white.opacity(0.09)

    /// Hairline around a control well. Without it the track disappears into the black
    /// board and a two-option control reads as one floating pill.
    static let controlTrackStroke = Color.white.opacity(0.1)

    /// Pointer-over fill for an unselected, enabled control.
    static let controlHover = Color.white.opacity(0.12)

    /// The selected segment: full white, reading as ink on the board.
    static let controlSelected = Color.white

    /// Hairline between major regions — header, footer, onboarding sections.
    static let separator = Color.white.opacity(0.12)

    // MARK: Content

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.5)

    /// Label colour on top of `controlSelected`.
    static let selectedText = Color.black

    // MARK: Signals

    /// Keyboard focus ring. Deliberately white rather than the system accent — the
    /// popover commits to a monochrome world and route bullets own the only colour.
    static let focusRing = Color.white.opacity(0.55)

    /// MTA yellow, reserved for feed warnings and startup failures.
    static let caution = Color(hex: 0xFCCC0A)

    /// Leave-now arrivals — warm enough to read as urgency without competing with route bullets.
    static let leaveNow = Color(hex: 0xFF9F0A)

    /// Opacity applied to too-late arrival rows. Keeps the train visible while signaling it is out of reach.
    static let tooLateOpacity = 0.38

    /// Soft fill behind a leave-now row.
    static let leaveNowHighlight = Color(hex: 0xFF9F0A).opacity(0.14)

    /// The update-available dot in the footer — the one place the popover borrows the
    /// system's "there is something new here" blue. Pinned to macOS's dark-mode value
    /// rather than `Color.accentColor`, which carries a lighter variant for Light Mode.
    static let accent = Color(hex: 0x0A84FF)
}

/// The hairline between regions of the popover.
///
/// `Divider` draws from the system separator palette, so on a Mac in Light Mode it is a
/// dark rule on a black board — invisible. This is the same 1pt line in `separator`,
/// with no system colour underneath it.
struct MenuDivider: View {
    @Environment(\.menuLayoutMetrics) private var metrics

    var body: some View {
        Rectangle()
            .fill(MenuTheme.separator)
            .frame(height: metrics.dividerThickness)
    }
}
