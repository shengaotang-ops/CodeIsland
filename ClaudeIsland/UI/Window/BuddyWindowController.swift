//
//  BuddyWindowController.swift
//  ClaudeIsland
//
//  Creates and manages the floating buddy and its panel as separate windows.
//

import AppKit
import Combine
import SwiftUI

class BuddyWindowController: NSWindowController {
    let viewModel: BuddyPanelViewModel
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?
    private var panelWindow: NSPanel?

    init() {
        let sessionMonitor = ClaudeSessionMonitor()
        sessionMonitor.startMonitoring()
        let vm = BuddyPanelViewModel(sessionMonitor: sessionMonitor)
        self.viewModel = vm

        let buddySize = BuddyPanelViewModel.buddySize + 12

        // Create the buddy window (always small, always visible)
        let buddyPanel = NSPanel(
            contentRect: NSRect(
                origin: CGPoint(x: vm.position.x, y: vm.position.y),
                size: CGSize(width: buddySize, height: buddySize)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        buddyPanel.level = .floating
        buddyPanel.isOpaque = false
        buddyPanel.backgroundColor = .clear
        buddyPanel.hasShadow = false
        buddyPanel.isMovable = false
        buddyPanel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        buddyPanel.isFloatingPanel = true
        buddyPanel.becomesKeyOnlyIfNeeded = true

        super.init(window: buddyPanel)

        // Set buddy SwiftUI content
        let buddyView = BuddyFloatingView(viewModel: vm, buddyReader: BuddyReader.shared)
        buddyPanel.contentView = NSHostingView(rootView: buddyView)

        // Direct window move callback for zero-lag drag
        vm.moveWindow = { [weak buddyPanel] pos in
            buddyPanel?.setFrameOrigin(pos)
        }

        // Observe expand/collapse to show/hide panel window
        vm.$isExpanded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded in
                if expanded {
                    self?.showPanelWindow()
                } else {
                    self?.hidePanelWindow()
                }
            }
            .store(in: &cancellables)

        // Monitor clicks outside to dismiss panel
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self, self.viewModel.isExpanded else { return }
            guard Date().timeIntervalSince(self.viewModel.lastExpandTime) > 0.5 else { return }

            let screenLocation = NSEvent.mouseLocation
            let buddyFrame = self.window?.frame ?? .zero
            let panelFrame = self.panelWindow?.frame ?? .zero

            if !buddyFrame.contains(screenLocation) && !panelFrame.contains(screenLocation) {
                DispatchQueue.main.async {
                    self.viewModel.collapse()
                }
            }
        }

        // Monitor escape key to dismiss
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 && self?.viewModel.isExpanded == true {
                self?.viewModel.collapse()
                return nil
            }
            return event
        }

        // Collapse panel when user jumps to terminal
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self, self.viewModel.isExpanded else { return }
            if Date().timeIntervalSince(TerminalJumper.lastJumpTime) < 0.5 {
                Task { @MainActor in
                    self.viewModel.collapse()
                }
            }
        }

        // Load buddy data
        BuddyReader.shared.reload()

        // Auto-popup: when a session transitions from processing → waitingForInput
        // and the user isn't focused on that session's terminal, expand and show chat
        setupNotificationPopup(sessionMonitor: sessionMonitor)
    }

    // MARK: - Notification Popup

    private var previousPhases: [String: SessionPhase] = [:]
    private var previousWaitingIds: Set<String> = []

    private func setupNotificationPopup(sessionMonitor: ClaudeSessionMonitor) {
        sessionMonitor.$instances
            .receive(on: DispatchQueue.main)
            .sink { [weak self] instances in
                self?.handleSessionChanges(instances)
            }
            .store(in: &cancellables)
    }

    private func handleSessionChanges(_ instances: [SessionState]) {
        let waitingSessions = instances.filter { $0.phase == .waitingForInput }
        let currentWaitingIds = Set(waitingSessions.map { $0.stableId })
        let newlyWaitingIds = currentWaitingIds.subtracting(previousWaitingIds)

        if !newlyWaitingIds.isEmpty {
            let newlyWaiting = waitingSessions.filter { newlyWaitingIds.contains($0.stableId) }
            DebugLogger.log("Buddy", "newlyWaiting=\(newlyWaiting.count) ids=\(newlyWaitingIds)")

            // Only popup for sessions that transitioned FROM processing/compacting
            let fromWorking = newlyWaiting.filter { session in
                let prev = previousPhases[session.stableId]
                DebugLogger.log("Buddy", "session=\(session.projectName) prevPhase=\(prev.map { "\($0)" } ?? "nil") curPhase=\(session.phase)")
                guard let prev = prev else { return false }
                return prev == .processing || prev == .compacting
            }

            // Suppress if user recently jumped to terminal
            let recentJump = Date().timeIntervalSince(TerminalJumper.lastJumpTime) < 3.0

            // Only popup for unfocused sessions
            let unfocused = fromWorking.filter { session in
                let isFront = TerminalVisibilityDetector.isSessionTerminalFrontmost(session)
                DebugLogger.log("Buddy", "focusCheck session=\(session.projectName) isFront=\(isFront)")
                return !isFront
            }

            DebugLogger.log("Buddy", "fromWorking=\(fromWorking.count) recentJump=\(recentJump) unfocused=\(unfocused.count)")

            if !recentJump && !unfocused.isEmpty {
                let session = unfocused[0]

                // Play notification sound
                if let soundName = AppSettings.notificationSound.soundName {
                    NSSound(named: soundName)?.play()
                }

                // Auto-expand panel with that session's chat after a brief delay
                Task { [weak self] in
                    await ChatHistoryManager.shared.forceReloadFromFile(
                        sessionId: session.sessionId,
                        cwd: session.cwd
                    )
                    try? await Task.sleep(for: .seconds(1))

                    guard let self = self else { return }
                    guard self.viewModel.sessionMonitor.instances.contains(where: {
                        $0.stableId == session.stableId && $0.phase == .waitingForInput
                    }) else { return }

                    if let current = self.viewModel.sessionMonitor.instances.first(where: {
                        $0.stableId == session.stableId
                    }) {
                        DebugLogger.log("Buddy", "Auto-popup for \(session.projectName)")
                        self.viewModel.expand()
                        self.viewModel.showChat(for: current)
                    }
                }
            }
        }

        // Update tracking state
        previousWaitingIds = currentWaitingIds
        for instance in instances {
            previousPhases[instance.stableId] = instance.phase
        }
        // Clean up stale entries
        let currentIds = Set(instances.map { $0.stableId })
        for key in previousPhases.keys where !currentIds.contains(key) {
            previousPhases.removeValue(forKey: key)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Panel Window

    private func showPanelWindow() {
        let panelSize = viewModel.panelSize
        let buddySize = BuddyPanelViewModel.buddySize + 12

        // Position panel above the buddy, centered horizontally
        let buddyCenterX = viewModel.position.x + buddySize / 2
        let originX = buddyCenterX - panelSize.width / 2
        let originY = viewModel.position.y + buddySize + 8

        // Clamp to screen bounds
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let clampedX = max(screen.minX, min(originX, screen.maxX - panelSize.width))
        let clampedY = max(screen.minY, min(originY, screen.maxY - panelSize.height))

        // Recreate panel each time for fresh SwiftUI gesture state
        panelWindow?.orderOut(nil)
        panelWindow = nil

        let panel = InteractivePanel(
            contentRect: NSRect(x: clampedX, y: clampedY,
                                width: panelSize.width, height: panelSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isFloatingPanel = true

        let panelView = BuddyPanelView(viewModel: viewModel)
        panel.contentView = NSHostingView(rootView: panelView)
        panelWindow = panel

        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanelWindow() {
        panelWindow?.orderOut(nil)
        panelWindow = nil
    }
}

// MARK: - Interactive Panel

/// NSPanel subclass that can become key window, enabling button clicks
/// and other interactive controls inside the panel.
/// NSPanel subclass that accepts clicks immediately without needing
/// the app to be active first. On first click, it makes itself key
/// and re-delivers the event so buttons respond on the first tap.
class InteractivePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            // Activate app + make key before SwiftUI processes the gesture
            makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
        super.sendEvent(event)
    }
}
