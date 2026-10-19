import AppKit
import StopTypingCore
import SwiftUI

/// The opt-in last resort: a centered window that takes focus until it's clicked away.
/// Its buttons have no keyboard shortcuts, so typing straight through it can't dismiss it.
@MainActor
final class StopWindow {
    enum Action {
        case acknowledge, snooze, ignore
    }

    private var panel: NSPanel?
    /// Where focus goes back to once the window is dismissed.
    private var previousApp: NSRunningApplication?

    var isShowing: Bool { panel != nil }

    /// - Parameter app: The app being typed in, offered as "Ignore <app>". Nil hides that button.
    func show(ignoring app: AppInfo?, onDismiss: @escaping @MainActor (Action) -> Void) {
        guard panel == nil else { return }
        previousApp = NSWorkspace.shared.frontmostApplication

        let host = NSHostingView(rootView: StopView(app: app) { [weak self] action in
            self?.dismiss()
            onDismiss(action)
        })
        let panel = FocusablePanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.level = .modalPanel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let visible = FrontmostWindow.screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.midY - panel.frame.height / 2
            ))
        }

        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        if let previousApp, previousApp != .current {
            previousApp.activate()
        }
        previousApp = nil
    }
}

/// Borderless panels refuse key status by default; this one needs it to hold focus.
private final class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct StopView: View {
    let app: AppInfo?
    let dismiss: (StopWindow.Action) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: Nudge.stop.systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.red)
                .symbolEffect(.bounce, options: .nonRepeating)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(Nudge.stop.title)
                    .font(.title2.bold())
                Text(Nudge.stop.message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) {
                Button("Got It") { dismiss(.acknowledge) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                HStack {
                    Button("Snooze 15 Minutes") { dismiss(.snooze) }
                    if let app {
                        Button("Ignore \(app.name)") { dismiss(.ignore) }
                    }
                }
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 380)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .padding(32)
    }
}
