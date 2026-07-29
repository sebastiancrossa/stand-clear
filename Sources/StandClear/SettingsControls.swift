import SwiftUI

/// A labelled block of settings: a small tracked heading, one control, and an optional
/// footnote underneath.
///
/// The popover is 340pt wide and every setting here is a single control, so the group
/// stays flat rather than boxing its content. A rounded container drawn around one
/// rounded control is a box inside a box, and it would read as a panel the user can
/// open. Grouping comes from the heading and from `settingsGroupSpacing` between
/// groups, which is wider than the gap between a heading and the control it names.
struct SettingsGroup<Content: View>: View {
    @Environment(\.menuLayoutMetrics) private var metrics

    let label: String
    var footnote: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.settingsGroupLabelSpacing) {
            Text(label)
                .font(.system(
                    size: metrics.settingsGroupLabelFontSize,
                    weight: .bold,
                    design: .rounded
                ))
                .tracking(metrics.settingsGroupLabelTracking)
                .foregroundStyle(MenuTheme.secondaryText)
                .accessibilityAddTraits(.isHeader)

            content

            if let footnote {
                Text(footnote)
                    .font(.system(size: metrics.settingsFootnoteFontSize))
                    .foregroundStyle(MenuTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, metrics.settingsFootnoteSpacing - metrics.settingsGroupLabelSpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A segmented selector drawn in the popover's palette.
///
/// The shape, height, and behaviour follow `NSSegmentedControl` — one tab stop, arrow
/// keys move the selection, the whole segment is the hit target — but the selected
/// segment is white on black instead of the system accent, because route bullets own
/// the only colour in this window.
struct SettingsSegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: String
        var glyph: String?
        var help: String?
        var accessibilityTitle: String?

        var id: Value { value }
    }

    @Environment(\.menuLayoutMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    let segments: [Segment]
    @Binding var selection: Value

    @Namespace private var selectionNamespace
    @State private var hoveredValue: Value?
    @FocusState private var isFocused: Bool

    private var innerCornerRadius: CGFloat {
        max(0, metrics.settingsControlCornerRadius - metrics.settingsControlInset)
    }

    private var segmentHeight: CGFloat {
        metrics.settingsControlHeight - (metrics.settingsControlInset * 2)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(metrics.settingsControlInset)
        .background {
            RoundedRectangle(
                cornerRadius: metrics.settingsControlCornerRadius,
                style: .continuous
            )
            .fill(MenuTheme.controlTrack)
            .overlay {
                RoundedRectangle(
                    cornerRadius: metrics.settingsControlCornerRadius,
                    style: .continuous
                )
                .strokeBorder(MenuTheme.controlTrackStroke, lineWidth: 1)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: selection)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredValue)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .overlay {
            RoundedRectangle(
                cornerRadius: metrics.settingsControlCornerRadius + metrics.settingsFocusRingInset,
                style: .continuous
            )
            .strokeBorder(MenuTheme.focusRing, lineWidth: metrics.settingsFocusRingWidth)
            .padding(-metrics.settingsFocusRingInset)
            .opacity(isFocused ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isFocused)
        }
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = segment.value == selection
        let isHovered = hoveredValue == segment.value

        return Button {
            select(segment.value)
        } label: {
            HStack(spacing: 4) {
                if let glyph = segment.glyph {
                    Text(glyph)
                }

                Text(segment.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(
                size: metrics.settingsSegmentFontSize,
                weight: .semibold,
                design: .rounded
            ))
            .foregroundStyle(foreground(isSelected: isSelected, isHovered: isHovered))
            .padding(.horizontal, metrics.settingsSegmentHorizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: segmentHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                        .fill(MenuTheme.controlSelected)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                        .fill(MenuTheme.controlHover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                hoveredValue = segment.value
            } else if hoveredValue == segment.value {
                hoveredValue = nil
            }
        }
        .help(segment.help ?? "")
        .accessibilityLabel(segment.accessibilityTitle ?? segment.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func foreground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return MenuTheme.selectedText }
        return isHovered ? MenuTheme.primaryText : MenuTheme.secondaryText
    }

    private func select(_ value: Value) {
        guard selection != value else { return }
        selection = value
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let index = segments.firstIndex(where: { $0.value == selection }) else {
            // Onboarding starts with nothing chosen, so an arrow key enters the
            // control from whichever end the user pressed toward.
            switch direction {
            case .left:
                segments.last.map { select($0.value) }
            case .right:
                segments.first.map { select($0.value) }
            default:
                break
            }
            return
        }

        switch direction {
        case .left where index > 0:
            select(segments[index - 1].value)
        case .right where index < segments.count - 1:
            select(segments[index + 1].value)
        default:
            break
        }
    }
}

/// Lays subviews left to right and wraps to a new line when the next one no longer
/// fits.
///
/// The LINES grid feeds this one trunk group per subview — ACE, BDFM, G, and so on —
/// so a group is never split across lines. That grouping is how the system is signed
/// and how riders read it, and stacking one group per row instead pushed the grid off
/// the bottom of a 480pt popover.
struct WrappingHStack: Layout {
    var itemSpacing: CGFloat
    var lineSpacing: CGFloat

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = lines.reduce(0) { $0 + $1.height }
            + (lineSpacing * CGFloat(max(0, lines.count - 1)))
        return CGSize(width: lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY

        for line in arrange(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX

            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + ((line.height - size.height) / 2)),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + itemSpacing
            }

            y += line.height + lineSpacing
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projectedWidth = line.indices.isEmpty
                ? size.width
                : line.width + itemSpacing + size.width

            if !line.indices.isEmpty, projectedWidth > maxWidth {
                lines.append(line)
                line = Line(indices: [index], width: size.width, height: size.height)
            } else {
                line.indices.append(index)
                line.width = projectedWidth
                line.height = max(line.height, size.height)
            }
        }

        if !line.indices.isEmpty {
            lines.append(line)
        }
        return lines
    }
}

/// The onboarding call to action. White on black, with the hover and pressed steps a
/// plain `Button` label does not get for free.
struct SettingsPrimaryButton: View {
    @Environment(\.menuLayoutMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let symbol: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: symbol)
            }
            .font(.system(
                size: metrics.settingsCTAFontSize,
                weight: .bold,
                design: .rounded
            ))
            .frame(maxWidth: .infinity)
            .frame(height: metrics.settingsCTAHeight)
            // Fading the whole button leaves a black label on a dark grey pill, which
            // is unreadable rather than unavailable. The disabled step instead drops
            // the fill to a well and lifts the label back to white.
            .foregroundStyle(isEnabled ? MenuTheme.selectedText : MenuTheme.tertiaryText)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled ? MenuTheme.controlSelected : MenuTheme.controlTrack)
                    .opacity(isEnabled && isHovered ? 0.88 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .scaleEffect(isEnabled && isHovered ? 1.01 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isEnabled)
        .onHover { isHovered = $0 }
    }
}
