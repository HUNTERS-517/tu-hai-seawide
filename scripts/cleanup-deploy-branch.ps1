$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root

$targets = @(
    "tools",
    "docs",
    ".agents",
    "CLAUDE.md",
    ".playwright-mcp",
    "pyproject.toml",
    "README.BE.md",
    "uv.lock"
)

# Squash into previous deploy commit: soft reset 1 commit (keep changes), then re-commit.
$branch = git rev-parse --abbrev-ref HEAD
if ($branch -ne "deploy-fe") {
    Write-Error "Current branch is '$branch', not deploy-fe -> skip reset/commit."
    exit 1
}

foreach ($item in $targets) {
    if (Test-Path $item) {
        Write-Host "Delete $item ... " -NoNewline
        Remove-Item -Recurse -Force $item
        Write-Host "Done"
    }
}

git reset --soft HEAD~1
