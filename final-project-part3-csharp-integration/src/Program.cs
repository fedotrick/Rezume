using System;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Console;
using PortfolioManagement.Samples;

namespace PortfolioManagement
{
    internal static class Program
    {
        private static async Task Main(string[] args)
        {
            var connectionString = Environment.GetEnvironmentVariable("PORTFOLIO_DB_CONNECTION")
                                   ?? "Server=localhost;Database=PortfolioManagement;Integrated Security=true;TrustServerCertificate=true;";

            using var loggerFactory = LoggerFactory.Create(builder =>
            {
                builder
                    .SetMinimumLevel(LogLevel.Information)
                    .AddSimpleConsole(options =>
                    {
                        options.SingleLine = true;
                        options.TimestampFormat = "HH:mm:ss ";
                    });
            });

            var portfolioManagerLogger = loggerFactory.CreateLogger<Services.PortfolioManager>();
            var portfolioRepositoryLogger = loggerFactory.CreateLogger<Data.PortfolioRepository>();

            Console.WriteLine("=== Portfolio Management Integration Examples ===");
            Console.WriteLine("Available examples:");
            Console.WriteLine("1 - Create portfolio and add transactions");
            Console.WriteLine("2 - Get portfolio analytics");
            Console.WriteLine("3 - Update quotes and recalculate value");
            Console.WriteLine("4 - Rebalance portfolio");
            Console.WriteLine("5 - Generate portfolio report");
            Console.WriteLine("A - Run all examples sequentially");
            Console.WriteLine();
            Console.Write("Select an option (default A): ");

            char selected = 'A';
            if (!Console.IsInputRedirected)
            {
                var keyInfo = Console.ReadKey(intercept: true);
                if (keyInfo.Key != ConsoleKey.Enter)
                {
                    selected = char.ToUpperInvariant(keyInfo.KeyChar);
                    Console.WriteLine(selected);
                }
                else
                {
                    Console.WriteLine();
                }
            }
            else
            {
                Console.WriteLine("A (auto-selected)");
            }

            switch (selected)
            {
                case '1':
                    await new Example1_CreatePortfolioAndAddTransactions(connectionString, portfolioManagerLogger).RunAsync();
                    break;
                case '2':
                    await new Example2_GetPortfolioAnalytics(connectionString, portfolioManagerLogger).RunAsync();
                    break;
                case '3':
                    await new Example3_UpdateQuotesAndRecalculateValue(connectionString, portfolioManagerLogger, portfolioRepositoryLogger).RunAsync();
                    break;
                case '4':
                    await new Example4_RebalancePortfolio(connectionString).RunAsync();
                    break;
                case '5':
                    await new Example5_GenerateReport(connectionString).RunAsync();
                    break;
                default:
                    await new Example1_CreatePortfolioAndAddTransactions(connectionString, portfolioManagerLogger).RunAsync();
                    Console.WriteLine();
                    await new Example2_GetPortfolioAnalytics(connectionString, portfolioManagerLogger).RunAsync();
                    Console.WriteLine();
                    await new Example3_UpdateQuotesAndRecalculateValue(connectionString, portfolioManagerLogger, portfolioRepositoryLogger).RunAsync();
                    Console.WriteLine();
                    await new Example4_RebalancePortfolio(connectionString).RunAsync();
                    Console.WriteLine();
                    await new Example5_GenerateReport(connectionString).RunAsync();
                    break;
            }

            Console.WriteLine();
            Console.WriteLine("Integration examples finished.");
        }
    }
}
