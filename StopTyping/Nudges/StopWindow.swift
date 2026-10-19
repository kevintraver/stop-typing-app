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

/// Styled as a bigger sibling of the on-screen nudge: the same material, hairline and red raised hand.
private struct StopView: View {
    let app: AppInfo?
    let dismiss: (StopWindow.Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: Nudge.stop.systemImage)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.red.gradient, in: .circle)
                    .symbolEffect(.bounce, options: .nonRepeating, value: hasAppeared)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Nudge.stop.title)
                        .font(.title3.weight(.semibold))
                    Text(Nudge.stop.message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                if let app {
                    Button("Ignore \(app.name)") { dismiss(.ignore) }
                        .buttonStyle(PillButtonStyle(kind: .quiet))
                }
                Spacer(minLength: 12)
                Button("Snooze 15 Min") { dismiss(.snooze) }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                    .accessibilityLabel("Snooze 15 minutes")
                Button("Got It") { dismiss(.acknowledge) }
                    .buttonStyle(PillButtonStyle(kind: .primary))
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(.regularMaterial, in: .rect(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
        .opacity(hasAppeared ? 1 : 0)
        .padding(32)
        .onAppear {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { hasAppeared = true }
        }
    }
}

/// Capsule buttons that keep their colors even when the panel isn't the active window,
/// unlike the system styles, which turn grey there.
private struct PillButtonStyle: ButtonStyle {
    enum Kind {
        /// Red, the action we want: acknowledge and go dictate.
        case primary
        case secondary
        /// No fill until hovered, for the opt-out.
        case quiet
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, kind: kind)
    }
}

private struct PillButton: View {
    let configuration: ButtonStyleConfiguration
    let kind: PillButtonStyle.Kind

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(kind == .primary ? .body.weight(.semibold) : .body)
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(background, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.capsule)
            .onHover { isHovered = $0 }
    }

    private var foreground: AnyShapeStyle {
        switch kind {
        case .primary: AnyShapeStyle(.white)
        case .secondary: AnyShapeStyle(.primary)
        case .quiet: AnyShapeStyle(.secondary)
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary: AnyShapeStyle(Color.red.opacity(isHovered ? 0.85 : 1))
        case .secondary: AnyShapeStyle(isHovered ? .tertiary : .quaternary)
        case .quiet: AnyShapeStyle(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        }
    }
}
