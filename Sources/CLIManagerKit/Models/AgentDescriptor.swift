import Foundation

/// File format used for slash-command files in an agent's commands directory.
public enum CommandFormat: Sendable {
    case markdown
    case geminiTOML
}

/// A single AI coding agent this tool knows how to target — where it looks for skills,
/// and where it looks for slash commands (if it supports them at all).
public struct AgentDescriptor: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let skillsPath: URL?
    public let commandsPath: URL?
    public let commandFormat: CommandFormat

    public init(id: String, name: String, skillsPath: URL?, commandsPath: URL?, commandFormat: CommandFormat) {
        self.id = id
        self.name = name
        self.skillsPath = skillsPath
        self.commandsPath = commandsPath
        self.commandFormat = commandFormat
    }

    /// The directory this agent reads items of `kind` from, or `nil` if it doesn't support that kind.
    public func path(for kind: ManagedItemKind) -> URL? {
        switch kind {
        case .skill: return skillsPath
        case .command: return commandsPath
        case .dotfile: return nil
        }
    }

    /// File extension a command file gets when installed for this agent.
    public var commandFileExtension: String { commandFormat == .geminiTOML ? "toml" : "md" }
}

/// The canonical set of agents this tool supports. Single source of truth for both skill
/// targets and command targets — kept as one list so an agent's identity (id, name) is
/// defined exactly once. Computed on every access (not cached) since each entry's paths are
/// derived from `home`, which itself re-reads a `HOME` override on every access — otherwise a
/// test or embedding app that sets `HOME` after this was first read would see stale paths.
public var allAgentDescriptors: [AgentDescriptor] {
    [
    .init(
        id: "opencode", name: "OpenCode",
        skillsPath: home.appendingPathComponent(".config/opencode/skills"),
        commandsPath: home.appendingPathComponent(".config/opencode/commands"),
        commandFormat: .markdown
    ),
    .init(
        id: "claude-code", name: "Claude Code",
        skillsPath: home.appendingPathComponent(".claude/skills"),
        commandsPath: home.appendingPathComponent(".claude/commands"),
        commandFormat: .markdown
    ),
    .init(
        id: "github-copilot", name: "GitHub Copilot",
        skillsPath: home.appendingPathComponent(".copilot/skills"),
        commandsPath: nil,
        commandFormat: .markdown
    ),
    .init(
        id: "cursor", name: "Cursor",
        skillsPath: home.appendingPathComponent(".cursor/skills"),
        commandsPath: nil,
        commandFormat: .markdown
    ),
    .init(
        id: "windsurf", name: "Windsurf",
        skillsPath: home.appendingPathComponent(".codeium/windsurf/skills"),
        commandsPath: home.appendingPathComponent(".codeium/windsurf/global_workflows"),
        commandFormat: .markdown
    ),
    .init(
        id: "gemini-cli", name: "Gemini CLI",
        skillsPath: home.appendingPathComponent(".gemini/skills"),
        commandsPath: home.appendingPathComponent(".gemini/commands"),
        commandFormat: .geminiTOML
    ),
    .init(
        id: "codex", name: "Codex",
        skillsPath: home.appendingPathComponent(".codex/skills"),
        commandsPath: nil,
        commandFormat: .markdown
    )
    ]
}

extension AgentDescriptor {
    /// Agents whose directory for `kind` already exists on disk.
    public static func detected(for kind: ManagedItemKind) -> [AgentDescriptor] {
        allAgentDescriptors.filter {
            guard let path = $0.path(for: kind) else {
                return false
            }
            return fm.fileExists(atPath: path.path)
        }
    }

    /// Resolves agent ids to descriptors that support `kind`. Ids that don't match a known
    /// agent, or match one that doesn't support `kind`, are returned in `unknown` so the
    /// caller can warn about them.
    public static func resolve(
        ids: [String], for kind: ManagedItemKind
    ) -> (resolved: [AgentDescriptor], unknown: [String]) {
        var resolved: [AgentDescriptor] = []
        var unknown: [String] = []
        for id in ids {
            guard let agent = allAgentDescriptors.first(where: { $0.id == id }), agent.path(for: kind) != nil else {
                unknown.append(id)
                continue
            }
            resolved.append(agent)
        }
        return (resolved, unknown)
    }
}
