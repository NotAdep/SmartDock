import CoreGraphics

/// Recognises windows laid out on the macOS tiling grid (fill, halves, quarters) and
/// maps them from one usable area to another. All rects are in AX coordinates.
enum Tiling {
    /// Which fraction of the area each window edge sits on (0, ½ or 1).
    struct Tile: Equatable {
        var left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat
        var isFill: Bool { left == 0 && top == 0 && right == 1 && bottom == 1 }
    }

    /// How far each edge sits *inside* its grid line (tiling margins, gaps, rounding).
    struct Insets {
        var left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat
    }

    enum DockEdge { case left, right, bottom }

    /// Per-edge distance from a grid line that still counts as on it. Covers Sequoia's
    /// "Tiled windows have margins" and apps that round their size (Terminal's grid).
    static let slack: ClosedRange<CGFloat> = -3...16

    static func match(_ frame: CGRect, in area: CGRect) -> (tile: Tile, insets: Insets)? {
        guard area.width > 0, area.height > 0 else { return nil }
        func line(_ origin: CGFloat, _ length: CGFloat, _ f: CGFloat) -> CGFloat { origin + length * f }

        // Leading edges measure inward as (edge - line), trailing edges as (line - edge).
        func leading(_ edge: CGFloat, _ origin: CGFloat, _ length: CGFloat) -> (CGFloat, CGFloat)? {
            for f: CGFloat in [0, 0.5] {
                let inset = edge - line(origin, length, f)
                if slack.contains(inset) { return (f, inset) }
            }
            return nil
        }
        func trailing(_ edge: CGFloat, _ origin: CGFloat, _ length: CGFloat) -> (CGFloat, CGFloat)? {
            for f: CGFloat in [1, 0.5] {
                let inset = line(origin, length, f) - edge
                if slack.contains(inset) { return (f, inset) }
            }
            return nil
        }

        guard let l = leading(frame.minX, area.minX, area.width),
              let r = trailing(frame.maxX, area.minX, area.width), l.0 < r.0,
              let t = leading(frame.minY, area.minY, area.height),
              let b = trailing(frame.maxY, area.minY, area.height), t.0 < b.0 else { return nil }

        return (Tile(left: l.0, top: t.0, right: r.0, bottom: b.0),
                Insets(left: l.1, top: t.1, right: r.1, bottom: b.1))
    }

    /// The edge the Dock occupies, judged by where `hidden` extends beyond `shown`.
    static func dockEdge(shown: CGRect, hidden: CGRect) -> DockEdge? {
        if hidden.maxY > shown.maxY + 1 { return .bottom }
        if hidden.minX < shown.minX - 1 { return .left }
        if hidden.maxX > shown.maxX + 1 { return .right }
        return nil
    }

    /// Re-lays a tiled window from the Dock-visible area onto the Dock-hidden one,
    /// keeping its margins and gaps. Grid lines move proportionally, so stacked tiles
    /// (top/bottom halves, quarters) stay even.
    static func remap(_ frame: CGRect, from shown: CGRect, to hidden: CGRect) -> CGRect? {
        guard let (tile, i) = match(frame, in: shown) else { return nil }
        let dock = dockEdge(shown: shown, hidden: hidden)

        // Outer-edge margin to reuse on the edge the Dock vacates. A rounded edge
        // (e.g. Terminal's bottom) is ignored by taking the smallest outer margin.
        var outer: [CGFloat] = []
        if tile.left == 0 && dock != .left { outer.append(i.left) }
        if tile.right == 1 && dock != .right { outer.append(i.right) }
        if tile.top == 0 { outer.append(i.top) }
        let margin = max(0, outer.min() ?? 0)

        func x(_ f: CGFloat) -> CGFloat { hidden.minX + hidden.width * f }
        func y(_ f: CGFloat) -> CGFloat { hidden.minY + hidden.height * f }

        let left = x(tile.left) + (tile.left == 0 && dock == .left ? margin : max(0, i.left))
        let right = x(tile.right) - (tile.right == 1 && dock == .right ? margin : max(0, i.right))
        let top = y(tile.top) + max(0, i.top)
        let bottom = y(tile.bottom) - (tile.bottom == 1 && dock == .bottom ? margin : max(0, i.bottom))
        return CGRect(x: left, y: top, width: right - left, height: bottom - top).integral
    }
}
