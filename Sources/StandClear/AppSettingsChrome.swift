import SwiftUI

/// Layout steps for the app Settings window.
///
/// The popover has `MenuLayoutMetrics` because its numbers are load-bearing — eight
/// arrival rows have to fit inside 480pt, and a test asserts it. Nothing here is
/// measured against a promise like that, so these are plain constants: one place to
/// change a step, without environment plumbing for numbers no test reads.
enum SettingsMetrics {
    static let sidebarMinWidth: CGFloat = 176
    static let sidebarIdealWidth: CGFloat = 196
    static let sidebarMaxWidth: CGFloat = 240
    static let sidebarRowFontSize: CGFloat = 12.5

    static let headerHorizontalPadding: CGFloat = 20
    static let headerTopPadding: CGFloat = 14
    static let headerBottomPadding: CGFloat = 12
    static let headerSpacing: CGFloat = 2
    static let headerTitleFontSize: CGFloat = 15
    static let headerCaptionFontSize: CGFloat = 11

    static let paneHorizontalPadding: CGFloat = 20
    static let paneTopPadding: CGFloat = 18
    static let paneBottomPadding: CGFloat = 22
    static let cardSpacing: CGFloat = 16

    static let cardCornerRadius: CGFloat = 12
    static let cardTitleFontSize: CGFloat = 10
    static let cardTitleTracking: CGFloat = 0.6
    static let cardTitleSpacing: CGFloat = 7
    static let cardFootnoteFontSize: CGFloat = 10.5
    static let cardFootnoteSpacing: CGFloat = 7

    static let rowHorizontalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 10
    static let rowMinHeight: CGFloat = 48
    static let rowItemSpacing: CGFloat = 11
    static let rowTextSpacing: CGFloat = 2
    static let rowTitleFontSize: CGFloat = 13
    static let rowSubtitleFontSize: CGFloat = 11

    static let iconTileSize: CGFloat = 28
    static let iconTileCornerRadius: CGFloat = 8
    static let iconTileSymbolFontSize: CGFloat = 13

    /// Hairlines between rows start at the text column rather than under the icon tile,
    /// so a card reads as one stack of labelled settings instead of a table with a
    /// gutter running down it.
    static var separatorLeadingInset: CGFloat {
        rowHorizontalPadding + iconTileSize + rowItemSpacing
    }
}

/// Surfaces for the app Settings window.
///
/// This window is standard macOS chrome, not the black arrival board, so its text and
/// controls stay on the system palette — the window is pinned to `darkAqua` (see
/// `forcesDarkAppearance`), which is what makes `.secondary` and a `Toggle` resolve
/// correctly here even on a Mac in Light Mode.
///
/// Only the surfaces are spelled out. `controlBackgroundColor` lands within a point or
/// two of `windowBackgroundColor` in the dark palette, so a card drawn with it is
/// invisible; these are white overlays picked to read as exactly one step above the
/// window without turning into a second window.
enum SettingsSurface {
    static let card = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.07)
    static let separator = Color.white.opacity(0.07)
    static let iconTile = Color.white.opacity(0.09)

    /// Pointer-over fill for a row that is itself the control — a link row.
    static let rowHover = Color.white.opacity(0.05)
}

/// The extra line under a row's subtitle: an update status, a permission state, or the
/// reason a control is unavailable.
///
/// It is separate from `subtitle` because the subtitle says what a setting *is*, which
/// does not change, and this says what is *true right now*, which does.
struct SettingsRowNote {
    /// How loudly the note reads.
    ///
    /// `warning` is red, and red is a promise that something is switched off and the rider
    /// has to go fix it — a denied location permission, a login item that would not
    /// register. It is not for things that merely did not happen: a failed update check
    /// leaves the app entirely usable, so it states itself in `neutral` and lets the
    /// "Check Now" button be the way out. Reaching for red there reports a problem the
    /// rider does not have.
    enum Tone {
        case neutral
        case accent
        case warning
    }

    let text: String
    var tone: Tone = .neutral

    var foreground: Color {
        switch tone {
        case .neutral: Color(nsColor: .secondaryLabelColor)
        case .accent: MenuTheme.accent
        case .warning: Color(nsColor: .systemRed)
        }
    }
}

/// The rounded glyph tile at the head of every settings row.
struct SettingsIconTile: View {
    let symbol: String
    var tint: Color?
    var isEnabled = true

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsMetrics.iconTileCornerRadius, style: .continuous)
            .fill(SettingsSurface.iconTile)
            .frame(width: SettingsMetrics.iconTileSize, height: SettingsMetrics.iconTileSize)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: SettingsMetrics.iconTileSymbolFontSize, weight: .medium))
                    .foregroundStyle(symbolForeground)
            }
            .accessibilityHidden(true)
    }

    private var symbolForeground: Color {
        if let tint {
            return tint.opacity(isEnabled ? 1 : 0.5)
        }
        return isEnabled
            ? Color(nsColor: .labelColor)
            : Color(nsColor: .tertiaryLabelColor)
    }
}

/// The shape every row in a card shares: glyph tile, a text column that takes the slack,
/// and a control pinned to the trailing edge.
///
/// `SettingsRow` covers the common title/subtitle shape on top of this. Rows that need
/// a control inside the text column — a station override's stepper — build on this
/// directly rather than growing another slot onto `SettingsRow`.
struct SettingsRowLayout<Label: View, Trailing: View>: View {
    let symbol: String
    var tint: Color?
    var isEnabled = true
    @ViewBuilder var label: Label
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: SettingsMetrics.rowItemSpacing) {
            SettingsIconTile(symbol: symbol, tint: tint, isEnabled: isEnabled)

            label
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, SettingsMetrics.rowHorizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        .frame(minHeight: SettingsMetrics.rowMinHeight)
    }
}

/// One setting: what it is, what it does, and the control that changes it.
struct SettingsRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var note: SettingsRowNote?
    var tint: Color?
    var isEnabled = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        SettingsRowLayout(symbol: symbol, tint: tint, isEnabled: isEnabled) {
            VStack(alignment: .leading, spacing: SettingsMetrics.rowTextSpacing) {
                Text(title)
                    .font(.system(size: SettingsMetrics.rowTitleFontSize, weight: .semibold))
                    .foregroundStyle(isEnabled ? .primary : .secondary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: SettingsMetrics.rowSubtitleFontSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let note {
                    Text(note.text)
                        .font(.system(size: SettingsMetrics.rowSubtitleFontSize))
                        .foregroundStyle(note.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
            }
            .accessibilityElement(children: .combine)
        } trailing: {
            trailing
        }
    }
}

extension SettingsRow where Trailing == EmptyView {
    /// A row that only states something — attribution, a privacy fact — and has nothing
    /// to change.
    init(
        symbol: String,
        title: String,
        subtitle: String? = nil,
        note: SettingsRowNote? = nil,
        tint: Color? = nil,
        isEnabled: Bool = true
    ) {
        self.init(
            symbol: symbol,
            title: title,
            subtitle: subtitle,
            note: note,
            tint: tint,
            isEnabled: isEnabled
        ) {
            EmptyView()
        }
    }
}

/// A row whose whole width is the link, with the system's leaves-the-app arrow where a
/// control would otherwise sit.
struct SettingsLinkRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let symbol: String
    let title: String
    var subtitle: String?
    let destination: URL

    @State private var isHovered = false

    var body: some View {
        Link(destination: destination) {
            SettingsRow(symbol: symbol, title: title, subtitle: subtitle) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .background(isHovered ? SettingsSurface.rowHover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .help("Open \(title) in your browser")
    }
}

/// One row's worth of content inside a `SettingsCard`.
struct SettingsCardRow {
    /// Identity for rows a card builds from live data — the nearby stations in Walk
    /// Time. State inside such a row has to follow its station rather than its position,
    /// or a reordered list hands one station's override to another. Fixed rows leave
    /// this nil and the card falls back to the position, which cannot drift.
    var id: AnyHashable?
    let content: AnyView

    init(id: AnyHashable? = nil, @ViewBuilder content: () -> some View) {
        self.id = id
        self.content = AnyView(content())
    }
}

/// Collects a card's rows so the card can put the hairlines *between* them.
///
/// A plain `ViewBuilder` hands a container one opaque value it cannot count or index,
/// and `Group(subviews:)` — the API that would let it — is macOS 15 while this app ships
/// to macOS 14. Gathering rows as values instead keeps the call sites reading like
/// SwiftUI, `if` and `for` included, and leaves the separators to one place.
@resultBuilder
enum SettingsCardBuilder {
    static func buildExpression(_ row: SettingsCardRow) -> [SettingsCardRow] {
        [row]
    }

    static func buildExpression<V: View>(_ view: V) -> [SettingsCardRow] {
        [SettingsCardRow { view }]
    }

    static func buildBlock(_ rows: [SettingsCardRow]...) -> [SettingsCardRow] {
        rows.flatMap { $0 }
    }

    static func buildArray(_ rows: [[SettingsCardRow]]) -> [SettingsCardRow] {
        rows.flatMap { $0 }
    }

    static func buildOptional(_ rows: [SettingsCardRow]?) -> [SettingsCardRow] {
        rows ?? []
    }

    static func buildEither(first rows: [SettingsCardRow]) -> [SettingsCardRow] {
        rows
    }

    static func buildEither(second rows: [SettingsCardRow]) -> [SettingsCardRow] {
        rows
    }
}

/// A group of settings drawn as one rounded surface with its rows hairline-separated.
///
/// The title is optional and used sparingly. A pane's name already sits in the sidebar
/// and again in the header, so most cards need no third label — the grouping itself is
/// the statement. Titles are for cards whose contents are not self-evident from their
/// rows, like a list of per-station overrides.
struct SettingsCard: View {
    private struct PositionedRow: Identifiable {
        let id: AnyHashable
        let content: AnyView
        let isFirst: Bool
    }

    var title: String?
    var footnote: String?
    private let rows: [SettingsCardRow]

    init(
        title: String? = nil,
        footnote: String? = nil,
        @SettingsCardBuilder rows: () -> [SettingsCardRow]
    ) {
        self.title = title
        self.footnote = footnote
        self.rows = rows()
    }

    private var positionedRows: [PositionedRow] {
        rows.enumerated().map { index, row in
            PositionedRow(
                id: row.id ?? AnyHashable(index),
                content: row.content,
                isFirst: index == 0
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: SettingsMetrics.cardTitleFontSize, weight: .bold))
                    .tracking(SettingsMetrics.cardTitleTracking)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.leading, 4)
                    .padding(.bottom, SettingsMetrics.cardTitleSpacing)
            }

            VStack(spacing: 0) {
                ForEach(positionedRows) { row in
                    if !row.isFirst {
                        SettingsRowSeparator()
                    }
                    row.content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: SettingsMetrics.cardCornerRadius,
                    style: .continuous
                )
                .fill(SettingsSurface.card)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: SettingsMetrics.cardCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: SettingsMetrics.cardCornerRadius,
                    style: .continuous
                )
                .strokeBorder(SettingsSurface.cardStroke, lineWidth: 1)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: SettingsMetrics.cardFootnoteFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, SettingsMetrics.cardFootnoteSpacing)
            }
        }
    }
}

private struct SettingsRowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(SettingsSurface.separator)
            .frame(height: 1)
            .padding(.leading, SettingsMetrics.separatorLeadingInset)
    }
}
