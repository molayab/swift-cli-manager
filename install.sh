#!/usr/bin/env bash
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
fail() { echo -e "${red}✗${reset} $*" >&2; }
info() { echo -e "${blue}i${reset} $*"; }

# ── constants ──────────────────────────────────────────────────────────────────
# GitHub repository that publishes pre-compiled release binaries.
# Each release must contain assets named:
#   agent-manager-macos-arm64    (Apple Silicon)
#   agent-manager-macos-x86_64  (Intel Mac)
GITHUB_REPO="molayab/swift-agent-manager"

# ── args ───────────────────────────────────────────────────────────────────────
GLOBAL=false
GLOBAL_BIN="/usr/local/bin"
INSTALL_BINARY=false
RELEASE_VERSION="latest"

usage() {
    echo "Usage: $0 [--binary [--version <tag>]] [--global]" >&2
    echo "" >&2
    echo "  (no flags)          Build from source using the Swift toolchain" >&2
    echo "  --binary            Download a pre-compiled binary from GitHub Releases" >&2
    echo "  --version <tag>     Pin to a specific release tag, e.g. v1.2.0 (requires --binary)" >&2
    echo "  --global            Install to /usr/local/bin instead of ./bin" >&2
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --global)
            GLOBAL=true
            shift
            ;;
        --binary)
            INSTALL_BINARY=true
            shift
            ;;
        --version)
            if [[ -z "${2-}" ]]; then
                fail "--version requires a tag argument (e.g. --version v1.0.0)"
                exit 1
            fi
            RELEASE_VERSION="$2"
            shift 2
            ;;
        --version=*)
            RELEASE_VERSION="${1#--version=}"
            shift
            ;;
        -h|--help)
            usage; exit 0
            ;;
        *)
            fail "Unknown option: $1"
            echo "" >&2
            usage
            exit 1
            ;;
    esac
done

# ── locate repo root (directory containing this script) ───────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── write repo config (lets the binary find skills/commands after install) ─────
write_repo_config() {
    local config_dir="$HOME/.config/agent-manager"
    mkdir -p "$config_dir"
    echo "$SCRIPT_DIR" > "$config_dir/repo"
    ok "Repo path saved to ${bold}~/.config/agent-manager/repo${reset}"
}

# ── copy a built/downloaded binary to the chosen destination ──────────────────
copy_to_destination() {
    local src="$1"
    local dest
    if $GLOBAL; then
        dest="$GLOBAL_BIN/agent-manager"
        info "Installing to ${bold}${dest}${reset}"
        if [ -w "$GLOBAL_BIN" ]; then
            cp "$src" "$dest"
            chmod +x "$dest"
        else
            warn "$(realpath "$GLOBAL_BIN") is not writable — using sudo"
            sudo cp "$src" "$dest"
            sudo chmod +x "$dest"
        fi
        write_repo_config
        ok "Installed.  Run: ${bold}agent-manager${reset}"
    else
        mkdir -p "$SCRIPT_DIR/bin"
        dest="$SCRIPT_DIR/bin/agent-manager"
        cp "$src" "$dest"
        chmod +x "$dest"
        write_repo_config
        ok "Installed.  Run: ${bold}./bin/agent-manager${reset}"
        info "Or add ${bold}$(realpath bin)${reset} to your PATH to run as ${bold}agent-manager${reset}"
    fi
}

# ── download pre-compiled binary from GitHub releases ─────────────────────────
install_from_github() {
    if ! command -v curl &>/dev/null; then
        fail "curl is required for --binary but was not found in PATH."
        exit 1
    fi

    # Map uname output to the asset naming convention used in GitHub releases.
    local os arch
    case "$(uname -s)" in
        Darwin) os="macos" ;;
        Linux)  os="linux" ;;
        *)
            fail "Unsupported platform: $(uname -s)"
            info "Build from source instead: ${bold}$0${reset} (without --binary)"
            exit 1
            ;;
    esac
    arch="$(uname -m)"   # arm64 | x86_64

    local asset_name="agent-manager-${os}-${arch}"

    # Select the GitHub API endpoint (latest or a pinned tag).
    local api_url
    if [[ "$RELEASE_VERSION" == "latest" ]]; then
        api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
    else
        api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${RELEASE_VERSION}"
    fi

    echo ""
    echo -e "${bold}Downloading agent-manager…${reset}  ${gray}${GITHUB_REPO}${reset}"
    echo ""
    info "Fetching release metadata…"

    local release_json
    release_json="$(curl -fsSL "$api_url")" || {
        fail "Could not fetch release metadata from GitHub."
        info "URL: ${api_url}"
        exit 1
    }

    # python3 is always available on macOS and is the most reliable JSON parser
    # in a dependency-free shell script.
    local tag_name download_url
    tag_name="$(python3 -c "
import sys, json
print(json.load(sys.stdin).get('tag_name', '?'))
" <<< "$release_json" 2>/dev/null || echo "?")"

    download_url="$(python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset.get('name', '') == '${asset_name}':
        print(asset['browser_download_url'])
        break
" <<< "$release_json" 2>/dev/null)"

    if [[ -z "$download_url" ]]; then
        fail "No binary found for ${bold}${asset_name}${reset} in release ${bold}${tag_name}${reset}."
        local available
        available="$(python3 -c "
import sys, json
for a in json.load(sys.stdin).get('assets', []):
    print('  ' + a['name'])
" <<< "$release_json" 2>/dev/null)"
        if [[ -n "$available" ]]; then
            info "Assets available in this release:"
            echo "$available"
        fi
        info "Build from source instead: ${bold}$0${reset} (without --binary)"
        exit 1
    fi

    info "Downloading ${bold}${asset_name}${reset}  ${gray}@ ${tag_name}${reset}"

    local tmp_file
    tmp_file="$(mktemp)"
    trap 'rm -f "$tmp_file"' EXIT

    curl -fSL --progress-bar -o "$tmp_file" "$download_url" || {
        fail "Download failed."
        exit 1
    }

    chmod +x "$tmp_file"
    echo ""
    copy_to_destination "$tmp_file"
}

# ── build from source ──────────────────────────────────────────────────────────
install_from_source() {
    if ! command -v swift &>/dev/null; then
        fail "swift not found in PATH."
        info "Install the Swift toolchain from ${bold}https://swift.org/download${reset}"
        info "Or download a pre-compiled binary: ${bold}$0 --binary${reset}"
        exit 1
    fi

    local swift_version
    swift_version="$(swift --version 2>&1 | head -1)"
    echo ""
    echo -e "${bold}Building agent-manager…${reset}  ${gray}${swift_version}${reset}"
    echo ""

    swift build -c release 2>&1 | sed "s/^/  /"

    local binary=".build/release/agent-manager"
    if [ ! -f "$binary" ]; then
        fail "Build succeeded but binary not found at ${binary}"
        exit 1
    fi

    echo ""
    copy_to_destination "$binary"
}

# ── dispatch ───────────────────────────────────────────────────────────────────
if $INSTALL_BINARY; then
    install_from_github
else
    install_from_source
fi

echo ""
