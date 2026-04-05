//
//  BuddyPanelView.swift
//  ClaudeIsland
//
//  Expanded panel shown when clicking the floating buddy
//

import Combine
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
/// so existing ClaudeInstancesView and ChatView work without modification.
///
/// The bridge creates a NotchViewModel and keeps it in "opened" state so
/// child views render their content. Actions like showChat/exitChat on the
/// bridge NotchViewModel are observed and forwarded to BuddyPanelViewModel.
@MainActor
class BuddyNotchBridge {
    static let shared = BuddyNotchBridge()
    weak var buddyViewModel: BuddyPanelViewModel?

    private var cancellables = Set<AnyCancellable>()

    lazy var notchViewModel: NotchViewModel = {
        // Create a minimal NotchViewModel with dummy geometry
        let vm = NotchViewModel(
            deviceNotchRect: .zero,
            screenRect: NSScreen.main?.frame ?? .zero,
            windowHeight: 500,
            hasPhysicalNotch: false
        )
        // Keep it in opened state so child views render content
        vm.status = .opened

        // Forward contentType changes back to buddyViewModel
        vm.$contentType
            .receive(on: DispatchQueue.main)
            .sink { [weak self] contentType in
                guard let buddy = self?.buddyViewModel else { return }
                switch contentType {
                case .chat(let session):
                    buddy.showChat(for: session)
                case .instances:
                    // Only forward if buddy is currently showing chat
                    // (avoids loops when buddy sets instances itself)
                    if case .chat = buddy.contentType {
                        buddy.exitChat()
                    }
                case .menu:
                    break // Buddy panel doesn't support menu
                }
            }
            .store(in: &cancellables)

        return vm
    }()

    private init() {}
}
