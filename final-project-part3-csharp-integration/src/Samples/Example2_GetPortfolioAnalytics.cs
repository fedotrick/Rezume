using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using PortfolioManagement.Common;
using PortfolioManagement.Services;

namespace PortfolioManagement.Samples
{
    /// <summary>
    /// Example 2: Getting portfolio analytics and displaying results
    /// </summary>
    public class Example2_GetPortfolioAnalytics
    {
        private readonly string _connectionString;
        private readonly ILogger<PortfolioManager> _logger;

        public Example2_GetPortfolioAnalytics(string connectionString, ILogger<PortfolioManager> logger = null)
        {
            _connectionString = connectionString;
            _logger = logger;
        }

        public async Task RunAsync()
        {
            Console.WriteLine("=== Example 2: Get Portfolio Analytics ===");
            Console.WriteLine();

            using var connectionManager = new ConnectionManager(_connectionString);
            var portfolioManager = new PortfolioManager(connectionManager, _logger);

            var portfolioIds = new[] { 1, 2, 3 };

            foreach (var portfolioId in portfolioIds)
            {
                try
                {
                    Console.WriteLine($"Fetching analytics for Portfolio ID: {portfolioId}");
                    Console.WriteLine(new string('-', 60));

                    var summary = await portfolioManager.GetPortfolioSummaryAsync(portfolioId);

                    Console.WriteLine($"Portfolio ID:              {summary.PortfolioId}");
                    Console.WriteLine($"Total Value:               ${summary.TotalValue:N2}");
                    Console.WriteLine($"Securities Held:           {summary.SecuritiesHeld}");
                    Console.WriteLine($"Distinct Security Types:   {summary.DistinctSecurityTypes}");
                    Console.WriteLine($"Total Transactions:        {summary.TotalTransactions}");
                    Console.WriteLine($"First Transaction Date:    {summary.FirstTransactionDate?.ToString("yyyy-MM-dd") ?? "N/A"}");
                    Console.WriteLine($"Last Transaction Date:     {summary.LastTransactionDate?.ToString("yyyy-MM-dd") ?? "N/A"}");
                    Console.WriteLine($"Snapshot Date:             {summary.SnapshotDate:yyyy-MM-dd HH:mm:ss}");
                    Console.WriteLine();

                    if (summary.AllocationByType.Any())
                    {
                        Console.WriteLine("Allocation by Type:");
                        Console.WriteLine("{0,-15} {1,10} {2,15} {3,15} {4,12}",
                            "Type", "Count", "Net Quantity", "Market Value", "Allocation %");
                        Console.WriteLine(new string('-', 67));

                        foreach (var allocation in summary.AllocationByType)
                        {
                            Console.WriteLine("{0,-15} {1,10} {2,15:N2} {3,15:N2} {4,11:N2}%",
                                allocation.SecurityType,
                                allocation.SecuritiesCount,
                                allocation.TotalNetQuantity,
                                allocation.TotalMarketValue,
                                allocation.AllocationPercent);
                        }
                        Console.WriteLine();
                    }

                    if (summary.Holdings.Any())
                    {
                        Console.WriteLine("Top Holdings:");
                        Console.WriteLine("{0,-25} {1,-10} {2,12} {3,12} {4,15} {5,12}",
                            "Security", "Type", "Quantity", "Price", "Market Value", "Allocation %");
                        Console.WriteLine(new string('-', 97));

                        var topHoldings = summary.Holdings.OrderByDescending(h => h.MarketValue).Take(5);
                        foreach (var holding in topHoldings)
                        {
                            Console.WriteLine("{0,-25} {1,-10} {2,12:N2} {3,12:N2} {4,15:N2} {5,11:N2}%",
                                holding.SecurityName.Length > 25 ? holding.SecurityName.Substring(0, 22) + "..." : holding.SecurityName,
                                holding.SecurityType,
                                holding.NetQuantity,
                                holding.CurrentPrice,
                                holding.MarketValue,
                                holding.AllocationPercent);
                        }
                        Console.WriteLine();
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"✗ Error fetching analytics for Portfolio {portfolioId}: {ex.Message}");
                    Console.WriteLine();
                }
            }

            Console.WriteLine("=== Example 2 Completed ===");
        }
    }
}
