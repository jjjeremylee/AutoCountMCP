# AutoCount MCP Plugin — Installer
# Usage: irm https://raw.githubusercontent.com/jjjeremylee/AutoCountMCP/master/install.ps1 | iex

param(
    [string]$SqlInstance = "",
    [string]$Database    = "",
    [string]$UserId      = "",
    [string]$Password    = ""
)

$repo       = "jjjeremylee/AutoCountMCP"
$installDir = "C:\AutoCountMCP"
$exePath    = "$installDir\AutoCountMCP.exe"
$cfgPath    = "$installDir\appsettings.json"
$claudeCfg  = "$env:APPDATA\Claude\claude_desktop_config.json"

function Pause-Exit($code = 0) {
    Write-Host ""
    Write-Host "Press Enter to close..." -ForegroundColor Gray
    Read-Host | Out-Null
    exit $code
}

Clear-Host
Write-Host ""
Write-Host "====================================" -ForegroundColor Cyan
Write-Host "  AutoCount MCP Plugin Installer    " -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

# ── 0. Check .NET 8 runtime ──────────────────────────────────────────────────
Write-Host "Checking .NET 8 runtime..." -ForegroundColor Yellow
$dotnetOk = dotnet --list-runtimes 2>$null | Select-String "Microsoft.NETCore.App 8\."
if (-not $dotnetOk) {
    Write-Host ".NET 8 runtime not found. Downloading installer..." -ForegroundColor Yellow
    $dotnetInstaller = "$env:TEMP\dotnet-install.ps1"
    Invoke-WebRequest "https://dot.net/v1/dotnet-install.ps1" -OutFile $dotnetInstaller -UseBasicParsing
    & $dotnetInstaller -Runtime dotnet -Channel 8.0 -InstallDir "$env:ProgramFiles\dotnet"
    $env:PATH = "$env:ProgramFiles\dotnet;" + $env:PATH
    Write-Host ".NET 8 installed." -ForegroundColor Green
} else {
    Write-Host ".NET 8 found." -ForegroundColor Green
}

# ── 1. Download latest release ────────────────────────────────────────────────
Write-Host "Checking latest release on GitHub..." -ForegroundColor Yellow

try {
    $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -ErrorAction Stop
    $asset   = $release.assets | Where-Object { $_.name -like "*win-x64*.zip" } | Select-Object -First 1
    $version = $release.tag_name
} catch {
    Write-Host "ERROR: Could not reach GitHub releases." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Pause-Exit 1
}

if (-not $asset) {
    Write-Host "ERROR: No release zip found for $version." -ForegroundColor Red
    Write-Host "Please ask the administrator to upload a release at:" -ForegroundColor Yellow
    Write-Host "  https://github.com/$repo/releases/new" -ForegroundColor Yellow
    Pause-Exit 1
}

Write-Host "Found: $version ($($asset.name), $([math]::Round($asset.size/1MB,1)) MB)" -ForegroundColor Green

New-Item -ItemType Directory -Force $installDir | Out-Null
$zipPath = "$env:TEMP\AutoCountMCP.zip"

Write-Host "Downloading..." -ForegroundColor Yellow
try {
    Invoke-WebRequest $asset.browser_download_url -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Host "ERROR: Download failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Pause-Exit 1
}

# ── 2. Extract ────────────────────────────────────────────────────────────────
Write-Host "Installing to $installDir ..." -ForegroundColor Yellow
Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

if (-not (Test-Path $exePath)) {
    Write-Host "ERROR: AutoCountMCP.exe not found after extraction." -ForegroundColor Red
    Pause-Exit 1
}
Write-Host "Extracted OK." -ForegroundColor Green

# ── 3. SQL Server configuration ───────────────────────────────────────────────
Write-Host ""
Write-Host "SQL Server Configuration" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan

# Auto-detect SQL Server instances
$detected = @(Get-Service -Name "MSSQL*" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "^MSSQL\$.+" } |
    ForEach-Object { ".\$($_.Name -replace '^MSSQL\$','')" })

if (-not $SqlInstance) {
    if ($detected.Count -gt 0) {
        Write-Host "Detected SQL instance(s): $($detected -join ', ')" -ForegroundColor Gray
        $input = Read-Host "SQL Server instance [press Enter for $($detected[0])]"
        $SqlInstance = if ($input) { $input } else { $detected[0] }
    } else {
        $SqlInstance = Read-Host "SQL Server instance (e.g. .\A2025 or 192.168.1.10\A2025)"
    }
}
Write-Host "Using: $SqlInstance" -ForegroundColor Gray

# List AED_ databases
if (-not $Database) {
    Write-Host "Connecting to SQL Server to find AutoCount databases..." -ForegroundColor Gray
    $dbs = @()
    try {
        Add-Type -AssemblyName "System.Data" -ErrorAction SilentlyContinue
        $connStr = "Server=$SqlInstance;Database=master;Integrated Security=true;TrustServerCertificate=true;Connection Timeout=5;"
        $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT name FROM sys.databases WHERE name LIKE 'AED[_]%' ORDER BY name"
        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) { $dbs += $reader.GetString(0) }
        $conn.Close()
    } catch {
        Write-Host "  (Could not auto-detect databases — will ask manually)" -ForegroundColor Gray
    }

    if ($dbs.Count -gt 0) {
        Write-Host "Found AutoCount databases:" -ForegroundColor Gray
        for ($i = 0; $i -lt $dbs.Count; $i++) {
            Write-Host "  [$($i+1)] $($dbs[$i])" -ForegroundColor Gray
        }
        $pick = Read-Host "Choose number or type database name [1]"
        if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $dbs.Count) {
            $Database = $dbs[[int]$pick - 1]
        } elseif ($pick) {
            $Database = $pick
        } else {
            $Database = $dbs[0]
        }
    } else {
        $Database = Read-Host "Default database name (e.g. AED_TEST)"
    }
}
Write-Host "Using: $Database" -ForegroundColor Gray

# Auth
$useWinAuth = $true
if (-not $UserId) {
    $authChoice = Read-Host "Use Windows Authentication? [Y/n]"
    if ($authChoice -match "^[Nn]") {
        $useWinAuth = $false
        $UserId   = Read-Host "SQL Username"
        $Password = Read-Host "SQL Password"
    }
}

# Write config
$settings = [ordered]@{
    AutoCount = [ordered]@{
        SqlInstance           = $SqlInstance
        DefaultDatabase       = $Database
        IntegratedSecurity    = $useWinAuth
        UserId                = $UserId
        Password              = $Password
        CommandTimeoutSeconds = 30
    }
} | ConvertTo-Json -Depth 3

Set-Content $cfgPath $settings -Encoding utf8
Write-Host "Config saved." -ForegroundColor Green

# ── 4. Register in Claude Desktop ─────────────────────────────────────────────
Write-Host ""
Write-Host "Registering with Claude Desktop..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force (Split-Path $claudeCfg) | Out-Null

$mcpEntry = [ordered]@{ command = $exePath }

if (Test-Path $claudeCfg) {
    try {
        $existing = Get-Content $claudeCfg -Raw | ConvertFrom-Json
        if (-not $existing.PSObject.Properties['mcpServers']) {
            $existing | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([PSCustomObject]@{})
        }
        $existing.mcpServers | Add-Member -NotePropertyName autocount -NotePropertyValue $mcpEntry -Force
        $existing | ConvertTo-Json -Depth 5 | Set-Content $claudeCfg -Encoding utf8
    } catch {
        # Overwrite if corrupt
        [PSCustomObject]@{ mcpServers = [PSCustomObject]@{ autocount = $mcpEntry } } |
            ConvertTo-Json -Depth 5 | Set-Content $claudeCfg -Encoding utf8
    }
} else {
    [PSCustomObject]@{ mcpServers = [PSCustomObject]@{ autocount = $mcpEntry } } |
        ConvertTo-Json -Depth 5 | Set-Content $claudeCfg -Encoding utf8
}

Write-Host "Registered in Claude Desktop." -ForegroundColor Green

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  AutoCount MCP installed! ($version)" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT: Restart Claude Desktop" -ForegroundColor Cyan
Write-Host "THEN: Ask Claude — 'List my AutoCount companies'" -ForegroundColor Cyan
Write-Host ""
Write-Host "Config: $cfgPath" -ForegroundColor Gray

Pause-Exit 0
