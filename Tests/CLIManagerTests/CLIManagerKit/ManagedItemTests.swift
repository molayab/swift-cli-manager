import Testing
import Foundation

@testable import CLIManagerKit

struct ManagedItemTests {

    // MARK: - Helpers

    private func makeItem(
        kind: ManagedItemKind,
        id: String,
        name: String? = nil,
        description: String = "",
        body: String = "",
        isPrivate: Bool = false,
        dotfileLink: String? = nil,
        dotfileFileName: String? = nil
    ) -> ManagedItem {
        ManagedItem(
            kind: kind,
            id: id,
            name: name ?? id,
            description: description,
            body: body,
            isPrivate: isPrivate,
            location: URL(fileURLWithPath: "/tmp/\(id)"),
            dotfileLink: dotfileLink,
            dotfileFileName: dotfileFileName
        )
    }

    // MARK: - resolve

    @Test("Returns the full list when no filter is specified")
    func resolveReturnsAllWhenFilterIsEmpty() {
        let items = [
            makeItem(kind: .skill, id: "swift-testing", name: "Swift Testing"),
            makeItem(kind: .skill, id: "swiftui", name: "SwiftUI")
        ]
        #expect(ManagedItem.resolve([], from: items).count == items.count)
    }

    @Test("Filters items matching by id, by name, multiple terms, or nothing for unknown terms", arguments: [
        (["swift-testing"], 1),   // match by id
        (["Swift Testing"], 1),   // match by name (case-sensitive)
        (["nonexistent"], 0),   // no match
        (["swift-testing", "swiftui"], 2)   // match multiple by id
    ])
    func resolveByIdOrName(filter: [String], expectedCount: Int) {
        let items = [
            makeItem(kind: .skill, id: "swift-testing", name: "Swift Testing"),
            makeItem(kind: .skill, id: "swiftui", name: "SwiftUI")
        ]
        #expect(ManagedItem.resolve(filter, from: items).count == expectedCount)
    }

    @Test("A private item is found by its base id (without the .private suffix)")
    func privateItemIsFoundByBaseID() throws {
        // Loaders strip .private when computing the id, so callers always use the clean id.
        let privateItem = makeItem(kind: .skill, id: "my-skill", name: "My Skill", isPrivate: true)
        let resolved = ManagedItem.resolve(["my-skill"], from: [privateItem])
        let first = try #require(resolved.first)
        #expect(first.isPrivate == true)
    }

    // MARK: - Dotfile-only computed properties

    @Test("linkTarget expands tilde to the user home directory")
    func linkTargetExpandsTilde() {
        let item = makeItem(kind: .dotfile, id: "gitconfig", dotfileLink: "~/.gitconfig", dotfileFileName: ".gitconfig")
        let expected = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gitconfig")
        #expect(item.linkTarget == expected)
    }

    @Test("linkTarget works for nested config paths")
    func linkTargetNestedPath() {
        let item = makeItem(
            kind: .dotfile, id: "starship",
            dotfileLink: "~/.config/starship/starship.toml", dotfileFileName: "starship.toml"
        )
        let expected = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/starship/starship.toml")
        #expect(item.linkTarget == expected)
    }

    @Test("sourceFile is location joined with the dotfile's fileName")
    func sourceFileCombinesLocationAndFileName() {
        let location = URL(fileURLWithPath: "/tmp/gitconfig")
        let item = ManagedItem(
            kind: .dotfile,
            id: "gitconfig",
            name: "Git Config",
            description: "",
            body: "",
            isPrivate: false,
            location: location,
            dotfileLink: "~/.gitconfig",
            dotfileFileName: ".gitconfig"
        )
        #expect(item.sourceFile == location.appendingPathComponent(".gitconfig"))
    }

    @Test("linkTarget and sourceFile are nil for non-dotfile kinds")
    func nonDotfileKindsHaveNoLinkOrSource() {
        let skill = makeItem(kind: .skill, id: "swiftui-pro")
        #expect(skill.linkTarget == nil)
        #expect(skill.sourceFile == nil)
    }

    // MARK: - geminiTOML

    @Test("Produces correct TOML with both a description line and a triple-quoted prompt block")
    func geminiTOMLWithDescriptionAndBody() {
        let cmd = makeItem(
            kind: .command, id: "review", description: "Reviews code", body: "Review the following code."
        )
        let expected = "description = \"Reviews code\"\nprompt = \"\"\"\nReview the following code.\n\"\"\""
        #expect(ManagedItem.geminiTOML(from: cmd) == expected)
    }

    @Test("Omits the description line entirely when description is empty")
    func geminiTOMLOmitsDescriptionLineWhenEmpty() {
        let cmd = makeItem(kind: .command, id: "review", description: "", body: "Do something.")
        let toml = ManagedItem.geminiTOML(from: cmd)
        #expect(toml.contains("description") == false)
        #expect(toml.hasPrefix("prompt = \"\"\""))
    }

    @Test("Doubles each backslash in the description so TOML interprets them as literal backslashes")
    func geminiTOMLDoublesBackslashesInDescription() {
        let cmd = makeItem(kind: .command, id: "review", description: "path\\to\\file", body: "body")
        let toml = ManagedItem.geminiTOML(from: cmd)
        #expect(toml.contains("path\\\\to\\\\file"))
    }

    @Test("Escapes double quotes in the description with a preceding backslash")
    func geminiTOMLEscapesDoubleQuotesInDescription() {
        let cmd = makeItem(kind: .command, id: "review", description: "say \"hello\"", body: "body")
        let toml = ManagedItem.geminiTOML(from: cmd)
        #expect(toml.contains("\\\"hello\\\""))
    }

    @Test("Replaces triple-quote sequences in the body to prevent accidentally closing the TOML multi-line string")
    func geminiTOMLEscapesTripleQuoteInBody() {
        let cmd = makeItem(kind: .command, id: "review", description: "", body: "Use \"\"\" for docstrings.")
        let toml = ManagedItem.geminiTOML(from: cmd)
        #expect(toml.contains("\"\"\\\""))
    }
}
