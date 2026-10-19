import StopTypingCore
import SwiftUI

/// A plain QWERTY keyboard with numbers and symbols pages, laid out like the system keyboard.
struct KeyboardView: View {
    static let height: CGFloat = 240

    let model: KeyboardModel
    let showsGlobeKey: Bool
    let nextKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            switch model.input.page {
            case .letters: lettersRows
            case .numbers: numbersRows
            case .symbols: symbolsRows
            }
            bottomRow
        }
        .padding(.horizontal, 3)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .opacity(model.isDimmed ? 0.45 : 1)
        .overlay(alignment: .bottomTrailing) {
            MicPulse(pulses: model.pulses)
        }
    }

    // MARK: Pages

    @ViewBuilder private var lettersRows: some View {
        characterRow("qwertyuiop")
        characterRow("asdfghjkl").padding(.horizontal, 18)
        HStack(spacing: 6) {
            FunctionKey(systemImage: shiftImage, accessibilityLabel: "Shift", isActive: model.input.shift != .off) {
                model.press(.shift)
            }
            .frame(width: 44)
            Spacer(minLength: 6)
            characterKeys("zxcvbnm")
            Spacer(minLength: 6)
            DeleteKey { model.press(.delete) }.frame(width: 44)
        }
    }

    @ViewBuilder private var numbersRows: some View {
        characterRow("1234567890")
        characterRow("-/:;()$&@\"")
        punctuationRow(switchTo: .symbols, label: "#+=")
    }

    @ViewBuilder private var symbolsRows: some View {
        characterRow("[]{}#%^*+=")
        characterRow("_\\|~<>€£¥•")
        punctuationRow(switchTo: .numbers, label: "123")
    }

    private func punctuationRow(switchTo page: KeyboardInput.Page, label: String) -> some View {
        HStack(spacing: 6) {
            FunctionKey(title: label) { model.press(.page(page)) }.frame(width: 44)
            Spacer(minLength: 6)
            characterKeys(".,?!'").frame(maxWidth: 260)
            Spacer(minLength: 6)
            DeleteKey { model.press(.delete) }.frame(width: 44)
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            FunctionKey(title: model.input.page == .letters ? "123" : "ABC") {
                model.press(.page(model.input.page == .letters ? .numbers : .letters))
            }
            .frame(width: 88)
            if showsGlobeKey {
                FunctionKey(systemImage: "globe", accessibilityLabel: "Next keyboard", action: nextKeyboard)
                    .frame(width: 44)
            }
            CharacterKey(title: "space", accessibilityLabel: "Space") { model.press(.space) }
            FunctionKey(systemImage: "return", accessibilityLabel: "Return") { model.press(.returnKey) }
                .frame(width: 88)
        }
    }

    // MARK: Helpers

    private var shiftImage: String {
        switch model.input.shift {
        case .off: "shift"
        case .once: "shift.fill"
        case .locked: "capslock.fill"
        }
    }

    private func characterRow(_ characters: String) -> some View {
        HStack(spacing: 6) { characterKeys(characters) }
    }

    private func characterKeys(_ characters: String) -> some View {
        ForEach(Array(characters).map(String.init), id: \.self) { character in
            let shown = model.input.page == .letters && model.input.shift != .off ? character.uppercased() : character
            CharacterKey(title: shown) { model.press(.character(character)) }
        }
    }
}

// MARK: - Keys

private enum KeyColors {
    static let character = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white })
    static let function = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1) })
    static let pressed = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.82, alpha: 1) })
}

private struct KeyStyle: ButtonStyle {
    let background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(configuration.isPressed ? KeyColors.pressed : background, in: .rect(cornerRadius: 6))
            .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
            .contentShape(.rect)
    }
}

private struct CharacterKey: View {
    let title: String
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(title.count == 1 ? .system(size: 23) : .system(size: 16))
                .foregroundStyle(.primary)
        }
        .buttonStyle(KeyStyle(background: KeyColors.character))
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

private struct FunctionKey: View {
    var title: String?
    var systemImage: String?
    var accessibilityLabel: String?
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 18, weight: .medium))
                } else if let title {
                    Text(title).font(.system(size: 16))
                }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(KeyStyle(background: isActive ? KeyColors.character : KeyColors.function))
        .accessibilityLabel(accessibilityLabel ?? title ?? "")
    }
}

/// Deletes once on touch, then repeats while held, like the system keyboard.
private struct DeleteKey: View {
    let action: () -> Void
    @State private var repeating: Task<Void, Never>?
    @GestureState private var isPressed = false

    var body: some View {
        Image(systemName: isPressed ? "delete.left.fill" : "delete.left")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isPressed ? KeyColors.character : KeyColors.function, in: .rect(cornerRadius: 6))
            .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in state = true }
                    .onChanged { _ in startRepeating() }
                    .onEnded { _ in stopRepeating() }
            )
            .accessibilityElement()
            .accessibilityLabel("Delete")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func startRepeating() {
        guard repeating == nil else { return }
        action()
        repeating = Task {
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                action()
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    private func stopRepeating() {
        repeating?.cancel()
        repeating = nil
    }
}

/// Points down at Apple's dictation mic, which iOS draws at the bottom-right just below the keyboard.
private struct MicPulse: View {
    let pulses: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowing = false

    var body: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 30))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .red)
            .scaleEffect(isShowing && !reduceMotion ? 1.15 : 1)
            .opacity(isShowing ? 1 : 0)
            .padding(.trailing, 22)
            .padding(.bottom, 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: pulses) { old, new in
                Task { await pulse(times: new - old) }
            }
    }

    private func pulse(times: Int) async {
        for _ in 0..<max(times, 1) {
            withAnimation(.easeOut(duration: 0.25)) { isShowing = true }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeIn(duration: 0.25)) { isShowing = false }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }
}
