import SwiftUI
import VoxOpsCore

struct HUDOrbView: View {
    let state: VoxState
    @State private var isPulsing = false
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .fill(orbColor)
            .frame(width: 32, height: 32)
            .shadow(color: glowColor, radius: glowRadius)
            .scaleEffect(isPulsing ? 1.15 : 1.0)
            .overlay(processingRing)
            .onChange(of: state) { _, newState in updateAnimations(newState) }
            .onAppear { updateAnimations(state) }
    }

    private var orbColor: Color {
        switch state {
        case .idle: return Color(white: 0.3)
        case .listening: return .red
        case .processing: return .orange
        case .success: return .green
        case .error: return .red
        }
    }

    private var glowColor: Color {
        switch state {
        case .idle: return .clear
        case .listening: return .red.opacity(0.6)
        case .processing: return .orange.opacity(0.5)
        case .success: return .green.opacity(0.5)
        case .error: return .red.opacity(0.5)
        }
    }

    private var glowRadius: CGFloat { state == .idle ? 0 : 12 }

    private var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    @ViewBuilder
    private var processingRing: some View {
        if isProcessing {
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Color.orange, lineWidth: 2)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
        }
    }

    private func updateAnimations(_ newState: VoxState) {
        switch newState {
        case .listening:
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isPulsing = true }
        case .processing:
            isPulsing = false
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { rotation = 360 }
        case .success, .error, .idle:
            withAnimation { isPulsing = false; rotation = 0 }
        }
    }
}
