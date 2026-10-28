#!/usr/bin/env bash
# Strip a freshly merged deploy-fe down to the paths in deploy-keep.txt.
# Only git-tracked files are touched: they always leave the index; deleting them
# from disk is best-effort (locked files, live worktrees, untracked data stay).
# Usage: cleanup-deploy-branch.sh [--dry-run]
set -u
script_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$script_dir/.." || exit 1

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$dry_run" -eq 0 ] && [ "$branch" != "deploy-fe" ]; then
    echo "Current branch is '$branch', not deploy-fe -> skip cleanup." >&2
    exit 1
fi

keep=()
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] || [ "${line:0:1}" = "#" ] || keep+=("$line")
done < "$script_dir/deploy-keep.txt"

# A keep entry matches the path itself or anything under it (entries may be nested, e.g. .beads/.gitignore).
is_kept() {
    local k
    for k in "${keep[@]}"; do
        k="${k%/}"
        [ "$1" = "$k" ] && return 0
        [[ "$1" == "$k/"* ]] && return 0
    done
    return 1
}

# Conflicts in removed paths are resolved by the removal; kept paths must be clean.
conflicts=()
while IFS= read -r -d '' f; do
    is_kept "$f" && conflicts+=("$f")
done < <(git diff -z --name-only --diff-filter=U)
if [ "${#conflicts[@]}" -gt 0 ]; then
    echo "Resolve merge conflicts in kept paths first:" >&2
    printf '  %s\n' "${conflicts[@]}" >&2
    exit 1
fi

# No associative arrays here: stock macOS bash is 3.2 and lacks declare -A.
remove_files=()
while IFS= read -r -d '' f; do
    is_kept "$f" && continue
    remove_files+=("$f")
done < <(git ls-files -z)

remove_top=()
if [ "${#remove_files[@]}" -eq 0 ]; then
    echo "Nothing to clean."
else
    # Per-top-level counts straight from the removal list; git ls-files never
    # repeats a path, so no dedupe step is needed.
    while read -r n top; do
        remove_top+=("$top")
        echo "Remove $top ($n tracked file(s))"
    done < <(printf '%s\n' "${remove_files[@]}" | sed 's|/.*||' | sort | uniq -c)
fi
[ "$dry_run" -eq 1 ] && exit 0

if [ "${#remove_top[@]}" -gt 0 ]; then
    # Per-file removal so kept nested paths survive inside a removed top-level dir.
    # -f only overrides the "staged differs" safety check; --cached keeps it index-only.
    printf '%s\0' "${remove_files[@]}" |
        git --literal-pathspecs rm -q -f --cached --ignore-unmatch \
            --pathspec-from-file=- --pathspec-file-nul || exit 1

    failed=0
    for f in "${remove_files[@]}"; do
        if [ -f "$f" ] || [ -L "$f" ]; then
            rm -f -- "$f" 2>/dev/null || { failed=$((failed + 1)); echo "WARN: could not delete $f" >&2; }
        fi
    done
    # Drop directories left empty; anything untracked keeps its dir alive.
    for top in "${remove_top[@]}"; do
        [ -d "$top" ] && find "$top" -depth -type d -empty -delete 2>/dev/null
    done
    [ "$failed" -gt 0 ] && echo "WARN: $failed file(s) left on disk; they are already out of the index." >&2
fi

# Squash into the previous deploy commit: drop the merge commit, keep the index.
git reset --soft HEAD~1
