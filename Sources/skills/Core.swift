import Foundation

// MARK: - Terminal output

let isTTY = isatty(STDOUT_FILENO) != 0
func c(_ code: String) -> String { isTTY ? "\u{1B}[\(code)m" : "" }

let reset  = c("0");  let bold   = c("1");  let dim    = c("2")
let green  = c("32"); let yellow = c("33"); let red    = c("31")
let cyan   = c("36"); let gray   = c("90"); let blue   = c("34")

func ok(_ s: String)   { print("\(green)✓\(reset) \(s)") }
func warn(_ s: String) { print("\(yellow)!\(reset) \(s)") }
func fail(_ s: String) { print("\(red)✗\(reset) \(s)") }
func info(_ s: String) { print("\(blue)i\(reset) \(s)") }
func skip(_ s: String) { print("\(gray)−\(reset) \(s)") }

// MARK: - Paths

let fm   = FileManager.default
let home = URL(fileURLWithPath: NSHomeDirectory())

/// Walk up from CWD until we find Package.swift — set automatically by `swift run`.
func findRepoRoot() -> URL {
    var url = URL(fileURLWithPath: fm.currentDirectoryPath)
    for _ in 0..<8 {
        if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
        url = url.deletingLastPathComponent()
    }
    return URL(fileURLWithPath: fm.currentDirectoryPath)
}

let repoRoot  = findRepoRoot()
let skillsDir = repoRoot.appendingPathComponent("skills")

// MARK: - Agent registry

struct Agent {
    let id: String
    let name: String
    let path: URL
}

let allAgents: [Agent] = [
    .init(id: "opencode",        name: "OpenCode",       path: home.appendingPathComponent(".config/opencode/skills")),
    .init(id: "claude-code",     name: "Claude Code",    path: home.appendingPathComponent(".claude/skills")),
    .init(id: "github-copilot",  name: "GitHub Copilot", path: home.appendingPathComponent(".copilot/skills")),
    .init(id: "cursor",          name: "Cursor",          path: home.appendingPathComponent(".cursor/skills")),
    .init(id: "cline",           name: "Cline / Warp",   path: home.appendingPathComponent(".agents/skills")),
    .init(id: "codex",           name: "Codex",           path: home.appendingPathComponent(".codex/skills")),
    .init(id: "gemini-cli",      name: "Gemini CLI",     path: home.appendingPathComponent(".gemini/skills")),
    .init(id: "windsurf",        name: "Windsurf",       path: home.appendingPathComponent(".codeium/windsurf/skills")),
]

func detectedAgents() -> [Agent] {
    allAgents.filter { fm.fileExists(atPath: $0.path.path) }
}

// MARK: - Skill loading

struct Skill {
    let id: String
    let dir: URL
    let name: String
    let description: String
}

private func yamlField(_ key: String, in text: String) -> String? {
    guard
        let regex = try? NSRegularExpression(pattern: "^\(key):\\s*(.+)$", options: .anchorsMatchLines),
        let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let range = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[range]).trimmingCharacters(in: .whitespaces)
}

func loadSkills() -> [Skill] {
    guard let entries = try? fm.contentsOfDirectory(
        at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey]
    ) else { return [] }

    return entries
        .filter { url in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                && fm.fileExists(atPath: url.appendingPathComponent("SKILL.md").path)
        }
        .map { dir in
            let text = (try? String(contentsOf: dir.appendingPathComponent("SKILL.md"))) ?? ""
            return Skill(
                id:          dir.lastPathComponent,
                dir:         dir,
                name:        yamlField("name",        in: text) ?? dir.lastPathComponent,
                description: yamlField("description", in: text) ?? ""
            )
        }
        .sorted { $0.id < $1.id }
}

func isSymlink(_ url: URL) -> Bool {
    (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
}

// MARK: - Resolution helpers

/// Returns target agents, or `nil` and prints a warning when none are found.
func resolveTargets(_ filterAgents: [String]) -> [Agent]? {
    guard !filterAgents.isEmpty else {
        let detected = detectedAgents()
        if detected.isEmpty {
            warn("No agents detected on this machine.")
            info("Use --agent <id>. Available: \(allAgents.map(\.id).joined(separator: ", "))")
            return nil
        }
        return detected
    }
    return filterAgents.compactMap { id in
        guard let agent = allAgents.first(where: { $0.id == id }) else {
            warn("Unknown agent: \(id)"); return nil
        }
        return agent
    }
}

func resolveSkills(_ filter: [String], from all: [Skill]) -> [Skill] {
    filter.isEmpty ? all : all.filter { filter.contains($0.id) || filter.contains($0.name) }
}

// MARK: - Git helper

@discardableResult
func runGit(_ args: String...) -> (output: String, exitCode: Int32) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["git"] + args
    p.currentDirectoryURL = repoRoot

    let pipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = pipe
    p.standardError = errPipe

    try? p.run()
    p.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return (out, p.terminationStatus)
}
