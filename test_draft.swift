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
        print("Draft, ClaudeChat, Session and Plan self-check passed")
    }
}
