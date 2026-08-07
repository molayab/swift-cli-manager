import ArgumentParser
import CLIManagerKit
import Foundation

struct DotfileList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all dotfiles in this repo."
    )

    func run() throws {
        let dotfiles = ManagedItem.load(.dotfile).items
        guard !dotfiles.isEmpty else {
            warn("No dotfiles found in dotfiles/")
            return
        }

        print("\n\(bold)Dotfiles\(reset) \(gray)(\(dotfiles.count))\(reset)\n")
        for dotfile in dotfiles {
            let privTag = dotfile.isPrivate ? " \(yellow)(private)\(reset)" : ""
            print("  \(cyan)\(bold)\(dotfile.name)\(reset)\(privTag)")
            if !dotfile.description.isEmpty { print("  \(dim)\(dotfile.description)\(reset)") }
            print("  \(gray)\(dotfile.dotfileLink ?? "")\(reset)")

            if dotfile.isLinked {
                print("  \(green)● linked\(reset)")
            } else {
                print("  \(gray)○ not linked\(reset)")
            }
            print()
        }
    }
}
