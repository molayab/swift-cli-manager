#!/usr/bin/env bash
# agent-manager quick installer
# Downloads a pre-compiled binary and creates a ready-to-use repo — no Swift toolchain required.
#
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/molayab/swift-agent-manager/main/quickinstall.sh | bash
#
# Or with options:
#   curl -fsSL https://raw.githubusercontent.com/molayab/swift-agent-manager/main/quickinstall.sh | bash -s -- [--dir <path>] [--global] [--version <tag>]
#
# Options:
#   --dir <path>      Where to create the repo (default: ~/.config/agent-manager/src)
#   --global          Also install the binary to /usr/local/bin
#   --version <tag>   Pin to a specific release tag (default: latest)

set -e

# ── helpers ────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    bold="\033[1m"; reset="\033[0m"
    green="\033[32m"; yellow="\033[33m"; red="\033[31m"
    blue="\033[34m"; gray="\033[90m"
else
    bold=""; reset=""; green=""; yellow=""; red=""; blue=""; gray=""
fi

ok()   { echo -e "${green}✓${reset} $*"; }
warn() { echo -e "${yellow}!${reset} $*"; }
fail() { echo -e "${red}✗${reset} $*" >&2; exit 1; }
info() { echo -e "${blue}i${reset} $*"; }

# ── constants ──────────────────────────────────────────────────────────────────
GITHUB_REPO="molayab/swift-agent-manager"

# ── defaults ───────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/.config/agent-manager/src"
GLOBAL=false
GLOBAL_BIN="/usr/local/bin"
RELEASE_VERSION="latest"

# ── args ───────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --dir)
            [[ -z "${2-}" ]] && fail "--dir requires a path argument."
            INSTALL_DIR="$2"; shift 2 ;;
        --dir=*)
            INSTALL_DIR="${1#--dir=}"; shift ;;
        --global)
            GLOBAL=true; shift ;;
        --version)
            [[ -z "${2-}" ]] && fail "--version requires a tag argument (e.g. --version 1.0.0)."
            RELEASE_VERSION="$2"; shift 2 ;;
        --version=*)
            RELEASE_VERSION="${1#--version=}"; shift ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            fail "Unknown option: $1" ;;
    esac
done

command -v curl &>/dev/null || fail "curl is required but was not found in PATH."
command -v git  &>/dev/null || fail "git is required but was not found in PATH."

# ── platform ───────────────────────────────────────────────────────────────────
case "$(uname -s)" in
    Darwin) os="macos" ;;
    Linux)  os="linux" ;;
    *)      fail "Unsupported platform: $(uname -s)" ;;
esac
arch="$(uname -m)"   # arm64 | x86_64
asset_name="agent-manager-${os}-${arch}"

# ── fetch release metadata ─────────────────────────────────────────────────────
if [[ "$RELEASE_VERSION" == "latest" ]]; then
    api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
else
    api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${RELEASE_VERSION}"
fi

echo ""
echo -e "${bold}agent-manager quick install${reset}  ${gray}${GITHUB_REPO}${reset}"
echo ""
info "Fetching release metadata…"

release_json="$(curl -fsSL "$api_url")" || fail "Could not fetch release metadata from GitHub."

tag_name="$(python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','?'))" <<< "$release_json" 2>/dev/null || echo "?")"

download_url="$(python3 -c "
import sys, json
for a in json.load(sys.stdin).get('assets', []):
    if a.get('name') == '${asset_name}':
        print(a['browser_download_url']); break
" <<< "$release_json" 2>/dev/null)"

[[ -z "$download_url" ]] && fail "No binary found for ${asset_name} in release ${tag_name}."

# ── download binary ────────────────────────────────────────────────────────────
info "Downloading ${bold}${asset_name}${reset}  ${gray}@ ${tag_name}${reset}"

tmp_binary="$(mktemp)"
trap 'rm -f "$tmp_binary"' EXIT

curl -fSL --progress-bar -o "$tmp_binary" "$download_url" || fail "Download failed."
chmod +x "$tmp_binary"

# ── create repo structure ──────────────────────────────────────────────────────
echo ""
info "Creating repo at ${bold}${INSTALL_DIR}${reset}"

mkdir -p "$INSTALL_DIR/skills"
mkdir -p "$INSTALL_DIR/commands"
mkdir -p "$INSTALL_DIR/bin"

# .gitignore — exclude binary, macOS noise, and private files
if [[ ! -f "$INSTALL_DIR/.gitignore" ]]; then
    cat > "$INSTALL_DIR/.gitignore" << 'EOF'
# Local binary (installed by quickinstall.sh / install.sh)
bin/

# macOS
.DS_Store

# Private skills and commands (local only, never committed)
skills/*.private/
commands/*.private.md
EOF
    ok "Created  ${gray}.gitignore${reset}"
fi

# Initialise git if not already a repo
if [[ ! -d "$INSTALL_DIR/.git" ]]; then
    git -C "$INSTALL_DIR" init -q
    git -C "$INSTALL_DIR" add .gitignore
    git -C "$INSTALL_DIR" commit -q -m "Initial commit"
    ok "Initialised git repository"
fi

# ── install binary ─────────────────────────────────────────────────────────────
cp "$tmp_binary" "$INSTALL_DIR/bin/agent-manager"
ok "Installed  ${gray}bin/agent-manager${reset}  ${gray}(${tag_name})${reset}"

if $GLOBAL; then
    if [ -w "$GLOBAL_BIN" ]; then
        cp "$tmp_binary" "$GLOBAL_BIN/agent-manager"
    else
        warn "$(realpath "$GLOBAL_BIN" 2>/dev/null || echo "$GLOBAL_BIN") is not writable — using sudo"
        sudo cp "$tmp_binary" "$GLOBAL_BIN/agent-manager"
    fi
    ok "Installed  ${gray}${GLOBAL_BIN}/agent-manager${reset}"
fi

# ── write repo config ──────────────────────────────────────────────────────────
config_dir="$HOME/.config/agent-manager"
mkdir -p "$config_dir"
echo "$INSTALL_DIR" > "$config_dir/repo"
ok "Repo path saved to ${bold}~/.config/agent-manager/repo${reset}"

# ── done ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${bold}Done!${reset}  Your agent-manager repo is at ${bold}${INSTALL_DIR}${reset}"
echo ""

if $GLOBAL; then
    info "Run: ${bold}agent-manager skill activate${reset}"
else
    info "Add ${bold}${INSTALL_DIR}/bin${reset} to your PATH, or run directly:"
    info "  ${bold}${INSTALL_DIR}/bin/agent-manager skill activate${reset}"
fi

info "To push to your own remote:"
info "  cd ~/.config/agent-manager/src && git remote add origin <your-repo-url> && git push -u origin main"
echo ""
