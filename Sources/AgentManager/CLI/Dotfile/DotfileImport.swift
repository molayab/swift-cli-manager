import ArgumentParser
import Foundation

struct DotfileImport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Scan home directory for common dotfiles and import them."
    )

    @Flag(name: .long, help: "Also create symlinks after importing.")
    var link = false

    // ── Well-known dotfiles ───────────────────────────────────────────────────

    /// (link target relative to ~, suggested slug, human-readable name)
    private static let knownDotfiles: [(link: String, slug: String, name: String)] = [
        // Shell
        ("~/.zshrc",              "zshrc",            "Zsh RC"),
        ("~/.zprofile",           "zprofile",         "Zsh Profile"),
        ("~/.zsh_profile",        "zsh-profile",      "Zsh Profile (alt)"),
        ("~/.bashrc",             "bashrc",           "Bash RC"),
        ("~/.bash_profile",       "bash-profile",     "Bash Profile"),
        ("~/.profile",            "profile",          "Shell Profile"),
        // Git
        ("~/.gitconfig",          "gitconfig",        "Git Config"),
        ("~/.gitignore_global",   "gitignore-global", "Git Global Ignore"),
        // Editors
        ("~/.vimrc",              "vimrc",            "Vim RC"),
        ("~/.nanorc",             "nanorc",           "Nano RC"),
        ("~/.editorconfig",       "editorconfig",     "EditorConfig"),
        // Terminal multiplexers
        ("~/.tmux.conf",          "tmux-conf",        "tmux Config"),
        ("~/.screenrc",           "screenrc",         "GNU Screen RC"),
        // Terminal emulators
        ("~/.wezterm.lua",        "wezterm",          "WezTerm Config"),
        ("~/.alacritty.toml",     "alacritty",        "Alacritty Config"),
        ("~/.config/alacritty/alacritty.toml", "alacritty", "Alacritty Config"),
        ("~/.config/kitty/kitty.conf",         "kitty",     "Kitty Config"),
        // Prompt / shell tools
        ("~/.config/starship/starship.toml",   "starship",  "Starship Prompt"),
        ("~/.config/fish/config.fish",         "fish",      "Fish Shell Config"),
        // Misc
        ("~/.ssh/config",         "ssh-config",       "SSH Config"),
        ("~/.curlrc",             "curlrc",           "curl RC"),
        ("~/.npmrc",              "npmrc",            "npm RC"),
        ("~/.config/gh/config.yml", "gh-config",     "GitHub CLI Config"),
    ]

    // ── Candidate ─────────────────────────────────────────────────────────────

    private struct Candidate {
        let link: String
        let slug: String
        let name: String
        let sourcePath: URL
        let fileName: String
    }

    // ── Run ───────────────────────────────────────────────────────────────────

    func run() throws {
        let existing = Set(DotfileModel.loadDotfiles().map { $0.id })
        let alreadySlugs = Set(DotfileModel.loadDotfiles().map { $0.link })

        // Find known dotfiles present on disk that are not yet tracked
        var seen = Set<String>()   // deduplicate by slug when multiple paths map to same slug
        let candidates: [Candidate] = Self.knownDotfiles.compactMap { entry in
            let expanded = URL(fileURLWithPath: expandingTilde(in: entry.link))
            // Skip if not a regular file, already tracked by slug or link, or duplicate slug
            guard fm.fileExists(atPath: expanded.path),
                  !isSymlink(expanded),
                  !existing.contains(entry.slug),
                  !alreadySlugs.contains(entry.link),
                  seen.insert(entry.slug).inserted
            else { return nil }
            return Candidate(
                link: entry.link,
                slug: entry.slug,
                name: entry.name,
                sourcePath: expanded,
                fileName: expanded.lastPathComponent
            )
        }

        guard !candidates.isEmpty else {
            if existing.isEmpty {
                warn("No common dotfiles found in home directory.")
            } else {
                ok("All found common dotfiles are already tracked.")
            }
            return
        }

        print("\n\(bold)Found \(candidates.count) untracked dotfile(s)\(reset)\n")

        let selected = selectInteractive(
            prompt: "Select dotfiles to import",
            items: candidates,
            display: { "\($0.name)  \(gray)\($0.link)\(reset)" }
        )
        guard !selected.isEmpty else {
            warn("Nothing selected.")
            return
        }

        print()
        for candidate in selected {
            try importCandidate(candidate)
        }

        if link {
            print()
            info("Creating symlinks…")
            let dotfiles = DotfileModel.loadDotfiles()
            for candidate in selected {
                guard let dotfile = dotfiles.first(where: { $0.id == candidate.slug }) else { continue }
                try linkDotfile(dotfile)
            }
        } else {
            print()
            info("Run  \(bold)agent-manager dotfile link\(reset)  to activate symlinks.")
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func importCandidate(_ candidate: Candidate) throws {
        let destDir = dotfilesDir.appendingPathComponent(candidate.slug)

        if fm.fileExists(atPath: destDir.path) {
            skip("  \(candidate.slug)  \(gray)directory already exists\(reset)")
            return
        }

        let template = """
        ---
        name: \(candidate.name)
        description:
        link: \(candidate.link)
        file: \(candidate.fileName)
        ---

        # \(candidate.name)

        Managed by agent-manager. Edit \(candidate.fileName) directly.
        """

        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        try template.write(to: destDir.appendingPathComponent("DOTFILE.md"), atomically: true, encoding: .utf8)
        try fm.copyItem(at: candidate.sourcePath, to: destDir.appendingPathComponent(candidate.fileName))
        ok("  \(candidate.slug)  \(gray)← \(candidate.link)\(reset)")
    }

    private func linkDotfile(_ dotfile: DotfileModel) throws {
        let target = dotfile.linkTarget
        let source = dotfile.sourceFile

        guard fm.fileExists(atPath: source.path) else {
            fail("  \(dotfile.id): source missing")
            return
        }

        if isSymlink(target) {
            let dest = try? fm.destinationOfSymbolicLink(atPath: target.path)
            if dest == source.path {
                skip("  \(dotfile.id)  \(gray)already linked\(reset)")
                return
            }
            try fm.removeItem(at: target)
        } else if fm.fileExists(atPath: target.path) {
            // The original file still exists (we copied, not moved) — replace with symlink
            try fm.removeItem(at: target)
        }

        try fm.createSymbolicLink(at: target, withDestinationURL: source)
        ok("  \(dotfile.id)  → \(gray)\(target.path)\(reset)")
    }
}
