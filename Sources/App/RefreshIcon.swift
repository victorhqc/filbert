import SwiftUI

// MARK: - Refresh icon

/// `withAnimation` is committed explicitly on each flag transition because
/// `repeatForever` animations started implicitly do not stop cleanly when the
/// driving value flips back.
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
