import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header()
            switch model.status {
            case .needsPermission, .unavailable:
                Divider()
                PermissionCallout()
            case .off, .snoozed, .listening:
                EmptyView()
            }
            Divider()
            TodayStats()
            Divider()
            SnoozeControls()
            if let app = model.recentApp {
                Divider()
                RecentAppToggle(app: app)
            }
            Divider()
            Footer()
        }
        .frame(width: 300)
    }
}

private struct Header: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stop Typing App")
                    .font(.headline)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Watch for long typing", isOn: $model.isWatching)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(16)
    }

    private var statusText: String {
        switch model.status {
        case .listening: String(localized: "Watching for long typing")
        case .off: String(localized: "Paused")
        case .needsPermission: String(localized: "Needs Input Monitoring permission")
        case .unavailable: String(localized: "Couldn't start listening")
        case .snoozed: model.snoozeDescription ?? ""
        }
    }
}

private struct PermissionCallout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.status == .unavailable {
                Text("Input Monitoring is on, but macOS needs Stop Typing App to restart before it can listen.")
                Button("Relaunch Stop Typing App") { model.relaunch() }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("Allow Stop Typing App in Privacy & Security → Input Monitoring. It only counts characters and never stores what you type.")
                HStack {
                    Button("Open Privacy Settings") { NSWorkspace.shared.open(KeyboardTap.privacySettingsURL) }
                        .buttonStyle(.borderedProminent)
                    Button("Set Up…") { model.showOnboarding() }
                        .accessibilityHint("Opens the setup checklist")
                }
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
    }
}

private struct TodayStats: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let today = model.preferences.stats.on(.now)
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Stat(value: today.nudges.formatted(), label: today.nudges == 1 ? "nudge" : "nudges")
                Stat(value: "≈ \(today.estimatedWords.formatted())", label: "words typed")
            }
        }
        .padding(16)
    }
}

private struct Stat: View {
    let value: String
    let label: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SnoozeControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if case .snoozed = model.status {
                HStack {
                    Label("Snoozed", systemImage: "moon.zzz")
                    Spacer()
                    Button("Resume") { model.resume() }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Snooze")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        ForEach(SnoozeOption.allCases) { option in
                            Button(String(localized: option.title)) { model.snooze(option) }
                        }
                    }
                    .controlSize(.small)
                }
                .disabled(model.status != .listening)
            }
        }
        .padding(16)
    }
}

private struct RecentAppToggle: View {
    @Environment(AppModel.self) private var model
    let app: AppInfo

    var body: some View {
        let isExcluded = model.isExcluded(app.bundleID)
        HStack {
            Label {
                Text(app.name)
                    .lineLimit(1)
            } icon: {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Spacer()
            Button(isExcluded ? "Stop Ignoring" : "Ignore") {
                model.setExcluded(!isExcluded, bundleID: app.bundleID)
            }
            .controlSize(.small)
            .accessibilityLabel(isExcluded ? "Stop ignoring \(app.name)" : "Ignore \(app.name)")
        }
        .padding(16)
    }
}

private struct Footer: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",")
            Spacer()
            Button("Quit Stop Typing App") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
