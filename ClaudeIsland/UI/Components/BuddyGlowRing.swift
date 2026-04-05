//
//  BuddyGlowRing.swift
//  ClaudeIsland
//
//  Animated glow ring around the buddy pet
//

import SwiftUI

struct BuddyGlowRing: View {
    let glowState: BuddyGlowState
    let size: CGFloat

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.clear)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(glowState.color, lineWidth: 3)
                    .blur(radius: 6)
                    .opacity(glowState == .idle ? 0 : (isPulsing ? 0.5 : 1.0))
            )
            .overlay(
                Circle()
                    .stroke(glowState.color, lineWidth: 1.5)
                    .opacity(glowState == .idle ? 0 : 0.8)
            )
            .onChange(of: glowState) { _, newState in
                if newState.shouldPulse {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isPulsing = false
                    }
                }
            }
            .onAppear {
                if glowState.shouldPulse {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
    }
}
