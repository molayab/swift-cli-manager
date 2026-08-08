import Foundation

/// The three kinds of thing this tool tracks in the repo and symlinks out to agents.
public enum ManagedItemKind: String, CaseIterable, Sendable {
    case skill
    case command
    case dotfile
}

/// A single skill, slash command, or dotfile tracked in the repo.
///
/// The three kinds share the same identity, frontmatter, and private/public toggle — this is
/// the one model consumers (the CLI, or an embedding app) work with, instead of three
/// near-identical per-kind types. `dotfileLink`/`dotfileFileName` are the only kind-specific
/// fields, populated for `.dotfile` items only.
public struct ManagedItem: Sendable, Identifiable {
    public let kind: ManagedItemKind
    public let id: String
    public let name: String
    public let description: String
    /// Frontmatter-stripped body content. Only `.command` items currently use this (for
    /// Gemini TOML export), but it's populated uniformly for all kinds.
    public let body: String
    public let isPrivate: Bool
    /// Where this item lives in the repo: a directory for `.skill`/`.dotfile` (containing
    /// SKILL.md/DOTFILE.md alongside any other files), the file itself for `.command`.
    public let location: URL
    public let dotfileLink: String?
    public let dotfileFileName: String?

    public init(
        kind: ManagedItemKind,
        id: String,
        name: String,
        description: String,
        body: String,
        isPrivate: Bool,
        location: URL,
        dotfileLink: String? = nil,
        dotfileFileName: String? = nil
    ) {
        self.kind = kind
        self.id = id
        self.name = name
        self.description = description
        self.body = body
        self.isPrivate = isPrivate
        self.location = location
        self.dotfileLink = dotfileLink
        self.dotfileFileName = dotfileFileName
    }

    // MARK: - Dotfile-only computed properties

    /// The actual file inside the repo directory. `nil` for non-dotfile kinds.
    public var sourceFile: URL? {
        guard kind == .dotfile, let dotfileFileName else {
            return nil
        }
        return location.appendingPathComponent(dotfileFileName)
    }

    /// Expanded path in the user's home directory where the symlink should live. `nil` for
    /// non-dotfile kinds.
    public var linkTarget: URL? {
        guard kind == .dotfile, let dotfileLink else {
            return nil
        }
        return URL(fileURLWithPath: expandingTilde(in: dotfileLink))
    }

    /// True if a symlink at `linkTarget` exists and points into this repo. Always `false` for
    /// non-dotfile kinds.
    public var isLinked: Bool {
        guard let linkTarget, let dest = symlinkDestination(at: linkTarget) else {
            return false
        }
        return isDescendant(URL(fileURLWithPath: dest), of: repoRoot)
    }

    // MARK: - Loading

    /// Loads every item of `kind` from its directory in the repo (`skills/`, `commands/`, or
    /// `dotfiles/`). `diagnostics` carries human-readable warnings for entries that were
    /// skipped (e.g. a dotfile missing its required `link:` field) — the caller decides
    /// whether/how to surface them.
    public static func load(_ kind: ManagedItemKind) -> (items: [ManagedItem], diagnostics: [String]) {
        switch kind {
        case .skill: return loadSkills()
        case .command: return loadCommands()
        case .dotfile: return loadDotfiles()
        }
    }

    /// Filters `items` down to the ones matching `filter` by id or name. An empty filter
    /// returns every item — shared by every kind instead of three duplicated implementations.
    public static func resolve(_ filter: [String], from items: [ManagedItem]) -> [ManagedItem] {
        filter.isEmpty ? items : items.filter { filter.contains($0.id) || filter.contains($0.name) }
    }

    /// Generates Gemini CLI–compatible TOML content from a `.command` item.
    public static func geminiTOML(from item: ManagedItem) -> String {
        var lines: [String] = []
        if !item.description.isEmpty {
            let escaped = item.description
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            lines.append("description = \"\(escaped)\"")
        }
        let safeBody = item.body.replacingOccurrences(of: "\"\"\"", with: "\"\"\\\"")
        lines.append("prompt = \"\"\"\n\(safeBody)\n\"\"\"")
        return lines.joined(separator: "\n")
    }

    // MARK: - Per-kind loaders

    private static func loadSkills() -> (items: [ManagedItem], diagnostics: [String]) {
        guard let entries = try? fm.contentsOfDirectory(
            at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return ([], []) }

        let items = entries
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    && fm.fileExists(atPath: url.appendingPathComponent("SKILL.md").path)
            }
            .map { dir -> ManagedItem in
                let dirName = dir.lastPathComponent
                let isPrivate = dirName.hasSuffix(".private")
                let id = isPrivate ? String(dirName.dropLast(".private".count)) : dirName
                let text = (try? String(contentsOf: dir.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
                return ManagedItem(
                    kind: .skill,
                    id: id,
                    name: Frontmatter.yamlField("name", in: text) ?? id,
                    description: Frontmatter.yamlField("description", in: text) ?? "",
                    body: Frontmatter.stripFrontmatter(text),
                    isPrivate: isPrivate,
                    location: dir
                )
            }
            .sorted { $0.id < $1.id }
        return (items, [])
    }

    private static func loadCommands() -> (items: [ManagedItem], diagnostics: [String]) {
        guard let entries = try? fm.contentsOfDirectory(
            at: commandsDir, includingPropertiesForKeys: nil
        ) else { return ([], []) }

        let items = entries
            .filter { $0.pathExtension == "md" }
            .map { file -> ManagedItem in
                let stem = file.deletingPathExtension().lastPathComponent
                let isPrivate = stem.hasSuffix(".private")
                let id = isPrivate ? String(stem.dropLast(".private".count)) : stem
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                return ManagedItem(
                    kind: .command,
                    id: id,
                    name: Frontmatter.yamlField("name", in: text) ?? id,
                    description: Frontmatter.yamlField("description", in: text) ?? "",
                    body: Frontmatter.stripFrontmatter(text),
                    isPrivate: isPrivate,
                    location: file
                )
            }
            .sorted { $0.id < $1.id }
        return (items, [])
    }

    private static func loadDotfiles() -> (items: [ManagedItem], diagnostics: [String]) {
        guard let entries = try? fm.contentsOfDirectory(
            at: dotfilesDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return ([], []) }

        var diagnostics: [String] = []
        let items = entries
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    && fm.fileExists(atPath: url.appendingPathComponent("DOTFILE.md").path)
            }
            .compactMap { dir -> ManagedItem? in
                let dirName = dir.lastPathComponent
                let isPrivate = dirName.hasSuffix(".private")
                let id = isPrivate ? String(dirName.dropLast(".private".count)) : dirName
                let text = (try? String(contentsOf: dir.appendingPathComponent("DOTFILE.md"), encoding: .utf8)) ?? ""

                guard let link = Frontmatter.yamlField("link", in: text), !link.isEmpty else {
                    diagnostics.append("dotfiles/\(dirName)/DOTFILE.md missing 'link:' field — skipping")
                    return nil
                }

                let fileName: String
                if let file = Frontmatter.yamlField("file", in: text), !file.isEmpty {
                    fileName = file
                } else {
                    fileName = URL(fileURLWithPath: link).lastPathComponent
                }

                return ManagedItem(
                    kind: .dotfile,
                    id: id,
                    name: Frontmatter.yamlField("name", in: text) ?? id,
                    description: Frontmatter.yamlField("description", in: text) ?? "",
                    body: Frontmatter.stripFrontmatter(text),
                    isPrivate: isPrivate,
                    location: dir,
                    dotfileLink: link,
                    dotfileFileName: fileName
                )
            }
            .sorted { $0.id < $1.id }
        return (items, diagnostics)
    }
}
