import ArgumentParser
import CLIManagerKit
import Foundation

struct SkillStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show activation status per agent."
    )

    func run() throws {
        let skills = ManagedItem.load(.skill).items
        print("\n\(bold)Status\(reset)\n")
        print("  \(bold)Repo:\(reset)   \(gray)\(repoRoot.path)\(reset)")
        print("  \(bold)Skills:\(reset) \(skills.count)\n")

        for agent in allAgentDescriptors {
            guard let agentPath = agent.skillsPath else { continue }
            let exists = fm.fileExists(atPath: agentPath.path)
            let indicator = exists ? "\(green)●\(reset)" : "\(gray)○\(reset)"
            print("  \(indicator) \(bold)\(agent.name)\(reset)  \(gray)\(agentPath.path)\(reset)")
            if exists {
                for skill in skills {
                    let dest = agentPath.appendingPathComponent(skill.id)
                    guard fm.fileExists(atPath: dest.path) else { continue }
                    print("      → \(skill.id)  \(gray)\(isSymlink(dest) ? "symlink" : "copy")\(reset)")
                }
            }
        }
        print()
    }
}
