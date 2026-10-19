import AppKit
import ServiceManagement
import StopTypingCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Detection", systemImage: "text.word.spacing") { DetectionSettings() }
            Tab("Ignore", systemImage: "eye.slash") { ExcludedAppsSettings() }
        }
        .frame(width: 480, height: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var preferences = model.preferences
        Form {
            Section {
                Toggle(isOn: $model.isWatching) {
                    Text("Watch for long typing")
                    if let snoozed = model.snoozeDescription {
                        Text("\(snoozed). Turn on to resume.")
                    }
                }
                LaunchAtLoginToggle()
            }

            Section {
                Toggle(isOn: $preferences.showsOnScreenNudge) {
                    Text("Show on-screen nudge")
                    Text("Appears near the top of the screen you're typing on. Drag it anywhere; it stays there.")
                }
            } header: {
                Text("On-Screen Nudge")
            } footer: {
                SectionActions {
                    Button("Preview") { model.preview(.gentle) }
                    Button("Reset Position") { model.resetNudgePosition() }
                        .disabled(preferences.nudgeOffset == nil)
                }
            }

            Section {
                Toggle(isOn: $preferences.stopsWhenIgnored) {
                    Text("Stop me if I keep typing")
                    Text("If you keep typing after a nudge, show a window you have to click to dismiss.")
                }
                if preferences.stopsWhenIgnored {
                    Toggle(isOn: $preferences.skipsStopInFullScreen) {
                        Text("Not in full-screen apps")
                        Text("Show the on-screen nudge instead.")
                    }
                }
            } header: {
                Text("Stop Window")
            } footer: {
                SectionActions {
                    Button("Preview") { model.preview(.stop) }
                }
            }

            Section("Notifications & Focus") {
                Toggle(isOn: $model.sendsNotifications) {
                    Text("Also send to Notification Center")
                    Text("Each nudge also appears as a notification, so you can find it later.")
                }
                if model.notificationsDenied {
                    LabeledContent("Notifications are turned off for Stop Typing App.") {
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                Toggle(isOn: $model.isQuietDuringFocus) {
                    Text("Stay quiet during Focus")
                    Text("No nudges at all while Do Not Disturb or another Focus is on.")
                }
            }

            Section {
                LabeledContent("Input Monitoring") {
                    if model.hasInputMonitoringPermission {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open Privacy Settings") { NSWorkspace.shared.open(KeyboardTap.privacySettingsURL) }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stop Typing App only counts characters to tell prose from shortcuts. It never stores or sends what you type.")
                        .foregroundStyle(.secondary)
                    SectionActions {
                        Button("Set Up…") { model.showOnboarding() }
                    }
                }
            }

            UpdatesSection()
        }
        .formStyle(.grouped)
    }
}

private struct UpdatesSection: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var updater = updater
        Section {
            Toggle(isOn: $updater.automaticallyChecksForUpdates) {
                Text("Check for updates automatically")
                if updater.isAvailable {
                    Text("Off by default. Automatic and manual checks contact GitHub and its download servers. They receive your IP address, app and updater versions, and request language; never your typing. Sparkle may save local update diagnostics.")
                } else {
                    Text("Development builds don't update themselves.")
                }
            }
            .disabled(!updater.isAvailable)
        } header: {
            Text("Updates")
        } footer: {
            SectionActions {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}

/// Small link-style actions under a section, for things that aren't settings themselves.
private struct SectionActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 16) {
            content
        }
        .buttonStyle(.link)
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Open at login", isOn: $isEnabled)
            .onChange(of: isEnabled) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    isEnabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

// MARK: - Detection

private struct DetectionSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        let detection = preferences.detection
        Form {
            Section {
                SliderRow(
                    "Nudge after",
                    value: "\(detection.sentenceLength) characters",
                    amount: $preferences.detection.sentenceLength.asDouble,
                    in: 15...60,
                    step: 5
                )
                SliderRow(
                    preferences.stopsWhenIgnored ? "Stop window after" : "Nudge firmly after",
                    value: "\(detection.paragraphLength) characters",
                    amount: $preferences.detection.paragraphLength.asDouble,
                    in: Double(detection.sentenceLength + 10)...300,
                    step: 10
                )
                if preferences.stopsWhenIgnored {
                    SliderRow(
                        "Time to switch to dictation",
                        value: Self.format(detection.stopDelay),
                        amount: $preferences.detection.stopDelay,
                        in: 15...120,
                        step: 5
                    )
                }
                SliderRow(
                    "A pause ends the burst after",
                    value: Self.format(detection.burstGap),
                    amount: $preferences.detection.burstGap,
                    in: 2...10,
                    step: 0.5
                )
                SliderRow(
                    "Wait between nudges",
                    value: Self.format(detection.cooldown),
                    amount: $preferences.detection.cooldown.stops(Self.cooldownStops),
                    in: 0...Double(Self.cooldownStops.count - 1),
                    step: 1
                )
            } footer: {
                Text(preferences.stopsWhenIgnored
                     ? "After a nudge, the stop window appears once you've typed that much and the time to switch has passed. Only typing that reads like prose counts; shortcuts, held keys, Vim motions and code are ignored, and Escape ends a burst."
                     : "Only typing that reads like prose counts: several words, mostly letters. Shortcuts, held keys, Vim motions and code-like text are ignored, and Escape ends a burst.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Defaults") { preferences.detection = DetectorConfiguration() }
                    .disabled(preferences.detection == DetectorConfiguration())
            }
        }
        .formStyle(.grouped)
        .onChange(of: preferences.detection.sentenceLength) { _, sentenceLength in
            preferences.detection.paragraphLength = max(preferences.detection.paragraphLength, sentenceLength + 10)
        }
    }

    private static let cooldownStops: [TimeInterval] = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600]

    private static func format(_ seconds: TimeInterval) -> String {
        let isWhole = seconds.rounded() == seconds
        return Duration.seconds(seconds).formatted(.units(
            allowed: [.minutes, .seconds],
            width: .wide,
            fractionalPart: isWhole ? .hide : .show(length: 1)
        ))
    }
}

/// A labelled slider with its current value shown under the label.
private struct SliderRow: View {
    let title: LocalizedStringResource
    let value: String
    @Binding var amount: Double
    let range: ClosedRange<Double>
    let step: Double

    init(_ title: LocalizedStringResource, value: String, amount: Binding<Double>, in range: ClosedRange<Double>, step: Double) {
        self.title = title
        self.value = value
        self._amount = amount
        self.range = range
        self.step = step
    }

    var body: some View {
        LabeledContent {
            Slider(value: $amount, in: range, step: step)
                .frame(width: 180)
                .accessibilityLabel(Text(title))
                .accessibilityValue(value)
        } label: {
            Text(title)
            Text(value)
                .monospacedDigit()
        }
    }
}

private extension Binding where Value == Double {
    /// Drives a slider over the indices of `stops`, so unevenly spaced values get evenly spaced positions.
    func stops(_ stops: [Double]) -> Binding<Double> {
        Binding<Double>(
            get: {
                let nearest = stops.indices.min { abs(stops[$0] - wrappedValue) < abs(stops[$1] - wrappedValue) }
                return Double(nearest ?? 0)
            },
            set: { wrappedValue = stops[Int($0.rounded())] }
        )
    }
}

private extension Binding where Value == Int {
    var asDouble: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = Int($0.rounded()) }
        )
    }
}

// MARK: - Apps

private struct ExcludedAppsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<String> = []
    @State private var isChoosingApps = false

    var body: some View {
        let apps = model.preferences.excludedApps.map(AppInfo.init)
        VStack(alignment: .leading, spacing: 8) {
            Text("Never nudge in these apps")
                .font(.headline)
            Text("Typing in these apps isn't counted at all. Useful for terminals, code editors and games.")
                .foregroundStyle(.secondary)

            List(apps, selection: $selection) { app in
                Label {
                    Text(app.name)
                } icon: {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                .contextMenu {
                    Button("Remove", role: .destructive) { model.setExcluded(false, bundleID: app.bundleID) }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .onDeleteCommand(perform: removeSelection)
            .overlay {
                if apps.isEmpty {
                    ContentUnavailableView("No Excluded Apps", systemImage: "app.dashed")
                }
            }

            HStack(spacing: 0) {
                Button { isChoosingApps = true } label: { ListControlLabel(systemImage: "plus") }
                    .accessibilityLabel("Add App")
                Divider()
                    .frame(height: 14)
                Button(action: removeSelection) { ListControlLabel(systemImage: "minus") }
                    .accessibilityLabel("Remove App")
                    .disabled(selection.isEmpty)
            }
            .buttonStyle(.borderless)
        }
        .padding(20)
        .fileImporter(
            isPresented: $isChoosingApps,
            allowedContentTypes: [.application],
            allowsMultipleSelection: true
        ) { result in
            for url in (try? result.get()) ?? [] {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let bundleID = Bundle(url: url)?.bundleIdentifier {
                    model.setExcluded(true, bundleID: bundleID)
                }
            }
        }
    }

    /// A full-size hit area for the +/− buttons. Icon-only borderless buttons are only as tall as their
    /// glyph, which made the thin minus stroke nearly impossible to click.
    private struct ListControlLabel: View {
        let systemImage: String

        var body: some View {
            Image(systemName: systemImage)
                .frame(width: 24, height: 22)
                .contentShape(.rect)
        }
    }

    private func removeSelection() {
        for bundleID in selection {
            model.setExcluded(false, bundleID: bundleID)
        }
        selection.removeAll()
    }
}
