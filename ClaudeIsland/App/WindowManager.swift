//
//  WindowManager.swift
//  ClaudeIsland
//
//  Manages the notch window lifecycle
//

import AppKit
import os.log

/// Logger for window management
private let logger = Logger(subsystem: "com.codeisland", category: "Window")

class WindowManager {
    private(set) var notchWindowController: NotchWindowController?
    private(set) var buddyWindowController: BuddyWindowController?

    /// Backward-compatible accessor for code that references windowController
    var windowController: NotchWindowController? { notchWindowController }

    /// Set up the window based on the current UI mode setting
    func setupWindow() {
        switch AppSettings.uiMode {
        case .notch:
            setupNotchWindow()
        case .floatingBuddy:
            setupBuddyWindow()
        }
    }

    /// Set up or recreate the notch window
    @discardableResult
    func setupNotchWindow() -> NotchWindowController? {
        // Close buddy window if switching
        buddyWindowController?.window?.close()
        buddyWindowController = nil

        // Use ScreenSelector for screen selection
        let screenSelector = ScreenSelector.shared
        screenSelector.refreshScreens()

        guard let screen = screenSelector.selectedScreen else {
            logger.warning("No screen found")
            return nil
        }

        if let existingController = notchWindowController {
            existingController.window?.orderOut(nil)
            existingController.window?.close()
            notchWindowController = nil
        }

        notchWindowController = NotchWindowController(screen: screen)
        notchWindowController?.showWindow(nil)

        return notchWindowController
    }

    /// Set up the floating buddy window
    func setupBuddyWindow() {
        // Close notch window if switching
        notchWindowController?.window?.orderOut(nil)
        notchWindowController?.window?.close()
        notchWindowController = nil

        if buddyWindowController == nil {
            buddyWindowController = BuddyWindowController()
        }
        buddyWindowController?.showWindow(nil)
        buddyWindowController?.window?.orderFrontRegardless()
    }
}
