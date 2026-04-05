# Floating Buddy Pet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a floating buddy pet UI mode as an alternative to the notch-based interface.

**Architecture:** A draggable 48×48 `NSPanel` renders the user's buddy with a glow ring indicating session state. Clicking expands to a 320×400 panel reusing existing `ClaudeInstancesView` and `ChatView`. `BuddyPanelViewModel` owns all state; `AppDelegate` and `WindowManager` are modified to support both UI modes.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSPanel), Combine

---

### Task 1: BuddyPanelViewModel — Core State

**Files:**
- Create: `ClaudeIsland/Core/BuddyPanelViewModel.swift`

This is the central state object for the floating buddy. It tracks expanded/collapsed, content type, glow color, and position.

- [ ] **Step 1: Create BuddyPanelViewModel**

```swift
// BuddyPanelViewModel.swift

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

    init(sessionMonitor: ClaudeSessionMonitor = .shared) {
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
```

- [ ] **Step 2: Add to Xcode project**

Open `ClaudeIsland.xcodeproj` and verify the file is included in the ClaudeIsland target (it should auto-include via folder reference).

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ClaudeIsland/Core/BuddyPanelViewModel.swift
git commit -m "feat: add BuddyPanelViewModel with glow state and position persistence"
```

---

### Task 2: BuddyGlowRing — Animated Glow Component

**Files:**
- Create: `ClaudeIsland/UI/Components/BuddyGlowRing.swift`

A reusable SwiftUI view that renders a colored glow ring around its content, with optional pulsing animation.

- [ ] **Step 1: Create BuddyGlowRing**

```swift
// BuddyGlowRing.swift

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
                    .stroke(glowState.color, lineWidth: 2)
                    .blur(radius: 4)
                    .opacity(glowState == .idle ? 0 : (isPulsing ? 0.4 : 1.0))
            )
            .overlay(
                Circle()
                    .stroke(glowState.color, lineWidth: 1)
                    .opacity(glowState == .idle ? 0 : 0.6)
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
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ClaudeIsland/UI/Components/BuddyGlowRing.swift
git commit -m "feat: add BuddyGlowRing animated glow component"
```

---

### Task 3: BuddyFloatingView — The 48×48 Buddy Widget

**Files:**
- Create: `ClaudeIsland/UI/Views/BuddyFloatingView.swift`

The collapsed buddy view: renders the buddy emoji/ASCII inside a glow ring, handles drag gestures.

- [ ] **Step 1: Create BuddyFloatingView**

```swift
// BuddyFloatingView.swift

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

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation
                viewModel.position = CGPoint(
                    x: viewModel.position.x + value.translation.width,
                    y: viewModel.position.y - value.translation.height // macOS Y is flipped
                )
                dragOffset = .zero
            }
            .onEnded { _ in
                // Delay resetting isDragging so the tap doesn't fire
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isDragging = false
                }
            }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ClaudeIsland/UI/Views/BuddyFloatingView.swift
git commit -m "feat: add BuddyFloatingView with drag and glow"
```

---

### Task 4: BuddyPanelView — Expanded Panel

**Files:**
- Create: `ClaudeIsland/UI/Views/BuddyPanelView.swift`

The expanded panel that shows when you click the buddy. Contains session list and chat, reusing existing views.

- [ ] **Step 1: Create BuddyPanelView**

```swift
// BuddyPanelView.swift

import SwiftUI

struct BuddyPanelView: View {
    @ObservedObject var viewModel: BuddyPanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            panelHeader

            Divider()
                .background(Color.white.opacity(0.1))

            // Content
            switch viewModel.contentType {
            case .instances:
                ClaudeInstancesView(
                    sessionMonitor: viewModel.sessionMonitor,
                    viewModel: panelBridge
                )
            case .chat(let session):
                ChatView(
                    sessionId: session.sessionId,
                    initialSession: session,
                    sessionMonitor: viewModel.sessionMonitor,
                    viewModel: panelBridge
                )
            }
        }
        .frame(width: viewModel.panelSize.width, height: viewModel.panelSize.height)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.4), radius: 12)
    }

    private var panelHeader: some View {
        HStack {
            if case .chat = viewModel.contentType {
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        viewModel.exitChat()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Sessions")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            } else {
                Text("Code Island")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            // Session count badge
            let count = viewModel.sessionMonitor.instances.filter { $0.phase != .ended }.count
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // Bridge to reuse existing views that expect NotchViewModel
    private var panelBridge: NotchViewModel {
        // We need a lightweight bridge — existing views use NotchViewModel
        // for showChat/exitChat. We'll create a shared bridge instance.
        BuddyNotchBridge.shared.buddyViewModel = viewModel
        return BuddyNotchBridge.shared.notchViewModel
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Bridge between BuddyPanelViewModel and NotchViewModel

/// Bridges BuddyPanelViewModel actions to NotchViewModel interface
/// so existing ClaudeInstancesView and ChatView work without modification
@MainActor
class BuddyNotchBridge {
    static let shared = BuddyNotchBridge()
    weak var buddyViewModel: BuddyPanelViewModel?

    lazy var notchViewModel: NotchViewModel = {
        // Create a minimal NotchViewModel that forwards to buddy
        let vm = NotchViewModel(
            deviceNotchRect: .zero,
            screenRect: NSScreen.main?.frame ?? .zero,
            windowHeight: 500,
            hasPhysicalNotch: false
        )
        // Override showChat/exitChat via Combine
        return vm
    }()

    private init() {}
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" build 2>&1 | grep -E "error:|BUILD"`

Expected: May have compilation issues due to `NotchViewModel` bridge — fix in next step.

- [ ] **Step 3: Commit**

```bash
git add ClaudeIsland/UI/Views/BuddyPanelView.swift
git commit -m "feat: add BuddyPanelView with session list and chat"
```

---

### Task 5: BuddyWindowController — Window Management

**Files:**
- Create: `ClaudeIsland/UI/Window/BuddyWindowController.swift`

Creates and manages the floating NSPanel, handles expand/collapse window resizing, click-outside dismissal.

- [ ] **Step 1: Create BuddyWindowController**

```swift
// BuddyWindowController.swift

import AppKit
import Combine
import SwiftUI

class BuddyWindowController: NSWindowController {
    let viewModel: BuddyPanelViewModel
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?

    init() {
        let vm = BuddyPanelViewModel()
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
                self?.updateWindowSize(expanded: expanded)
            }
            .store(in: &cancellables)

        // Monitor clicks outside to dismiss panel
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, self.viewModel.isExpanded else { return }
            guard let window = self.window else { return }

            let clickLocation = event.locationInWindow
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
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ClaudeIsland/UI/Window/BuddyWindowController.swift
git commit -m "feat: add BuddyWindowController with floating panel"
```

---

### Task 6: Settings — UI Mode Toggle

**Files:**
- Modify: `ClaudeIsland/Core/Settings.swift`

Add a setting to choose between notch mode and floating buddy mode.

- [ ] **Step 1: Add UIMode to Settings.swift**

Add this enum and setting to `Settings.swift`:

```swift
enum UIMode: String {
    case notch = "notch"
    case floatingBuddy = "floatingBuddy"
}

// Inside AppSettings struct, add:
static var uiMode: UIMode {
    get {
        let raw = UserDefaults.standard.string(forKey: "uiMode") ?? UIMode.notch.rawValue
        return UIMode(rawValue: raw) ?? .notch
    }
    set {
        UserDefaults.standard.set(newValue.rawValue, forKey: "uiMode")
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ClaudeIsland/Core/Settings.swift
git commit -m "feat: add UIMode setting for notch vs floating buddy"
```

---

### Task 7: AppDelegate & WindowManager — Wire Up Buddy Mode

**Files:**
- Modify: `ClaudeIsland/App/AppDelegate.swift`
- Modify: `ClaudeIsland/App/WindowManager.swift`

Launch the correct window type based on the UI mode setting.

- [ ] **Step 1: Update WindowManager to support both modes**

Replace `WindowManager.swift` content:

```swift
import AppKit
import os.log

private let logger = Logger(subsystem: "com.codeisland", category: "Window")

class WindowManager {
    private(set) var notchWindowController: NotchWindowController?
    private(set) var buddyWindowController: BuddyWindowController?

    var windowController: NotchWindowController? { notchWindowController }

    func setupWindow() {
        switch AppSettings.uiMode {
        case .notch:
            setupNotchWindow()
        case .floatingBuddy:
            setupBuddyWindow()
        }
    }

    @discardableResult
    func setupNotchWindow() -> NotchWindowController? {
        // Close buddy window if switching
        buddyWindowController?.window?.close()
        buddyWindowController = nil

        let screenSelector = ScreenSelector.shared
        screenSelector.refreshScreens()

        guard let screen = screenSelector.selectedScreen else {
            logger.warning("No screen found")
            return nil
        }

        if let existing = notchWindowController {
            existing.window?.orderOut(nil)
            existing.window?.close()
            notchWindowController = nil
        }

        notchWindowController = NotchWindowController(screen: screen)
        notchWindowController?.showWindow(nil)

        return notchWindowController
    }

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
```

- [ ] **Step 2: Update AppDelegate to use setupWindow()**

In `AppDelegate.swift`, change `applicationDidFinishLaunching`:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    if !ensureSingleInstance() {
        NSApplication.shared.terminate(nil)
        return
    }

    HookInstaller.installIfNeeded()
    NSApplication.shared.setActivationPolicy(.accessory)

    windowManager = WindowManager()
    windowManager?.setupWindow()

    screenObserver = ScreenObserver { [weak self] in
        self?.handleScreenChange()
    }
}
```

Update `handleScreenChange`:

```swift
private func handleScreenChange() {
    if Date().timeIntervalSince(TerminalJumper.lastJumpTime) < 5.0 {
        DebugLogger.log("Screen", "didChangeScreenParameters — skipped (jump cooldown)")
        return
    }
    // Only recreate window for notch mode (buddy doesn't depend on screen)
    if AppSettings.uiMode == .notch {
        DebugLogger.log("Screen", "didChangeScreenParameters — recreating window")
        _ = windowManager?.setupNotchWindow()
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ClaudeIsland/App/AppDelegate.swift ClaudeIsland/App/WindowManager.swift
git commit -m "feat: wire up buddy mode in AppDelegate and WindowManager"
```

---

### Task 8: Integration — Fix Bridge and Test End-to-End

**Files:**
- Modify: `ClaudeIsland/UI/Views/BuddyPanelView.swift` (fix bridge compilation issues)
- Modify: `ClaudeIsland/Core/Settings.swift` (set default to floatingBuddy for testing)

This task fixes any compilation issues from the bridge between `BuddyPanelViewModel` and the existing views that expect `NotchViewModel`, and does a full end-to-end test.

- [ ] **Step 1: Set default UI mode to floating buddy for testing**

In `Settings.swift`, temporarily change the default:

```swift
static var uiMode: UIMode {
    get {
        let raw = UserDefaults.standard.string(forKey: "uiMode") ?? UIMode.floatingBuddy.rawValue
        return UIMode(rawValue: raw) ?? .floatingBuddy
    }
    // ...
}
```

- [ ] **Step 2: Build and fix any compilation errors**

Run: `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" build 2>&1 | grep "error:"`

Fix each error. Common issues:
- `NotchViewModel` initializer requirements — the bridge may need adjustment
- `ClaudeInstancesView` / `ChatView` expecting specific `NotchViewModel` methods
- Missing imports

- [ ] **Step 3: Build, install, and test**

```bash
xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" build 2>&1 | grep -E "error:|BUILD"
pkill -x "Code Island" 2>/dev/null; sleep 1
rm -rf "/Applications/Code Island.app"
cp -R "$(xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Release -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/Code Island.app" "/Applications/Code Island.app"
open "/Applications/Code Island.app"
```

- [ ] **Step 4: Manual testing checklist**

Verify:
- Buddy appears as a 48×48 floating widget
- Buddy can be dragged around the screen
- Clicking buddy expands the panel
- Panel shows session list
- Clicking a session shows chat
- Clicking outside panel collapses it
- Glow changes color when session is processing
- Position persists after relaunch

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: integration fixes and end-to-end floating buddy"
```

---

### Task 9: Cleanup — Remove Debug Logging and Set Default

**Files:**
- Modify: `ClaudeIsland/Core/Settings.swift` (set default back to notch)
- Modify: `ClaudeIsland/Core/NotchViewModel.swift` (remove debug logging from notch work)
- Modify: `ClaudeIsland/Core/NotchActivityCoordinator.swift` (remove debug logging)

- [ ] **Step 1: Set UI mode default back to notch**

In `Settings.swift`, change default back:

```swift
let raw = UserDefaults.standard.string(forKey: "uiMode") ?? UIMode.notch.rawValue
```

- [ ] **Step 2: Remove temporary debug logging**

Remove `DebugLogger.log("Notch", ...)` lines from `NotchViewModel.swift` and `DebugLogger.log("Activity", ...)` from `NotchActivityCoordinator.swift` that were added for debugging.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" build 2>&1 | grep -E "error:|BUILD"`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: cleanup debug logging, set notch as default UI mode"
```
