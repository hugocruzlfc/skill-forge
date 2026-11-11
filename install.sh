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

Skills live in skills/<name> or skills/<group>/<name> and are installed flat,
so skill names must be unique across groups.
With no skill names, every skill is installed.
USAGE
}

# Prints "name<TAB>path" for every skill, flat (skills/<name>) or
# grouped one level deep (skills/<group>/<name>).
list_skill_paths() {
  local f dir
  while IFS= read -r f; do
    dir="$(dirname "$f")"
    printf '%s\t%s\n' "$(basename "$dir")" "$dir"
  done < <(find "$REPO_DIR/skills" -mindepth 2 -maxdepth 3 -name SKILL.md | sort)
}

list_skills() {
  list_skill_paths | cut -f1
}

find_skill() {
  list_skill_paths | awk -F'\t' -v n="$1" '$1 == n { print $2; exit }'
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

duplicates="$(list_skills | sort | uniq -d)"
if [[ -n "$duplicates" ]]; then
  echo "error: duplicate skill names (they are installed flat, so they must be unique):" >&2
  echo "$duplicates" >&2
  exit 1
fi

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
    src="$(find_skill "$name")"
    dest="$target/$name"

    if [[ -z "$src" ]]; then
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