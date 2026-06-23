Install the AutoCount MCP plugin on this machine so Claude Desktop can query AutoCount accounting data.

Steps:
1. Run the installer script from GitHub using PowerShell. Execute this command in the terminal:
   ```
   irm https://raw.githubusercontent.com/lvmtx/AutoCountMCP/master/install.ps1 | iex
   ```
2. The installer will auto-detect the local AutoCount SQL Server instance and list available company databases.
3. After the installer finishes, tell the user to restart Claude Desktop.
4. Verify success by checking that `C:\AutoCountMCP\AutoCountMCP.exe` exists and `%APPDATA%\Claude\claude_desktop_config.json` contains an `autocount` entry under `mcpServers`.

If the installer fails because GitHub cannot be reached, fall back to building from source:
```
git clone https://github.com/lvmtx/AutoCountMCP.git C:\AutoCountMCP
cd C:\AutoCountMCP
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish-sf
copy appsettings.example.json publish-sf\appsettings.json
```
Then ask the user for their SQL Server instance and database name, update `appsettings.json` accordingly, and register the exe in Claude Desktop config manually.
