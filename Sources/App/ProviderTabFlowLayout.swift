import SwiftUI

/// Tabs keep their natural width up to half a row, so short tabs do not
/// stretch and long ones still leave room for a second tab beside them.
struct ProviderTabFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let containerWidth = proposal.replacingUnspecifiedDimensions().width
        let sizes = tabSizes(for: subviews, containerWidth: containerWidth)
        let rows = Self.rows(for: sizes.map(\.width), containerWidth: containerWidth, spacing: spacing)
        let height = rows.map { row in rowHeight(row, sizes: sizes) }.reduce(0, +)
            + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: containerWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let sizes = tabSizes(for: subviews, containerWidth: bounds.width)
        let rows = Self.rows(for: sizes.map(\.width), containerWidth: bounds.width, spacing: spacing)
        var rowY = bounds.minY
        for row in rows {
            let height = rowHeight(row, sizes: sizes)
            var tabX = bounds.minX
            for index in row {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: tabX, y: rowY + (height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                tabX += size.width + spacing
            }
            rowY += height + spacing
        }
    }

    static func maxTabWidth(containerWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        max((containerWidth - spacing) / 2, 0)
    }

    static func rows(for widths: [CGFloat], containerWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var currentWidth: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let neededWidth = current.isEmpty ? width : currentWidth + spacing + width
            if !current.isEmpty, neededWidth > containerWidth {
                rows.append(current)
                current = [index]
                currentWidth = width
            } else {
                current.append(index)
                currentWidth = neededWidth
            }
        }
        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private func tabSizes(for subviews: Subviews, containerWidth: CGFloat) -> [CGSize] {
        let maxWidth = Self.maxTabWidth(containerWidth: containerWidth, spacing: spacing)
        return subviews.map { subview in
            let ideal = subview.sizeThatFits(.unspecified)
            guard ideal.width > maxWidth else { return ideal }
            let capped = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            return CGSize(width: maxWidth, height: capped.height)
        }
    }

    private func rowHeight(_ row: [Int], sizes: [CGSize]) -> CGFloat {
        row.map { sizes[$0].height }.max() ?? 0
    }
}
