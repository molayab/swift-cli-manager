import Foundation

public nonisolated(unsafe) let fm = FileManager.default

/// The user's home directory. Honors a `HOME` environment override — set by tests, sandboxes,
/// or a caller that wants to point this tool at a scratch directory instead of the real one —
/// falling back to `NSHomeDirectory()`, which does *not* read `HOME` itself on macOS. Computed
/// fresh on every access (not cached) so an override taking effect mid-process is picked up
/// immediately, the same way `repoRoot` already re-resolves per `findRepoRoot()` call.
public var home: URL {
    if let override = ProcessInfo.processInfo.environment["HOME"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    return URL(fileURLWithPath: NSHomeDirectory())
}

/// Expands a leading `~` to the current user's home directory.
public func expandingTilde(in path: String) -> String {
    guard path.hasPrefix("~") else {
        return path
    }
    return home.path + path.dropFirst()
}

public func findRepoRoot() -> URL {
    // 1. Explicit environment override — useful in CI or multi-repo setups.
    if let envPath = ProcessInfo.processInfo.environment["CLI_MANAGER_REPO"] {
        let url = URL(fileURLWithPath: expandingTilde(in: envPath))
        if fm.fileExists(atPath: url.path) {
            return url
        }
    }

    // 2. Config file written by install.sh — the primary path for installed binaries.
    let configFile = home
        .appendingPathComponent(".config")
        .appendingPathComponent("cli-manager")
        .appendingPathComponent("repo")
    if let saved = try? String(contentsOf: configFile, encoding: .utf8) {
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let url = URL(fileURLWithPath: expandingTilde(in: trimmed))
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }
    }

    // 3. Walk up from CWD looking for Package.swift — fallback for `swift run` / dev.
    var url = URL(fileURLWithPath: fm.currentDirectoryPath)
    for _ in 0..<8 {
        if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            return url
        }
        url = url.deletingLastPathComponent()
    }
    return URL(fileURLWithPath: fm.currentDirectoryPath)
}

// Computed on every access, like `home` above, rather than cached at first use — so a test (or
// any caller) that sets `CLI_MANAGER_REPO`/`HOME` for one operation doesn't leak a stale value
// into the next.
public var repoRoot: URL { findRepoRoot() }
public var skillsDir: URL { repoRoot.appendingPathComponent("skills") }
public var commandsDir: URL { repoRoot.appendingPathComponent("commands") }
public var dotfilesDir: URL { repoRoot.appendingPathComponent("dotfiles") }

public func isSymlink(_ url: URL) -> Bool {
    (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
}

/// Returns the absolute, standardized path that `symlink` resolves to.
/// `destinationOfSymbolicLink` can return a relative path; this resolves
/// it against the symlink's parent directory before standardizing.
public func symlinkDestination(at symlink: URL) -> String? {
    guard let dest = try? fm.destinationOfSymbolicLink(atPath: symlink.path) else { return nil }
    if dest.hasPrefix("/") {
        return URL(fileURLWithPath: dest).standardized.path
    }
    return symlink.deletingLastPathComponent()
        .appendingPathComponent(dest)
        .standardized.path
}

/// Returns true when `url` is located inside `ancestor`, verified by comparing
/// path components rather than a raw string prefix. This prevents false matches
/// on paths that share a common string prefix (e.g. `/repo` vs `/repo-fork`).
public func isDescendant(_ url: URL, of ancestor: URL) -> Bool {
    let child  = url.standardized.pathComponents
    let parent = ancestor.standardized.pathComponents
    guard child.count > parent.count else { return false }
    return child.prefix(parent.count).elementsEqual(parent)
}

public func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
}

/// Converts a human-readable name to a lowercase, hyphen-separated slug.
public func makeSlug(from name: String) -> String {
    name
        .lowercased()
        .replacingOccurrences(of: " ", with: "-")
        .filter { $0.isLetter || $0.isNumber || $0 == "-" }
}

/// One agent's outcome from `relinkSymlinks`.
public struct RelinkResult: Sendable {
    public let agentName: String
    public let succeeded: Bool
    public let message: String
}

/// Repoints existing symlinks under each agent directory to a new target URL.
/// Skips entries that are not currently symlinks. Returns one result per agent touched
/// (success or failure) so the caller can print it.
@discardableResult
public func relinkSymlinks(
    agents: [(path: URL, name: String)], childName: String, to newURL: URL
) -> [RelinkResult] {
    var results: [RelinkResult] = []
    for agent in agents {
        let dest = agent.path.appendingPathComponent(childName)
        guard isSymlink(dest) else { continue }
        do {
            try fm.removeItem(at: dest)
            try fm.createSymbolicLink(at: dest, withDestinationURL: newURL)
            let message = "Updated symlink → \(agent.name)"
            results.append(RelinkResult(agentName: agent.name, succeeded: true, message: message))
        } catch {
            let reason = error.localizedDescription
            let message = "Could not update symlink in \(agent.name): \(reason)"
            results.append(RelinkResult(agentName: agent.name, succeeded: false, message: message))
        }
    }
    return results
}
