#!/usr/bin/env bash
cd "$(dirname "$0")/.."

targets=(
    tools
    docs
    .agents
    CLAUDE.md
    .playwright-mcp
    pyproject.toml
    README.BE.md
    uv.lock
)

# Gộp vào commit deploy trước đó: lùi 1 commit (giữ nguyên thay đổi), rồi commit lại.
branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != "deploy-fe" ]; then
    echo "Đang ở branch '$branch', không phải deploy-fe -> bỏ qua reset/commit." >&2
    exit 1
fi

for item in "${targets[@]}"; do
    if [ -e "$item" ]; then
        printf 'Delete %s ... ' "$item"
        rm -rf "$item"
        echo "Done"
    fi
done

git reset --soft HEAD~1
