import ArgumentParser
import CLIManagerKit
import Foundation

struct SkillDeactivate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deactivate",
        abstract: "Remove skills from agent directories."
    )

    @OptionGroup var filter: SkillFilterOptions

    @Flag(name: .long, help: "Preview changes without applying them.")
    var dryRun = false

    func run() throws {
        let allSkills = ManagedItem.load(.skill).items
        guard !allSkills.isEmpty else {
            fail("No skills found in skills/")
            return
        }

        let skills: [ManagedItem] = filter.skill.isEmpty
            ? selectInteractive(prompt: "Select skills to deactivate", items: allSkills, display: \.name)
        : ManagedItem.resolve(filter.skill, from: allSkills)
        guard !skills.isEmpty else {
            fail("No matching skills.")
            return
        }

        guard let targets = selectAgentTargets(filter: filter.agent, for: .skill) else {
            return
        }

        print("\n\(bold)Deactivating \(skills.count) skill(s) from \(targets.count) agent(s)\(reset)"
            + (dryRun ? "  \(yellow)(dry run)\(reset)" : "") + "\n")

        for agent in targets {
            guard let agentPath = agent.skillsPath else { continue }
            print("\(bold)\(agent.name)\(reset)  \(gray)\(agentPath.path)\(reset)")
            for skill in skills {
                deactivateSkill(skill, at: agentPath)
            }
            print()
        }
    }

    private func deactivateSkill(_ skill: ManagedItem, at agentPath: URL) {
        let dest = agentPath.appendingPathComponent(skill.id)
        guard fm.fileExists(atPath: dest.path) else {
            skip("  \(skill.id)  \(gray)not active\(reset)"); return
        }
        if dryRun {
            ok("  \(skill.id)  \(gray)→ would remove\(reset)")
        } else {
            do {
                try fm.removeItem(at: dest)
                ok("  \(skill.id)  \(gray)removed\(reset)")
            } catch {
                fail("  \(skill.id): \(error.localizedDescription)")
            }
        }
    }
}
