import Testing
import Foundation
#if canImport(Darwin)
@preconcurrency import Darwin
#elseif canImport(Glibc)
@preconcurrency import Glibc
#endif

@testable import CLIManagerKit

/// Verifies that `home` (and everything derived from it — `expandingTilde`,
/// `allAgentDescriptors`, agent detection) honors a `HOME` environment override rather than
/// always resolving to the real user home via `NSHomeDirectory()`.
///
/// `.serialized` because these tests mutate the process-wide `HOME` environment variable —
/// running them concurrently with each other would race. A class (not a struct) lets `deinit`
/// restore the original `HOME` and clean up the scratch directory after every test, the same
/// pattern `FileManagerHelpersTests` uses for its temp directory.
@Suite(.serialized)
final class HomeOverrideTests {
    let tempHome: URL
    let originalHome: String?

    init() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIManagerTests-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        originalHome = ProcessInfo.processInfo.environment["HOME"]
        setenv("HOME", tempHome.path, 1)
    }

    deinit {
        if let originalHome {
            setenv("HOME", originalHome, 1)
        } else {
            unsetenv("HOME")
        }
        try? FileManager.default.removeItem(at: tempHome)
    }

    @Test("home reflects a HOME environment override instead of NSHomeDirectory()")
    func homeReflectsEnvironmentOverride() {
        #expect(home.path == tempHome.path)
    }

    @Test("expandingTilde expands against the overridden HOME, not the real one")
    func expandingTildeUsesOverriddenHome() {
        #expect(expandingTilde(in: "~/.gitconfig") == tempHome.path + "/.gitconfig")
    }

    @Test("AgentDescriptor paths are derived from the overridden HOME")
    func agentDescriptorPathsUseOverriddenHome() throws {
        let claude = try #require(allAgentDescriptors.first { $0.id == "claude-code" })
        #expect(claude.skillsPath == tempHome.appendingPathComponent(".claude/skills"))
    }

    @Test("detected(for:) only reports agents whose directory exists under the overridden HOME")
    func detectedUsesOverriddenHome() throws {
        let claudeSkills = tempHome.appendingPathComponent(".claude/skills")
        try FileManager.default.createDirectory(at: claudeSkills, withIntermediateDirectories: true)

        let detected = AgentDescriptor.detected(for: .skill)
        #expect(detected.map(\.id).contains("claude-code"))
        #expect(detected.allSatisfy { $0.skillsPath?.path.hasPrefix(tempHome.path) == true })
    }
}
