// Presses Return on Claude Code's new-session page, but only after checking (through Accessibility) that its text box
// really holds the expected text. Runs off the main thread.
import AppKit
import Carbon.HIToolbox

enum ClaudeChat {
    static let wait: TimeInterval = 20       // Claude may still be starting

    /// Text as compared: the editor may add or collapse white space.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Only the new-session page counts (https://claude.ai/epitaxy), never an open session (…/epitaxy/<id>) or a chat.
    static func isNewSession(_ url: URL?) -> Bool {
        guard let url, url.host == "claude.ai" else { return false }
        return url.path == "/epitaxy" || url.path == "/epitaxy/"
    }

    /// Return right after "@word" or "/word" could pick from a menu, so such text is only filled in, not sent.
    static func endsInMention(_ text: String) -> Bool {
        normalized(text).split(separator: " ").last.map { $0.contains("@") || $0.hasPrefix("/") } ?? false
    }

    /// ponytail: files you left attached in that new-session draft go along; Claude's attachment chips have only
    /// localized labels to find them by. Check for them here if Claude ever gives them a stable identifier.
    static func sendWhenReady(_ text: String, bundleID: String) -> Bool {
        let wanted = normalized(text)
        guard !wanted.isEmpty, !endsInMention(wanted) else { return false }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 2)   // for every element, so a hung Claude can't stall us
        let deadline = Date().addingTimeInterval(wait)
        var app: AXUIElement?, pid: pid_t = 0, raised = false, matches = 0
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
            guard let claude = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
            if app == nil || claude.processIdentifier != pid {
                pid = claude.processIdentifier
                app = AXUIElementCreateApplication(pid)
            }
            guard let app else { continue }
            // Chromium builds its accessibility tree only when asked. Left on until Claude quits: whether another tool
            // also asked can't be read back, and switching it off would break that tool.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            guard let box = newSessionBox(app, holding: wanted, until: deadline) else { matches = 0; continue }
            if !isFront(pid) {                         // opened from another app: bring Claude forward, once
                matches = 0
                if !raised { AXUIElementSetAttributeValue(app, "AXFrontmost" as CFString, kCFBooleanTrue); raised = true }
                continue
            }
            if !(attribute(box, "AXFocused") as? Bool ?? false) {
                AXUIElementSetAttributeValue(box, "AXFocused" as CFString, kCFBooleanTrue)
                matches = 0
                continue
            }
            matches += 1
            guard matches >= 2 else { continue }           // same text, still in front, twice in a row
            for down in [true, false] {
                let key = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Return), keyDown: down)
                key?.flags = []                            // not ⇧Return or ⌘Return if you happen to hold one
                key?.postToPid(pid)
            }
            Thread.sleep(forTimeInterval: 1.5)
            let end = Date().addingTimeInterval(3)         // shorter than two 2 s timeouts, so a hung Claude counts as unconfirmed
            return newSessionBox(app, holding: wanted, until: end) == nil && Date() < end   // looked everywhere, gone: sent. Never pressed twice.
        }
        return false
    }

    private static func isFront(_ pid: pid_t) -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    /// The text box of the new-session page in Claude's focused window that holds exactly `wanted`.
    private static func newSessionBox(_ app: AXUIElement, holding wanted: String, until deadline: Date) -> AXUIElement? {
        guard let window = attribute(app, "AXFocusedWindow") ?? attribute(app, "AXMainWindow") else { return nil }
        var queue: [(element: AXUIElement, onPage: Bool)] = [(window as! AXUIElement, false)], next = 0
        while next < queue.count, next < 20_000, Date() < deadline {
            let (element, inherited) = queue[next]
            next += 1
            let role = attribute(element, "AXRole") as? String
            var onPage = inherited
            if role == "AXWebArea" { onPage = isNewSession(attribute(element, "AXURL") as? URL) }
            if role == "AXTextArea", onPage, normalized(attribute(element, "AXValue") as? String ?? "") == wanted { return element }
            for child in (attribute(element, "AXChildren") as? [AXUIElement]) ?? [] { queue.append((child, onPage)) }
        }
        return nil
    }
}
