import ArgumentParser
import CLIManagerKit
import Foundation

struct SkillList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all skills in this repo."
    )

    func run() throws {
        let skills = ManagedItem.load(.skill).items
        guard !skills.isEmpty else {
            warn("No skills found in skills/")
            return
        }

        let agents = AgentDescriptor.detected(for: .skill)
        print("\n\(bold)Skills\(reset) \(gray)(\(skills.count))\(reset)\n")
        for skill in skills {
            let privTag = skill.isPrivate ? " \(yellow)(private)\(reset)" : ""
            print("  \(cyan)\(bold)\(skill.name)\(reset)\(privTag)")
            if !skill.description.isEmpty { print("  \(dim)\(skill.description)\(reset)") }

            if !agents.isEmpty {
                let activeIn: [(agent: AgentDescriptor, dest: URL)] = agents.compactMap { agent in
                    guard let path = agent.skillsPath else {
                        return nil
                    }
                    let dest = path.appendingPathComponent(skill.id)
                    guard fm.fileExists(atPath: dest.path) else {
                        return nil
                    }
                    return (agent, dest)
                }
                if activeIn.isEmpty {
                    print("  \(gray)not activated\(reset)")
                } else {
                    let names = activeIn.map { entry -> String in
                        let tag = isSymlink(entry.dest) ? "" : " \(yellow)(copy)\(reset)"
                        return "\(green)●\(reset) \(entry.agent.name)\(tag)"
                    }.joined(separator: "  ")
                    print("  \(names)")
                }
            }
            print()
        }
    }
}
