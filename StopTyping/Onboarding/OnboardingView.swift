import AppKit
import StopTypingCore
import SwiftUI

/// Everything the app can ask macOS for, as one checklist with each row's live state.
/// Only Input Monitoring is required; the other rows are switches for features that need a permission.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Header()
            VStack(spacing: 0) {
                InputMonitoringRow()
                Divider()
                NotificationsRow()
                Divider()
                FocusRow()
                if model.updater.isAvailable {
                    Divider()
                    UpdatesRow()
                }
            }
            .background(.quinary, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            HStack {
                Spacer()
                Button("Later") { model.closeOnboarding() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { model.completeOnboarding() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasInputMonitoringPermission)
            }
        }
        .padding(24)
        .frame(width: 460)
        .task {
            // System Settings doesn't tell the app about a grant, so check while the checklist is open.
            while !Task.isCancelled {
                model.refreshPermission()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// The same red raised hand the nudges use.
private struct Header: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: Nudge.stop.systemImage)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.red.gradient, in: .circle)
                .accessibilityHidden(true)
            Text("Welcome to Stop Typing App")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Stop Typing App nudges you to dictate when you type out paragraphs. It counts characters; it never stores or sends what you type.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InputMonitoringRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ChecklistRow(
            isDone: model.hasInputMonitoringPermission,
            title: "Input Monitoring",
            badge: "Required",
            detail: "Lets Stop Typing App notice when you type in other apps."
        ) {
            if !model.hasInputMonitoringPermission {
                Button(model.preferences.hasRequestedInputMonitoring ? "Open System Settings…" : "Allow…") {
                    model.requestInputMonitoring()
                }
                .accessibilityHint("Allows Input Monitoring")
            } else if model.status == .unavailable {
                // The rare case where macOS still refuses the tap after the grant.
                Button("Relaunch") { model.relaunch() }
                    .accessibilityHint("Restarts Stop Typing App so it can start listening")
            } else {
                Text("Allowed")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NotificationsRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ChecklistRow(
            isDone: model.sendsNotifications,
            title: "Notifications",
            badge: "Optional",
            detail: "Also sends each nudge to Notification Center, so you can find it later."
        ) {
            Toggle("Notifications", isOn: $model.sendsNotifications)
                .toggleStyle(.switch)
                .labelsHidden()
        } footer: {
            if model.notificationsDenied {
                HStack(spacing: 8) {
                    Text("Notifications are turned off for Stop Typing App.")
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                    .buttonStyle(.link)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FocusRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ChecklistRow(
            isDone: model.isQuietDuringFocus,
            title: "Focus Status",
            badge: "Optional",
            detail: "Stays quiet during Do Not Disturb and other Focuses."
        ) {
            Toggle("Stay quiet during Focus", isOn: $model.isQuietDuringFocus)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

/// Off until the user turns it on, so out of the box the app makes no network connections.
private struct UpdatesRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var updater = model.updater
        ChecklistRow(
            isDone: updater.automaticallyChecksForUpdates,
            title: "Automatic Updates",
            badge: "Optional",
            detail: "Asks GitHub once a day for a newer version, sending the app's name and version and, like any web request, your IP address. Off means no network connections at all."
        ) {
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

/// A checkmark that fills in once the row is done, its title and explanation, and its own control.
private struct ChecklistRow<Accessory: View, Footer: View>: View {
    let isDone: Bool
    let title: LocalizedStringResource
    let badge: LocalizedStringResource
    let detail: LocalizedStringResource
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let footer: Footer

    var body: some View {
        HStack(spacing: 12) {
            // Hidden from VoiceOver: each row's control already says whether it's done.
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
                .animation(.default, value: isDone)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(badge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                footer
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(12)
        .accessibilityElement(children: .contain)
    }
}

extension ChecklistRow where Footer == EmptyView {
    init(
        isDone: Bool,
        title: LocalizedStringResource,
        badge: LocalizedStringResource,
        detail: LocalizedStringResource,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(isDone: isDone, title: title, badge: badge, detail: detail, accessory: accessory, footer: { EmptyView() })
    }
}
