#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude/skills"
AGENTS_DIR="$HOME/.agents/skills"

TARGETS=()
SKILLS=()
COPY=0
FORCE=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options] [skill ...]

Options:
  -t, --target <name|path>  Where to install. Can be repeated. One of:
                              claude   -> ~/.claude/skills  (Claude Code)
                              agents   -> ~/.agents/skills  (Copilot, Codex)
                              copilot  -> alias of "agents"
                              both     -> claude + agents
                              <path>   -> any custom directory
                            If omitted, you will be asked interactively.
  -l, --list                List available skills and exit
  --copy                    Copy instead of creating symlinks
  --force                   Replace existing folders that are not symlinks
  -h, --help                Show this help

With no skill names, every skill under skills/ is installed.
USAGE
}

list_skills() {
  local d
  for d in "$REPO_DIR"/skills/*/; do
    [[ -f "$d/SKILL.md" ]] && basename "$d"
  done
}

add_target() {
  case "$1" in
    claude)         TARGETS+=("$CLAUDE_DIR") ;;
    agents|copilot) TARGETS+=("$AGENTS_DIR") ;;
    both)           TARGETS+=("$CLAUDE_DIR" "$AGENTS_DIR") ;;
    *)              TARGETS+=("$1") ;;
  esac
}

prompt_target() {
  if [[ ! -t 0 ]]; then
    echo "error: no --target given and no interactive terminal available." >&2
    echo "       use: --target claude | agents | both | <path>" >&2
    exit 1
  fi
  echo "Install skills for:"
  echo "  1) Claude Code        (~/.claude/skills)"
  echo "  2) Copilot / agents   (~/.agents/skills)"
  echo "  3) Both"
  read -rp "Choose [1-3]: " choice
  case "$choice" in
    1) add_target claude ;;
    2) add_target agents ;;
    3) add_target both ;;
    *) echo "error: invalid choice" >&2; exit 1 ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)
      [[ -n "${2:-}" ]] || { echo "error: --target needs a value" >&2; exit 1; }
      add_target "$2"
      shift 2 ;;
    -l|--list) list_skills; exit 0 ;;
    --copy)    COPY=1; shift ;;
    --force)   FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        echo "error: unknown option: $1" >&2; usage; exit 1 ;;
    *)         SKILLS+=("$1"); shift ;;
  esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  prompt_target
fi

if [[ ${#SKILLS[@]} -eq 0 ]]; then
  while IFS= read -r name; do SKILLS+=("$name"); done < <(list_skills)
fi

if [[ ${#SKILLS[@]} -eq 0 ]]; then
  echo "error: no skills found under $REPO_DIR/skills" >&2
  exit 1
fi

if [[ ${#TARGETS[@]} -gt 1 ]]; then
  echo "note: VS Code Copilot reads both ~/.claude/skills and ~/.agents/skills," >&2
  echo "      so the same skill may show up twice there." >&2
fi

for target in "${TARGETS[@]}"; do
  mkdir -p "$target"
  for name in "${SKILLS[@]}"; do
    src="$REPO_DIR/skills/$name"
    dest="$target/$name"

    if [[ ! -f "$src/SKILL.md" ]]; then
      echo "skip:   $name (not found or missing SKILL.md)"
      continue
    fi

    if [[ -L "$dest" ]]; then
      rm "$dest"
    elif [[ -e "$dest" ]]; then
      if [[ $FORCE -eq 1 ]]; then
        rm -rf "$dest"
      else
        echo "skip:   $name (already exists at $dest; use --force to replace)"
        continue
      fi
    fi

    if [[ $COPY -eq 1 ]]; then
      cp -R "$src" "$dest"
      echo "copied: $name -> $dest"
    else
      ln -s "$src" "$dest"
      echo "linked: $name -> $dest"
    fi
  done
done