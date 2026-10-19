import AppKit
import StopTypingCore
import SwiftUI

extension Nudge {
    var title: LocalizedStringResource {
        switch self {
        case .gentle: "You're typing a lot."
        case .firm: "Still typing?"
        case .stop: "Time to stop typing"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .gentle: "Use dictation instead."
        case .firm: "Switch to your voice. It's faster."
        case .stop: "You kept typing after a nudge. Use dictation instead."
        }
    }

    var systemImage: String {
        switch self {
        case .gentle: "mic.fill"
        case .firm: "hand.raised.fill"
        case .stop: "exclamationmark.octagon.fill"
        }
    }
}

/// A short-lived, click-through overlay near the top of the screen the pointer is on.
/// It never takes focus, so it can't interrupt what's being typed.
@MainActor
final class NudgeHUD {
    /// Where the top of the nudge sits below the menu bar until the user drags it somewhere else.
    static let defaultOffset = CGSize(width: 0, height: 40)

    private let preferences: Preferences
    private lazy var panel = makePanel()
    private var dismissal: Task<Void, Never>?
    /// True while the HUD positions the panel itself, so only the user's drags are saved.
    private var isPositioning = false
    private var animates: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func show(_ nudge: Nudge) {
        let host = NSHostingView(rootView: NudgeView(nudge: nudge) { [weak self] hovering in
            self?.hoverChanged(hovering, nudge: nudge)
        })
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        if let visible = FrontmostWindow.screen?.visibleFrame {
            let offset = preferences.nudgeOffset ?? Self.defaultOffset
            let size = panel.frame.size
            isPositioning = true
            panel.setFrameOrigin(NSPoint(
                x: min(max(visible.midX + offset.width - size.width / 2, visible.minX), visible.maxX - size.width),
                y: min(max(visible.maxY - offset.height - size.height, visible.minY), visible.maxY - size.height)
            ))
            isPositioning = false
        }

        if !panel.isVisible {
            panel.alphaValue = animates ? 0 : 1
            panel.orderFrontRegardless()
        }
        scheduleDismissal(after: nudge == .gentle ? .seconds(3.5) : .seconds(5), fadeIn: true)
    }

    /// Hovering, and so dragging, keeps the nudge on screen; leaving it starts a short countdown.
    private func hoverChanged(_ hovering: Bool, nudge: Nudge) {
        if hovering {
            dismissal?.cancel()
            panel.alphaValue = 1
        } else {
            scheduleDismissal(after: .seconds(1.5), fadeIn: false)
        }
    }

    private func scheduleDismissal(after delay: Duration, fadeIn: Bool) {
        dismissal?.cancel()
        dismissal = Task {
            if fadeIn { await fade(to: 1) }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await fade(to: 0)
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func fade(to alpha: CGFloat) async {
        guard animates else {
            panel.alphaValue = alpha
            return
        }
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = alpha
        }
    }

    private func panelMoved() {
        guard !isPositioning, let visible = panel.screen?.visibleFrame else { return }
        preferences.nudgeOffset = CGSize(
            width: panel.frame.midX - visible.midX,
            height: visible.maxY - panel.frame.maxY
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        _ = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelMoved() }
        }
        return panel
    }
}

/// The nudge capsule. It can be dragged anywhere; clicks on the transparent margin pass through.
private struct NudgeView: View {
    let nudge: Nudge
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: nudge.systemImage)
                .font(.title2)
                .foregroundStyle(nudge == .gentle ? AnyShapeStyle(.tint) : AnyShapeStyle(.red))
                .symbolEffect(.bounce, options: .nonRepeating)
            VStack(alignment: .leading, spacing: 2) {
                Text(nudge.title)
                    .font(.headline)
                Text(nudge.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.separator))
        .contentShape(.capsule)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        .onHover(perform: onHover)
        .pointerStyle(.grabIdle)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(24)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
