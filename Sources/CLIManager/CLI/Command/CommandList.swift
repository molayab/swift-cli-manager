import ArgumentParser
import CLIManagerKit
import Foundation

struct CommandList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all commands in this repo."
    )

    func run() throws {
        let cmds = ManagedItem.load(.command).items
        guard !cmds.isEmpty else {
            warn("No commands found in commands/")
            return
        }

        let agents = AgentDescriptor.detected(for: .command)
        print("\n\(bold)Commands\(reset) \(gray)(\(cmds.count))\(reset)\n")
        for cmd in cmds {
            let privTag = cmd.isPrivate ? " \(yellow)(private)\(reset)" : ""
            print("  \(cyan)\(bold)/\(cmd.id)\(reset)\(privTag)")
            if !cmd.description.isEmpty { print("  \(dim)\(cmd.description)\(reset)") }

            if !agents.isEmpty {
                let activeIn: [(agent: AgentDescriptor, dest: URL)] = agents.compactMap { agent in
                    guard let path = agent.commandsPath else {
                        return nil
                    }
                    let dest = path.appendingPathComponent("\(cmd.id).\(agent.commandFileExtension)")
                    guard fm.fileExists(atPath: dest.path) else {
                        return nil
                    }
                    return (agent, dest)
                }
                if activeIn.isEmpty {
                    print("  \(gray)not activated\(reset)")
                } else {
                    let names = activeIn.map { entry -> String in
                        let tag = (entry.agent.commandFormat == .markdown && isSymlink(entry.dest))
                            ? "" : " \(yellow)(copy)\(reset)"
                        return "\(green)●\(reset) \(entry.agent.name)\(tag)"
                    }.joined(separator: "  ")
                    print("  \(names)")
                }
            }
            print()
        }
    }
}
