# AutoCount MCP Plugin for Claude

Connect Claude (Desktop / Claude Code) directly to your **AutoCount accounting database**. Ask Claude questions about invoices, debtors, stock, GL balances, and more in plain English.

## What Claude Can Do

| Tool | Description |
|---|---|
| `ListCompanies` | List all AutoCount company databases |
| `SearchArInvoices` | Search AR/sales invoices by date, customer, doc no |
| `GetArInvoiceDetail` | Get full invoice with line items |
| `SearchApInvoices` | Search AP/purchase invoices |
| `GetOutstandingAr` | AR aging / outstanding amounts |
| `SearchDebtors` | Find customers by name or code |
| `SearchCreditors` | Find suppliers |
| `SearchStockItems` | Search inventory items |
| `GetStockBalance` | Stock quantity on hand |
| `GetGlBalance` | GL account balances for a date range |
| `SearchSalesOrders` | Search sales orders |

## Requirements

- Windows with AutoCount Accounting installed
- SQL Server instance: `.\A2025` (default AutoCount instance)
- [.NET 8 SDK](https://dotnet.microsoft.com/download) (for building from source)
- [Claude Desktop](https://claude.ai/download) or Claude Code

---

## Quick Install (Other Devices)

### Option A — Download Pre-built Release (Easiest)

1. Go to **[Releases](../../releases)** → download `AutoCountMCP-win-x64.zip`
2. Extract to `C:\AutoCountMCP\`
3. Copy `appsettings.example.json` → `appsettings.json` and edit:

```json
{
  "AutoCount": {
    "SqlInstance": ".\\A2025",
    "DefaultDatabase": "AED_TEST",
    "IntegratedSecurity": true
  }
}
```

4. Add to Claude Desktop config (`%APPDATA%\Claude\claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "autocount": {
      "command": "C:\\AutoCountMCP\\AutoCountMCP.exe"
    }
  }
}
```

5. Restart Claude Desktop.

---

### Option B — Build from Source

```powershell
git clone https://github.com/YOUR_USERNAME/autocount-mcp
cd autocount-mcp

# Run the installer (sets up build + config + Claude Desktop registration)
.\install.ps1 -SqlInstance ".\A2025" -Database "AED_TEST"
```

Or manually:

```powershell
copy appsettings.example.json appsettings.json
# Edit appsettings.json with your SQL Server details

dotnet publish -c Release -r win-x64 --self-contained true -o publish -p:PublishSingleFile=true
```

---

## Configuration

Edit `appsettings.json` next to the `.exe`:

| Setting | Default | Description |
|---|---|---|
| `SqlInstance` | `.\\A2025` | SQL Server instance name |
| `DefaultDatabase` | `AED_TEST` | Default company database |
| `IntegratedSecurity` | `true` | Use Windows auth (recommended) |
| `UserId` | *(empty)* | SQL login (if not using Windows auth) |
| `Password` | *(empty)* | SQL password |

### Network SQL Server (shared server across devices)

Change `SqlInstance` to the server's hostname or IP:

```json
"SqlInstance": "192.168.1.10\\A2025"
```

All devices then connect to the same AutoCount SQL Server — no local SQL Server needed.

---

## Switching Companies

In Claude, say: *"List companies"* — then use the database name in your queries:

> *"Search AR invoices in AED_BUBBLE from 2024-01-01 to 2024-12-31"*

Or change `DefaultDatabase` in `appsettings.json` and restart Claude Desktop.

---

## How It Works

```
Claude Desktop / Claude Code
        ↓  MCP protocol (stdio)
AutoCountMCP.exe
        ↓  SQL queries
AutoCount SQL Server (.\A2025)
        ↓
AED_xxx databases (vARInvoice, vAPInvoice, Item, Debtor, etc.)
```

The plugin does **not** depend on the AutoCount DLL version. It connects directly to the SQL Server, so it works even when AutoCount updates to a new version.

---

## AutoCount Version Updates

When AutoCount updates (new `AutoCount_Source_v*` folder), **nothing changes here** — the SQL Server instance and database schema remain compatible. Just keep using the same `appsettings.json`.

---

## Troubleshooting

**Claude doesn't show AutoCount tools**
- Check `%APPDATA%\Claude\claude_desktop_config.json` has the `autocount` entry
- Restart Claude Desktop (not just reload)

**SQL connection error**
- Verify SQL Server is running: `Get-Service MSSQL$A2025`
- Test connection: open SSMS and connect to `.\A2025`
- Check `appsettings.json` has the correct instance name

**"View not found" errors**
- Some views (`vARInvoice`, `vSalesOrder`) only exist if that AutoCount module is activated
- Use `ListCompanies` first to verify the database name
