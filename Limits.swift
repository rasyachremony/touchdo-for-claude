// Claude plan limits and the token total, without spending any tokens.
// ponytail: both read Claude Code's own output (the text of `claude -p /usage`, its stats cache and transcripts), not a
// documented API; if either changes, the bars keep their last numbers.
import Foundation

enum ClaudeUsage {
    /// The limits in `claude -p /usage`, shaped like usage.json: used_percentage 0-100, resets_at in epoch seconds.
    /// "Current session" is the 5-hour window, "Current week (all models)" the weekly one, and the first other
    /// "Current week (…)" a per-model weekly window (Fable), kept with its name under "seven_day_model".
    static func parse(_ text: String, now: Date = Date()) -> [String: Any] {
        let pattern = try! NSRegularExpression(pattern: #"^Current (session|week(?: \(([^)]+)\))?): (\d+(?:\.\d+)?)% used(?: · resets (.+?)(?: \(([^)]+)\))?$)?"#,
                                               options: .anchorsMatchLines)
        var usage: [String: Any] = [:]
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            func group(_ i: Int) -> String? { Range(match.range(at: i), in: text).map { String(text[$0]) } }
            guard let used = group(3).flatMap(Double.init) else { continue }
            var limit: [String: Any] = ["used_percentage": used]
            if let when = group(4), let reset = resetDate(when, zone: group(5), now: now) { limit["resets_at"] = reset.timeIntervalSince1970 }
            if group(1) == "session" { usage["five_hour"] = limit }
            else if group(2) == nil || group(2) == "all models" { usage["seven_day"] = limit }
            else if usage["seven_day_model"] == nil { limit["name"] = group(2); usage["seven_day_model"] = limit }
        }
        return usage
    }

    /// "Nov 28 at 1pm", "Nov 28 at 1:30pm" or just "7pm" (the next 7pm), in the given time zone. The text has no year: a
    /// date more than a day back belongs to next year (December reading a January reset).
    static func resetDate(_ text: String, zone: String?, now: Date) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = f.timeZone
        f.defaultDate = calendar.startOfDay(for: now)   // fills the missing parts: today, minute and seconds 0
        for format in ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d, h:mma", "MMM d, ha", "h:mma", "ha"] {
            f.dateFormat = format
            guard let date = f.date(from: text) else { continue }
            if !format.hasPrefix("MMM"), date < now { return calendar.date(byAdding: .day, value: 1, to: date) }   // "1am" after midnight
            if date < now.addingTimeInterval(-86_400) { return calendar.date(byAdding: .year, value: 1, to: date) }
            return date
        }
        return nil
    }
}

/// Every token Claude Code has used on this Mac (input, output and cache, like its stats): its stats cache up to the
/// day it was last computed, plus each reply in the transcripts after that day. A transcript is read once, then only
/// from where it grew. Use from one thread at a time.
final class TokenTotal {
    private let claude: URL
    private var base = 0, after = Date.distantPast, cacheStamp: Date?
    private var offsets: [String: UInt64] = [:], seen = Set<String>(), counted = 0
    private let iso = ISO8601DateFormatter()

    init(claude: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")) {
        self.claude = claude
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func update() -> Int {
        let cache = claude.appendingPathComponent("stats-cache.json")
        let stamp = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if stamp != cacheStamp {                   // recomputed by /stats: count again after its new last day
            cacheStamp = stamp
            base = 0
            after = .distantPast
            offsets = [:]; seen = []; counted = 0
            if let data = try? Data(contentsOf: cache), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for case let model as [String: Any] in (json["modelUsage"] as? [String: Any] ?? [:]).values { base += tokens(model) }
                // A UTC day (Claude Code writes toISOString's date): count from 00:00 UTC of the day after it.
                let day = DateFormatter()
                day.locale = Locale(identifier: "en_US_POSIX")
                day.timeZone = TimeZone(identifier: "UTC")
                day.dateFormat = "yyyy-MM-dd"
                if let last = (json["lastComputedDate"] as? String).flatMap(day.date) { after = last.addingTimeInterval(86_400) }
            }
        }
        let files = FileManager.default.enumerator(at: claude.appendingPathComponent("projects"), includingPropertiesForKeys: [.fileSizeKey])
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "jsonl", let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(UInt64.init) else { continue }
            var start = offsets[url.path] ?? 0
            if size < start { start = 0 }          // rewritten: read it again, seen ids keep replies from counting twice
            guard size > start, let handle = try? FileHandle(forReadingFrom: url), (try? handle.seek(toOffset: start)) != nil else { continue }
            defer { try? handle.close() }
            var rest = Data()                      // a line cut by the chunk edge
            while true {
                let more: Bool = autoreleasepool {     // 8 MB at a time: transcripts can be gigabytes
                    guard let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty else { return false }
                    rest.append(chunk)
                    guard let end = rest.lastIndex(of: 10) else { return true }   // whole lines only; a half-written one waits
                    for line in rest[..<end].split(separator: 10) where line.range(of: Data(#""usage""#.utf8)) != nil { count(Data(line)) }
                    start += UInt64(rest.distance(from: rest.startIndex, to: end) + 1)
                    rest = Data(rest[rest.index(after: end)...])
                    return true
                }
                if !more { break }
            }
            offsets[url.path] = start
        }
        return base + counted
    }

    private func count(_ line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              json["type"] as? String == "assistant",
              let time = (json["timestamp"] as? String).flatMap(iso.date), time >= after,
              let message = json["message"] as? [String: Any], let id = message["id"] as? String,
              let usage = message["usage"] as? [String: Any], seen.insert(id).inserted else { return }   // one reply, several lines
        counted += tokens(usage)
    }

    private func tokens(_ usage: [String: Any]) -> Int {
        ["inputTokens", "outputTokens", "cacheReadInputTokens", "cacheCreationInputTokens",
         "input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"].reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
    }

    /// "9.4B token", "350M token".
    static func label(_ total: Int) -> String {
        total >= 1_000_000_000 ? String(format: "%.1fB token", Double(total) / 1e9) : String(format: "%.0fM token", Double(total) / 1e6)
    }
}
