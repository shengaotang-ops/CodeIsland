//
//  BuddyWindowController.swift
//  ClaudeIsland
//
//  Creates and manages the floating NSPanel for buddy mode
//

import AppKit
import Combine
import SwiftUI

class BuddyWindowController: NSWindowController {
    let viewModel: BuddyPanelViewModel
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?
    private var lastExpandTime: Date = .distantPast

    init() {
        let sessionMonitor = ClaudeSessionMonitor()
        let vm = BuddyPanelViewModel(sessionMonitor: sessionMonitor)
        self.viewModel = vm

        // Create the floating panel
        let panel = NSPanel(
            contentRect: NSRect(
                origin: CGPoint(x: vm.position.x, y: vm.position.y),
                size: CGSize(width: BuddyPanelViewModel.buddySize + 12,
                             height: BuddyPanelViewModel.buddySize + 12)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true

        super.init(window: panel)

        // Set SwiftUI content
        let rootView = BuddyRootView(viewModel: vm)
        panel.contentView = NSHostingView(rootView: rootView)

        // Observe position changes to move window
        vm.$position
            .receive(on: DispatchQueue.main)
            .sink { [weak panel] pos in
                guard let panel = panel else { return }
                panel.setFrameOrigin(pos)
            }
            .store(in: &cancellables)

        // Observe expand/collapse to resize window
        vm.$isExpanded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded in
                if expanded {
                    self?.lastExpandTime = Date()
                }
                self?.updateWindowSize(expanded: expanded)
            }
            .store(in: &cancellables)

        // Monitor clicks outside to dismiss panel
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, self.viewModel.isExpanded else { return }
            // Ignore clicks within 0.5s of expanding (the click that opened the panel)
            guard Date().timeIntervalSince(self.lastExpandTime) > 0.5 else { return }
            guard let window = self.window else { return }

            let screenLocation = NSEvent.mouseLocation
            let windowFrame = window.frame

            if !windowFrame.contains(screenLocation) {
                DispatchQueue.main.async {
                    self.viewModel.collapse()
                }
            }
        }

        // Monitor escape key to dismiss
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 && self?.viewModel.isExpanded == true { // Escape
                self?.viewModel.collapse()
                return nil
            }
            return event
        }

        // Load buddy data
        BuddyReader.shared.reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func updateWindowSize(expanded: Bool) {
        guard let panel = window else { return }

        if expanded {
            let panelSize = viewModel.panelSize
            let buddySize = BuddyPanelViewModel.buddySize + 12
            // Panel appears above the buddy
            let newOrigin = CGPoint(
                x: viewModel.position.x - (panelSize.width - buddySize) / 2,
                y: viewModel.position.y + buddySize + 8
            )
            // Clamp to screen bounds
            let screen = NSScreen.main?.visibleFrame ?? .zero
            let clampedX = max(screen.minX, min(newOrigin.x, screen.maxX - panelSize.width))
            let clampedY = max(screen.minY, min(newOrigin.y, screen.maxY - panelSize.height))

            let totalHeight = panelSize.height + buddySize + 8
            panel.setFrame(
                NSRect(x: clampedX, y: viewModel.position.y,
                       width: panelSize.width, height: totalHeight),
                display: true,
                animate: true
            )
            panel.hasShadow = true
        } else {
            let buddySize = BuddyPanelViewModel.buddySize + 12
            panel.setFrame(
                NSRect(origin: viewModel.position,
                       size: CGSize(width: buddySize, height: buddySize)),
                display: true,
                animate: true
            )
            panel.hasShadow = false
        }
    }
}

// MARK: - Root View (switches between buddy and buddy+panel)

struct BuddyRootView: View {
    @ObservedObject var viewModel: BuddyPanelViewModel
    @ObservedObject var buddyReader = BuddyReader.shared

    var body: some View {
        VStack(spacing: 8) {
            if viewModel.isExpanded {
                BuddyPanelView(viewModel: viewModel)
            }

            BuddyFloatingView(viewModel: viewModel, buddyReader: buddyReader)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
