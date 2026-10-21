import ArgumentParser
import CLIManagerKit
import Foundation

struct SkillPrivate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "private",
        abstract: "Toggle a skill between private (untracked) and public (committed)."
    )

    @Argument(help: "Skill id to toggle (e.g. swiftui-pro).")
    var name: String

    func run() throws {
        let skills = ManagedItem.load(.skill).items
        guard let skill = skills.first(where: { $0.id == name }) else {
            fail("Skill '\(name)' not found."); return
        }

        let newDirName = skill.isPrivate ? skill.id : "\(skill.id).private"
        let newDir = skillsDir.appendingPathComponent(newDirName)

        guard !fm.fileExists(atPath: newDir.path) else {
            fail("'\(newDirName)' already exists in skills/ — resolve the conflict first."); return
        }

        try fm.moveItem(at: skill.location, to: newDir)
        updateSymlinks(for: skill, newDir: newDir)

        let state = skill.isPrivate ? "public (will be committed)" : "private (git-ignored)"
        ok("'\(skill.id)' is now \(state)")
    }

    private func updateSymlinks(for skill: ManagedItem, newDir: URL) {
        let results = relinkSymlinks(
            agents: allAgentDescriptors.compactMap { agent in
                agent.skillsPath.map { (path: $0, name: agent.name) }
            },
            childName: skill.id,
            to: newDir
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
