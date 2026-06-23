using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using ModelContextProtocol.Server;
using AutoCountMCP;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddSingleton<AutoCountDb>(sp =>
{
    var cfg = builder.Configuration;
    return new AutoCountDb(
        cfg["AutoCount:SqlInstance"] ?? ".\\A2025",
        cfg["AutoCount:DefaultDatabase"] ?? "AED_TEST",
        bool.Parse(cfg["AutoCount:IntegratedSecurity"] ?? "true"),
        cfg["AutoCount:UserId"] ?? "",
        cfg["AutoCount:Password"] ?? "",
        int.Parse(cfg["AutoCount:CommandTimeoutSeconds"] ?? "30")
    );
});

builder.Services
    .AddMcpServer()
    .WithStdioServerTransport()
    .WithTools<AutoCountTools>();

await builder.Build().RunAsync();
