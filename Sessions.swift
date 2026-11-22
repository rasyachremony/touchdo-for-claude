// Claude Code sessions running on this Mac, from the files Claude Code keeps in ~/.claude/sessions (one per process).
// ponytail: those files are Claude Code's own bookkeeping, not a documented API; if they change, the label goes empty.
import Foundation

struct Session: Decodable {
    var pid: Int32
    var kind: String?, name: String?, status: String?
    var statusUpdatedAt: Double?             // milliseconds

    var working: Bool { status == "busy" }

    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")

    /// Live interactive sessions working right now (not idle, stopped or past ones), the latest first.
    static func active(in folder: URL = folder, alive: (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }   // the .key files next to them are never read
            .compactMap { try? JSONDecoder().decode(Session.self, from: Data(contentsOf: $0)) }
            .filter { $0.working && $0.kind == "interactive" && alive($0.pid) }
            .sorted { ($0.statusUpdatedAt ?? 0) > ($1.statusUpdatedAt ?? 0) }
    }
}
