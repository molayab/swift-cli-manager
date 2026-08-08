import ArgumentParser
import CLIManagerKit
import Foundation

struct CommandPrivate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "private",
        abstract: "Toggle a command between private (untracked) and public (committed)."
    )

    @Argument(help: "Command id to toggle (e.g. review).")
    var name: String

    func run() throws {
        let cmds = ManagedItem.load(.command).items
        guard let cmd = cmds.first(where: { $0.id == name }) else {
            fail("Command '\(name)' not found."); return
        }

        let newFilename = cmd.isPrivate ? "\(cmd.id).md" : "\(cmd.id).private.md"
        let newFile = commandsDir.appendingPathComponent(newFilename)

        guard !fm.fileExists(atPath: newFile.path) else {
            fail("'\(newFilename)' already exists in commands/ — resolve the conflict first."); return
        }

        try fm.moveItem(at: cmd.location, to: newFile)
        updateSymlinks(for: cmd, newFile: newFile)

        let state = cmd.isPrivate ? "public (will be committed)" : "private (git-ignored)"
        ok("'/\(cmd.id)' is now \(state)")
    }

    private func updateSymlinks(for cmd: ManagedItem, newFile: URL) {
        let results = relinkSymlinks(
            agents: allAgentDescriptors
                .filter { $0.commandFormat == .markdown }
                .compactMap { agent in agent.commandsPath.map { (path: $0, name: agent.name) } },
            childName: "\(cmd.id).md",
            to: newFile
        )
        for result in results {
            if result.succeeded {
                info("  \(result.message)")
            } else {
                warn("  \(result.message)")
            }
        }
    }
}
