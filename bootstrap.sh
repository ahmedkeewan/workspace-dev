#!/usr/bin/env bash
# Idempotent workspace setup: system tools → pinned toolchain → clone missing repos
# → install deps → git hooks → secrets file → CLI on PATH. Safe to re-run any time.
#
#   ./bootstrap.sh                        full setup
#   ./bootstrap.sh --install-only <repo>  reinstall one repo's deps (used by `dev update`)
set -euo pipefail

DEV_DIR=$(cd "$(dirname "$0")" && pwd)
DEV_ROOT=$(dirname "$DEV_DIR")
# shellcheck source=dev.conf
source "$DEV_DIR/dev.conf"
HOME_DIR=${DEV_HOME:-$HOME/.$NAME-dev}
SELF=$(basename "$DEV_DIR")
FAILED=()

step() { printf '\n==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
repos() { grep -v '^\s*#' "$DEV_DIR/repos.txt" | grep -v '^\s*$'; }
toolchain_env() { eval "$(mise env -C "$DEV_DIR" -s bash)"; }

install_repo() {  # name install-cmd
  local name=$1 cmd=$2
  [ "$cmd" = - ] && return 0
  [ -d "$DEV_ROOT/$name" ] || return 0
  echo "  $name: $cmd"
  ( cd "$DEV_ROOT/$name" && bash -c "$cmd" ) >"$HOME_DIR/install-$name.log" 2>&1 ||
    { warn "$name: install failed — see $HOME_DIR/install-$name.log"; FAILED+=("install:$name"); }
}

mkdir -p "$HOME_DIR"

if [ "${1:-}" = --install-only ]; then
  toolchain_env
  repos | while read -r name branch cmd; do
    if [ "$name" = "${2:?repo}" ]; then install_repo "$name" "$cmd"; fi
  done
  exit 0
fi

step "System tools"
case "$(uname -s)" in
  Darwin)
    if ! command -v brew >/dev/null; then
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    brew bundle --file "$DEV_DIR/Brewfile" --quiet
    # Keep whatever Docker runtime is already there (Colima, OrbStack, Docker Desktop);
    # otherwise install Colima: free for commercial use (MIT).
    if ! command -v docker >/dev/null; then
      brew install colima docker docker-compose
      cfg=$HOME/.docker/config.json; mkdir -p "$HOME/.docker"; [ -f "$cfg" ] || echo '{}' >"$cfg"
      jq '.cliPluginsExtraDirs = ((.cliPluginsExtraDirs // []) + ["/opt/homebrew/lib/docker/cli-plugins"] | unique)' \
        "$cfg" >"$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    fi
    if ! docker info >/dev/null 2>&1 && command -v colima >/dev/null; then colima start --memory 8 --cpu 4; fi
    ;;
  Linux)
    missing=$(for t in git curl jq; do command -v $t >/dev/null || echo $t; done)
    if [ -n "$missing" ]; then
      command -v apt-get >/dev/null || { warn "install manually: $missing"; exit 1; }
      # shellcheck disable=SC2086
      sudo apt-get update -qq && sudo apt-get install -y -qq $missing
    fi
    command -v mise >/dev/null || { curl -fsSL https://mise.run | sh; export PATH=$HOME/.local/bin:$PATH; }
    command -v docker >/dev/null || warn "no docker: install Docker Engine for the local stores"
    ;;
  *) warn "unsupported OS $(uname -s) (macOS or Linux/WSL2)"; exit 1 ;;
esac

step "Toolchain (mise.toml)"
# Symlink to the workspace dir so the pins apply in every sibling repo, not just here.
if [ -e "$DEV_ROOT/mise.toml" ] && [ ! -L "$DEV_ROOT/mise.toml" ]; then
  warn "$DEV_ROOT/mise.toml exists and isn't ours — left alone; pins apply via \`$CLI\` only"
else
  ln -sf "$SELF/mise.toml" "$DEV_ROOT/mise.toml"
  mise trust -q "$DEV_ROOT/mise.toml"
fi
mise trust -q "$DEV_DIR/mise.toml"
mise install -C "$DEV_DIR"
toolchain_env
mkdir -p "$HOME/.config/process-compose"  # silences process-compose's config-dir debug log

step "Repos → $DEV_ROOT"
use_gh=0; command -v gh >/dev/null && gh auth status >/dev/null 2>&1 && use_gh=1
[ $use_gh = 1 ] || warn "gh not logged in — cloning over https (run \`gh auth login\` if this fails)"
while read -r name branch _; do
  dir=$DEV_ROOT/$name
  if [ -d "$dir/.git" ]; then echo "  $name: present ($(git -C "$dir" branch --show-current))"; continue; fi
  echo "  $name: cloning ($branch)"
  if [ $use_gh = 1 ]; then gh repo clone "$GH_ORG/$name" "$dir" -- -q -b "$branch"
  else git clone -q -b "$branch" "https://github.com/$GH_ORG/$name.git" "$dir"; fi ||
    { warn "$name: clone failed (no access?)"; FAILED+=("clone:$name"); }
done < <(repos)

step "Dependencies (logs in $HOME_DIR/install-<repo>.log)"
while read -r name _ cmd; do install_repo "$name" "$cmd"; done < <(repos)

step "Git hooks (core.hooksPath → $SELF/hooks)"
# Repo-level config, so every worktree of a repo gets the hooks too.
while read -r name _; do
  dir=$DEV_ROOT/$name
  [ -d "$dir/.git" ] || continue
  cur=$(git -C "$dir" config --local core.hooksPath || true)
  if [ -n "$cur" ] && [ "$cur" != "$DEV_DIR/hooks" ]; then
    warn "$name: core.hooksPath is already $cur — left alone"; continue
  fi
  git -C "$dir" config core.hooksPath "$DEV_DIR/hooks"
  echo "  $name"
done < <(repos)

step "Secrets"
if [ -f "$HOME_DIR/secrets.env" ]; then echo "  $HOME_DIR/secrets.env exists — untouched"
else
  install -m 600 "$DEV_DIR/secrets.env.example" "$HOME_DIR/secrets.env"
  echo "  created $HOME_DIR/secrets.env — fill in what you need"
fi

step "$CLI CLI"
mkdir -p "$HOME/.local/bin"
link=$HOME/.local/bin/$CLI
if [ -e "$link" ] && [ "$(realpath "$link")" != "$DEV_DIR/bin/dev" ]; then
  warn "$link already points at $(realpath "$link") — left alone; set a unique CLI in dev.conf"
  FAILED+=("cli")
else
  ln -sf "$DEV_DIR/bin/dev" "$link"
  case ":$PATH:" in *":$HOME/.local/bin:"*) echo "  $CLI → $link" ;;
    *) warn "add ~/.local/bin to PATH (e.g. echo 'export PATH=\$HOME/.local/bin:\$PATH' >> ~/.zshrc)" ;; esac
fi

step "Doctor"
"$DEV_DIR/bin/dev" doctor || true

if [ ${#FAILED[@]} -gt 0 ]; then
  warn "finished with problems: ${FAILED[*]}"; exit 1
fi
printf '\nDone. Try: %s up web\n' "$CLI"
