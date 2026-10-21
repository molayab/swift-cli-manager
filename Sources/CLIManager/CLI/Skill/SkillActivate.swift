import ArgumentParser
import CLIManagerKit
import Foundation

struct SkillActivate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Symlink skills into agent directories."
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
            ? selectInteractive(prompt: "Select skills to activate", items: allSkills, display: \.name)
        : ManagedItem.resolve(filter.skill, from: allSkills)
        guard !skills.isEmpty else {
            fail("No matching skills.")
            return
        }

        guard let targets = selectAgentTargets(filter: filter.agent, for: .skill) else {
            return
        }

        print("\n\(bold)Activating \(skills.count) skill(s) → \(targets.count) agent(s)\(reset)"
            + (dryRun ? "  \(yellow)(dry run)\(reset)" : "") + "\n")

        for agent in targets {
            guard let agentPath = agent.skillsPath else { continue }
            print("\(bold)\(agent.name)\(reset)  \(gray)\(agentPath.path)\(reset)")
            if !dryRun && !fm.fileExists(atPath: agentPath.path) {
                try fm.createDirectory(at: agentPath, withIntermediateDirectories: true)
            }
            for skill in skills {
                try activateSkill(skill, at: agentPath)
            }
            print()
        }
    }

    private func activateSkill(_ skill: ManagedItem, at agentPath: URL) throws {
        let dest = agentPath.appendingPathComponent(skill.id)
        if fm.fileExists(atPath: dest.path) {
            skip("  \(skill.id)  \(gray)already active (\(isSymlink(dest) ? "symlink" : "copy"))\(reset)")
        } else if dryRun {
            ok("  \(skill.id)  \(gray)→ would symlink\(reset)")
        } else {
            do {
                try fm.createSymbolicLink(at: dest, withDestinationURL: skill.location)
                ok("  \(skill.id)")
            } catch {
                fail("  \(skill.id): \(error.localizedDescription)")
            }
        }
    }
}
