import Testing
import Foundation

@testable import CLIManagerKit

struct AgentDescriptorTests {

    // MARK: - Canonical registry

    @Test("Every agent id in the canonical registry is unique")
    func agentIDsAreUnique() {
        let ids = allAgentDescriptors.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every agent supports skills, commands, or both")
    func everyAgentSupportsAtLeastOneKind() {
        for agent in allAgentDescriptors {
            #expect(agent.skillsPath != nil || agent.commandsPath != nil)
        }
    }

    // MARK: - path(for:)

    @Test("path(for:) returns the skills path for .skill and nil for .dotfile")
    func pathForSkillAndDotfile() {
        let agent = AgentDescriptor(
            id: "test-agent", name: "Test Agent",
            skillsPath: URL(fileURLWithPath: "/tmp/skills"),
            commandsPath: nil,
            commandFormat: .markdown
        )
        #expect(agent.path(for: .skill) == URL(fileURLWithPath: "/tmp/skills"))
        #expect(agent.path(for: .command) == nil)
        #expect(agent.path(for: .dotfile) == nil)
    }

    // MARK: - commandFileExtension

    @Test("commandFileExtension is toml for Gemini's format and md otherwise")
    func commandFileExtensionByFormat() {
        let markdownAgent = AgentDescriptor(
            id: "a", name: "A", skillsPath: nil, commandsPath: URL(fileURLWithPath: "/tmp"), commandFormat: .markdown
        )
        let tomlAgent = AgentDescriptor(
            id: "b", name: "B", skillsPath: nil, commandsPath: URL(fileURLWithPath: "/tmp"), commandFormat: .geminiTOML
        )
        #expect(markdownAgent.commandFileExtension == "md")
        #expect(tomlAgent.commandFileExtension == "toml")
    }

    // MARK: - resolve(ids:for:)

    @Test("resolve(ids:for:) matches by id and reports unknown ids separately")
    func resolveMatchesKnownAndReportsUnknown() {
        let (resolved, unknown) = AgentDescriptor.resolve(ids: ["claude-code", "not-a-real-agent"], for: .skill)
        #expect(resolved.map(\.id) == ["claude-code"])
        #expect(unknown == ["not-a-real-agent"])
    }

    @Test("resolve(ids:for:) treats an agent that doesn't support the kind as unknown")
    func resolveTreatsUnsupportedKindAsUnknown() {
        // GitHub Copilot has no commandsPath in the canonical registry.
        let (resolved, unknown) = AgentDescriptor.resolve(ids: ["github-copilot"], for: .command)
        #expect(resolved.isEmpty)
        #expect(unknown == ["github-copilot"])
    }
}
