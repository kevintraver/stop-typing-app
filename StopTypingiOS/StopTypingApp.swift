import StopTypingCore
import SwiftUI

@main
struct StopTypingiOSApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Setup, a place to try the keyboard, and the detection settings the keyboard reads.
struct ContentView: View {
    @State private var detection = SharedSettings.detection
    @State private var hapticsEnabled = SharedSettings.hapticsEnabled
    @State private var practice = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SetupStep(number: 1, title: "Add the keyboard", detail: "Settings → General → Keyboard → Keyboards → Add New Keyboard… → Stop Typing App. It doesn't need Full Access.")
                    SetupStep(number: 2, title: "Turn on Dictation", detail: "Settings → General → Keyboard → Enable Dictation. That puts Apple's microphone below the keyboard, where every nudge points.")
                    SetupStep(number: 3, title: "Switch to it", detail: "In any text field, hold the globe key and choose Stop Typing App.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: {
                    Text("Set up")
                }

                Section {
                    TextEditor(text: $practice).frame(minHeight: 120)
                } header: {
                    Text("Try it")
                } footer: {
                    Text("Type a couple of sentences. The keys dim and an arrow points at the microphone below the keyboard.")
                }

                Section {
                    Stepper(value: $detection.sentenceLength, in: 15...60, step: 5) {
                        LabeledContent("Nudge after", value: "\(detection.sentenceLength) characters")
                    }
                    Stepper(value: $detection.paragraphLength, in: (detection.sentenceLength + 10)...300, step: 10) {
                        LabeledContent("Nudge again after", value: "\(detection.paragraphLength) characters")
                    }
                    Toggle("Haptic", isOn: $hapticsEnabled)
                } header: {
                    Text("Nudges")
                }

                Section {
                    Text("The keyboard turns each key press into a count the moment you tap it, never reads what's in the field, and has no Full Access, so it can't use the network. Your typing never leaves the keyboard.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("Stop Typing App")
            .onChange(of: detection) { _, new in
                var detection = new
                detection.paragraphLength = max(detection.paragraphLength, detection.sentenceLength + 10)
                SharedSettings.detection = detection
            }
            .onChange(of: hapticsEnabled) { _, new in SharedSettings.hapticsEnabled = new }
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.red, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
