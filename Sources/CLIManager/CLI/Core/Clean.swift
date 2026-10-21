import ArgumentParser
import CLIManagerKit
import Foundation

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Remove dead symlinks from all agent directories."
    )

    @Flag(name: .long, help: "Preview removals without applying them.")
    var dryRun = false

    func run() throws {
        print("\n\(bold)Scanning agent directories for dead symlinks…\(reset)\n")

        var totalDead = 0
        var totalRemoved = 0

        for agent in allAgentDescriptors {
            if let skillsPath = agent.skillsPath {
                let (dead, removed) = try scanDir(skillsPath, label: "\(agent.name) (skills)")
                totalDead += dead
                totalRemoved += removed
            }
            if let commandsPath = agent.commandsPath {
                let (dead, removed) = try scanDir(commandsPath, label: "\(agent.name) (commands)")
                totalDead += dead
                totalRemoved += removed
            }
        }

        print()
        if totalDead == 0 {
            ok("No dead symlinks found.")
        } else if dryRun {
            warn("\(totalDead) dead symlink(s) found — run without --dry-run to remove.")
        } else {
            ok("Removed \(totalRemoved) dead symlink(s).")
        }
    }

    // MARK: - Helpers

    private func scanDir(_ dir: URL, label: String) throws -> (dead: Int, removed: Int) {
        guard isDirectory(dir) else {
            return (0, 0)
        }
        let entries = (try? fm.contentsOfDirectory(
            at: dir.resolvingSymlinksInPath(),
            includingPropertiesForKeys: nil
        )) ?? []

        let dead = entries.filter { isDeadSymlink($0) }
        guard !dead.isEmpty else {
            return (0, 0)
        }

        print("  \(bold)\(label)\(reset)  \(gray)\(dir.path)\(reset)")
        var removed = 0
        for link in dead {
            if dryRun {
                skip("  \(link.lastPathComponent)  \(gray)would remove\(reset)")
            } else {
                try fm.removeItem(at: link)
                ok("  \(link.lastPathComponent)  \(gray)removed\(reset)")
                removed += 1
            }
        }
        print()
        return (dead.count, removed)
    }

    private func isDeadSymlink(_ url: URL) -> Bool {
        isSymlink(url) && !fm.fileExists(atPath: url.path)
    }
}
