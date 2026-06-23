using Microsoft.Data.SqlClient;
using System.Data;

namespace AutoCountMCP;

public class AutoCountDb
{
    private readonly string _connectionString;
    private readonly int _timeoutSeconds;

    public AutoCountDb(string sqlInstance, string database, bool integratedSecurity, string userId, string password, int timeoutSeconds)
    {
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = sqlInstance,
            InitialCatalog = database,
            IntegratedSecurity = integratedSecurity,
            TrustServerCertificate = true,
            CommandTimeout = timeoutSeconds
        };
        if (!integratedSecurity)
        {
            builder.UserID = userId;
            builder.Password = password;
        }
        _connectionString = builder.ConnectionString;
        _timeoutSeconds = timeoutSeconds;
    }

    public AutoCountDb WithDatabase(string database)
    {
        var builder = new SqlConnectionStringBuilder(_connectionString)
        {
            InitialCatalog = database
        };
        return new AutoCountDb(builder.ConnectionString, _timeoutSeconds);
    }

    private AutoCountDb(string connectionString, int timeoutSeconds)
    {
        _connectionString = connectionString;
        _timeoutSeconds = timeoutSeconds;
    }

    public async Task<DataTable> QueryAsync(string sql, Dictionary<string, object>? parameters = null)
    {
        await using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync();
        await using var cmd = new SqlCommand(sql, conn) { CommandTimeout = _timeoutSeconds };
        if (parameters != null)
            foreach (var kv in parameters)
                cmd.Parameters.AddWithValue(kv.Key, kv.Value ?? DBNull.Value);
        var adapter = new SqlDataAdapter(cmd);
        var table = new DataTable();
        adapter.Fill(table);
        return table;
    }

    public async Task<List<string>> GetDatabasesAsync(string sqlInstance)
    {
        var masterConn = _connectionString.Replace(
            new SqlConnectionStringBuilder(_connectionString).InitialCatalog,
            "master");
        await using var conn = new SqlConnection(masterConn);
        await conn.OpenAsync();
        await using var cmd = new SqlCommand(
            "SELECT name FROM sys.databases WHERE name LIKE 'AED_%' ORDER BY name", conn);
        var results = new List<string>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
            results.Add(reader.GetString(0));
        return results;
    }

    public static string DataTableToJson(DataTable table)
    {
        var rows = new List<Dictionary<string, object?>>();
        foreach (DataRow row in table.Rows)
        {
            var dict = new Dictionary<string, object?>();
            foreach (DataColumn col in table.Columns)
                dict[col.ColumnName] = row[col] == DBNull.Value ? null : row[col];
            rows.Add(dict);
        }
        return System.Text.Json.JsonSerializer.Serialize(rows, new System.Text.Json.JsonSerializerOptions
        {
            WriteIndented = true
        });
    }
}
