# my-skills

Personal AI agent skills manager, written in Swift.

Compatible with **OpenCode**, **Claude Code**, **GitHub Copilot**, **Cursor**, **Cline**, and more.

## Run

```sh
swift run skills <command>
```

## Commands

| Command | Description |
|---------|-------------|
| `activate` | Symlink skills into agent directories |
| `deactivate` | Remove skills from agent directories |
| `new <name>` | Scaffold a new skill |
| `list` | List all skills in this repo |
| `status` | Show activation status per agent |

## Options

| Flag | Description |
|------|-------------|
| `-s, --skill <name>` | Target a specific skill (repeatable) |
| `-a, --agent <id>` | Target a specific agent (repeatable) |
| `--dry-run` | Preview changes without applying them |

## Examples

```sh
# Activate all skills to all detected agents
swift run skills activate

# Target one agent
swift run skills activate -a cline

# Activate a single skill
swift run skills activate -s swiftui-pro

# Preview without making changes
swift run skills activate --dry-run

# Deactivate a skill
swift run skills deactivate -s swift-testing-pro

# Create a new skill
swift run skills new "my-skill"

# Check what's installed where
swift run skills status
```

## Install the binary (optional)

Build a release binary and put it on your PATH so you can run `skills` directly:

```sh
swift build -c release
cp .build/release/skills /usr/local/bin/skills

# Then use it from anywhere:
skills activate
skills status
skills new "my-skill"
```

## Adding a skill

Either use `new`:

```sh
swift run skills new "my-skill"
# → creates skills/my-skill/SKILL.md
```

Or create a directory manually under `skills/` with a `SKILL.md`:

```
skills/
└── my-skill/
    └── SKILL.md
```

`SKILL.md` requires YAML frontmatter with `name` and `description`:

```markdown
---
name: my-skill
description: What this skill does and when the agent should use it.
---

# My Skill

Instructions for the agent...
```

Then activate it:

```sh
swift run skills activate -s my-skill
```
