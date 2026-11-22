// The Claude plan Claude Code is signed in to ("Max 5x", "Pro", …), from the plan fields in ~/.claude.json.
// ponytail: Claude Code's own state file, not a documented API; if it changes, only the logo shows.
import Foundation

struct Plan: Decodable {
    struct Account: Decodable { var organizationType: String?, organizationRateLimitTier: String?, userRateLimitTier: String? }
    var oauthAccount: Account?               // nothing else in the file is decoded

    static let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")

    /// Two short lines: the plan and, for Max, its size. Empty when signed out.
    var lines: [String] {
        guard let type = oauthAccount?.organizationType, type.hasPrefix("claude_") else { return [] }
        let name = type.dropFirst("claude_".count).replacingOccurrences(of: "_", with: " ").capitalized
        let tier = oauthAccount?.userRateLimitTier ?? oauthAccount?.organizationRateLimitTier ?? ""
        let size = tier.split(separator: "_").last.map(String.init) ?? ""
        return size.range(of: "^[0-9]+x$", options: .regularExpression) != nil ? [name, size] : [name]
    }

    static func current(_ file: URL = file) -> Plan? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Plan.self, from: $0) }
    }
}
