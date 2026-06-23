# AutoCount MCP Plugin — One-liner installer
# Usage: irm https://raw.githubusercontent.com/lvmtx/AutoCountMCP/master/install.ps1 | iex

param(
    [string]$SqlInstance = "",
    [string]$Database    = "",
    [string]$UserId      = "",
    [string]$Password    = ""
)

$repo      = "lvmtx/AutoCountMCP"
$installDir = "C:\AutoCountMCP"
$exePath   = "$installDir\AutoCountMCP.exe"
$cfgPath   = "$installDir\appsettings.json"
$claudeCfg = "$env:APPDATA\Claude\claude_desktop_config.json"

Write-Host ""
Write-Host "====================================" -ForegroundColor Cyan
Write-Host "  AutoCount MCP Plugin Installer    " -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Download latest release ───────────────────────────────────────────────
Write-Host "Fetching latest release from GitHub..." -ForegroundColor Yellow
try {
    $release  = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
    $asset    = $release.assets | Where-Object { $_.name -like "*win-x64*.zip" } | Select-Object -First 1
    $version  = $release.tag_name
    Write-Host "Latest version: $version" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Cannot reach GitHub. Check internet connection." -ForegroundColor Red
    exit 1
}

if (-not $asset) {
    Write-Host "ERROR: No win-x64 zip found in release $version." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force $installDir | Out-Null
$zipPath = "$env:TEMP\AutoCountMCP.zip"

Write-Host "Downloading $($asset.name) ($([math]::Round($asset.size/1MB,1)) MB)..." -ForegroundColor Yellow
Invoke-WebRequest $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
Write-Host "Download complete." -ForegroundColor Green

# ── 2. Extract ───────────────────────────────────────────────────────────────
Write-Host "Installing to $installDir..." -ForegroundColor Yellow
Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
Remove-Item $zipPath -Force

if (-not (Test-Path $exePath)) {
    Write-Host "ERROR: AutoCountMCP.exe not found after extraction." -ForegroundColor Red
    exit 1
}
Write-Host "Installed." -ForegroundColor Green

# ── 3. Configure SQL connection ──────────────────────────────────────────────
Write-Host ""
Write-Host "SQL Server Configuration" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan

# Auto-detect local AutoCount SQL instance
$detected = Get-Service -Name "MSSQL*" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "MSSQL\$" } |
            ForEach-Object { ".\$($_.Name -replace 'MSSQL\$','')" }

if (-not $SqlInstance) {
    if ($detected) {
        Write-Host "Detected SQL instance(s): $($detected -join ', ')" -ForegroundColor Gray
        $SqlInstance = Read-Host "SQL Server instance [$($detected[0])]"
        if (-not $SqlInstance) { $SqlInstance = $detected[0] }
    } else {
        $SqlInstance = Read-Host "SQL Server instance (e.g. .\A2025 or 192.168.1.10\A2025)"
    }
}

if (-not $Database) {
    # Try to list available AED_ databases
    try {
        $connStr = "Server=$SqlInstance;Database=master;Integrated Security=true;TrustServerCertificate=true;Connection Timeout=5;"
        $conn = New-Object System.Data.SqlClient.SqlConnection $connStr
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT name FROM sys.databases WHERE name LIKE 'AED[_]%' ORDER BY name"
        $reader = $cmd.ExecuteReader()
        $dbs = @()
        while ($reader.Read()) { $dbs += $reader.GetString(0) }
        $conn.Close()
        if ($dbs.Count -gt 0) {
            Write-Host "Found AutoCount databases:" -ForegroundColor Gray
            $dbs | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
            $Database = Read-Host "Default database [$($dbs[0])]"
            if (-not $Database) { $Database = $dbs[0] }
        }
    } catch { }

    if (-not $Database) {
        $Database = Read-Host "Default database (e.g. AED_TEST)"
    }
}

$useWinAuth = $true
if (-not $UserId) {
    $authChoice = Read-Host "Use Windows Authentication? [Y/n]"
    if ($authChoice -match "^[Nn]") {
        $useWinAuth = $false
        $UserId   = Read-Host "SQL Username"
        $Password = Read-Host "SQL Password"
    }
}

# Write appsettings.json
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
Write-Host "Config saved to $cfgPath" -ForegroundColor Green

# ── 4. Register in Claude Desktop ────────────────────────────────────────────
Write-Host ""
Write-Host "Registering with Claude Desktop..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force "$env:APPDATA\Claude" | Out-Null

$mcpEntry = [ordered]@{ command = $exePath }

if (Test-Path $claudeCfg) {
    $existing = Get-Content $claudeCfg -Raw | ConvertFrom-Json
    if (-not $existing.PSObject.Properties['mcpServers']) {
        $existing | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([PSCustomObject]@{})
    }
    $existing.mcpServers | Add-Member -NotePropertyName autocount -NotePropertyValue $mcpEntry -Force
    $existing | ConvertTo-Json -Depth 5 | Set-Content $claudeCfg -Encoding utf8
} else {
    [PSCustomObject]@{
        mcpServers = [PSCustomObject]@{ autocount = $mcpEntry }
    } | ConvertTo-Json -Depth 5 | Set-Content $claudeCfg -Encoding utf8
}

Write-Host "Registered." -ForegroundColor Green

# ── Done ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host "  Installation complete! ($version)  " -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: Restart Claude Desktop" -ForegroundColor Cyan
Write-Host "Then ask Claude: 'List my AutoCount companies'" -ForegroundColor Cyan
Write-Host ""
Write-Host "To change settings later, edit:" -ForegroundColor Gray
Write-Host "  $cfgPath" -ForegroundColor Gray
