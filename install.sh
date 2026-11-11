#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/skills"
COPY=0
FORCE=0
SKILLS=()

usage() {
  cat <<EOF
Uso: ./install.sh [opciones] [skill ...]

  -t, --target <claude|agents|ruta>  Destino (por defecto: claude -> ~/.claude/skills,
                                     agents -> ~/.agents/skills)
  --copy                             Copia en vez de crear symlinks
  --force                            Reemplaza carpetas existentes que no sean symlinks
  -h, --help                         Muestra esta ayuda

Sin nombres de skill, instala todas las de skills/.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)
      case "${2:-}" in
        claude) TARGET="$HOME/.claude/skills" ;;
        agents) TARGET="$HOME/.agents/skills" ;;
        "") echo "Falta el valor de --target" >&2; exit 1 ;;
        *) TARGET="$2" ;;
      esac
      shift 2 ;;
    --copy) COPY=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Opción desconocida: $1" >&2; usage; exit 1 ;;
    *) SKILLS+=("$1"); shift ;;
  esac
done

if [[ ${#SKILLS[@]} -eq 0 ]]; then
  for d in "$REPO_DIR"/skills/*/; do
    [[ -f "$d/SKILL.md" ]] && SKILLS+=("$(basename "$d")")
  done
fi

mkdir -p "$TARGET"

for name in "${SKILLS[@]}"; do
  src="$REPO_DIR/skills/$name"
  dest="$TARGET/$name"

  if [[ ! -f "$src/SKILL.md" ]]; then
    echo "skip: $name (no existe o no tiene SKILL.md)"
    continue
  fi

  if [[ -L "$dest" ]]; then
    rm "$dest"
  elif [[ -e "$dest" ]]; then
    if [[ $FORCE -eq 1 ]]; then
      rm -rf "$dest"
    else
      echo "skip: $name (ya existe en $dest; usa --force para reemplazar)"
      continue
    fi
  fi

  if [[ $COPY -eq 1 ]]; then
    cp -R "$src" "$dest"
    echo "copiada:  $name -> $dest"
  else
    ln -s "$src" "$dest"
    echo "enlazada: $name -> $dest"
  fi
done