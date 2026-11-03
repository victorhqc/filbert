import SwiftUI

struct UsageRing: View {
    let fraction: Double
    let color: Color?
    var lineWidth: CGFloat = 2
    var diameter: CGFloat = 14
    var colorOpacity: Double = 1

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.2), lineWidth: lineWidth)
            if let color {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color.opacity(colorOpacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
