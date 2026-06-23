# AutoCount MCP Plugin Installer
# Run as Administrator if needed

param(
    [string]$SqlInstance = ".\A2025",
    [string]$Database = "AED_TEST",
    [switch]$UseWindowsAuth = $true,
    [string]$UserId = "",
    [string]$Password = ""
)

$installDir = "C:\AutoCountMCP"
$publishDir = "$installDir\publish"
$claudeConfig = "$env:APPDATA\Claude\claude_desktop_config.json"

Write-Host "=== AutoCount MCP Plugin Installer ===" -ForegroundColor Cyan

# 1. Check dotnet
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: .NET 8 SDK not found. Install from https://dot.net" -ForegroundColor Red
    exit 1
}
Write-Host "dotnet found: $(dotnet --version)" -ForegroundColor Green

# 2. Build & publish
Write-Host "Building..." -ForegroundColor Yellow
Set-Location $installDir
dotnet publish -c Release -r win-x64 --self-contained true -o $publishDir -p:PublishSingleFile=true
if ($LASTEXITCODE -ne 0) { Write-Host "Build failed." -ForegroundColor Red; exit 1 }
Write-Host "Build OK" -ForegroundColor Green

# 3. Write appsettings.json
$settings = @{
    AutoCount = @{
        SqlInstance             = $SqlInstance
        DefaultDatabase         = $Database
        IntegratedSecurity      = $UseWindowsAuth.IsPresent
        UserId                  = $UserId
        Password                = $Password
        CommandTimeoutSeconds   = 30
    }
} | ConvertTo-Json -Depth 3

Set-Content "$publishDir\appsettings.json" $settings -Encoding utf8
Write-Host "Config written to $publishDir\appsettings.json" -ForegroundColor Green

# 4. Register in Claude Desktop
New-Item -ItemType Directory -Force "$env:APPDATA\Claude" | Out-Null
$mcpEntry = @{ command = "$publishDir\AutoCountMCP.exe" }

if (Test-Path $claudeConfig) {
    $existing = Get-Content $claudeConfig | ConvertFrom-Json
    if (-not $existing.mcpServers) { $existing | Add-Member -NotePropertyName mcpServers -NotePropertyValue @{} }
    $existing.mcpServers | Add-Member -NotePropertyName autocount -NotePropertyValue $mcpEntry -Force
    $existing | ConvertTo-Json -Depth 5 | Set-Content $claudeConfig -Encoding utf8
} else {
    @{ mcpServers = @{ autocount = $mcpEntry } } | ConvertTo-Json -Depth 5 | Set-Content $claudeConfig -Encoding utf8
}

Write-Host "Registered in Claude Desktop config" -ForegroundColor Green
Write-Host ""
Write-Host "Done! Restart Claude Desktop to activate AutoCount tools." -ForegroundColor Cyan
Write-Host "Edit $publishDir\appsettings.json to change SQL Server or database." -ForegroundColor Gray
