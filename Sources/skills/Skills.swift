import ArgumentParser
import Foundation

// MARK: - Root command

@main
struct Skills: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skills",
        abstract: "Personal AI agent skills manager.",
        subcommands: [Activate.self, Deactivate.self, New.self, List.self, Status.self, Sync.self, Repo.self, Push.self, Pull.self]
    )
}

// MARK: - Shared filter options

struct FilterOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Target a specific skill by name (repeatable).")
    var skill: [String] = []

    @Option(name: .shortAndLong, help: "Target a specific agent by ID (repeatable).")
    var agent: [String] = []
}

// MARK: - activate

struct Activate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Symlink skills into agent directories."
    )

    @OptionGroup var filter: FilterOptions

    @Flag(name: .long, help: "Preview changes without applying them.")
    var dryRun = false

    func run() throws {
        let skills = resolveSkills(filter.skill, from: loadSkills())
        guard !skills.isEmpty else { fail("No matching skills."); return }
        guard let targets = resolveTargets(filter.agent) else { return }

        print("\n\(bold)Activating \(skills.count) skill(s) → \(targets.count) agent(s)\(reset)"
            + (dryRun ? "  \(yellow)(dry run)\(reset)" : "") + "\n")

        for agent in targets {
            print("\(bold)\(agent.name)\(reset)  \(gray)\(agent.path.path)\(reset)")
            if !dryRun && !fm.fileExists(atPath: agent.path.path) {
                try fm.createDirectory(at: agent.path, withIntermediateDirectories: true)
            }
            for skill in skills {
                let dest = agent.path.appendingPathComponent(skill.id)
                if fm.fileExists(atPath: dest.path) {
                    skip("  \(skill.id)  \(gray)already active (\(isSymlink(dest) ? "symlink" : "copy"))\(reset)")
                } else if dryRun {
                    ok("  \(skill.id)  \(gray)→ would symlink\(reset)")
                } else {
                    do {
                        try fm.createSymbolicLink(at: dest, withDestinationURL: skill.dir)
                        ok("  \(skill.id)")
                    } catch {
                        fail("  \(skill.id): \(error.localizedDescription)")
                    }
                }
            }
            print()
        }
    }
}

// MARK: - deactivate

struct Deactivate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove skills from agent directories."
    )

    @OptionGroup var filter: FilterOptions

    @Flag(name: .long, help: "Preview changes without applying them.")
    var dryRun = false

    func run() throws {
        let skills = resolveSkills(filter.skill, from: loadSkills())
        guard !skills.isEmpty else { fail("No matching skills."); return }
        guard let targets = resolveTargets(filter.agent) else { return }

        print("\n\(bold)Deactivating \(skills.count) skill(s) from \(targets.count) agent(s)\(reset)"
            + (dryRun ? "  \(yellow)(dry run)\(reset)" : "") + "\n")

        for agent in targets {
            print("\(bold)\(agent.name)\(reset)  \(gray)\(agent.path.path)\(reset)")
            for skill in skills {
                let dest = agent.path.appendingPathComponent(skill.id)
                guard fm.fileExists(atPath: dest.path) else {
                    skip("  \(skill.id)  \(gray)not active\(reset)"); continue
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
            print()
        }
    }
}

// MARK: - new

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scaffold a new skill."
    )

    @Argument(help: "Name for the new skill.")
    var name: String

    func run() throws {
        let slug = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        guard !slug.isEmpty else {
            throw ValidationError("Provide a valid skill name.")
        }

        let dest = skillsDir.appendingPathComponent(slug)
        guard !fm.fileExists(atPath: dest.path) else {
            fail("Already exists: skills/\(slug)"); return
        }

        let template = """
        ---
        name: \(slug)
        description: Describe what this skill does and when the agent should use it.
        ---

        # \(slug)

        ## Overview

        Describe the purpose of this skill.

        ## When to Use

        Describe the scenarios where this skill should be activated.

        ## Steps

        1. First, do this.
        2. Then, do that.
        """

        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try template.write(to: dest.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        ok("Created  \(gray)skills/\(slug)/SKILL.md\(reset)")
        info("Edit the file, then run:  swift run skills activate --skill \(slug)")
    }
}

// MARK: - list

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all skills in this repo."
    )

    func run() throws {
        let skills = loadSkills()
        guard !skills.isEmpty else { warn("No skills found in skills/"); return }

        let agents = detectedAgents()
        print("\n\(bold)Skills\(reset) \(gray)(\(skills.count))\(reset)\n")
        for skill in skills {
            print("  \(cyan)\(bold)\(skill.name)\(reset)")
            if !skill.description.isEmpty { print("  \(dim)\(skill.description)\(reset)") }

            // Activation status across detected agents
            if !agents.isEmpty {
                let activeIn = agents.filter {
                    fm.fileExists(atPath: $0.path.appendingPathComponent(skill.id).path)
                }
                if activeIn.isEmpty {
                    print("  \(gray)not activated\(reset)")
                } else {
                    let names = activeIn.map { a in
                        let dest = a.path.appendingPathComponent(skill.id)
                        let tag = isSymlink(dest) ? "" : " \(yellow)(copy)\(reset)"
                        return "\(green)●\(reset) \(a.name)\(tag)"
                    }.joined(separator: "  ")
                    print("  \(names)")
                }
            }
            print()
        }
    }
}

// MARK: - status

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show activation status per agent."
    )

    func run() throws {
        let skills = loadSkills()
        print("\n\(bold)Status\(reset)\n")
        print("  \(bold)Repo:\(reset)   \(gray)\(repoRoot.path)\(reset)")
        print("  \(bold)Skills:\(reset) \(skills.count)\n")

        for agent in allAgents {
            let exists = fm.fileExists(atPath: agent.path.path)
            print("  \(exists ? "\(green)●\(reset)" : "\(gray)○\(reset)") \(bold)\(agent.name)\(reset)  \(gray)\(agent.path.path)\(reset)")
            if exists {
                for skill in skills {
                    let dest = agent.path.appendingPathComponent(skill.id)
                    guard fm.fileExists(atPath: dest.path) else { continue }
                    print("      → \(skill.id)  \(gray)\(isSymlink(dest) ? "symlink" : "copy")\(reset)")
                }
            }
        }
        print()
    }
}

// MARK: - sync

struct Sync: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Convert plain-copy skills in agent dirs into symlinks."
    )

    @OptionGroup var filter: FilterOptions

    @Flag(name: .long, help: "Preview changes without applying them.")
    var dryRun = false

    func run() throws {
        let skills = resolveSkills(filter.skill, from: loadSkills())
        guard !skills.isEmpty else { fail("No matching skills."); return }
        guard let targets = resolveTargets(filter.agent) else { return }

        print("\n\(bold)Syncing \(skills.count) skill(s) across \(targets.count) agent(s)\(reset)"
            + (dryRun ? "  \(yellow)(dry run)\(reset)" : "") + "\n")

        for agent in targets {
            print("\(bold)\(agent.name)\(reset)  \(gray)\(agent.path.path)\(reset)")
            for skill in skills {
                let dest = agent.path.appendingPathComponent(skill.id)

                guard fm.fileExists(atPath: dest.path) else {
                    skip("  \(skill.id)  \(gray)not installed\(reset)")
                    continue
                }

                if isSymlink(dest) {
                    skip("  \(skill.id)  \(gray)already a symlink\(reset)")
                    continue
                }

                // It's a plain copy — replace with symlink.
                if dryRun {
                    ok("  \(skill.id)  \(gray)→ would replace copy with symlink\(reset)")
                } else {
                    do {
                        try fm.removeItem(at: dest)
                        try fm.createSymbolicLink(at: dest, withDestinationURL: skill.dir)
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

// MARK: - repo

struct Repo: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show git repository status, or initialise one."
    )

    @Flag(name: .customLong("init"), help: "Initialise a git repository if one does not exist.")
    var shouldInit = false

    func run() throws {
        let gitDir = repoRoot.appendingPathComponent(".git")
        let hasGit = fm.fileExists(atPath: gitDir.path)

        print("\n\(bold)Repository\(reset)  \(gray)\(repoRoot.path)\(reset)\n")

        if !hasGit {
            if shouldInit {
                let result = runGit("init")
                if result.exitCode == 0 {
                    ok("Initialised git repository.")
                } else {
                    fail("git init failed.")
                }
            } else {
                warn("No git repository found.")
                info("Run with --init to create one.")
            }
            print()
            return
        }

        // Branch
        let branch = runGit("rev-parse", "--abbrev-ref", "HEAD").output
        print("  \(bold)Branch:\(reset)   \(branch.isEmpty ? "\(gray)unknown\(reset)" : branch)")

        // Remote URL
        let remote = runGit("remote", "get-url", "origin").output
        print("  \(bold)Remote:\(reset)   \(remote.isEmpty ? "\(gray)none\(reset)" : remote)")

        // Commit count
        let countResult = runGit("rev-list", "--count", "HEAD")
        if countResult.exitCode == 0, let n = Int(countResult.output) {
            print("  \(bold)Commits:\(reset)  \(n)")
        } else {
            print("  \(bold)Commits:\(reset)  \(gray)none yet\(reset)")
        }

        // Dirty working tree?
        let dirty = runGit("status", "--porcelain").output
        print("  \(bold)Status:\(reset)   \(dirty.isEmpty ? "\(green)clean\(reset)" : "\(yellow)uncommitted changes\(reset)")")

        print()
    }
}

// MARK: - push

struct Push: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stage all changes, commit, and push to remote."
    )

    @Option(name: .shortAndLong, help: "Commit message.")
    var message: String = "Update skills"

    func run() throws {
        let gitDir = repoRoot.appendingPathComponent(".git")
        guard fm.fileExists(atPath: gitDir.path) else {
            fail("No git repository found. Run `skills repo --init` first.")
            return
        }

        // Stage
        let add = runGit("add", ".")
        guard add.exitCode == 0 else { fail("git add failed."); return }

        // Check if there's anything to commit
        let staged = runGit("diff", "--cached", "--quiet")
        if staged.exitCode == 0 {
            info("Nothing to commit — working tree clean.")
            return
        }

        // Commit
        let commit = runGit("commit", "-m", message)
        guard commit.exitCode == 0 else {
            fail("git commit failed:\n\(commit.output)")
            return
        }
        ok("Committed: \(message)")

        // Push
        let remote = runGit("remote").output
        guard !remote.isEmpty else {
            warn("No remote configured — skipping push.")
            info("Add one with: git remote add origin <url>")
            return
        }

        let branch = runGit("rev-parse", "--abbrev-ref", "HEAD").output
        let push = runGit("push", "-u", remote, branch)
        if push.exitCode == 0 {
            ok("Pushed to \(remote)/\(branch)")
        } else {
            fail("git push failed.")
        }
    }
}

// MARK: - pull

struct Pull: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Pull latest changes from remote."
    )

    func run() throws {
        let gitDir = repoRoot.appendingPathComponent(".git")
        guard fm.fileExists(atPath: gitDir.path) else {
            fail("No git repository found. Run `skills repo --init` first.")
            return
        }

        let remote = runGit("remote").output
        guard !remote.isEmpty else {
            warn("No remote configured.")
            info("Add one with: git remote add origin <url>")
            return
        }

        print("\n\(bold)Pulling latest changes…\(reset)\n")
        let result = runGit("pull")
        if result.exitCode == 0 {
            let msg = result.output.isEmpty ? "Already up to date." : result.output
            ok(msg)
        } else {
            fail("git pull failed.")
        }
        print()
    }
}
