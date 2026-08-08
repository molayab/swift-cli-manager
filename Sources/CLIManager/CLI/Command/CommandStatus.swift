import ArgumentParser
import CLIManagerKit
import Foundation

struct CommandStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show command activation status per agent."
    )

    func run() throws {
        let cmds = ManagedItem.load(.command).items
        print("\n\(bold)Command Status\(reset)\n")
        print("  \(bold)Repo:\(reset)     \(gray)\(repoRoot.path)\(reset)")
        print("  \(bold)Commands:\(reset) \(cmds.count)\n")

        for agent in allAgentDescriptors {
            guard let agentPath = agent.commandsPath else { continue }
            let exists = fm.fileExists(atPath: agentPath.path)
            let indicator = exists ? "\(green)●\(reset)" : "\(gray)○\(reset)"
            print("  \(indicator) \(bold)\(agent.name)\(reset)  \(gray)\(agentPath.path)\(reset)")
            if exists {
                for cmd in cmds {
                    let dest = agentPath.appendingPathComponent("\(cmd.id).\(agent.commandFileExtension)")
                    guard fm.fileExists(atPath: dest.path) else { continue }
                    let kind = agent.commandFormat == .markdown ? (isSymlink(dest) ? "symlink" : "copy") : "toml"
                    print("      → /\(cmd.id)  \(gray)\(kind)\(reset)")
                }
            }
        }
        print()
    }
}
