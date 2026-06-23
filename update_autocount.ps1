# update_autocount.ps1
# Full pipeline: decompile new AutoCount version → push source to GitHub → rebuild MCP plugin
#
# Usage:
#   .\update_autocount.ps1 -SourceDir "C:\Program Files\AutoCount\Accounting 2.2"

param(
    [Parameter(Mandatory)]
    [string]$SourceDir,
    [string]$BaseOutputDir  = "C:\",
    [string]$SourceRepoUrl  = "https://github.com/lvmtx/AutoCountSource.git",
    [string]$DecompileScript = ".\decompile_with_version.ps1"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent

# ── Step 1: Decompile ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 1/3 — Decompile AutoCount DLLs" -ForegroundColor Cyan
Write-Host "Source: $SourceDir" -ForegroundColor Gray

if (-not (Test-Path $DecompileScript)) {
    Write-Host "ERROR: Decompile script not found: $DecompileScript" -ForegroundColor Red
    exit 1
}

& $DecompileScript -SourceDir $SourceDir -BaseOutputDir $BaseOutputDir
if ($LASTEXITCODE -ne 0) { Write-Host "Decompile failed." -ForegroundColor Red; exit 1 }

# ── Step 2: Push source to GitHub ────────────────────────────────────────────
Write-Host ""
Write-Host "Step 2/3 — Push source to GitHub" -ForegroundColor Cyan

& "$scriptDir\push_source.ps1" -ExtractBaseDir $BaseOutputDir -RemoteUrl $SourceRepoUrl
if ($LASTEXITCODE -ne 0) { Write-Host "Push failed." -ForegroundColor Red; exit 1 }

# ── Step 3: Rebuild MCP plugin ───────────────────────────────────────────────
Write-Host ""
Write-Host "Step 3/3 — Rebuild AutoCount MCP plugin" -ForegroundColor Cyan

$mcpDir = $scriptDir   # MCP project lives alongside this script
Push-Location $mcpDir
dotnet publish -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o "$mcpDir\publish-sf" 2>&1 | Select-Object -Last 3
Pop-Location

if ($LASTEXITCODE -ne 0) { Write-Host "MCP rebuild failed." -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "All done!" -ForegroundColor Green
Write-Host "  - Source pushed to GitHub with version tag" -ForegroundColor Gray
Write-Host "  - MCP plugin rebuilt at $mcpDir\publish-sf\AutoCountMCP.exe" -ForegroundColor Gray
Write-Host "  - Restart Claude Desktop to use the updated plugin" -ForegroundColor Gray
