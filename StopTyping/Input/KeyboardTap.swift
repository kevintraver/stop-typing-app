import Carbon.HIToolbox
import CoreGraphics
import Foundation
import StopTypingCore

struct TimedKeystroke: Sendable {
    var keystroke: Keystroke
    /// Seconds since boot; monotonic, unaffected by clock changes.
    var time: TimeInterval
}

enum KeyboardTapError: Error {
    /// Input Monitoring hasn't been granted.
    case permissionDenied
    /// Permission is granted but the system refused the tap; usually fixed by relaunching.
    case unavailable
}

/// A listen-only, system-wide key-down tap. It can observe typing but never delay, change or drop it.
///
/// The tap runs on its own thread so a busy main thread can't make the system time it out.
enum KeyboardTap {
    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system Input Monitoring prompt the first time; afterwards it only returns the current state.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    /// Starts the tap. It stops when the stream's consumer goes away.
    static func keystrokes() throws(KeyboardTapError) -> AsyncStream<TimedKeystroke> {
        guard hasPermission else { throw .permissionDenied }

        let (stream, continuation) = AsyncStream.makeStream(
            of: TimedKeystroke.self,
            bufferingPolicy: .bufferingNewest(256)
        )
        let context = TapContext(continuation: continuation)
        let userInfo = Unmanaged.passRetained(context).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: tapCallback,
            userInfo: userInfo
        ) else {
            Unmanaged<TapContext>.fromOpaque(userInfo).release()
            throw .unavailable
        }
        context.port = port

        let thread = Thread {
            context.run()
            // Balances the retain handed to the tap as `userInfo`; the tap is invalidated by now.
            Unmanaged.passUnretained(context).release()
        }
        thread.name = "StopTyping.KeyboardTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        context.started.wait()

        continuation.onTermination = { _ in context.stop() }
        return stream
    }
}

/// State shared between the caller and the tap thread.
/// `port` is set before the thread starts and `runLoop` before `started` is signalled, so later reads are safe.
private final class TapContext: @unchecked Sendable {
    let continuation: AsyncStream<TimedKeystroke>.Continuation
    let started = DispatchSemaphore(value: 0)
    var port: CFMachPort?
    private var runLoop: CFRunLoop?

    init(continuation: AsyncStream<TimedKeystroke>.Continuation) {
        self.continuation = continuation
    }

    func run() {
        guard let port else { return }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        runLoop = CFRunLoopGetCurrent()
        started.signal()
        CFRunLoopRun()
        CFMachPortInvalidate(port)
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
    }
}

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let port = context.port { CGEvent.tapEnable(tap: port, enable: true) }
    case .keyDown:
        if let keystroke = Keystroke(event) {
            context.continuation.yield(TimedKeystroke(keystroke: keystroke, time: ProcessInfo.processInfo.systemUptime))
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

private extension Keystroke {
    /// Classifies a key-down event. Returns nil for auto-repeat and keys that produce no characters.
    init?(_ event: CGEvent) {
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return nil }

        if !event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]) {
            self = .shortcut
            return
        }
        if event.getIntegerValueField(.keyboardEventKeycode) == kVK_Escape {
            self = .escape
            return
        }

        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
        guard length > 0 else { return nil }
        self = .text(String(utf16CodeUnits: characters, count: length))
    }
}
