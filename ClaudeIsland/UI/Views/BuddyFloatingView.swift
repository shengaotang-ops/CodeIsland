//
//  BuddyFloatingView.swift
//  ClaudeIsland
//
//  The floating buddy widget with drag support
//

import SwiftUI

struct BuddyFloatingView: View {
    @ObservedObject var viewModel: BuddyPanelViewModel
    @ObservedObject var buddyReader: BuddyReader

    @State private var isDragging = false
    @State private var dragStartPosition: CGPoint = .zero

    private let size: CGFloat = BuddyPanelViewModel.buddySize

    /// Color tint based on session state — applied to the buddy ASCII art itself
    private var glowColor: Color? {
        switch viewModel.glowState {
        case .idle: return nil
        case .processing: return Color(red: 0.29, green: 0.87, blue: 0.5)
        case .needsInput: return Color(red: 0.98, green: 0.75, blue: 0.15)
        case .needsApproval: return Color(red: 0.97, green: 0.44, blue: 0.44)
        }
    }

    var body: some View {
        buddyContent
            .frame(width: size + 12, height: size + 12)
            .contentShape(Rectangle())
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
            BuddyASCIIView(buddy: buddy, showName: false)
                .fixedSize()
                .brightness(0.3)
                .colorMultiply(glowColor ?? buddy.rarity.color)
                .shadow(color: (glowColor ?? .clear).opacity(0.5), radius: glowColor != nil ? 4 : 0)
                .scaleEffect(1.1)
        } else {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartPosition = viewModel.position
                }
                let newPos = CGPoint(
                    x: dragStartPosition.x + value.translation.width,
                    y: dragStartPosition.y - value.translation.height
                )
                viewModel.moveWindow?(newPos)
                viewModel.positionSilent = newPos
            }
            .onEnded { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isDragging = false
                }
            }
    }
}
