#!/usr/bin/env bash
for dir in */; do
  dir="${dir%/}"
  [[ ! -d "$dir/.git" ]] && continue

  cd "$dir"

  uncommitted=$(git status --porcelain)
  unpushed=$(git log --branches --not --remotes --oneline 2>/dev/null)

  if [[ -n "$uncommitted" || -n "$unpushed" ]]; then
    echo "==> DIRTY: $dir"
    [[ -n "$uncommitted" ]] && echo "  uncommitted changes"
    [[ -n "$unpushed" ]] && echo "  unpushed commits: $(echo "$unpushed" | wc -l | tr -d ' ')"
  else
    echo "==> CLEAN, deleting: $dir"
    cd ..
    rm -rf "$dir"
    continue
  fi

  cd ..
done
