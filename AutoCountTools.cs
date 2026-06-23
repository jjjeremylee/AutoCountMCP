using ModelContextProtocol.Server;
using System.ComponentModel;

namespace AutoCountMCP;

[McpServerToolType]
public class AutoCountTools(AutoCountDb db)
{
    // ── Company / Version ────────────────────────────────────────────────────

    [McpServerTool, Description(
        "List all AutoCount company databases on this server. " +
        "Returns database names (AED_xxx format). Use the name as 'company' in other tools.")]
    public async Task<string> ListCompanies()
    {
        var table = await db.WithDatabase("master").QueryAsync(
            "SELECT name AS Database, create_date AS Created FROM sys.databases " +
            "WHERE name LIKE 'AED[_]%' ORDER BY name",
            null);
        return AutoCountDb.DataTableToJson(table);
    }

    [McpServerTool, Description(
        "Get AutoCount version installed on this machine by scanning C:\\AutoCount_Source_v* folders.")]
    public Task<string> GetAutoCountVersion()
    {
        var dirs = Directory.GetDirectories("C:\\", "AutoCount_Source_v*")
            .OrderByDescending(d => d)
            .ToList();
        if (dirs.Count == 0)
            return Task.FromResult("No AutoCount source folder found at C:\\AutoCount_Source_v*");
        var latest = Path.GetFileName(dirs[0]);
        var version = latest.Replace("AutoCount_Source_v", "");
        return Task.FromResult($"Latest: {version}\nAll versions: {string.Join(", ", dirs.Select(Path.GetFileName))}");
    }

    // ── AR Invoices (Sales) ──────────────────────────────────────────────────

    [McpServerTool, Description(
        "Search AR (sales) invoices in AutoCount. " +
        "Parameters: company (database name e.g. AED_TEST), " +
        "fromDate (yyyy-MM-dd), toDate (yyyy-MM-dd), " +
        "debtorCode (customer account code, optional), " +
        "docNo (invoice number filter, optional), " +
        "top (max rows, default 50).")]
    public async Task<string> SearchArInvoices(
        string company,
        string fromDate,
        string toDate,
        string? debtorCode = null,
        string? docNo = null,
        int top = 50)
    {
        var dbComp = db.WithDatabase(company);
        var where = "DocDate BETWEEN @From AND @To AND Cancelled='F'";
        var p = new Dictionary<string, object>
        {
            ["@From"] = DateTime.Parse(fromDate),
            ["@To"] = DateTime.Parse(toDate),
        };
        if (!string.IsNullOrEmpty(debtorCode)) { where += " AND DebtorCode=@Debtor"; p["@Debtor"] = debtorCode; }
        if (!string.IsNullOrEmpty(docNo)) { where += " AND DocNo LIKE @DocNo"; p["@DocNo"] = $"%{docNo}%"; }

        var sql = $@"SELECT TOP {top}
            DocNo, DocDate, DebtorCode, DebtorName=IsNull(CompanyName,''),
            CurrencyCode, DocAmt, LocalDocAmt, PaymentAmt, OutstandingAmt,
            Description, DocStatus, RefDocNo, SalesAgent, ProjectNo
        FROM vARInvoice
        WHERE {where}
        ORDER BY DocDate DESC, DocNo DESC";

        var table = await dbComp.QueryAsync(sql, p);
        return $"Found {table.Rows.Count} invoices:\n{AutoCountDb.DataTableToJson(table)}";
    }

    [McpServerTool, Description(
        "Get full AR invoice detail with line items. " +
        "Parameters: company (database name), docNo (exact invoice number).")]
    public async Task<string> GetArInvoiceDetail(string company, string docNo)
    {
        var dbComp = db.WithDatabase(company);
        var headerSql = @"SELECT * FROM vARInvoice WHERE DocNo=@DocNo AND Cancelled='F'";
        var detailSql = @"SELECT Seq, ItemCode, Description, Qty, UOM, UnitPrice, Disc, Tax, Amount, LocalAmount
            FROM vARInvoiceDetail WHERE DocNo=@DocNo ORDER BY Seq";
        var p = new Dictionary<string, object> { ["@DocNo"] = docNo };
        var header = await dbComp.QueryAsync(headerSql, p);
        var detail = await dbComp.QueryAsync(detailSql, p);
        if (header.Rows.Count == 0) return $"Invoice {docNo} not found.";
        return $"Header:\n{AutoCountDb.DataTableToJson(header)}\n\nLine Items:\n{AutoCountDb.DataTableToJson(detail)}";
    }

    // ── AP Invoices (Purchase) ───────────────────────────────────────────────

    [McpServerTool, Description(
        "Search AP (purchase) invoices in AutoCount. " +
        "Parameters: company, fromDate (yyyy-MM-dd), toDate (yyyy-MM-dd), " +
        "creditorCode (supplier code, optional), docNo (optional), top (default 50).")]
    public async Task<string> SearchApInvoices(
        string company,
        string fromDate,
        string toDate,
        string? creditorCode = null,
        string? docNo = null,
        int top = 50)
    {
        var dbComp = db.WithDatabase(company);
        var where = "DocDate BETWEEN @From AND @To AND Cancelled='F'";
        var p = new Dictionary<string, object>
        {
            ["@From"] = DateTime.Parse(fromDate),
            ["@To"] = DateTime.Parse(toDate),
        };
        if (!string.IsNullOrEmpty(creditorCode)) { where += " AND CreditorCode=@Cred"; p["@Cred"] = creditorCode; }
        if (!string.IsNullOrEmpty(docNo)) { where += " AND DocNo LIKE @DocNo"; p["@DocNo"] = $"%{docNo}%"; }

        var sql = $@"SELECT TOP {top}
            DocNo, DocDate, CreditorCode, CompanyName,
            CurrencyCode, DocAmt, LocalDocAmt, PaymentAmt, OutstandingAmt,
            Description, DocStatus, RefDocNo, PurchaseAgent, ProjectNo
        FROM vAPInvoice
        WHERE {where}
        ORDER BY DocDate DESC, DocNo DESC";

        var table = await dbComp.QueryAsync(sql, p);
        return $"Found {table.Rows.Count} AP invoices:\n{AutoCountDb.DataTableToJson(table)}";
    }

    // ── Debtors (Customers) ──────────────────────────────────────────────────

    [McpServerTool, Description(
        "Search AutoCount debtors (customers/accounts receivable). " +
        "Parameters: company, search (name or code partial match, optional), " +
        "top (default 50).")]
    public async Task<string> SearchDebtors(string company, string? search = null, int top = 50)
    {
        var dbComp = db.WithDatabase(company);
        var where = "1=1";
        var p = new Dictionary<string, object>();
        if (!string.IsNullOrEmpty(search))
        {
            where = "(AccNo LIKE @S OR CompanyName LIKE @S OR ContactPerson LIKE @S OR Phone1 LIKE @S)";
            p["@S"] = $"%{search}%";
        }
        var sql = $@"SELECT TOP {top}
            AccNo, CompanyName, ContactPerson, Phone1, Email, Area, Agent,
            CurrencyCode, CreditLimit, OutstandingBalance, IsNull(TaxRegNo,'') AS TaxRegNo
        FROM Debtor
        WHERE {where} AND IsActive='T'
        ORDER BY AccNo";

        var table = await dbComp.QueryAsync(sql, p);
        return $"Found {table.Rows.Count} debtors:\n{AutoCountDb.DataTableToJson(table)}";
    }

    [McpServerTool, Description(
        "Get outstanding AR (accounts receivable) for a debtor or all debtors. " +
        "Parameters: company, debtorCode (optional — omit for all), asOfDate (yyyy-MM-dd, optional).")]
    public async Task<string> GetOutstandingAr(string company, string? debtorCode = null, string? asOfDate = null)
    {
        var dbComp = db.WithDatabase(company);
        var where = "OutstandingAmt > 0 AND Cancelled='F'";
        var p = new Dictionary<string, object>();
        if (!string.IsNullOrEmpty(debtorCode)) { where += " AND DebtorCode=@D"; p["@D"] = debtorCode; }
        if (!string.IsNullOrEmpty(asOfDate)) { where += " AND DocDate <= @D2"; p["@D2"] = DateTime.Parse(asOfDate); }

        var sql = $@"SELECT
            DebtorCode, IsNull(CompanyName,'') AS CompanyName,
            DocNo, DocDate, DocAmt, OutstandingAmt, CurrencyCode,
            DATEDIFF(day, DocDate, GETDATE()) AS AgeDays
        FROM vARInvoice
        WHERE {where}
        ORDER BY DebtorCode, DocDate";

        var table = await dbComp.QueryAsync(sql, p);
        return $"Outstanding AR ({table.Rows.Count} invoices):\n{AutoCountDb.DataTableToJson(table)}";
    }

    // ── Creditors (Suppliers) ─────────────────────────────────────────────────

    [McpServerTool, Description(
        "Search AutoCount creditors (suppliers/accounts payable). " +
        "Parameters: company, search (name or code, optional), top (default 50).")]
    public async Task<string> SearchCreditors(string company, string? search = null, int top = 50)
    {
        var dbComp = db.WithDatabase(company);
        var where = "1=1";
        var p = new Dictionary<string, object>();
        if (!string.IsNullOrEmpty(search))
        {
            where = "(AccNo LIKE @S OR CompanyName LIKE @S OR Phone1 LIKE @S)";
            p["@S"] = $"%{search}%";
        }
        var sql = $@"SELECT TOP {top}
            AccNo, CompanyName, ContactPerson, Phone1, Email, Area, Agent,
            CurrencyCode, CreditLimit, OutstandingBalance
        FROM Creditor
        WHERE {where} AND IsActive='T'
        ORDER BY AccNo";

        var table = await dbComp.QueryAsync(sql, p);
        return $"Found {table.Rows.Count} creditors:\n{AutoCountDb.DataTableToJson(table)}";
    }

    // ── Stock / Inventory ─────────────────────────────────────────────────────

    [McpServerTool, Description(
        "Search AutoCount stock items (inventory). " +
        "Parameters: company, search (item code or description, optional), " +
        "stockGroup (optional), top (default 50).")]
    public async Task<string> SearchStockItems(string company, string? search = null, string? stockGroup = null, int top = 50)
    {
        var dbComp = db.WithDatabase(company);
        var where = "IsActive='T'";
        var p = new Dictionary<string, object>();
        if (!string.IsNullOrEmpty(search))
        {
            where += " AND (ItemCode LIKE @S OR Description LIKE @S OR ShortName LIKE @S)";
            p["@S"] = $"%{search}%";
        }
        if (!string.IsNullOrEmpty(stockGroup)) { where += " AND StockGroup=@G"; p["@G"] = stockGroup; }

        var sql = $@"SELECT TOP {top}
            ItemCode, Description, ShortName, StockGroup, BaseUOM,
            CostPrice, SellingPrice1 AS SellingPrice,
            IsNull(BalQty,0) AS StockQty,
            IsNull(BalAmt,0) AS StockValue
        FROM Item
        LEFT JOIN (
            SELECT ItemCode AS IC, SUM(Qty) AS BalQty, SUM(Amount) AS BalAmt
            FROM ItemBatch GROUP BY ItemCode
        ) B ON B.IC = Item.ItemCode
        WHERE {where}
        ORDER BY ItemCode";

        var table = await dbComp.QueryAsync(sql, p);
        return $"Found {table.Rows.Count} items:\n{AutoCountDb.DataTableToJson(table)}";
    }

    [McpServerTool, Description(
        "Get stock balance (quantity on hand) for specific item or all items. " +
        "Parameters: company, itemCode (optional), location (optional).")]
    public async Task<string> GetStockBalance(string company, string? itemCode = null, string? location = null)
    {
        var dbComp = db.WithDatabase(company);
        var where = "1=1";
        var p = new Dictionary<string, object>();
        if (!string.IsNullOrEmpty(itemCode)) { where += " AND I.ItemCode=@Item"; p["@Item"] = itemCode; }
        if (!string.IsNullOrEmpty(location)) { where += " AND IB.Location=@Loc"; p["@Loc"] = location; }

        var sql = $@"SELECT
            I.ItemCode, I.Description, I.BaseUOM,
            IsNull(SUM(IB.Qty),0) AS BalQty,
            IsNull(SUM(IB.Amount),0) AS BalAmt,
            IB.Location
        FROM Item I
        LEFT JOIN ItemBatch IB ON IB.ItemCode = I.ItemCode
        WHERE {where}
        GROUP BY I.ItemCode, I.Description, I.BaseUOM, IB.Location
        ORDER BY I.ItemCode";

        var table = await dbComp.QueryAsync(sql, p);
        return $"Stock balance ({table.Rows.Count} rows):\n{AutoCountDb.DataTableToJson(table)}";
    }

    // ── General Ledger ────────────────────────────────────────────────────────

    [McpServerTool, Description(
        "Get GL account balance for a date range. " +
        "Parameters: company, fromDate (yyyy-MM-dd), toDate (yyyy-MM-dd), " +
        "accNo (GL account number, optional), accType (optional: A=Asset, L=Liability, E=Equity, I=Income, X=Expense).")]
    public async Task<string> GetGlBalance(
        string company,
        string fromDate,
        string toDate,
        string? accNo = null,
        string? accType = null)
    {
        var dbComp = db.WithDatabase(company);
        var where = "JE.DocDate BETWEEN @From AND @To";
        var p = new Dictionary<string, object>
        {
            ["@From"] = DateTime.Parse(fromDate),
            ["@To"] = DateTime.Parse(toDate),
        };
        if (!string.IsNullOrEmpty(accNo)) { where += " AND JE.AccNo=@Acc"; p["@Acc"] = accNo; }
        if (!string.IsNullOrEmpty(accType)) { where += " AND AC.AccType=@Type"; p["@Type"] = accType; }

        var sql = $@"SELECT
            JE.AccNo, AC.AccName, AC.AccType,
            SUM(JE.DR) AS TotalDR,
            SUM(JE.CR) AS TotalCR,
            SUM(JE.DR) - SUM(JE.CR) AS NetBalance
        FROM JournalEntryDetail JE
        JOIN Account AC ON AC.AccNo = JE.AccNo
        WHERE {where}
        GROUP BY JE.AccNo, AC.AccName, AC.AccType
        ORDER BY JE.AccNo";

        var table = await dbComp.QueryAsync(sql, p);
        return $"GL Balance ({table.Rows.Count} accounts):\n{AutoCountDb.DataTableToJson(table)}";
    }

    // ── Sales Orders ──────────────────────────────────────────────────────────

    [McpServerTool, Description(
        "Search AutoCount sales orders. " +
        "Parameters: company, fromDate (yyyy-MM-dd), toDate (yyyy-MM-dd), " +
        "debtorCode (optional), status (optional: A=Approved, F=Fully transferred), top (default 50).")]
    public async Task<string> SearchSalesOrders(
        string company,
        string fromDate,
        string toDate,
        string? debtorCode = null,
        string? status = null,
        int top = 50)
    {
        var dbComp = db.WithDatabase(company);
        var where = "DocDate BETWEEN @From AND @To AND Cancelled='F'";
        var p = new Dictionary<string, object>
        {
            ["@From"] = DateTime.Parse(fromDate),
            ["@To"] = DateTime.Parse(toDate),
        };
        if (!string.IsNullOrEmpty(debtorCode)) { where += " AND DebtorCode=@D"; p["@D"] = debtorCode; }
        if (!string.IsNullOrEmpty(status)) { where += " AND DocStatus=@S"; p["@S"] = status; }

        var sql = $@"SELECT TOP {top}
            DocNo, DocDate, DebtorCode, IsNull(CompanyName,'') AS CompanyName,
            DocAmt, OutstandingAmt, DocStatus, Description, SalesAgent
        FROM vSalesOrder
        WHERE {where}
        ORDER BY DocDate DESC, DocNo DESC";

        var table = await dbComp.QueryAsync(sql, p);
        return $"Found {table.Rows.Count} sales orders:\n{AutoCountDb.DataTableToJson(table)}";
    }
}
