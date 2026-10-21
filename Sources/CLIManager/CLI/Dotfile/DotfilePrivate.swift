import ArgumentParser
import CLIManagerKit
import Foundation

struct DotfilePrivate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "private",
        abstract: "Toggle a dotfile between private (untracked) and public (committed)."
    )

    @Argument(help: "Dotfile id to toggle (e.g. gitconfig).")
    var name: String

    func run() throws {
        let dotfiles = ManagedItem.load(.dotfile).items
        guard let dotfile = dotfiles.first(where: { $0.id == name }) else {
            fail("Dotfile '\(name)' not found."); return
        }

        let newDirName = dotfile.isPrivate ? dotfile.id : "\(dotfile.id).private"
        let newDir = dotfilesDir.appendingPathComponent(newDirName)

        guard !fm.fileExists(atPath: newDir.path) else {
            fail("'\(newDirName)' already exists in dotfiles/ — resolve the conflict first.")
            return
        }

        try fm.moveItem(at: dotfile.location, to: newDir)

        // Re-point any existing symlink at linkTarget to the new source file location
        if let linkTarget = dotfile.linkTarget, let fileName = dotfile.dotfileFileName, isSymlink(linkTarget) {
            let newSource = newDir.appendingPathComponent(fileName)
            try fm.removeItem(at: linkTarget)
            try fm.createSymbolicLink(at: linkTarget, withDestinationURL: newSource)
            info("  Updated symlink at \(dotfile.dotfileLink ?? "")")
        }

        let state = dotfile.isPrivate ? "public (will be committed)" : "private (git-ignored)"
        ok("'\(dotfile.id)' is now \(state)")
    }
}
