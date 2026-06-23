# push_source.ps1
# Run after decompile_with_version.ps1 to push new AutoCount source to GitHub
# Each version is committed and tagged — full history preserved
#
# Usage:
#   .\push_source.ps1
#   .\push_source.ps1 -RemoteUrl "https://github.com/lvmtx/AutoCountSource.git"
#   .\push_source.ps1 -ExtractBaseDir "D:\AutoCount_Source"

param(
    [string]$ExtractBaseDir = "C:\",
    [string]$GitRepoDir     = "C:\AutoCountSource",
    [string]$RemoteUrl      = "https://github.com/jjjeremylee/AutoCountSource.git",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# ── 1. Detect latest extracted version ───────────────────────────────────────
Write-Host ""
Write-Host "AutoCount Source → GitHub" -ForegroundColor Cyan
Write-Host "--------------------------" -ForegroundColor Cyan

$folders = Get-ChildItem $ExtractBaseDir -Directory -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match "^AutoCount_Source_v(\d+\.\d+\.\d+\.\d+)$" } |
           Sort-Object { [version]($_.Name -replace "AutoCount_Source_v","") } -Descending

if (-not $folders) {
    Write-Host "ERROR: No AutoCount_Source_v* folder found under $ExtractBaseDir" -ForegroundColor Red
    exit 1
}

$latestFolder = $folders[0]
$version      = $latestFolder.Name -replace "AutoCount_Source_v",""
$sourceDir    = $latestFolder.FullName
$tag          = "v$version"

Write-Host "Found: $($latestFolder.Name)" -ForegroundColor Green
if ($folders.Count -gt 1) {
    Write-Host "Previous versions:" -ForegroundColor Gray
    $folders | Select-Object -Skip 1 | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor Gray
    }
}

# ── 2. Init or update local git repo ─────────────────────────────────────────
if (-not (Test-Path "$GitRepoDir\.git")) {
    Write-Host ""
    Write-Host "Initialising git repo at $GitRepoDir..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force $GitRepoDir | Out-Null
    Set-Location $GitRepoDir
    git init -b main
    git remote add origin $RemoteUrl

    # Try to pull existing history if repo already has commits on GitHub
    try {
        git pull origin main --allow-unrelated-histories 2>$null
        Write-Host "Pulled existing history from GitHub." -ForegroundColor Green
    } catch { }

    # Write .gitignore
    Set-Content "$GitRepoDir\.gitignore" @"
# Binaries
*.dll
*.exe
*.pdb
*.nupkg

# Images (large, rarely useful in diffs)
*.png
*.svg
*.bmp
*.jpg
*.jpeg
*.gif
*.cur
*.ico

# Other binary resources
*.fmx
*.blob
*.preset
*.cache

# Build outputs
bin/
obj/
.vs/
"@
} else {
    Set-Location $GitRepoDir
}

# ── 3. Check if version already tagged ───────────────────────────────────────
$existingTag = git tag -l $tag 2>$null
if ($existingTag) {
    Write-Host ""
    Write-Host "Version $tag already exists in git. Nothing to push." -ForegroundColor Yellow
    Write-Host "To re-push, first delete the tag: git tag -d $tag && git push origin :refs/tags/$tag" -ForegroundColor Gray
    exit 0
}

# ── 4. Sync source files ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "Syncing $version source files..." -ForegroundColor Yellow

# Track only source file types (skip images/binaries)
$trackExtensions = @(".cs",".csproj",".sln",".sql",".resx",".xaml",".xml",".json",".config",".md",".txt",".props",".targets")

# Remove old source content (keep .git and .gitignore)
Get-ChildItem $GitRepoDir -Exclude ".git",".gitignore" |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Copy source files preserving folder structure
$files = Get-ChildItem $sourceDir -Recurse -File |
         Where-Object { $_.Extension -in $trackExtensions }

$total = $files.Count
Write-Host "Copying $total source files..." -ForegroundColor Gray

$i = 0
foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($sourceDir.Length).TrimStart('\')
    $destPath     = Join-Path $GitRepoDir $relativePath
    $destDir      = Split-Path $destPath -Parent

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Force $destDir | Out-Null
    }
    Copy-Item $file.FullName $destPath -Force

    $i++
    if ($i % 5000 -eq 0) {
        Write-Host "  $i / $total files copied..." -ForegroundColor Gray
    }
}
Write-Host "  $total / $total files copied." -ForegroundColor Green

# Write a version marker file
Set-Content "$GitRepoDir\VERSION" $version -Encoding utf8

if ($DryRun) {
    Write-Host ""
    Write-Host "[DryRun] Would commit and push $tag — skipping git operations." -ForegroundColor Yellow
    exit 0
}

# ── 5. Commit, tag, push ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "Committing..." -ForegroundColor Yellow

git add -A
$changed = git status --porcelain | Measure-Object | Select-Object -ExpandProperty Count
if ($changed -eq 0) {
    Write-Host "No file changes detected — nothing to commit." -ForegroundColor Yellow
    exit 0
}

git commit -m "AutoCount $version"
git tag $tag
Write-Host "Tagged: $tag" -ForegroundColor Green

Write-Host "Pushing to GitHub..." -ForegroundColor Yellow
git push origin main
git push origin $tag

Write-Host ""
Write-Host "Done! AutoCount $version pushed to GitHub." -ForegroundColor Green
Write-Host "View at: $($RemoteUrl -replace '\.git$','') /releases/tag/$tag" -ForegroundColor Cyan
