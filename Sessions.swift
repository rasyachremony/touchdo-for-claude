// Claude Code sessions running on this Mac, from the files Claude Code keeps in ~/.claude/sessions (one per process).
// ponytail: those files are Claude Code's own bookkeeping, not a documented API; if they change, the label goes empty.
import Foundation

struct Session: Decodable {
    var pid: Int32
    var kind: String?, name: String?, status: String?
    var waitingFor: String?                  // with status "waiting": "permission prompt", "input needed", …
    var statusUpdatedAt: Double?             // milliseconds
    var hostSessionId: String?               // the Claude app's own id ("local_…") for a session started there

    /// Opens this session in the Claude app; nil for a session that runs in a terminal.
    var appLink: URL? {
        guard let id = hostSessionId, id.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "claude://code/continue?session=\(id)")
    }

    var working: Bool { status == "busy" }
    /// Stopped until you answer: a permission prompt, a question or a dialog.
    var needsYou: Bool { status == "waiting" }

    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")

    /// Live interactive sessions working or waiting for you (not idle, stopped or past ones): waiting ones first, then the latest.
    static func active(in folder: URL = folder, alive: (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }   // the .key files next to them are never read
            .compactMap { try? JSONDecoder().decode(Session.self, from: Data(contentsOf: $0)) }
            .filter { ($0.working || $0.needsYou) && $0.kind == "interactive" && alive($0.pid) }
            .sorted { ($0.needsYou ? 1 : 0, $0.statusUpdatedAt ?? 0) > ($1.needsYou ? 1 : 0, $1.statusUpdatedAt ?? 0) }
    }
}
