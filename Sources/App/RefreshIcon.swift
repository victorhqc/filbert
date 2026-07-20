import SwiftUI

// MARK: - Refresh icon (ui 07 AC3)

/// `arrow.clockwise` glyph that rotates continuously while `isRefreshing`
/// is true and stops when it flips back. The view-model flag drives both
/// the animation and the click-debounce (ui 07 AC3/AC4).
///
/// `withAnimation(... .repeatForever)` is committed explicitly on each flag
/// transition: implicit `.animation(_:value:)` was tried first but left the
/// glyph mid-rotation when the flag flipped back, so the explicit form is
/// used (ui 07 Risks).
struct RefreshIcon: View {
    let isRefreshing: Bool

    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(rotation))
            .onChange(of: isRefreshing) { _, newValue in
                if newValue {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        rotation = 0
                    }
                }
            }
            .onAppear {
                if isRefreshing {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            }
    }
}
