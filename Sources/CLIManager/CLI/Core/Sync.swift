import ArgumentParser
import CLIManagerKit
import Foundation

struct Sync: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Convert plain-copy skills in agent dirs into symlinks."
    )

    @OptionGroup var filter: SkillFilterOptions

    @Flag(name: .long, help: "Preview changes without applying them.")
    var dryRun = false

    func run() throws {
        let skills = ManagedItem.resolve(filter.skill, from: ManagedItem.load(.skill).items)
        guard !skills.isEmpty else {
            fail("No matching skills.")
            return
        }
        guard let targets = resolveAgentTargets(filter.agent, for: .skill) else {
            return
        }

        print("\n\(bold)Syncing \(skills.count) skill(s) across \(targets.count) agent(s)\(reset)"
            + (dryRun ? "  \(yellow)(dry run)\(reset)" : "") + "\n")

        for agent in targets {
            guard let agentPath = agent.skillsPath else { continue }
            print("\(bold)\(agent.name)\(reset)  \(gray)\(agentPath.path)\(reset)")
            for skill in skills {
                let dest = agentPath.appendingPathComponent(skill.id)

                guard fm.fileExists(atPath: dest.path) else {
                    skip("  \(skill.id)  \(gray)not installed\(reset)")
                    continue
                }

                if isSymlink(dest) {
                    skip("  \(skill.id)  \(gray)already a symlink\(reset)")
                    continue
                }

                if dryRun {
                    ok("  \(skill.id)  \(gray)→ would replace copy with symlink\(reset)")
                } else {
                    do {
                        try fm.removeItem(at: dest)
                        try fm.createSymbolicLink(at: dest, withDestinationURL: skill.location)
                        ok("  \(skill.id)  \(gray)copy → symlink\(reset)")
                    } catch {
                        fail("  \(skill.id): \(error.localizedDescription)")
                    }
                }
            }
            print()
        }
    }
}
