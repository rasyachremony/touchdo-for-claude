// Self-check, run with ./test.sh
import Foundation

@main enum TestDraft {
    static func main() {
        var d = Draft("beli kopi susu")
        d.selectAll(); d.deleteBackward()                       // ⌘A then ⌫ clears everything
        assert(d.text == "" && d.caret == 0)
        d.undo(); assert(d.text == "beli kopi susu")            // ⌘Z brings it back
        d = Draft("beli kopi susu")
        d.deleteBackward(.word); assert(d.text == "beli kopi ")  // ⌥⌫ removes the last word
        d.deleteBackward(.line); assert(d.text == "")           // ⌘⌫ removes to the start
        d = Draft("beli kopi susu")
        d.move(left: true, .word); d.move(left: true, .word, extend: true)   // ⌥← then ⇧⌥← selects "kopi "
        assert(d.selectedText == "kopi ")
        d.insert("teh "); assert(d.text == "beli teh susu")     // typing replaces the selection
        d.move(left: false, .line); d.move(left: true, extend: true); d.move(left: true, extend: true)
        assert(d.selectedText == "su")                          // ⇧← twice
        d.move(left: true); assert(d.selection == nil && d.caret == d.text.count - 2)   // ← collapses to the left edge
        d.deleteForward(.line); assert(d.text == "beli teh su") // Ctrl-K removes to the end
        assert(d.cut() == nil)                                  // nothing selected, nothing cut
        d.selectAll(); assert(d.cut() == "beli teh su" && d.text == "")
        d = Draft("a"); d.insert("\u{301}"); assert(d.caret <= d.text.count)   // combining accent never pushes the caret past the end
        d = Draft("x"); d.insert("\n\u{7}"); assert(d.text == "x ")            // newline becomes a space, control chars dropped
        d = Draft("beli kopi"); d.move(left: false, .line, extend: true)       // ⇧→ at the end selects nothing
        d.deleteBackward(); assert(d.text == "beli kop" && d.selection == nil)
        assert(d.selectedText == nil)                                         // used to crash (stale anchor past the end)
        d = Draft("e"); d.move(left: true); d.insert("\u{301}x"); assert(d.text == "\u{301}xe" || d.caret <= d.text.count)
        // ClaudeChat: Return may only ever be pressed on the new-session page that holds exactly the to-do.
        assert(ClaudeChat.normalized(" beli\n kopi  susu\n") == "beli kopi susu")
        assert(ClaudeChat.isNewSession(URL(string: "https://claude.ai/epitaxy?q=x")))
        for other in ["https://claude.ai/epitaxy/local_1", "https://claude.ai/epitaxy/scheduled", "https://claude.ai/new", "https://evilclaude.ai/epitaxy", "file:///epitaxy"] {
            assert(!ClaudeChat.isNewSession(URL(string: other)))
        }
        assert(ClaudeChat.endsInMention("tanya @budi ") && !ClaudeChat.endsInMention("@budi cek ini") && !ClaudeChat.endsInMention(""))
        assert(ClaudeChat.endsInMention("/review") && !ClaudeChat.endsInMention("/review cek ini") && !ClaudeChat.endsInMention("baca a/b"))
        // Sessions: only live interactive ones that are working or waiting for you; waiting first, then the latest.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tbk-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (pid, kind, status) in [(1, "interactive", "busy"), (2, "interactive", "waiting"), (3, "interactive", "idle"), (4, "print", "busy"), (5, "interactive", "busy"), (6, "interactive", "busy"), (7, "interactive", "waiting")] {
            try! "{\"pid\":\(pid),\"kind\":\"\(kind)\",\"status\":\"\(status)\",\"statusUpdatedAt\":\(pid)}".write(to: dir.appendingPathComponent("\(pid).json"), atomically: true, encoding: .utf8)
        }
        try! "secret".write(to: dir.appendingPathComponent("1.abc.key"), atomically: true, encoding: .utf8)
        assert(Session.active(in: dir, alive: { $0 != 5 }).map(\.pid) == [7, 2, 6, 1])   // waiting ones first
        try? FileManager.default.removeItem(at: dir)
        // Plan: the name and, for Max, its size; the rest of the file is ignored.
        func plan(_ json: String) -> [String] { (try? JSONDecoder().decode(Plan.self, from: Data(json.utf8)))?.lines ?? ["?"] }
        assert(plan("{\"oauthAccount\":{\"organizationType\":\"claude_max\",\"organizationRateLimitTier\":\"default_claude_max_5x\"}}") == ["Max", "5x"])
        assert(plan("{\"oauthAccount\":{\"organizationType\":\"claude_pro\",\"organizationRateLimitTier\":\"default_claude_ai\"}}") == ["Pro"])
        assert(plan("{}") == [])
        // Limits: the text of `claude -p /usage` becomes usage.json's shape, with the per-model week under its name.
        let jakarta = TimeZone(identifier: "Asia/Jakarta")!
        var parts = DateComponents(); parts.year = 2026; parts.month = 11; parts.day = 24; parts.hour = 15; parts.minute = 7; parts.second = 42
        var jkt = Calendar(identifier: .gregorian); jkt.timeZone = jakarta
        let now = jkt.date(from: parts)!
        let text = """
        Current session: 11% used · resets Nov 24 at 7pm (Asia/Jakarta)
        Current week (all models): 45% used · resets Nov 28 at 1:30pm (Asia/Jakarta)
        Current week (Fable): 24% used · resets Nov 28 at 1pm (Asia/Jakarta)
        Last 24h · 1549 requests · 8 sessions
          93%  Check which models your subagents use
        """
        let limits = ClaudeUsage.parse(text, now: now)
        func reset(_ key: String) -> Date? { ((limits[key] as? [String: Any])?["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) } }
        func used(_ key: String) -> Double? { (limits[key] as? [String: Any])?["used_percentage"] as? Double }
        assert(used("five_hour") == 11 && used("seven_day") == 45 && used("seven_day_model") == 24)
        assert((limits["seven_day_model"] as? [String: Any])?["name"] as? String == "Fable")
        assert(reset("five_hour") == jkt.date(bySettingHour: 19, minute: 0, second: 0, of: now))
        assert(jkt.dateComponents([.month, .day, .hour, .minute], from: reset("seven_day")!) == DateComponents(month: 11, day: 28, hour: 13, minute: 30))
        assert(jkt.component(.year, from: ClaudeUsage.resetDate("Jan 2 at 1pm", zone: "Asia/Jakarta", now: now)!) == 2027)   // no year in the text
        let late = jkt.date(bySettingHour: 23, minute: 10, second: 0, of: now)!
        assert(ClaudeUsage.resetDate("1am", zone: "Asia/Jakarta", now: late) == jkt.date(bySettingHour: 1, minute: 0, second: 0, of: late.addingTimeInterval(3600)))   // after midnight: tomorrow
        assert(ClaudeUsage.resetDate("11:30pm", zone: "Asia/Jakarta", now: late)! > late)
        assert(ClaudeUsage.parse("Current week: 3% used", now: now).keys.sorted() == ["seven_day"])
        assert(ClaudeUsage.parse("Not signed in", now: now).isEmpty)
        // Token total: the stats cache, plus replies after its last day, each reply once even over several lines.
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("tbk-\(UUID().uuidString)")
        let project = home.appendingPathComponent("projects/p")
        try! FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try! #"{"lastComputedDate":"2026-11-18","modelUsage":{"a":{"inputTokens":100,"outputTokens":50,"cacheReadInputTokens":800,"cacheCreationInputTokens":50}}}"#
            .write(to: home.appendingPathComponent("stats-cache.json"), atomically: true, encoding: .utf8)
        func reply(_ id: String, _ day: String, _ n: Int) -> String {
            #"{"type":"assistant","timestamp":"\#(day)T12:00:00.000Z","message":{"id":"\#(id)","usage":{"input_tokens":\#(n),"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        }
        let log = project.appendingPathComponent("s.jsonl")
        try! [reply("old", "2026-11-17", 5000), reply("m1", "2026-11-20", 9), reply("m1", "2026-11-20", 9), "{\"type\":\"user\"}"].joined(separator: "\n").appending("\n")
            .write(to: log, atomically: true, encoding: .utf8)
        let total = TokenTotal(claude: home)
        assert(total.update() == 1000 + 10)                     // cache + m1 once; the old reply is in the cache already
        let more = try! FileHandle(forWritingTo: log); more.seekToEndOfFile()
        more.write(Data((reply("m2", "2026-11-21", 99) + "\n" + reply("m3", "2026-11-21", 7)).utf8)); try! more.close()   // m3 half-written
        assert(total.update() == 1010 + 100)                    // only the new whole line
        assert(TokenTotal.label(9_424_727_542) == "9.4B token" && TokenTotal.label(350_000_000) == "350M token")
        try? FileManager.default.removeItem(at: home)
        print("Draft, ClaudeChat, Session, Plan, limits and token total self-check passed")
    }
}
