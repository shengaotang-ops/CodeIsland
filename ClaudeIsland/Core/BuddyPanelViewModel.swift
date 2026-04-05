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
    case menu
    case chat(SessionState)

    static func == (lhs: BuddyPanelContent, rhs: BuddyPanelContent) -> Bool {
        switch (lhs, rhs) {
        case (.instances, .instances): return true
        case (.menu, .menu): return true
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

    /// Set position without triggering the $position Combine publisher.
    /// Used during drag for direct window movement (bypasses Combine for zero-lag drag).
    var positionSilent: CGPoint {
        get { position }
        set {
            // Directly update backing storage without triggering @Published
            let key = Self.positionXKey
            UserDefaults.standard.set(newValue.x, forKey: key)
            UserDefaults.standard.set(newValue.y, forKey: Self.positionYKey)
            // Use withMutation to avoid triggering SwiftUI re-render during drag
            position = newValue
        }
    }

    /// Callback for direct window movement during drag (set by window controller)
    var moveWindow: ((CGPoint) -> Void)?

    // MARK: - Session monitor
    private var cancellables = Set<AnyCancellable>()
    let sessionMonitor: ClaudeSessionMonitor

    // MARK: - Panel sizing
    var panelSize: CGSize {
        switch contentType {
        case .instances: return CGSize(width: 320, height: 400)
        case .menu: return CGSize(width: 320, height: 440)
        case .chat: return CGSize(width: 360, height: 500)
        }
    }

    static let buddySize: CGFloat = 96

    /// A NotchViewModel that child views (ClaudeInstancesView, ChatView) can bind to.
    /// Actions on it are forwarded back to this BuddyPanelViewModel.
    lazy var notchBridge: NotchViewModel = {
        let vm = NotchViewModel(
            deviceNotchRect: .zero,
            screenRect: NSScreen.main?.frame ?? .zero,
            windowHeight: 500,
            hasPhysicalNotch: false,
            handleEvents: false
        )
        // Keep it permanently opened so child views render content
        vm.status = .opened

        // Forward NotchViewModel contentType changes → BuddyPanelViewModel
        vm.$contentType
            .dropFirst() // skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] contentType in
                guard let self = self, !self.isSyncingBridge else { return }
                self.isSyncingBridge = true
                defer { self.isSyncingBridge = false }
                switch contentType {
                case .chat(let session):
                    self.showChat(for: session)
                case .instances:
                    if self.contentType != .instances {
                        self.contentType = .instances
                    }
                case .menu:
                    self.contentType = .menu
                }
            }
            .store(in: &cancellables)

        return vm
    }()

    /// Prevents infinite loops during bridge sync
    private var isSyncingBridge = false

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

    /// Set by expand() so the window controller can debounce the click-outside monitor.
    /// Must be set synchronously (not via Combine sink) to beat the global event monitor.
    var lastExpandTime: Date = .distantPast

    func expand() {
        lastExpandTime = Date()
        isExpanded = true
        contentType = .instances
    }

    func collapse() {
        isExpanded = false
        contentType = .instances
        syncBridgeContentType()
    }

    func showChat(for session: SessionState) {
        contentType = .chat(session)
        syncBridgeContentType()
    }

    func exitChat() {
        contentType = .instances
        syncBridgeContentType()
    }

    /// Push contentType to the notch bridge (skipped if the bridge triggered the change)
    func syncBridgeContentType() {
        guard !isSyncingBridge else { return }
        isSyncingBridge = true
        defer { isSyncingBridge = false }
        switch contentType {
        case .instances:
            notchBridge.contentType = .instances
        case .menu:
            notchBridge.contentType = .menu
        case .chat(let session):
            notchBridge.contentType = .chat(session)
        }
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
