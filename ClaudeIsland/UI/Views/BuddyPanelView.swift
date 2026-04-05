//
//  BuddyPanelView.swift
//  ClaudeIsland
//
//  Expanded panel shown when clicking the floating buddy
//

import SwiftUI

struct BuddyPanelView: View {
    @ObservedObject var viewModel: BuddyPanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            panelHeader

            Divider()
                .background(Color.white.opacity(0.1))

            // Content — child views bind to the notch bridge owned by viewModel
            switch viewModel.contentType {
            case .instances:
                ClaudeInstancesView(
                    sessionMonitor: viewModel.sessionMonitor,
                    viewModel: viewModel.notchBridge
                )
            case .menu:
                NotchMenuView(viewModel: viewModel.notchBridge)
            case .chat(let session):
                ChatView(
                    sessionId: session.sessionId,
                    initialSession: session,
                    sessionMonitor: viewModel.sessionMonitor,
                    viewModel: viewModel.notchBridge
                )
            }
        }
        .frame(width: viewModel.panelSize.width, height: viewModel.panelSize.height)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.4), radius: 12)
    }

    private var panelHeader: some View {
        HStack {
            if viewModel.contentType != .instances {
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        viewModel.contentType = .instances
                        viewModel.syncBridgeContentType()
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
