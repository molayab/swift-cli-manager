import ArgumentParser
import CLIManagerKit
import Foundation

struct CommandDeactivate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deactivate",
        abstract: "Remove commands from agent directories."
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
            ? selectInteractive(prompt: "Select commands to deactivate", items: allCmds, display: { "/\($0.id)" })
        : ManagedItem.resolve(command, from: allCmds)
        guard !cmds.isEmpty else {
            fail("No matching commands.")
            return
        }

        guard let targets = selectAgentTargets(filter: agent, for: .command) else {
            return
        }

        print("\n\(bold)Deactivating \(cmds.count) command(s) from \(targets.count) agent(s)\(reset)"
            + (dryRun ? "  \(yellow)(dry run)\(reset)" : "") + "\n")

        for agent in targets {
            guard let agentPath = agent.commandsPath else { continue }
            print("\(bold)\(agent.name)\(reset)  \(gray)\(agentPath.path)\(reset)")
            for cmd in cmds {
                deactivateCommand(cmd, for: agent, at: agentPath)
            }
            print()
        }
    }

    private func deactivateCommand(_ cmd: ManagedItem, for agent: AgentDescriptor, at agentPath: URL) {
        let dest = agentPath.appendingPathComponent("\(cmd.id).\(agent.commandFileExtension)")
        guard fm.fileExists(atPath: dest.path) else {
            skip("  /\(cmd.id)  \(gray)not active\(reset)"); return
        }
        if dryRun {
            ok("  /\(cmd.id)  \(gray)→ would remove\(reset)")
        } else {
            do {
                try fm.removeItem(at: dest)
                ok("  /\(cmd.id)  \(gray)removed\(reset)")
            } catch {
                fail("  /\(cmd.id): \(error.localizedDescription)")
            }
        }
    }
}
