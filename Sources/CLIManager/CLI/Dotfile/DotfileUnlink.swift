import ArgumentParser
import CLIManagerKit
import Foundation

struct DotfileUnlink: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unlink",
        abstract: "Remove symlinks for dotfiles from their target paths."
    )

    @Option(name: .shortAndLong, help: "Dotfile id to unlink (repeatable).")
    var dotfile: [String] = []

    @Flag(name: .long, help: "Preview changes without applying them.")
    var dryRun = false

    func run() throws {
        let all = ManagedItem.load(.dotfile).items
        guard !all.isEmpty else {
            fail("No dotfiles found in dotfiles/")
            return
        }

        let selected: [ManagedItem] = dotfile.isEmpty
            ? selectInteractive(prompt: "Select dotfiles to unlink", items: all, display: \.name)
            : ManagedItem.resolve(dotfile, from: all)
        guard !selected.isEmpty else {
            fail("No matching dotfiles.")
            return
        }

        print("\n\(bold)Unlinking \(selected.count) dotfile(s)\(reset)"
            + (dryRun ? "  \(yellow)(dry run)\(reset)" : "") + "\n")

        for dotfileItem in selected {
            try unlinkDotfile(dotfileItem)
        }
    }

    private func unlinkDotfile(_ dotfile: ManagedItem) throws {
        guard let target = dotfile.linkTarget else {
            fail("  \(dotfile.id): not a dotfile item")
            return
        }

        guard isSymlink(target) else {
            if fm.fileExists(atPath: target.path) {
                skip("  \(dotfile.id)  \(gray)not a symlink — skipping\(reset)")
            } else {
                skip("  \(dotfile.id)  \(gray)nothing at \(target.path)\(reset)")
            }
            return
        }

        // Only remove symlinks that point into this repo
        if let dest = symlinkDestination(at: target),
           !isDescendant(URL(fileURLWithPath: dest), of: repoRoot) {
            warn("  \(dotfile.id)  symlink points outside repo (\(dest)) — skipping for safety")
            return
        }

        if dryRun {
            ok("  \(dotfile.id)  \(gray)→ would remove symlink at \(target.path)\(reset)")
        } else {
            try fm.removeItem(at: target)
            ok("  \(dotfile.id)  unlinked")
        }
    }
}
