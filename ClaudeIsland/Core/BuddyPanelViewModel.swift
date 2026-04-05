//
//  BuddyPanelViewModel.swift
//  ClaudeIsland
//
//  Core state for the floating buddy panel
//

import Combine
import SwiftUI

enum BuddyGlowState: Equatable {
    case idle        // No glow
    case processing  // Green
    case needsInput  // Orange, pulsing
    case needsApproval // Red, pulsing

    var color: Color {
        switch self {
        case .idle: return .clear
        case .processing: return Color(red: 0.29, green: 0.87, blue: 0.5)     // #4ADE80
        case .needsInput: return Color(red: 0.98, green: 0.75, blue: 0.15)    // #FBBF24
        case .needsApproval: return Color(red: 0.97, green: 0.44, blue: 0.44) // #F87171
        }
    }

    var shouldPulse: Bool {
        self == .needsInput || self == .needsApproval
    }
}

enum BuddyPanelContent: Equatable {
    case instances
    case chat(SessionState)

    static func == (lhs: BuddyPanelContent, rhs: BuddyPanelContent) -> Bool {
        switch (lhs, rhs) {
        case (.instances, .instances): return true
        case (.chat(let a), .chat(let b)): return a.sessionId == b.sessionId
        default: return false
        }
    }
}

@MainActor
class BuddyPanelViewModel: ObservableObject {
    // MARK: - Published State
    @Published var isExpanded = false
    @Published var contentType: BuddyPanelContent = .instances
    @Published var glowState: BuddyGlowState = .idle

    // MARK: - Position (persisted)
    @Published var position: CGPoint {
        didSet { savePosition() }
    }

    // MARK: - Session monitor
    private var cancellables = Set<AnyCancellable>()
    let sessionMonitor: ClaudeSessionMonitor

    // MARK: - Panel sizing
    var panelSize: CGSize {
        switch contentType {
        case .instances: return CGSize(width: 320, height: 400)
        case .chat: return CGSize(width: 360, height: 500)
        }
    }

    static let buddySize: CGFloat = 48

    init(sessionMonitor: ClaudeSessionMonitor) {
        self.sessionMonitor = sessionMonitor
        self.position = Self.loadPosition()

        // Observe session changes to update glow
        sessionMonitor.$instances
            .receive(on: DispatchQueue.main)
            .sink { [weak self] instances in
                self?.updateGlowState(from: instances)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func toggle() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if isExpanded {
                collapse()
            } else {
                expand()
            }
        }
    }

    func expand() {
        isExpanded = true
        contentType = .instances
    }

    func collapse() {
        isExpanded = false
        contentType = .instances
    }

    func showChat(for session: SessionState) {
        contentType = .chat(session)
    }

    func exitChat() {
        contentType = .instances
    }

    // MARK: - Glow State

    private func updateGlowState(from instances: [SessionState]) {
        let active = instances.filter { $0.phase != .ended }

        if active.contains(where: { $0.phase.isWaitingForApproval }) {
            glowState = .needsApproval
        } else if active.contains(where: { $0.phase == .waitingForInput }) {
            glowState = .needsInput
        } else if active.contains(where: { $0.phase == .processing || $0.phase == .compacting }) {
            glowState = .processing
        } else {
            glowState = .idle
        }
    }

    // MARK: - Position Persistence

    private static let positionXKey = "buddyPositionX"
    private static let positionYKey = "buddyPositionY"

    private static func loadPosition() -> CGPoint {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: positionXKey) != nil {
            return CGPoint(
                x: defaults.double(forKey: positionXKey),
                y: defaults.double(forKey: positionYKey)
            )
        }
        // Default: bottom-right, 20px from edges
        guard let screen = NSScreen.main else { return CGPoint(x: 100, y: 100) }
        return CGPoint(
            x: screen.visibleFrame.maxX - buddySize - 20,
            y: screen.visibleFrame.minY + 20
        )
    }

    private func savePosition() {
        UserDefaults.standard.set(position.x, forKey: Self.positionXKey)
        UserDefaults.standard.set(position.y, forKey: Self.positionYKey)
    }
}
