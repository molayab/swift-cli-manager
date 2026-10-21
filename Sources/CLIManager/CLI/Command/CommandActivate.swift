import ArgumentParser
import CLIManagerKit
import Foundation

struct CommandActivate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Install commands into agent directories."
    )

    @Option(name: .shortAndLong, help: "Target a specific command by name (repeatable).")
    var command: [String] = []

    @Option(name: .shortAndLong, help: "Target a specific agent by ID (repeatable).")
    var agent: [String] = []

    @Flag(name: .long, help: "Preview changes without applying them.")
    var dryRun = false

    func run() throws {
        let allCmds = ManagedItem.load(.command).items
        guard !allCmds.isEmpty else {
            fail("No commands found in commands/")
            return
        }

        let cmds: [ManagedItem] = command.isEmpty
            ? selectInteractive(prompt: "Select commands to activate", items: allCmds, display: { "/\($0.id)" })
        : ManagedItem.resolve(command, from: allCmds)
        guard !cmds.isEmpty else {
            fail("No matching commands.")
            return
        }

        guard let targets = selectAgentTargets(filter: agent, for: .command) else {
            return
        }

        print("\n\(bold)Activating \(cmds.count) command(s) → \(targets.count) agent(s)\(reset)"
            + (dryRun ? "  \(yellow)(dry run)\(reset)" : "") + "\n")

        for agent in targets {
            guard let agentPath = agent.commandsPath else { continue }
            print("\(bold)\(agent.name)\(reset)  \(gray)\(agentPath.path)\(reset)")
            if !dryRun && !fm.fileExists(atPath: agentPath.path) {
                try fm.createDirectory(at: agentPath, withIntermediateDirectories: true)
            }
            for cmd in cmds {
                try activateCommand(cmd, into: agent, at: agentPath)
            }
            print()
        }
    }

    private func activateCommand(_ cmd: ManagedItem, into agent: AgentDescriptor, at agentPath: URL) throws {
        let dest = agentPath.appendingPathComponent("\(cmd.id).\(agent.commandFileExtension)")
        if fm.fileExists(atPath: dest.path) {
            let kind = agent.commandFormat == .markdown ? (isSymlink(dest) ? "symlink" : "copy") : "toml"
            skip("  /\(cmd.id)  \(gray)already active (\(kind))\(reset)")
            return
        }
        if dryRun {
            let action = agent.commandFormat == .geminiTOML ? "would write TOML" : "would symlink"
            ok("  /\(cmd.id)  \(gray)→ \(action)\(reset)")
            return
        }
        do {
            switch agent.commandFormat {
            case .markdown:
                try fm.createSymbolicLink(at: dest, withDestinationURL: cmd.location)
                ok("  /\(cmd.id)")
            case .geminiTOML:
                try ManagedItem.geminiTOML(from: cmd).write(to: dest, atomically: true, encoding: .utf8)
                ok("  /\(cmd.id)  \(gray)→ TOML\(reset)")
            }
        } catch {
            fail("  /\(cmd.id): \(error.localizedDescription)")
        }
    }
}
