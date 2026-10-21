import ArgumentParser
import CLIManagerKit
import Foundation

struct CommandImport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Copy commands from agent directories into this repo."
    )

    @Option(name: .shortAndLong, help: "Target a specific agent by ID (repeatable).")
    var agent: [String] = []

    @Flag(name: .long, help: "Overwrite an existing local command.")
    var force = false

    func run() throws {
        let markdownAgents = allAgentDescriptors.filter { $0.commandsPath != nil && $0.commandFormat == .markdown }

        let targets: [AgentDescriptor]
        if agent.isEmpty {
            let detected = markdownAgents.filter { $0.commandsPath.map(isDirectory) == true }
            guard !detected.isEmpty else {
                warn("No command agents detected on this machine.")
                info("Use --agent <id>. Available: \(markdownAgents.map(\.id).joined(separator: ", "))")
                return
            }
            targets = selectInteractive(prompt: "Select agents to import from", items: detected, display: \.name)
        } else {
            targets = agent.compactMap { agentID in
                guard let match = markdownAgents.first(where: { $0.id == agentID }) else {
                    warn("Unknown or unsupported agent: \(agentID)")
                    return nil
                }
                return match
            }
        }
        guard !targets.isEmpty else {
            fail("No agents selected.")
            return
        }

        try fm.createDirectory(at: commandsDir, withIntermediateDirectories: true)

        print("\n\(bold)Importing commands → \(commandsDir.path)\(reset)\n")

        for target in targets {
            print("\(bold)\(target.name)\(reset)  \(gray)\(target.commandsPath?.path ?? "")\(reset)")
            try importCommands(from: target)
            print()
        }
    }

    private func importCommands(from agent: AgentDescriptor) throws {
        guard let agentPath = agent.commandsPath, isDirectory(agentPath) else {
            warn("  \(agent.name) commands directory not found — skipping.")
            return
        }

        let resolvedPath = agentPath.resolvingSymlinksInPath()
        let entries = try fm.contentsOfDirectory(
            at: resolvedPath,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "md" }

        guard !entries.isEmpty else {
            info("  no .md files found")
            return
        }

        for entry in entries {
            let source = entry.resolvingSymlinksInPath()
            // Skip entries that are already tracked inside this repo
            if source.path.hasPrefix(commandsDir.resolvingSymlinksInPath().path) {
                skip("  /\(entry.deletingPathExtension().lastPathComponent)  \(gray)already in repo\(reset)")
                continue
            }
            let dest = commandsDir.appendingPathComponent(entry.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                if force {
                    try fm.removeItem(at: dest)
                } else {
                    skip("  /\(entry.deletingPathExtension().lastPathComponent)  \(gray)already in repo\(reset)")
                    continue
                }
            }
            try fm.copyItem(at: source, to: dest)
            ok("  /\(entry.deletingPathExtension().lastPathComponent)")
        }
    }
}
