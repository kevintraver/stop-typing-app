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
            Tab("Try It", systemImage: "keyboard") { TryItSettings() }
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

            StatisticsSection()

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

private struct StatisticsSection: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingReset = false

    var body: some View {
        let today = model.preferences.stats.on(.now)
        Section {
            LabeledContent("Nudges today", value: today.nudges.formatted())
            LabeledContent("Words typed today", value: "≈ \(today.estimatedWords.formatted())")
        } header: {
            Text("Statistics")
        } footer: {
            SectionActions {
                Button("Reset Statistics") { isConfirmingReset = true }
                    .disabled(today.nudges == 0 && today.proseCharacters == 0)
            }
        }
        .confirmationDialog("Reset today's statistics?", isPresented: $isConfirmingReset) {
            Button("Reset", role: .destructive) { model.preferences.resetStats() }
        } message: {
            Text("Your nudge and word counts start over from zero.")
        }
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
    @State private var showsAdvanced = false

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
                DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                    SliderRow(
                        "Letters",
                        value: "At least \(detection.minimumLetterRatio.formatted(.percent.precision(.fractionLength(0)))) of characters",
                        amount: $preferences.detection.minimumLetterRatio.hundredths,
                        in: 0.4...0.9,
                        step: 0.05
                    )
                    SliderRow(
                        "Word breaks",
                        value: "At least 1 per \(detection.charactersPerWordBreak) characters",
                        amount: $preferences.detection.charactersPerWordBreak.asDouble,
                        in: 6...24,
                        step: 1
                    )
                    SliderRow(
                        "Short bursts end after",
                        value: "\(Self.format(detection.shortBurstGap)) when under \(detection.shortBurstLength) characters",
                        amount: $preferences.detection.shortBurstGap,
                        in: 1...5,
                        step: 0.5
                    )
                    SliderRow(
                        preferences.stopsWhenIgnored ? "Stop window also after" : "Nudge firmly also after",
                        value: "\(Self.format(detection.sustainedTyping)) of typing",
                        amount: $preferences.detection.sustainedTyping,
                        in: 15...300,
                        step: 15
                    )
                    if !preferences.stopsWhenIgnored {
                        SliderRow(
                            "Firm nudges at most every",
                            value: Self.format(detection.escalationInterval),
                            amount: $preferences.detection.escalationInterval,
                            in: 10...120,
                            step: 5
                        )
                    }
                }
            } footer: {
                Text("How typing is told from prose. A burst needs that share of letters and that many word breaks before it counts.")
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

private extension Binding where Value == Double {
    /// Rounds what the slider sets to two decimals, so a step of 0.05 lands on 0.6 rather than 0.6000000000000001
    /// and Restore Defaults can tell the value is already the default.
    var hundredths: Binding<Double> {
        Binding<Double>(
            get: { wrappedValue },
            set: { wrappedValue = ($0 * 100).rounded() / 100 }
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

// MARK: - Try It

/// A place to type and watch the detector count it. The readout is the real detector, fed by the
/// event tap like any other app, so what happens here is what happens everywhere.
private struct TryItSettings: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var now = ProcessInfo.processInfo.systemUptime
    @FocusState private var isEditing: Bool

    var body: some View {
        // Read so the readout refreshes with every counted key; the time itself comes from `now`.
        let _ = model.lastCountedKey
        let detection = model.preferences.detection
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .focused($isEditing)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Type a sentence or two…")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("Type Here")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing typed here is saved. The readout is the real detector, so it also follows typing in other apps.")
                        .foregroundStyle(.secondary)
                    SectionActions {
                        Button("Start Over") {
                            text = ""
                            model.startOverTyping()
                        }
                    }
                }
            }

            Section("What the Detector Sees") {
                if let reason = reasonNotCounting {
                    ReadoutRow("Not counting", value: reason)
                }
                ReadoutRow("Burst", value: burstText(detection))
                ReadoutRow("Prose", value: proseText(detection))
                ReadoutRow("Nudge", value: nudgeText(detection))
            }
        }
        .formStyle(.grouped)
        .onAppear { isEditing = true }
        .task {
            // Pauses, cooldowns and countdowns move without any key arriving.
            while !Task.isCancelled {
                now = ProcessInfo.processInfo.systemUptime
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private var reasonNotCounting: String? {
        switch model.status {
        case .off: return String(localized: "Watch for long typing is off")
        case .needsPermission: return String(localized: "Needs Input Monitoring")
        case .unavailable: return String(localized: "Couldn't start listening")
        case .snoozed: return model.snoozeDescription
        case .listening: break
        }
        if let bundleID = Bundle.main.bundleIdentifier, model.isExcluded(bundleID) {
            return String(localized: "Stop Typing App is on its own ignore list")
        }
        return nil
    }

    /// The burst, unless a pause has already ended it.
    private var activeBurst: TypingDetector.BurstSummary? {
        model.currentBurst.flatMap { now - $0.lastKey < $0.endsAfterPause ? $0 : nil }
    }

    private func burstText(_ detection: DetectorConfiguration) -> String {
        guard let burst = model.currentBurst else { return String(localized: "None yet") }
        guard activeBurst != nil else {
            return String(localized: "Ended after \(Self.characters(burst.length)). The next key starts a new one.")
        }
        let breaks = burst.wordBreaks == 1 ? String(localized: "1 word break") : String(localized: "\(burst.wordBreaks) word breaks")
        let counts = String(localized: "\(Self.characters(burst.length)), \(breaks), \(Self.percent(burst.letters, of: burst.length)) letters")
        let idle = now - burst.lastKey
        return idle >= 1 ? String(localized: "\(counts), pausing \(Self.seconds(idle, fraction: true))") : counts
    }

    private func proseText(_ detection: DetectorConfiguration) -> String {
        guard let burst = activeBurst else { return String(localized: "No") }
        if detection.readsAsProse(length: burst.length, letters: burst.letters, wordBreaks: burst.wordBreaks) {
            return String(localized: "Yes")
        }
        if burst.length < detection.sentenceLength {
            return String(localized: "Not yet: \(Self.characters(detection.sentenceLength - burst.length)) more")
        }
        if burst.wordBreaks < detection.minimumWordBreaks || burst.wordBreaks * detection.charactersPerWordBreak < burst.length {
            return String(localized: "No: too few word breaks, needs 1 per \(detection.charactersPerWordBreak) characters")
        }
        let needed = detection.minimumLetterRatio.formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "No: only \(Self.percent(burst.letters, of: burst.length)) letters, needs \(needed)")
    }

    /// What the detector will do next, following the same rules as `TypingDetector.nudge(for:at:)`.
    private func nudgeText(_ detection: DetectorConfiguration) -> String {
        if model.preferences.isQuietDuringFocus && model.isInFocus { return String(localized: "None during Focus") }
        let whenProse = String(localized: "Gentle, once this reads as prose")
        guard let last = model.lastNudge else { return whenProse }
        let since = now - last.time
        // Anything under a second reads as "now": the countdowns show whole seconds.
        if last.kind == .stop {
            let left = detection.cooldown - since
            return left >= 1 ? String(localized: "Quiet for \(Self.seconds(left)) after Got It") : whenProse
        }
        guard let burst = activeBurst, burst.wasNudged else {
            let left = detection.cooldown - since
            return left >= 1 ? String(localized: "Gentle in \(Self.seconds(left)), once this reads as prose") : whenProse
        }

        let usesStopWindow = model.preferences.stopsWhenIgnored
        let shown = last.kind == .gentle ? String(localized: "Gentle shown.") : String(localized: "Firm shown.")
        let next = usesStopWindow ? String(localized: "Stop window")
            : last.kind == .firm ? String(localized: "Firm again") : String(localized: "Firm nudge")
        let gate = (usesStopWindow ? detection.stopDelay : detection.escalationInterval) - since
        let isLong = burst.length >= detection.paragraphLength || now - burst.start >= detection.sustainedTyping
        if isLong && gate < 1 { return String(localized: "\(shown) \(next) with the next key") }
        var conditions: [String] = []
        if gate >= 1 { conditions.append(String(localized: "in \(Self.seconds(gate))")) }
        if !isLong {
            conditions.append(String(localized: "once past \(detection.paragraphLength) characters or \(Self.seconds(detection.sustainedTyping)) of typing"))
        }
        return "\(shown) \(next) \(conditions.joined(separator: ", "))"
    }

    private static func characters(_ count: Int) -> String {
        count == 1 ? String(localized: "1 character") : String(localized: "\(count) characters")
    }

    private static func percent(_ part: Int, of whole: Int) -> String {
        (Double(part) / Double(max(whole, 1))).formatted(.percent.precision(.fractionLength(0)))
    }

    private static func seconds(_ seconds: TimeInterval, fraction: Bool = false) -> String {
        Duration.seconds(max(seconds, 0)).formatted(.units(
            allowed: [.minutes, .seconds],
            width: .narrow,
            fractionalPart: fraction ? .show(length: 1) : .hide
        ))
    }
}

/// A readout line: a label with a value that may wrap.
private struct ReadoutRow: View {
    let title: LocalizedStringResource
    let value: String

    init(_ title: LocalizedStringResource, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        } label: {
            Text(title)
        }
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
