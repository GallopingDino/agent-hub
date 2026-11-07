#!/bin/bash
# Links every skill in this folder into the user-wide skill folders of Claude Code and Codex, so edits here apply at once.
set -euo pipefail
shopt -s nullglob

readonly SKILLS_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly TARGET_DIRS=("$HOME/.claude/skills" "$HOME/.codex/skills")

for target_dir in "${TARGET_DIRS[@]}"; do
    mkdir -p "$target_dir"
    for skill_dir in "$SKILLS_DIR"/*/; do
        skill_name="$(basename "$skill_dir")"
        link="$target_dir/$skill_name"
        if [[ -e "$link" && ! -L "$link" ]]; then
            echo "skipped $link: a skill that is not ours already has this name" >&2
            continue
        fi
        ln -sfn "${skill_dir%/}" "$link"
        echo "$link -> ${skill_dir%/}"
    done
done
