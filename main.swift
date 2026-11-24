// TouchDo: to-dos with deadlines, keep-awake and a push-to-talk Claude button behind one Control Strip button,
// plus a menu bar icon to see and add to-dos from the desktop.
// Uses private Touch Bar API (DFRFoundation + NSTouchBar system-modal calls), checked on macOS 27.0.1.
// The Control Strip gives third-party apps one ~70pt slot, so everything opens from a single button.
// If a future macOS drops the API, the app quits quietly instead of crashing.
import AppKit
import Carbon.HIToolbox

// MARK: - Private Touch Bar API

private let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)
private func dfrFunction<T>(_ name: String, _: T.Type) -> T? {
    guard let dfr, let symbol = dlsym(dfr, name) else { return nil }
    return unsafeBitCast(symbol, to: T.self)
}
private let setStripPresence = dfrFunction("DFRElementSetControlStripPresenceForIdentifier", (@convention(c) (CFString, Bool) -> Void).self)
private let setCloseBox = dfrFunction("DFRSystemModalShowsCloseBoxWhenFrontMost", (@convention(c) (Bool) -> Void).self)

/// Calls a private class method; logs and does nothing if this macOS no longer has it.
private func classCall(_ cls: AnyClass, _ selector: String, _ a: Any?) {
    let sel = NSSelectorFromString(selector)
    guard (cls as AnyObject).responds(to: sel) else { return NSLog("TouchDo: missing \(selector)") }
    _ = (cls as AnyObject).perform(sel, with: a)
}
private func classCall(_ cls: AnyClass, _ selector: String, _ a: Any?, _ b: Any?) {
    let sel = NSSelectorFromString(selector)
    guard (cls as AnyObject).responds(to: sel) else { return NSLog("TouchDo: missing \(selector)") }
    _ = (cls as AnyObject).perform(sel, with: a, with: b)
}

extension NSTouchBarItem.Identifier {
    static let tray = NSTouchBarItem.Identifier("io.github.rasyachremony.TouchDo.tray")
    static let mic = NSTouchBarItem.Identifier("tbk.mic"), awake = NSTouchBarItem.Identifier("tbk.awake")
    static let count = NSTouchBarItem.Identifier("tbk.count"), add = NSTouchBarItem.Identifier("tbk.add")
    static let list = NSTouchBarItem.Identifier("tbk.list")
    static let draft = NSTouchBarItem.Identifier("tbk.draft"), saveDraft = NSTouchBarItem.Identifier("tbk.save")
    static let cancelDraft = NSTouchBarItem.Identifier("tbk.cancel"), back = NSTouchBarItem.Identifier("tbk.back")
    static let itemTitle = NSTouchBarItem.Identifier("tbk.item.title"), itemDone = NSTouchBarItem.Identifier("tbk.item.done")
    static let itemEdit = NSTouchBarItem.Identifier("tbk.item.edit"), itemDate = NSTouchBarItem.Identifier("tbk.item.date")
    static let itemDelete = NSTouchBarItem.Identifier("tbk.item.delete"), itemClaude = NSTouchBarItem.Identifier("tbk.item.claude")
    static let dateNone = NSTouchBarItem.Identifier("tbk.date.none"), dateToday = NSTouchBarItem.Identifier("tbk.date.today")
    static let dateTomorrow = NSTouchBarItem.Identifier("tbk.date.tomorrow"), dateList = NSTouchBarItem.Identifier("tbk.date.list")
    static let awakeTitle = NSTouchBarItem.Identifier("tbk.awake.title"), awakeOff = NSTouchBarItem.Identifier("tbk.awake.off")
    static let quit = NSTouchBarItem.Identifier("tbk.quit"), usage = NSTouchBarItem.Identifier("tbk.usage")
    static let sessions = NSTouchBarItem.Identifier("tbk.sessions"), plan = NSTouchBarItem.Identifier("tbk.plan")
    static let noEscape = NSTouchBarItem.Identifier("tbk.noEscape")
    /// Not a real Control Strip button: presenting the rings under it keeps our logo button visible.
    static let restingTray = NSTouchBarItem.Identifier("io.github.rasyachremony.TouchDo.resting")
    static func awakeFor(_ minutes: Int) -> NSTouchBarItem.Identifier { .init("tbk.awake.\(minutes)") }
}

struct Todo: Codable, Equatable { var text: String; var done = false; var due: Date? = nil }
/// A deleted to-do, kept 30 days in trash.json so the menu bar can bring it back.
struct Trashed: Codable { var todo: Todo; var deleted: Date }

/// Rounded "chip" for one to-do or one date in a scrubber.
final class Chip: NSScrubberTextItemView {
    static let id = NSUserInterfaceItemIdentifier("chip")
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        textField.lineBreakMode = .byTruncatingTail
    }
    required init?(coder: NSCoder) { fatalError("not used") }
}

/// Touch Bar mic: hold to talk (push-to-talk), double tap to keep dictating until the next tap.
final class HoldView: NSView {
    var onHoldStart: () -> Void = {}, onHoldEnd: () -> Void = {}, onDoubleTap: () -> Void = {}, onTapWhileOn: () -> Void = {}
    /// Set by the app while dictation stays on after a double tap; the button stays red.
    var latched = false { didSet { paint() } }
    private let idle = NSColor(white: 1, alpha: 0.16).cgColor, red = NSColor.systemRed.withAlphaComponent(0.75).cgColor
    private var fingers = 0, holding = false, lastTap = Date.distantPast
    private var holdTimer: DispatchWorkItem?
    init(image: NSImage) {
        super.init(frame: NSRect(x: 0, y: 0, width: 64, height: 30))
        allowedTouchTypes = [.direct]
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = idle
        let imageView = NSImageView(image: image)
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        widthAnchor.constraint(equalToConstant: 64).isActive = true
        setAccessibilityLabel("Tahan buat ngomong ke Claude, ketuk dua kali biar tetap nyala")
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    private func paint() { layer?.backgroundColor = (latched || holding) ? red : idle }

    override func touchesBegan(with event: NSEvent) {
        fingers += event.touches(matching: .began, in: self).count
        guard fingers == 1, !latched else { return }   // a second finger, or a tap that will switch dictation off
        let timer = DispatchWorkItem { [weak self] in   // still down after a moment: it's a hold, start talking
            guard let self, self.fingers > 0 else { return }
            self.holding = true
            self.paint()
            self.onHoldStart()
        }
        holdTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: timer)
    }
    override func touchesEnded(with event: NSEvent) {
        fingers = max(0, fingers - event.touches(matching: [.ended, .cancelled], in: self).count)
        guard fingers == 0 else { return }
        holdTimer?.cancel()
        if holding {
            holding = false
            paint()
            return onHoldEnd()
        }
        if latched { return onTapWhileOn() }
        if Date().timeIntervalSince(lastTap) < 0.4 {
            lastTap = .distantPast
            onDoubleTap()
        } else {
            lastTap = Date()
        }
    }
    override func touchesCancelled(with event: NSEvent) { touchesEnded(with: event) }
}

final class App: NSObject, NSApplicationDelegate, NSTouchBarDelegate, NSScrubberDataSource, NSScrubberFlowLayoutDelegate, NSMenuDelegate {
    private let claudeID = "com.anthropic.claudefordesktop"
    private let claudeColor = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
    private let claudeWarmUp: TimeInterval = 5   // seconds after Claude starts before the mic works; tune if it misses
    private let font = NSFont.systemFont(ofSize: 15)
    private let calendar = Calendar.current
    private let awakeChoices: [(minutes: Int, title: String)] = [(30, "30m"), (60, "1 jam"), (120, "2 jam"), (0, "∞")]
    private lazy var dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    // MARK: State

    private var todos: [Todo] = []
    private var selected = 0                 // the to-do the item and date bars act on
    private var editing = false              // typing replaces todos[selected].text instead of adding
    private lazy var todoURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "io.github.rasyachremony.TouchDo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("todos.json")
    }()
    /// Claude plan limits, written by the Claude Code status line script (see usageURL).
    private struct Limit: Decodable { var used_percentage: Double?; var resets_at: Double?; var name: String? }
    /// seven_day_model: a weekly limit of one model (Fable), from `claude -p /usage`.
    private struct Usage: Decodable { var five_hour: Limit?; var seven_day: Limit?; var seven_day_model: Limit? }
    private var usage = Usage()
    private var usageStamp: Date?
    private lazy var usageURL = todoURL.deletingLastPathComponent().appendingPathComponent("usage.json")
    private var trash: [Trashed] = []
    private lazy var trashURL = todoURL.deletingLastPathComponent().appendingPathComponent("trash.json")
    private var awakeActivity: NSObjectProtocol?
    private var awakeUntil: Date?            // nil while awake means "until switched off"
    private var awakeMinutes: Int?           // the chosen option, to highlight it
    private var shownBar: NSTouchBar?
    private var ticker: Timer?, barWatch: Timer?
    private var stripPID = App.controlStripPID()
    private var talking = false
    private weak var micView: HoldView?
    private weak var awakeButton: NSButton?, itemDoneButton: NSButton?
    private var choiceButtons: [Int: NSButton] = [:]

    // Typing: while on, a keyboard event tap turns keystrokes into the draft shown on the Touch Bar.
    private var typing = false, caretOn = true, draftShown = false
    private var edit = Draft()               // the text being typed, with caret, selection and undo (Draft.swift)
    private var draft: String {
        get { edit.text }
        set { edit = Draft(newValue) }
    }
    private var tap: CFMachPort?, tapSource: CFRunLoopSource?
    private var blink: Timer?
    private var lastKey = Date(), typingStart = Date()
    private var endKey: Int?                 // Return/Esc that ended typing, until its key-up has been eaten

    // MARK: Views

    private lazy var trayButton = NSButton(image: trayLogo(), target: self, action: #selector(openHome))
    private lazy var trayItem = viewItem(.tray, trayButton)
    // Clearing done to-dos lives in the menu bar.
    private lazy var homeBar = bar([.mic, .awake, .count, .add, .list])
    /// Shown at the far left whenever no other bar is up and you aren't typing: the live 5h / weekly rings.
    private lazy var restingBar: NSTouchBar = {
        let b = bar([.plan, .usage, .sessions, .flexibleSpace])
        b.escapeKeyReplacementItemIdentifier = .noEscape   // an empty item where the ✕ would go
        return b
    }()
    private lazy var itemBar = bar([.back, .itemTitle, .itemClaude, .itemDone, .itemEdit, .itemDate, .itemDelete])
    private lazy var dateBar = bar([.back, .dateNone, .dateToday, .dateTomorrow, .dateList])
    private lazy var typingBar = bar([.draft, .saveDraft, .cancelDraft])
    private lazy var awakeBar = bar([.back, .awakeTitle] + awakeChoices.map { .awakeFor($0.minutes) } + [.awakeOff, .flexibleSpace, .quit])
    private lazy var countLabel = NSTextField(labelWithString: "")
    private lazy var itemLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.widthAnchor.constraint(equalToConstant: 230).isActive = true
        return label
    }()
    private lazy var draftLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.widthAnchor.constraint(equalToConstant: 400).isActive = true
        return label
    }()
    private lazy var scrubber = makeScrubber(width: 280)
    private lazy var dateScrubber = makeScrubber(width: 300)
    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "To-do TouchDo")
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        return item
    }()

    private func makeScrubber(width: CGFloat) -> NSScrubber {
        let s = NSScrubber()
        s.dataSource = self
        s.delegate = self
        s.mode = .free                               // swipe to scroll, tap to select
        s.showsAdditionalContentIndicators = true    // fades the edge when there is more to scroll
        let layout = NSScrubberFlowLayout()
        layout.itemSpacing = 6
        s.scrubberLayout = layout
        s.register(Chip.self, forItemIdentifier: Chip.id)
        s.widthAnchor.constraint(equalToConstant: width).isActive = true
        return s
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if others.contains(where: { $0 != .current }) { exit(0) }   // already running; exit(0) so launchd leaves it
        guard setStripPresence != nil, (NSTouchBarItem.self as AnyObject).responds(to: NSSelectorFromString("addSystemTrayItem:")) else {
            NSLog("TouchDo: this macOS has no Control Strip API, quitting")
            exit(0)
        }
        loadTodos()
        loadTrash()
        restoreAwake()
        classCall(NSTouchBarItem.self, "addSystemTrayItem:", trayItem)
        showStripButton()
        todosChanged(save: false)
        let slow = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(slow, forMode: .common)
        ticker = slow
        // The status line rewrites usage.json after every Claude Code reply; check often so the rings follow at once.
        usageTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.readUsage() }
        readUsage()
        startResting()   // no Accessibility prompt at login; the bars wait until it is granted
    }

    // MARK: Claude plan limits (5 hours and weekly)

    private var usageTimer: Timer?
    private weak var usageView: NSTextField?
    // An exact width: left to size itself, the label made macOS stretch the bar over the Control Strip.
    private var usageWidth: NSLayoutConstraint?

    private weak var planView: NSImageView?
    private var planWidth: NSLayoutConstraint?
    private var planLines: [String] = [], planStamp: Date?

    /// Follows ~/.claude.json, so a new plan or account shows up by itself.
    private func showPlan() {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: Plan.file.path))?[.modificationDate] as? Date
        guard stamp != planStamp else { return }
        planStamp = stamp
        let lines = Plan.current()?.lines ?? []
        guard lines != planLines else { return }
        planLines = lines
        let image = planImage()
        planView?.image = image
        planWidth?.constant = image.size.width
    }

    /// The Claude app's own icon, small, and the plan in one or two small lines.
    private func planImage() -> NSImage {
        let logo = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        func attributes(_ i: Int) -> [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: i == 0 ? claudeColor : NSColor(white: 1, alpha: 0.6)] }
        let lines = (planLines.isEmpty ? [] : [planLines.joined(separator: " ")]) + [tokenLine].compactMap { $0 }, textWidth = lines.enumerated().map { ceil(($1 as NSString).size(withAttributes: attributes($0)).width) }.max() ?? 0
        let side: CGFloat = logo == nil ? 0 : 20, gap: CGFloat = side > 0 && textWidth > 0 ? 5 : 0
        let image = NSImage(size: NSSize(width: max(1, side + gap + textWidth), height: 28), flipped: false) { rect in
            logo?.draw(in: NSRect(x: 0, y: (rect.height - side) / 2, width: side, height: side))
            for (i, line) in lines.enumerated() {
                let height = (line as NSString).size(withAttributes: attributes(i)).height
                let y = lines.count == 1 ? (rect.height - height) / 2 : i == 0 ? rect.height / 2 : rect.height / 2 - height
                (line as NSString).draw(at: NSPoint(x: side + gap, y: y), withAttributes: attributes(i))
            }
            return true
        }
        image.accessibilityDescription = "Claude " + lines.joined(separator: " ")
        return image
    }

    // Sessions working right now, one chip each ("● name 6m"), in a row you can scroll; tap one to open it in the
    // Claude app. Yellow ones wait for you.
    private lazy var sessionScrubber = makeScrubber(width: 300)
    private var sessions: [Session] = []

    private func showSessions() {
        let active = Session.active()
        // Room right of the limits: the app area is 685 pt, less gaps and edges (measured on the device).
        let room = max(90, 600 - (usageWidth?.constant ?? 210) - (planWidth?.constant ?? 50))
        sessionScrubber.constraints.first { $0.firstAttribute == .width }?.constant = room
        let changed = active.map(\.pid) != sessions.map(\.pid)
        let texts = sessions.indices.map(sessionText)
        sessions = active
        if changed { sessionScrubber.reloadData() }        // keeps where you scrolled while the list stays the same
        else if sessions.indices.map(sessionText) != texts { sessionScrubber.reloadItems(at: IndexSet(sessions.indices)) }
    }

    private func sessionText(_ index: Int) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        guard sessions.indices.contains(index) else {
            return NSAttributedString(string: "○ tidak ada sesi jalan", attributes: [.font: font, .foregroundColor: NSColor(white: 1, alpha: 0.35)])
        }
        let session = sessions[index]
        let minutes = max(0, Int(Date().timeIntervalSince1970 - (session.statusUpdatedAt ?? 0) / 1000) / 60)
        var tail = session.statusUpdatedAt == nil ? "" : minutes < 60 ? " \(minutes)m" : " \(minutes / 60)j"
        if session.needsYou { tail = session.waitingFor == "permission prompt" ? " izin" : " nunggu" }
        var name = session.name?.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces) ?? ""
        if name.isEmpty { name = "Claude Code" }
        if name.count > 28 { name = String(name.prefix(27)).trimmingCharacters(in: .whitespaces) + "…" }
        let main = session.needsYou ? NSColor.systemYellow : NSColor(white: 1, alpha: 0.9)
        let text = NSMutableAttributedString(string: "● ", attributes: [.font: font, .foregroundColor: session.needsYou ? NSColor.systemYellow : NSColor.systemGreen])
        text.append(NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: main]))
        text.append(NSAttributedString(string: tail, attributes: [.font: font, .foregroundColor: main.withAlphaComponent(0.6)]))
        return text
    }

    private func openSession(_ index: Int) {
        sessionScrubber.selectedIndex = -1          // so tapping the same chip again opens it again
        guard sessions.indices.contains(index), let link = sessions[index].appLink else { return NSSound.beep() }
        NSWorkspace.shared.open(link)
    }

    private func showUsage() {
        guard let view = usageView else { return }
        view.attributedStringValue = usageText()
        usageWidth?.constant = ceil(view.attributedStringValue.size().width) + 4
    }

    // Every `autoRefresh` seconds: the limits from `claude -p /usage` (Claude Code's own /usage command; it asks
    // Anthropic for your limits and runs no model, so it costs no tokens), then the token total from Claude Code's files.
    private let autoRefresh: TimeInterval = 60
    private var refreshing = false, lastRefresh = Date.distantPast
    private let tokenTotal = TokenTotal()      // only touched by the one refresh running at a time
    private var tokenLine: String?

    private func refreshUsageIfStale() {
        guard !refreshing, Date().timeIntervalSince(lastRefresh) >= autoRefresh else { return }
        refreshing = true
        lastRefresh = Date()
        // No plan (API key or signed out): no limits to fetch.
        let claude = planLines.isEmpty ? nil : ["~/.local/bin/claude", "~/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .map({ NSString(string: $0).expandingTildeInPath }).first(where: FileManager.default.isExecutableFile)
        let url = usageURL, tokens = tokenTotal
        DispatchQueue.global(qos: .utility).async { [weak self] in
            if let claude {
                let run = Process()
                run.executableURL = URL(fileURLWithPath: claude)
                run.arguments = ["-p", "/usage", "--strict-mcp-config", "--no-session-persistence", "--setting-sources", ""]
                // launchd's PATH has no Homebrew or npm folders; an npm-installed claude needs to find node.
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "\((claude as NSString).deletingLastPathComponent):/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
                run.environment = environment
                run.currentDirectoryURL = FileManager.default.temporaryDirectory
                let out = Pipe()
                run.standardOutput = out
                run.standardError = FileHandle.nullDevice
                run.standardInput = FileHandle.nullDevice
                if (try? run.run()) != nil {
                    let killer = DispatchWorkItem { if run.isRunning { run.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: killer)
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    run.waitUntilExit()
                    killer.cancel()
                    let usage = ClaudeUsage.parse(String(decoding: data, as: UTF8.self))
                    if !usage.isEmpty, let json = try? JSONSerialization.data(withJSONObject: usage) {
                        let temp = url.appendingPathExtension("auto")
                        if (try? json.write(to: temp)) != nil { rename(temp.path, url.path) }   // atomic, like the status line's mv
                    }
                }
            }
            let total = tokens.update()            // the first read of all transcripts takes a while; later ones are quick
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                let line = total > 0 ? TokenTotal.label(total) : nil
                if line != self.tokenLine {
                    self.tokenLine = line
                    let image = self.planImage()
                    self.planView?.image = image
                    self.planWidth?.constant = image.size.width
                }
                self.readUsage()
            }
        }
    }

    private func readUsage() {
        let stamp = (try? usageURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        defer { refreshUsageIfStale() }
        showPlan()
        showSessions()
        if stamp == nil, usageStamp != nil {   // file gone: show "no data" instead of old numbers
            usageStamp = nil
            usage = Usage()
            showUsage()
        } else if stamp != usageStamp, let data = try? Data(contentsOf: usageURL), let fresh = try? JSONDecoder().decode(Usage.self, from: data) {
            usageStamp = stamp
            usage = fresh
            showUsage()
        }
    }

    /// Percent used, or nil when unknown. A window whose reset time has passed starts again at 0.
    private func percent(_ limit: Limit?) -> Double? {
        guard let limit, let used = limit.used_percentage else { return nil }
        if let reset = limit.resets_at, Date(timeIntervalSince1970: reset) <= Date() { return 0 }
        return min(max(used, 0), 100).rounded()   // colour, blocks, label and menu all use this one number
    }

    private func limitColor(_ p: Double) -> NSColor { p >= 80 ? .systemRed : p >= 50 ? .systemYellow : .systemGreen }

    /// "14:00" for the 5-hour window, "Sen 09:00" for the weekly one (local time).
    private func resetLabel(_ date: Date, weekday: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = weekday ? "EEE HH:mm" : "HH:mm"
        return f.string(from: date)
    }

    private func limitLine(_ name: String, _ limit: Limit?, weekday: Bool) -> String {
        guard let p = percent(limit) else { return "\(name): belum ada data" }
        var line = "\(name): \(Int(p.rounded()))% terpakai"
        if let reset = limit?.resets_at, Date(timeIntervalSince1970: reset) > Date() {
            let f = DateFormatter()
            f.locale = Locale(identifier: "id_ID")
            f.dateFormat = weekday ? "EEE HH:mm" : "HH:mm"
            line += ", reset \(f.string(from: Date(timeIntervalSince1970: reset)))"
        }
        return line
    }



    func applicationWillTerminate(_ note: Notification) {
        // Keep the saved choice: an update or crash restarts us within seconds and restoreAwake picks it up again.
        // After a log out the heartbeat is old, so it doesn't come back. Quit from the menu clears it (quit()).
        if let activity = awakeActivity { ProcessInfo.processInfo.endActivity(activity) }
    }

    private static func controlStripPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlstrip").first?.processIdentifier
    }

    private func tick() {
        refreshAwake()
        if awakeActivity != nil { UserDefaults.standard.set(Date(), forKey: "awakeHeartbeat") }
        // A restarted Control Strip never redraws our old button (re-adding shows an empty slot), so start over:
        // exit non-zero and launchd's KeepAlive starts a fresh copy. Wait while a to-do is being typed, and
        // don't exit when opened by hand (no launchd to bring it back).
        guard let pid = App.controlStripPID(), pid != stripPID, !typing, !talking, !sending, NSApp.modalWindow == nil else { return }
        if ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == Bundle.main.bundleIdentifier { exit(1) }
        stripPID = pid
    }

    @objc private func quit() {
        dismissShownBar()                     // ends a dictation left on by a double tap
        setAwake(minutes: nil)
        NSApp.terminate(nil)
    }

    // MARK: Touch Bar plumbing

    private func icon(_ name: String, _ label: String, _ color: NSColor? = nil, size: CGFloat = 16) -> NSImage {
        var config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        if let color { config = config.applying(.init(paletteColors: [color])) }
        return NSImage(systemSymbolName: name, accessibilityDescription: label)?.withSymbolConfiguration(config) ?? NSImage()
    }

    /// The Control Strip button: a mini logo of the three features, with a red badge for open to-dos;
    /// the cup fills yellow while the Mac is kept awake.
    private func trayLogo() -> NSImage {
        let on = awakeOn
        let open = todos.filter { !$0.done }.count
        let parts = [icon("checklist", "", .systemBlue, size: 13),
                     icon(on ? "cup.and.saucer.fill" : "cup.and.saucer", "", on ? .systemYellow : .white, size: 13),
                     icon("mic.fill", "", claudeColor, size: 13)]
        let logo = NSImage(size: NSSize(width: 64, height: 26), flipped: false) { rect in
            let cell = rect.width / CGFloat(parts.count)
            for (i, part) in parts.enumerated() {
                part.draw(in: NSRect(x: cell * CGFloat(i) + (cell - part.size.width) / 2, y: (rect.height - part.size.height) / 2 - 1,
                                     width: part.size.width, height: part.size.height))
            }
            if open > 0 {
                let text = "\(open)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 8), .foregroundColor: NSColor.white]
                let size = text.size(withAttributes: attributes)
                let badge = NSRect(x: cell - max(size.width + 5, 11) + 3, y: rect.height - 11, width: max(size.width + 5, 11), height: 11)
                NSColor.systemRed.setFill()
                NSBezierPath(roundedRect: badge, xRadius: 5.5, yRadius: 5.5).fill()
                text.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attributes)
            }
            return true
        }
        logo.accessibilityDescription = "TouchDo: \(open) to-do belum selesai"
        return logo
    }

    /// Small lines of ASCII bars, coloured part = used (green / yellow / red), then percent and reset time;
    /// a third one for a model's own weekly limit when Claude Code reports one:
    /// 5h    ██░░░░░░░░  19% ↻04:10
    /// Week  ██░░░░░░░░  16% ↻Sab 13:00
    /// Fable █░░░░░░░░░   8% ↻Sab 13:00
    private func usageText() -> NSAttributedString {
        let dim = NSColor(white: 1, alpha: 0.22), label = NSColor(white: 1, alpha: 0.7)
        var rows = [("5h", usage.five_hour, false), ("Week", usage.seven_day, true)]
        if let model = usage.seven_day_model { rows.append((String((model.name ?? "Model").prefix(5)), model, true)) }
        let font = rows.count > 2 ? NSFont.monospacedSystemFont(ofSize: 8, weight: .semibold) : smallFont
        let lines = smallLines(height: rows.count > 2 ? 10 : 14)
        let text = NSMutableAttributedString()
        func add(_ s: String, _ color: NSColor) {
            text.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: lines]))
        }
        let nameWidth = rows.map(\.0.count).max() ?? 4
        for (i, (name, limit, weekday)) in rows.enumerated() {
            let p = percent(limit), cells = 10
            let filled = p.map { $0 > 0 ? max(1, min(cells, Int(($0 / 10).rounded()))) : 0 } ?? 0   // any use shows a block
            let color = p.map(limitColor) ?? dim
            add((i > 0 ? "\n" : "") + name.padding(toLength: nameWidth, withPad: " ", startingAt: 0) + " ", label)
            add(String(repeating: "█", count: filled), color)
            add(String(repeating: "░", count: cells - filled), p == nil ? dim : color.withAlphaComponent(0.35))
            add(p.map { String(format: " %3d%%", Int($0)) } ?? "    –", p == nil ? dim : color)
            if let reset = limit?.resets_at.map({ Date(timeIntervalSince1970: $0) }), reset > Date() {
                add(" ↻" + resetLabel(reset, weekday: weekday), label.withAlphaComponent(0.5))
            }
        }
        return text
    }

    private let smallFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)

    private func smallLines(height: CGFloat = 14, tabs: [CGFloat] = []) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.maximumLineHeight = height         // 14: two lines in the 30 pt Touch Bar, 10: three
        style.minimumLineHeight = height
        style.lineBreakMode = .byClipping
        style.tabStops = tabs.map { NSTextTab(textAlignment: .left, location: $0) }
        return style
    }

    private func twoLineLabel() -> NSTextField {
        let view = NSTextField(labelWithString: "")
        view.usesSingleLineMode = false
        view.maximumNumberOfLines = 2
        view.cell?.wraps = true
        view.cell?.isScrollable = false
        return view
    }

    private func button(_ id: NSTouchBarItem.Identifier, symbol: String? = nil, title: String = "", label: String = "",
                        tint: NSColor? = nil, bezel: NSColor? = nil, tag: Int = 0, _ action: Selector) -> NSCustomTouchBarItem {
        let b = NSButton(title: title, target: self, action: action)
        if let symbol {
            b.image = icon(symbol, label, tint)
            b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
        b.bezelColor = bezel
        b.tag = tag
        return viewItem(id, b)
    }

    private func bar(_ ids: [NSTouchBarItem.Identifier]) -> NSTouchBar {
        let b = NSTouchBar()
        b.delegate = self
        b.defaultItemIdentifiers = ids
        return b
    }

    private func viewItem(_ id: NSTouchBarItem.Identifier, _ view: NSView) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: id)
        item.view = view
        return item
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if let choice = awakeChoices.first(where: { NSTouchBarItem.Identifier.awakeFor($0.minutes) == id }) {
            let item = button(id, title: choice.title, tag: choice.minutes, #selector(awakeChosen(_:)))
            choiceButtons[choice.minutes] = item.view as? NSButton
            refreshAwake()
            return item
        }
        switch id {
        case .mic:
            let hold = HoldView(image: icon("mic.fill", "Tahan buat ngomong ke Claude", claudeColor))
            hold.onHoldStart = { [weak self] in self?.micDown() }
            hold.onHoldEnd = { [weak self] in self?.micUp() }
            hold.onDoubleTap = { [weak self] in self?.micDown(stayOn: true) }
            hold.onTapWhileOn = { [weak self] in self?.micUp() }
            micView = hold
            return viewItem(id, hold)
        case .awake:
            let item = button(id, symbol: "cup.and.saucer", label: "Mac nyala terus", #selector(openAwake))
            awakeButton = item.view as? NSButton
            refreshAwake()
            return item
        case .usage:                           // 5-hour and weekly Claude limits, updated live from usage.json
            let view = twoLineLabel()
            view.maximumNumberOfLines = 3
            view.attributedStringValue = usageText()
            usageWidth = view.widthAnchor.constraint(equalToConstant: ceil(view.attributedStringValue.size().width) + 4)
            usageWidth?.isActive = true
            usageView = view
            return viewItem(id, view)
        case .plan:                            // Claude's logo and the plan in use
            let view = NSImageView(image: planImage())
            planWidth = view.widthAnchor.constraint(equalToConstant: view.image!.size.width)
            planWidth?.isActive = true
            planView = view
            return viewItem(id, view)
        case .sessions:                        // Claude Code sessions at work, right of the limits
            showSessions()
            return viewItem(id, sessionScrubber)
        case .noEscape:
            let blank = NSView()
            blank.widthAnchor.constraint(equalToConstant: 1).isActive = true
            return viewItem(id, blank)
        case .count: return viewItem(id, countLabel)
        case .add: return button(id, symbol: "plus", label: "Tambah to-do", bezel: .systemBlue, #selector(addTodo))
        case .list: return viewItem(id, scrubber)
        case .back: return button(id, symbol: "chevron.left", label: "Kembali", #selector(openHome))
        case .itemTitle: return viewItem(id, itemLabel)
        case .itemDone:
            let item = button(id, symbol: "checkmark.circle", title: "Selesai", bezel: .systemGreen, #selector(toggleSelected))
            itemDoneButton = item.view as? NSButton
            return item
        case .itemClaude: return button(id, symbol: "paperplane.fill", label: "Jalankan di Claude Code", bezel: claudeColor, #selector(runInClaude))
        case .itemEdit: return button(id, symbol: "pencil", label: "Edit", #selector(editSelected))
        case .itemDate: return button(id, symbol: "calendar", label: "Tanggal", #selector(openDates))
        case .itemDelete: return button(id, symbol: "trash", label: "Hapus", bezel: .systemRed, #selector(deleteSelected))
        case .dateNone: return button(id, title: "Tanpa", tag: -1, #selector(dateChosen(_:)))
        case .dateToday: return button(id, title: "Hari ini", tag: 0, #selector(dateChosen(_:)))
        case .dateTomorrow: return button(id, title: "Besok", tag: 1, #selector(dateChosen(_:)))
        case .dateList: return viewItem(id, dateScrubber)
        case .draft: return viewItem(id, draftLabel)
        case .saveDraft: return button(id, symbol: "checkmark", label: "Simpan", bezel: .systemBlue, #selector(saveDraft))
        case .cancelDraft: return button(id, symbol: "xmark", label: "Batal", #selector(cancelDraft))
        case .awakeTitle: return viewItem(id, awakeTitle)
        case .awakeOff: return button(id, title: "Matikan", bezel: .systemRed, #selector(awakeOffChosen))
        case .quit: return button(id, symbol: "power", title: "Keluar", label: "Keluar dari TouchDo", #selector(quit))
        default: return nil
        }
    }

    /// Closing a system-modal bar (ours or the ✕ box) also hides its Control Strip button (tested), so put it back.
    private func showStripButton() {
        setStripPresence?(NSTouchBarItem.Identifier.tray.rawValue as CFString, true)
    }

    private func present(_ bar: NSTouchBar) {
        if bar !== typingBar { endTyping() }
        if talking, bar !== homeBar {            // the mic lives on the home bar: leaving it finishes the dictation
            talking = false
            micView?.latched = false
            pressClaudeShortcut()
        }
        if bar === dateBar { dateScrubber.reloadData(); dateScrubber.selectedIndex = -1 }   // chips follow today's date
        hideResting()
        if let shown = shownBar, shown !== bar { classCall(NSTouchBar.self, "dismissSystemModalTouchBar:", shown) }
        setCloseBox?(true)
        classCall(NSTouchBar.self, "presentSystemModalTouchBar:systemTrayItemIdentifier:", bar, NSTouchBarItem.Identifier.tray.rawValue)
        shownBar = bar
        // Notice when the bar is closed with ✕: its first item leaves the window once it has been on screen.
        var seen = false
        let presentedAt = Date()
        barWatch?.invalidate()
        barWatch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self, let shown = self.shownBar, let first = shown.defaultItemIdentifiers.first else { return timer.invalidate() }
            if shown.item(forIdentifier: first)?.view?.window != nil { seen = true; return }
            if seen || Date().timeIntervalSince(presentedAt) > 1.5 { self.dismissShownBar() }   // closed before we saw it
        }
    }

    private func dismissShownBar() {
        if talking { talking = false; micView?.latched = false; pressClaudeShortcut() }   // bar gone: finish the dictation
        if let shown = shownBar { classCall(NSTouchBar.self, "dismissSystemModalTouchBar:", shown) }
        shownBar = nil
        barWatch?.invalidate()
        barWatch = nil
        showStripButton()
    }

    // MARK: Rings at the far left while you're not typing
    // macOS gives other apps' bars no room for us, so the rings sit in a system-modal bar of their own (no ✕).
    // It covers the app's own Touch Bar, so it steps aside on any keypress (typing suggestions come back) and
    // returns after `restingDelay` seconds without typing.

    private let restingDelay: TimeInterval = 2      // shorter hides typing suggestions while you pause to tap one
    private var restingShown = false, lastTyped = Date.distantPast
    private var restingGone = 0              // half-second ticks the shown bar has been off screen
    private var keyWatch: CFMachPort?

    private func startResting() {
        lastTyped = Date().addingTimeInterval(2)   // wait after launch so our Control Strip button is in place first
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.updateResting() }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The keyboard watch needs Accessibility; it is retried until granted (it may come after launch).
    private func startKeyWatch() {
        let trusted = AXIsProcessTrusted()
        if let old = keyWatch, !trusted || !CGEvent.tapIsEnabled(tap: old) {   // permission was turned off: this tap is dead
            CFMachPortInvalidate(old)
            keyWatch = nil
        }
        guard keyWatch == nil, trusted else { return }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        keyWatch = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask,
                                     callback: { _, type, event, info in
            let app = Unmanaged<App>.fromOpaque(info!).takeUnretainedValue()
            if type == .keyDown, !event.flags.contains(.maskCommand), !event.flags.contains(.maskControl) { app.keyTyped() }
            else if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let tap = app.keyWatch {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let keyWatch { CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, keyWatch, 0), .commonModes) }
    }

    private func keyTyped() {
        lastTyped = Date()
        hideResting()
        // Back the moment the delay is over, without waiting for the half-second timer.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(updateResting), object: nil)
        perform(#selector(updateResting), with: nil, afterDelay: restingDelay + 0.02, inModes: [.common])
    }

    @objc private func updateResting() {
        startKeyWatch()
        if !usageText().isEqual(to: usageView?.attributedStringValue ?? NSAttributedString()) { showUsage() }   // a reset passed
        // Secure input (password fields, Secure Keyboard Entry) hides keypresses from us: keep the app's own bar then.
        let idle = Date().timeIntervalSince(lastTyped) >= restingDelay && !IsSecureEventInputEnabled()
        let ours = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        // macOS can drop the bar by itself (Control Strip reload, Touch Bar sleep); notice it and show it again.
        if restingShown, usageView?.window == nil {
            restingGone += 1
            if restingGone >= 3 {
                classCall(NSTouchBar.self, "dismissSystemModalTouchBar:", restingBar)
                restingShown = false
                restingGone = 0
            }
        } else {
            restingGone = 0
        }
        if shownBar == nil, !typing, idle, !ours, keyWatch != nil {
            guard !restingShown else { return }
            setCloseBox?(false)
            classCall(NSTouchBar.self, "presentSystemModalTouchBar:systemTrayItemIdentifier:", restingBar, NSTouchBarItem.Identifier.restingTray.rawValue)
            restingShown = true
            showStripButton()
        } else if !idle || ours || keyWatch == nil {
            hideResting()
        }
    }

    private func hideResting() {
        guard restingShown else { return }
        classCall(NSTouchBar.self, "dismissSystemModalTouchBar:", restingBar)
        restingShown = false
        showStripButton()
    }

    @objc private func openHome() {
        sortTodos()
        scrubber.reloadData()
        refreshCounts()
        refreshAwake()
        present(homeBar)
    }

    /// Accessibility lets the app read keys for a to-do and press Claude's shortcut. Asks (and opens the
    /// settings pane, needed when an old grant went stale after a rebuild) when it is missing.
    private func hasAccessibility() -> Bool {
        if AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) { return true }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        return false
    }

    // MARK: To-do data

    private func loadTodos() {
        guard FileManager.default.fileExists(atPath: todoURL.path) else { return }
        do {
            todos = try JSONDecoder().decode([Todo].self, from: Data(contentsOf: todoURL))
        } catch {
            // Never overwrite a list we could not read: keep it aside and start empty.
            let aside = todoURL.deletingLastPathComponent().appendingPathComponent("todos-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: todoURL, to: aside)
            NSLog("TouchDo: could not read todos.json (\(error)), kept it as \(aside.lastPathComponent)")
        }
    }

    private func saveTodos() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        do { try encoder.encode(todos).write(to: todoURL, options: .atomic) }
        catch { NSLog("TouchDo: could not save to-dos: \(error)") }
    }

    /// Open first, earliest deadline first, no deadline after dated ones, done last; ties keep their order.
    private func sortTodos() {
        todos = todos.enumerated()
            .sorted { ($0.element.done ? 1 : 0, $0.element.due ?? .distantFuture, $0.offset) < ($1.element.done ? 1 : 0, $1.element.due ?? .distantFuture, $1.offset) }
            .map(\.element)
    }

    /// Every change goes through here so the Touch Bar, the badge and the menu bar stay in step.
    private func todosChanged(save: Bool = true) {
        sortTodos()
        if save { saveTodos() }
        scrubber.reloadData()
        refreshCounts()
    }

    private func refreshCounts() {
        let open = todos.filter { !$0.done }.count
        countLabel.stringValue = open == 0 ? "Beres" : "\(open) lagi"
        countLabel.textColor = open == 0 ? .systemGreen : .systemOrange
        trayButton.image = trayLogo()
        statusItem.button?.title = open > 0 ? " \(open)" : ""
    }

    private func dueLabel(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Hari ini" }
        if calendar.isDateInTomorrow(date) { return "Besok" }
        if calendar.isDateInYesterday(date) { return "Kemarin" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: date).day ?? 0
        return days == 2 ? "Lusa" : dayFormatter.string(from: date)
    }

    /// Red = late, orange = today, yellow = tomorrow, blue = later, grey = no deadline.
    private func urgency(_ todo: Todo) -> NSColor? {
        guard !todo.done, let due = todo.due else { return nil }
        if due < calendar.startOfDay(for: Date()) { return .systemRed }
        if calendar.isDateInToday(due) { return .systemOrange }
        if calendar.isDateInTomorrow(due) { return .systemYellow }
        return .systemBlue
    }

    // MARK: To-do list on the Touch Bar

    private func chipText(_ index: Int) -> NSAttributedString {
        guard todos.indices.contains(index) else {
            return NSAttributedString(string: "Belum ada to-do. Tap + buat nambah", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        }
        let todo = todos[index]
        if todo.done {
            return NSAttributedString(string: "✓ " + todo.text, attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor,
                                                                           .strikethroughStyle: NSUnderlineStyle.single.rawValue])
        }
        let s = NSMutableAttributedString(string: todo.text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        if let due = todo.due {
            s.append(NSAttributedString(string: "  " + dueLabel(due), attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                                                   .foregroundColor: NSColor.white.withAlphaComponent(0.85)]))
        }
        return s
    }

    private func dateChoices() -> [Date] {   // the scrubber offers the two weeks after tomorrow
        (2...15).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: Date())) }
    }

    func numberOfItems(for scrubber: NSScrubber) -> Int {
        scrubber === dateScrubber ? dateChoices().count : scrubber === sessionScrubber ? max(sessions.count, 1) : max(todos.count, 1)
    }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let chip = scrubber.makeItem(withIdentifier: Chip.id, owner: nil) as? Chip ?? Chip(frame: .zero)
        if scrubber === dateScrubber {
            chip.textField.attributedStringValue = NSAttributedString(string: dueLabel(dateChoices()[index]), attributes: [.font: font])
            chip.layer?.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
        } else if scrubber === sessionScrubber {
            chip.textField.attributedStringValue = sessionText(index)
            let waiting = sessions.indices.contains(index) && sessions[index].needsYou
            chip.layer?.backgroundColor = (waiting ? NSColor.systemYellow.withAlphaComponent(0.25) : NSColor(white: 1, alpha: sessions.isEmpty ? 0 : 0.1)).cgColor
        } else {
            chip.textField.attributedStringValue = chipText(index)
            let tint = todos.indices.contains(index) ? urgency(todos[index]) : nil
            chip.layer?.backgroundColor = (tint?.withAlphaComponent(0.5) ?? NSColor(white: 1, alpha: todos.indices.contains(index) && todos[index].done ? 0.06 : 0.14)).cgColor
        }
        return chip
    }

    func scrubber(_ scrubber: NSScrubber, layout: NSScrubberFlowLayout, sizeForItemAt index: Int) -> NSSize {
        if scrubber === dateScrubber { return NSSize(width: 92, height: 30) }
        if scrubber === sessionScrubber { return NSSize(width: sessionText(index).size().width + 22, height: 30) }
        return NSSize(width: min(chipText(index).size().width + 28, 300), height: 30)
    }

    func scrubber(_ scrubber: NSScrubber, didSelectItemAt index: Int) {
        if scrubber === dateScrubber { return setDue(dateChoices()[index]) }
        if scrubber === sessionScrubber { return openSession(index) }
        guard todos.indices.contains(index) else { return addTodo() }   // the empty-list hint opens typing
        selected = index
        openItem()
    }

    // MARK: One to-do: done / edit / date / delete

    private func openItem() {
        guard todos.indices.contains(selected) else { return openHome() }
        let todo = todos[selected]
        itemLabel.attributedStringValue = chipText(selected)
        present(itemBar)
        itemDoneButton?.title = todo.done ? "Belum" : "Selesai"
        itemDoneButton?.image = icon(todo.done ? "arrow.uturn.backward.circle" : "checkmark.circle", todo.done ? "Belum" : "Selesai")
    }

    @objc private func toggleSelected() {
        guard todos.indices.contains(selected) else { return openHome() }
        todos[selected].done.toggle()
        todosChanged()
        openHome()
    }

    @objc private func deleteSelected() {
        guard todos.indices.contains(selected) else { return openHome() }
        moveToTrash([todos.remove(at: selected)])
        todosChanged()
        openHome()
    }

    @objc private func editSelected() {
        guard todos.indices.contains(selected) else { return openHome() }
        editing = true
        draft = todos[selected].text
        startTyping()
    }

    // MARK: Run a to-do in a new Claude Code session
    // Claude's link claude://code/new?q=… opens a new session with the text filled in but never sends it. Return is
    // pressed only once, and only after Accessibility shows that exact text on the new-session page with Claude in
    // front; otherwise the text just stays there for you to send. Folder and permission mode are Claude's own choice.

    private var sending = false

    @objc private func runInClaude() {
        guard !sending else { return NSSound.beep() }   // the previous one is still on its way
        guard todos.indices.contains(selected), hasAccessibility() else { return }
        let text = todos[selected].text
        var parts = URLComponents(string: "claude://code/new")!
        parts.queryItems = [URLQueryItem(name: "q", value: text)]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")   // "+" would become a space
        guard let url = parts.url else { return }
        sending = true
        dismissShownBar()
        NSWorkspace.shared.open(url)
        DispatchQueue.global(qos: .userInitiated).async { [weak self, claudeID] in
            let sent = ClaudeChat.sendWhenReady(text, bundleID: claudeID)
            if !sent { NSLog("TouchDo: the to-do was not confirmed as sent to Claude Code") }
            DispatchQueue.main.async {
                self?.sending = false
                if !sent { NSSound.beep() }                 // unsent, or not confirmed
            }
        }
    }

    @objc private func openDates() { present(dateBar) }

    @objc private func dateChosen(_ sender: NSButton) {
        setDue(sender.tag < 0 ? nil : calendar.date(byAdding: .day, value: sender.tag, to: calendar.startOfDay(for: Date())))
    }

    private func setDue(_ date: Date?) {
        if todos.indices.contains(selected) { todos[selected].due = date }
        todosChanged()
        openHome()
    }

    @objc private func clearDone() {
        moveToTrash(todos.filter(\.done))
        todos.removeAll { $0.done }
        todosChanged()
    }

    // MARK: Trash: deleted to-dos stay 30 days, to bring back from the menu bar

    private func loadTrash() {
        trash = (try? JSONDecoder().decode([Trashed].self, from: Data(contentsOf: trashURL))) ?? []
    }

    private func moveToTrash(_ removed: [Todo]) {
        trash.insert(contentsOf: removed.map { Trashed(todo: $0, deleted: Date()) }, at: 0)
        saveTrash()
    }

    private func saveTrash() {
        trash.removeAll { $0.deleted < Date().addingTimeInterval(-30 * 86_400) }
        do { try JSONEncoder().encode(trash).write(to: trashURL, options: .atomic) }
        catch { NSLog("TouchDo: could not save the trash: \(error)") }
    }

    @objc private func restoreTrashed(_ sender: NSMenuItem) {
        guard trash.indices.contains(sender.tag) else { return }
        todos.append(trash.remove(at: sender.tag).todo)
        saveTrash()
        todosChanged()
    }

    @objc private func emptyTrash() {
        hideResting()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Kosongkan sampah?"
        alert.informativeText = "\(trash.count) to-do dihapus permanen dan nggak bisa dipulihkan."
        alert.addButton(withTitle: "Kosongkan")
        alert.addButton(withTitle: "Batal")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        trash = []
        saveTrash()
    }

    // MARK: Typing a to-do on the Touch Bar
    // macOS 27 won't let a background app take keyboard focus, even after a Touch Bar tap (tested), so a
    // keyboard event tap reads the keys instead: the app in front keeps its focus and nothing shows on screen.

    @objc private func addTodo() {
        if editing { draft = "" }            // don't carry an abandoned edit into a new to-do
        editing = false
        startTyping()
    }

    private func startTyping() {
        guard hasAccessibility() else { return }
        present(typingBar)
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                             eventsOfInterest: mask, callback: { _, type, event, info in
            Unmanaged<App>.fromOpaque(info!).takeUnretainedValue().handleKey(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return dismissShownBar() }
        teardownTap()                         // a tap still waiting for an old Return's key-up
        tap = newTap
        tapSource = CFMachPortCreateRunLoopSource(nil, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        typing = true
        draftShown = false
        typingStart = Date()
        caretOn = true
        edit = Draft(edit.text)               // resume a kept draft (or the text being edited) with the caret at its end
        lastKey = Date()
        renderDraft()
        blink?.invalidate()
        blink = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in self?.blinkTick() }
    }

    /// True once the typing bar is off screen (closed with ✕, Touch Bar switched), even if that happened at once.
    private func barGone() -> Bool {
        if draftLabel.window != nil { draftShown = true; return false }
        return draftShown || Date().timeIntervalSince(typingStart) > 1
    }

    private func blinkTick() {
        // Stop reading keys as soon as the bar is gone or after a quiet minute.
        if barGone() || Date().timeIntervalSince(lastKey) > 60 { return endTyping() }
        caretOn.toggle()
        renderDraft()
    }

    /// Runs for every key press and release while typing. Returning nil keeps the key from the app in front.
    private func handleKey(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if let held = endKey {                 // typing ended on Return/Esc: eat its repeats and key-up, then stop
            if key == held {
                if type == .keyUp { endKey = nil; teardownTap() }
                return nil
            }
            endKey = nil
            teardownTap()
            return pass
        }
        guard typing else { return pass }
        let flags = event.flags
        let command = flags.contains(.maskCommand), control = flags.contains(.maskControl)
        let option = flags.contains(.maskAlternate), shift = flags.contains(.maskShift)
        if type == .keyUp { return command || control ? pass : nil }
        guard type == .keyDown else { return pass }
        if barGone() { endTyping(); return pass }
        lastKey = Date()
        if key == kVK_Return || key == kVK_ANSI_KeypadEnter || key == kVK_Escape {
            endKey = key
            func giveUpOnKeyUp() {             // in case the key-up never comes; wait while the key is really held
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.endKey == key else { return }
                    if CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(key)) { return giveUpOnKeyUp() }
                    self.endKey = nil
                    self.teardownTap()
                }
            }
            giveUpOnKeyUp()
            key == kVK_Escape ? cancelDraft() : saveDraft()
            return nil
        }
        // Editing shortcuts act on the draft, like in any Mac text field, and never reach the app in front.
        let word: Draft.Unit = option ? .word : .char
        // The letter on this keyboard layout's ⌘ layer: right on QWERTZ, AZERTY and Dvorak, and still Latin on Cyrillic, Arabic…
        let letter = command || control ? NSEvent(cgEvent: event)?.characters(byApplyingModifiers: .command)?.lowercased() : nil
        switch key {
        case kVK_LeftArrow, kVK_RightArrow:
            edit.move(left: key == kVK_LeftArrow, command ? .line : word, extend: shift)
        case kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End:
            edit.move(left: key == kVK_UpArrow || key == kVK_Home, .line, extend: shift)
        case kVK_Delete:                       // ⌫, ⌥⌫ word, ⌘⌫ to the start; Shift-⌫ works like ⌫
            edit.deleteBackward(command ? .line : word)
        case kVK_ForwardDelete:                // fn-⌫, ⌥ word, ⌘ to the end
            edit.deleteForward(command ? .line : word)
        case _ where command:
            switch letter {
            case "a": edit.selectAll()
            case "c": if let text = edit.selectedText { copy(text) }
            case "x": if let text = edit.cut() { copy(text) }
            case "v": edit.insert(NSPasteboard.general.string(forType: .string) ?? "")
            case "z": if !shift { edit.undo() }   // ⇧⌘Z (redo) is swallowed, not passed to the app
            default:
                endTyping()                    // ⌘Tab, ⌘Space… leave typing and go through
                return pass
            }
        case _ where control:                  // the Emacs keys every Mac text field knows
            switch letter {
            case "a": edit.move(left: true, .line, extend: shift)
            case "e": edit.move(left: false, .line, extend: shift)
            case "b": edit.move(left: true, extend: shift)
            case "f": edit.move(left: false, extend: shift)
            case "h": edit.deleteBackward()
            case "d": edit.deleteForward()
            case "k":                   // cut to the end
                if let text = edit.cut() {
                    copy(text)
                } else {
                    let tail = String(Array(edit.text)[edit.caret...])
                    if !tail.isEmpty { copy(tail) }
                    edit.deleteForward(.line)
                }
            default:
                endTyping()                    // other Ctrl shortcuts leave typing and go through
                return pass
            }
        case kVK_Tab: break
        default: edit.insert(NSEvent(cgEvent: event)?.characters ?? "")
        }
        caretOn = true
        renderDraft()
        return nil
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// New to-do: save it and ask for a deadline. Edit: replace the text and go back to the list.
    @objc private func saveDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        endTyping()
        guard !text.isEmpty else { return openHome() }
        if editing, todos.indices.contains(selected) {
            todos[selected].text = text
            todosChanged()
            return openHome()
        }
        todos.append(Todo(text: text))
        saveTodos()
        refreshCounts()
        selected = todos.count - 1
        present(dateBar)
    }

    @objc private func cancelDraft() {
        draft = ""
        endTyping()
        openHome()
    }

    /// Stops reading keys right away. The tap itself goes after the current callback returns, or, when typing
    /// ended on Return/Esc, once that key is released so its repeats can't reach the app in front.
    private func endTyping() {
        guard typing else { return }
        typing = false
        blink?.invalidate()
        blink = nil
        if endKey == nil { teardownTap() }
        if shownBar === typingBar { dismissShownBar() }
    }

    private func teardownTap() {
        let oldTap = tap, oldSource = tapSource
        tap = nil
        tapSource = nil
        DispatchQueue.main.async {
            if let oldTap { CGEvent.tapEnable(tap: oldTap, enable: false); CFMachPortInvalidate(oldTap) }
            if let oldSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), oldSource, .commonModes) }
        }
    }

    /// Draft text with a blinking blue typing line at the caret; long drafts show a window around the caret.
    private func renderDraft() {
        let chars = Array(draft)
        let at = min(edit.caret, chars.count), selected = edit.selection
        let lo = max(0, min(at - 20, chars.count - 40)), hi = min(chars.count, lo + 40)
        let normal: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor]
        var highlight = normal
        highlight[.backgroundColor] = NSColor.systemBlue.withAlphaComponent(0.55)
        let caretStyle: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: .light),
                                                         .foregroundColor: caretOn ? NSColor.systemBlue : NSColor.clear, .baselineOffset: -1]
        let s = NSMutableAttributedString(string: lo > 0 ? "…" : "", attributes: normal)
        for i in lo...hi {
            if i == at, selected == nil { s.append(NSAttributedString(string: "|", attributes: caretStyle)) }
            if i < hi { s.append(NSAttributedString(string: String(chars[i]), attributes: selected?.contains(i) == true ? highlight : normal)) }
        }
        if hi < chars.count { s.append(NSAttributedString(string: "…", attributes: normal)) }
        let secure = IsSecureEventInputEnabled()   // a password field or Secure Keyboard Entry hides keys from us
        if draft.isEmpty || secure {
            var hint = normal
            hint[.foregroundColor] = secure ? NSColor.systemOrange : NSColor.secondaryLabelColor
            s.append(NSAttributedString(string: secure ? " Ada input aman yang aktif, ketikan nggak kebaca" : "Ketik to-do baru, Enter buat simpan", attributes: hint))
        }
        draftLabel.attributedStringValue = s
    }

    // MARK: Menu bar: see, tick and add to-dos from the desktop

    func menuNeedsUpdate(_ menu: NSMenu) {
        // The menu and its dialogs take the keyboard and can reorder to-dos: stop typing, close bars that hold an index.
        endTyping()
        if shownBar === itemBar || shownBar === dateBar { dismissShownBar() }
        menu.removeAllItems()
        let open = todos.filter { !$0.done }.count
        var limits = [("Limit 5 jam", usage.five_hour, false), ("Limit mingguan", usage.seven_day, true)]
        if let model = usage.seven_day_model { limits.append(("Limit mingguan \(model.name ?? "model")", model, true)) }
        if let tokenLine { menu.addItem(withTitle: "Total \(tokenLine) di Mac ini", action: nil, keyEquivalent: "") }
        for (name, limit, weekday) in limits {
            let item = NSMenuItem(title: limitLine(name, limit, weekday: weekday), action: nil, keyEquivalent: "")
            item.image = dot(percent(limit).map(limitColor) ?? .systemGray)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: open == 0 ? "Semua to-do beres" : "\(open) to-do belum selesai", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        for (index, todo) in todos.enumerated() {
            let item = NSMenuItem(title: todo.text + (todo.due.map { "  —  " + dueLabel($0) } ?? ""), action: nil, keyEquivalent: "")
            item.state = todo.done ? .on : .off
            item.image = dot(urgency(todo) ?? .systemGray)
            let actions = NSMenu()
            actions.addItem(menuItem(todo.done ? "Tandai belum selesai" : "Tandai selesai", #selector(menuToggle(_:)), index))
            actions.addItem(menuItem("Edit…", #selector(menuEdit(_:)), index))
            actions.addItem(menuItem("Hapus", #selector(menuDelete(_:)), index))
            item.submenu = actions
            menu.addItem(item)
        }
        if !todos.isEmpty { menu.addItem(.separator()) }
        menu.addItem(menuItem("Tambah to-do…", #selector(menuAdd), 0, key: "n"))
        if todos.contains(where: { $0.done }) { menu.addItem(menuItem("Hapus yang selesai", #selector(clearDone), 0)) }
        saveTrash()                                // drops what is past 30 days
        if !trash.isEmpty {
            let item = NSMenuItem(title: "Sampah (\(trash.count))", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            let inside = NSMenu()
            inside.addItem(withTitle: "Klik buat pulihkan", action: nil, keyEquivalent: "")
            for (index, gone) in trash.prefix(30).enumerated() { inside.addItem(menuItem(gone.todo.text, #selector(restoreTrashed(_:)), index)) }
            inside.addItem(.separator())
            inside.addItem(menuItem("Kosongkan sampah…", #selector(emptyTrash), 0))
            item.submenu = inside
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Keluar TouchDo", #selector(quit), 0, key: "q"))
    }

    private func menuItem(_ title: String, _ action: Selector, _ tag: Int, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.tag = tag
        return item
    }

    private func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    @objc private func menuToggle(_ sender: NSMenuItem) {
        guard todos.indices.contains(sender.tag) else { return }
        todos[sender.tag].done.toggle()
        todosChanged()
    }

    @objc private func menuDelete(_ sender: NSMenuItem) {
        guard todos.indices.contains(sender.tag) else { return }
        moveToTrash([todos.remove(at: sender.tag)])
        todosChanged()
    }

    @objc private func menuEdit(_ sender: NSMenuItem) {
        guard todos.indices.contains(sender.tag) else { return }
        let old = todos[sender.tag]
        // The Touch Bar can change the list while the dialog is open: find the to-do again (it may have been ticked).
        guard let answer = askTodo("Edit to-do", old),
              let index = todos.firstIndex(of: old) ?? todos.firstIndex(where: { $0.text == old.text && $0.due == old.due }) else { return }
        todos[index].text = answer.text
        todos[index].due = answer.due
        todosChanged()
    }

    @objc private func menuAdd() {
        guard let answer = askTodo("To-do baru", nil) else { return }
        todos.append(Todo(text: answer.text, due: answer.due))
        todosChanged()
    }

    /// Small dialog: text plus an optional deadline. Returns nil when cancelled or empty.
    private func askTodo(_ title: String, _ todo: Todo?) -> (text: String, due: Date?)? {
        hideResting()
        NSApp.activate(ignoringOtherApps: true)   // activate() needs macOS 14
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Simpan")
        alert.addButton(withTitle: "Batal")
        let field = NSTextField(frame: NSRect(x: 0, y: 34, width: 300, height: 24))
        field.placeholderString = "Mau ngapain?"
        field.stringValue = todo?.text ?? ""
        let hasDue = NSButton(checkboxWithTitle: "Deadline", target: nil, action: nil)
        hasDue.frame = NSRect(x: 0, y: 4, width: 95, height: 22)
        hasDue.state = todo?.due == nil ? .off : .on
        let picker = NSDatePicker(frame: NSRect(x: 100, y: 2, width: 200, height: 26))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .yearMonthDay
        picker.dateValue = todo?.due ?? Date()
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        [field, hasDue, picker].forEach(box.addSubview)
        alert.accessoryView = box
        alert.window.initialFirstResponder = field
        let answer = alert.runModal()
        NSApp.hide(nil)                      // hand focus back so the Touch Bar buttons work again
        guard answer == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (text, hasDue.state == .on ? calendar.startOfDay(for: picker.dateValue) : nil)
    }

    // MARK: Keep awake (survives a quick relaunch by launchd, but not a Quit or a later start)

    private let awakeTitle = NSTextField(labelWithString: "Nyala terus:")

    @objc private func openAwake() {
        awakeTitle.stringValue = insomniaBinary() != nil ? "Insomnia:" : "Nyala terus:"
        refreshAwake()
        present(awakeBar)
    }

    @objc private func awakeChosen(_ sender: NSButton) {
        if let insomnia = insomniaBinary() {
            setAwake(minutes: sender.tag)          // ours covers the gap, and stays on if Insomnia can't start
            let seconds = sender.tag > 0 ? sender.tag * 60 : insomniaMaxSeconds()
            runInsomnia(insomnia, [["end"], ["start", "\(seconds)"]], choice: sender.tag)
        } else {
            setAwake(minutes: sender.tag)
        }
        dismissShownBar()
    }

    @objc private func awakeOffChosen() {
        setAwake(minutes: nil)
        if let insomnia = insomniaBinary() { runInsomnia(insomnia, [["end"]], choice: nil) }   // also ends one still starting
        dismissShownBar()
    }

    // MARK: Insomnia (com.kgarg.insomnia): when its --session command is there, ☕ starts and ends its sessions

    private var insomniaEnds: Date?          // end of the running Insomnia session, read from its session.json
    private var insomniaMinutes: Int?        // the choice that started it here, to highlight it
    private var insomniaChoiceEnds: Date?    // the session that choice belongs to
    private var insomniaRequest = 0          // only the latest tap decides
    private let insomniaQueue = DispatchQueue(label: "io.github.rasyachremony.TouchDo.insomnia", qos: .userInitiated)   // one command at a time
    private let insomniaDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Insomnia")

    /// The Insomnia binary, only if it is a version with --session (it says so in its Info.plist) and is running.
    private func insomniaBinary() -> String? {
        // Read Info.plist fresh: Bundle caches it, so an Insomnia updated while we run would stay "old" forever.
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.kgarg.insomnia").first,
              let plist = app.bundleURL.flatMap({ NSDictionary(contentsOf: $0.appendingPathComponent("Contents/Info.plist")) }),
              (plist["InsomniaSessionCommandVersion"] as? Int ?? 0) >= 1 else { return nil }
        return app.executableURL?.path
    }

    private func insomniaMaxSeconds() -> Int {
        let config = try? JSONSerialization.jsonObject(with: Data(contentsOf: insomniaDir.appendingPathComponent("config.json"))) as? [String: Any]
        return config?["maxDuration"] as? Int ?? 30 * 24 * 3600   // "∞" = Insomnia's longest session
    }

    /// Runs `Insomnia --session …` commands in order, off the main thread, then rereads the session.
    private func runInsomnia(_ binary: String, _ commands: [[String]], choice: Int?) {
        insomniaRequest += 1
        let request = insomniaRequest
        insomniaQueue.async { [weak self] in
            var ok = false
            for args in commands {
                let run = Process()
                run.executableURL = URL(fileURLWithPath: binary)
                run.arguments = ["--session"] + args
                run.standardInput = FileHandle.nullDevice
                run.standardOutput = FileHandle.nullDevice
                run.standardError = FileHandle.nullDevice
                ok = false
                guard (try? run.run()) != nil else { break }
                run.waitUntilExit()
                ok = run.terminationStatus == 0
                if !ok { NSLog("TouchDo: Insomnia --session \(args.joined(separator: " ")) failed (\(run.terminationStatus))") }
            }
            DispatchQueue.main.async {
                guard let self, request == self.insomniaRequest else { return }
                if let choice, ok {
                    self.setAwake(minutes: nil)    // Insomnia has it now (lid closed too)
                    self.insomniaMinutes = choice
                    self.insomniaChoiceEnds = self.insomniaEnds
                }
                self.refreshAwake()
            }
        }
    }

    /// The running Insomnia session's end time, or nil. session.json is Insomnia's own record of it.
    private func readInsomnia() {
        guard insomniaBinary() != nil,
              let data = try? Data(contentsOf: insomniaDir.appendingPathComponent("session.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["endsAt"] as? String else { insomniaEnds = nil; insomniaMinutes = nil; return }
        let iso = ISO8601DateFormatter()
        var end = iso.date(from: text)
        if end == nil { iso.formatOptions.insert(.withFractionalSeconds); end = iso.date(from: text) }
        insomniaEnds = end.flatMap { $0 > Date() ? $0 : nil }
        if insomniaEnds == nil || insomniaEnds != insomniaChoiceEnds { insomniaMinutes = nil }   // another session
    }

    /// minutes: nil = off, 0 = until switched off, otherwise a timer.
    private func setAwake(minutes: Int?, until: Date? = nil) {
        if let activity = awakeActivity { ProcessInfo.processInfo.endActivity(activity) }
        awakeActivity = nil
        awakeMinutes = minutes
        awakeUntil = until ?? minutes.flatMap { $0 > 0 ? Date().addingTimeInterval(Double($0) * 60) : nil }
        if minutes != nil {
            awakeActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
                                                                  reason: "TouchDo: Mac nyala terus")
        }
        let defaults = UserDefaults.standard
        if let minutes { defaults.set(minutes, forKey: "awakeMinutes") } else { defaults.removeObject(forKey: "awakeMinutes") }
        defaults.set(awakeUntil, forKey: "awakeUntil")
        defaults.set(minutes == nil ? nil : Date(), forKey: "awakeHeartbeat")
        refreshAwake()
    }

    /// Only a relaunch within a minute (crash, Control Strip restart) brings keep-awake back.
    private func restoreAwake() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "awakeMinutes") != nil,
              let beat = defaults.object(forKey: "awakeHeartbeat") as? Date, Date().timeIntervalSince(beat) < 60 else {
            return setAwake(minutes: nil)
        }
        setAwake(minutes: defaults.integer(forKey: "awakeMinutes"), until: defaults.object(forKey: "awakeUntil") as? Date)
    }

    private var awakeOn: Bool { awakeActivity != nil || insomniaEnds != nil }

    private func refreshAwake() {
        if let end = awakeUntil, end <= Date() { return setAwake(minutes: nil) }
        readInsomnia()
        let on = awakeOn
        // With both on, show the one that lasts longer.
        let ours = awakeActivity != nil && (awakeUntil == nil || insomniaEnds == nil || awakeUntil! >= insomniaEnds!)
        trayButton.image = trayLogo()
        if let b = awakeButton {
            b.image = icon(on ? "cup.and.saucer.fill" : "cup.and.saucer", "Mac nyala terus", on ? .systemYellow : nil)
            let end = ours ? awakeUntil : insomniaEnds
            b.title = on ? (end.map(remaining) ?? "∞") : ""
            b.imagePosition = b.title.isEmpty ? .imageOnly : .imageLeading
        }
        let chosen = ours ? awakeMinutes : insomniaMinutes
        for (minutes, b) in choiceButtons { b.bezelColor = minutes == chosen ? NSColor.systemYellow.withAlphaComponent(0.6) : nil }
    }

    private func remaining(_ end: Date) -> String {
        let minutes = max(1, Int(ceil(end.timeIntervalSinceNow / 60)))
        if minutes >= 48 * 60 { return "\(minutes / (24 * 60))h" }   // days ("h" = hari)
        return minutes >= 60 ? String(format: "%d:%02d", minutes / 60, minutes % 60) : "\(minutes)m"
    }

    // MARK: Voice: hold the mic to talk to Claude, or double tap to keep dictating (Quick Entry dictation shortcut ⌃⌥⌘D)

    private func micDown(stayOn: Bool = false) {
        guard !talking, hasAccessibility() else { return }
        let claude = NSRunningApplication.runningApplications(withBundleIdentifier: claudeID).first
        // Claude shows up before its ⌃⌥⌘D shortcut works; a press that early would be lost and flip every later one.
        if let claude, !claude.isFinishedLaunching || Date().timeIntervalSince(claude.launchDate ?? .distantPast) < claudeWarmUp { return }
        guard claude != nil else {
            // Claude isn't open: start it; the next hold talks once it is up.
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            return
        }
        talking = true
        micView?.latched = stayOn
        pressClaudeShortcut()                 // start dictating
    }

    private func micUp() {
        guard talking else { return }
        talking = false
        micView?.latched = false
        pressClaudeShortcut()                 // finish dictating
        dismissShownBar()
    }

    private func pressClaudeShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_D), keyDown: down)
            event?.flags = [.maskControl, .maskAlternate, .maskCommand]
            event?.post(tap: .cghidEventTap)
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
