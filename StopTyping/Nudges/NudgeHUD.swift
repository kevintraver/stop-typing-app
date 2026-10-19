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
        case .stop: "hand.raised.fill"
        }
    }
}

/// A short-lived overlay near the top of the screen you're typing on. It never takes focus, so it
/// can't interrupt what's being typed. It fades on its own, or goes at once with Esc, a click, or its ✕.
@MainActor
final class NudgeHUD {
    /// Where the top of the nudge sits below the menu bar until the user drags it somewhere else.
    static let defaultOffset = CGSize(width: 0, height: 40)

    private let preferences: Preferences
    private lazy var panel = makePanel()
    private var dismissal: Task<Void, Never>?
    /// True while the HUD positions the panel itself, so only the user's drags are saved.
    private var isPositioning = false
    /// When the user last dragged the nudge, so the click that ends a drag doesn't also dismiss it.
    private var lastDragged: ContinuousClock.Instant?
    private var animates: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func show(_ nudge: Nudge) {
        let host = NSHostingView(rootView: NudgeView(
            nudge: nudge,
            onHover: { [weak self] hovering in self?.hoverChanged(hovering, nudge: nudge) },
            onClick: { [weak self] in self?.clicked() },
            onDismiss: { [weak self] in self?.dismiss() }
        ))
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

    /// Hides the nudge now, if it's showing.
    func dismiss() {
        guard panel.isVisible else { return }
        dismissal?.cancel()
        dismissal = Task {
            await fade(to: 0)
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    /// A drag moves the window under the pointer, so it ends looking like a click. Only a click
    /// that didn't just finish a drag dismisses.
    private func clicked() {
        if let lastDragged, ContinuousClock.now - lastDragged < .milliseconds(400) { return }
        dismiss()
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
        lastDragged = .now
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

/// The nudge capsule. Drag it anywhere, click it or its ✕ to dismiss; clicks on the transparent
/// margin pass through.
private struct NudgeView: View {
    let nudge: Nudge
    let onHover: (Bool) -> Void
    let onClick: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

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
            // Always laid out so the capsule doesn't change size when the ✕ appears on hover.
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.separator))
        .contentShape(.capsule)
        .gesture(WindowDragGesture())
        .simultaneousGesture(TapGesture().onEnded(onClick))
        .allowsWindowActivationEvents(true)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .pointerStyle(.grabIdle)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(24)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Dismiss", onDismiss)
    }
}
