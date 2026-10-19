import AppKit

/// The front window of the app you're working in. Window bounds and owners are readable without
/// Screen Recording permission (titles aren't, and aren't used).
@MainActor
enum FrontmostWindow {
    /// The frontmost app's front window, in AppKit screen coordinates.
    static var frame: CGRect? {
        guard let pid = frontmostPID, let primary = NSScreen.screens.first else { return nil }
        // The list is ordered front to back.
        for window in normalWindows where window[kCGWindowOwnerPID as String] as? pid_t == pid {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds)
            else { continue }
            // Quartz measures from the top-left of the primary display; AppKit from its bottom-left.
            return CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        return nil
    }

    private static var frontmostPID: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    /// Visible windows at the normal level, which excludes the menu bar, Dock and overlays like this app's.
    private static var normalWindows: [[String: Any]] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.filter {
            $0[kCGWindowLayer as String] as? Int == 0 && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0
        }
    }

    /// The screen showing most of the front window, or the one with the pointer.
    static var screen: NSScreen? {
        if let frame,
           let best = NSScreen.screens.max(by: { overlap($0, frame) < overlap($1, frame) }),
           overlap(best, frame) > 0 {
            return best
        }
        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    /// True when the frontmost app is in full screen.
    ///
    /// Native full screen gives the app its own Space, so its windows are the only normal ones on screen.
    /// Its window stops below the notch, so a frame check has to allow for the top safe-area inset.
    static var isFullScreen: Bool {
        guard let pid = frontmostPID else { return false }
        let windows = normalWindows
        if !windows.isEmpty && windows.allSatisfy({ $0[kCGWindowOwnerPID as String] as? pid_t == pid }) {
            return true
        }
        guard let frame, let screen else { return false }
        var covered = screen.frame
        covered.size.height -= screen.safeAreaInsets.top
        return frame.insetBy(dx: -1, dy: -1).contains(covered)
    }

    private static func overlap(_ screen: NSScreen, _ frame: CGRect) -> CGFloat {
        let shared = screen.frame.intersection(frame)
        return shared.isNull ? 0 : shared.width * shared.height
    }
}
