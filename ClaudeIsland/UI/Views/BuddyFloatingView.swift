//
//  BuddyFloatingView.swift
//  ClaudeIsland
//
//  The 48x48 floating buddy widget with drag support
//

import SwiftUI

struct BuddyFloatingView: View {
    @ObservedObject var viewModel: BuddyPanelViewModel
    @ObservedObject var buddyReader: BuddyReader

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    private let size: CGFloat = BuddyPanelViewModel.buddySize

    var body: some View {
        ZStack {
            // Glow ring
            BuddyGlowRing(glowState: viewModel.glowState, size: size + 8)

            // Buddy content
            buddyContent
                .frame(width: size, height: size)
                .clipShape(Circle())
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.8))
                )
        }
        .frame(width: size + 12, height: size + 12)
        .contentShape(Circle())
        .gesture(dragGesture)
        .onTapGesture {
            if !isDragging {
                viewModel.toggle()
            }
        }
    }

    @ViewBuilder
    private var buddyContent: some View {
        if let buddy = buddyReader.buddy {
            // Use emoji view at 48x48 — matches EmojiPixelView's canvasSize
            EmojiPixelView(
                emoji: buddy.species.emoji,
                style: viewModel.glowState == .processing ? .wave : .rock
            )
            .scaleEffect(0.9)
        } else {
            // Fallback: simple icon
            Image(systemName: "person.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    @State private var dragStartPosition: CGPoint = .zero

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartPosition = viewModel.position
                }
                viewModel.position = CGPoint(
                    x: dragStartPosition.x + value.translation.width,
                    y: dragStartPosition.y - value.translation.height // macOS Y is flipped
                )
            }
            .onEnded { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isDragging = false
                }
            }
    }
}
