using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using PortfolioManagement.Common;
using PortfolioManagement.Data;
using PortfolioManagement.Models;
using PortfolioManagement.Services;

namespace PortfolioManagement.Samples
{
    /// <summary>
    /// Example 3: Update quotes and recalculate portfolio value
    /// Demonstrates bulk quote upload and triggering portfolio value recalculation
    /// </summary>
    public class Example3_UpdateQuotesAndRecalculateValue
    {
        private readonly string _connectionString;
        private readonly ILogger<PortfolioManager> _managerLogger;
        private readonly ILogger<PortfolioRepository> _repoLogger;

        public Example3_UpdateQuotesAndRecalculateValue(
            string connectionString,
            ILogger<PortfolioManager> managerLogger = null,
            ILogger<PortfolioRepository> repoLogger = null)
        {
            _connectionString = connectionString;
            _managerLogger = managerLogger;
            _repoLogger = repoLogger;
        }

        public async Task RunAsync()
        {
            Console.WriteLine("=== Example 3: Update Quotes and Recalculate Portfolio Value ===");
            Console.WriteLine();

            var optionsBuilder = new DbContextOptionsBuilder<PortfolioDbContext>();
            optionsBuilder.UseSqlServer(_connectionString);

            await using var context = new PortfolioDbContext(optionsBuilder.Options);
            var repository = new PortfolioRepository(context, _repoLogger);

            var newQuotes = new List<Quote>
            {
                new Quote
                {
                    SecurityID = 1,
                    Price = 152.30m,
                    QuoteDate = DateTime.UtcNow,
                    Volume = 25000000,
                    Source = "Example API"
                },
                new Quote
                {
                    SecurityID = 2,
                    Price = 285.50m,
                    QuoteDate = DateTime.UtcNow,
                    Volume = 18000000,
                    Source = "Example API"
                },
                new Quote
                {
                    SecurityID = 3,
                    Price = 145.75m,
                    QuoteDate = DateTime.UtcNow,
                    Volume = 12000000,
                    Source = "Example API"
                }
            };

            Console.WriteLine($"Adding {newQuotes.Count} new quotes...");
            var quotesAdded = await repository.BulkAddQuotesAsync(newQuotes);
            Console.WriteLine($"✓ Successfully added {quotesAdded} quotes");
            Console.WriteLine();

            using var connectionManager = new ConnectionManager(_connectionString);
            var portfolioManager = new PortfolioManager(connectionManager, _managerLogger);

            var portfolioId = 1;
            Console.WriteLine($"Recalculating value for Portfolio ID: {portfolioId}...");
            var newValue = await portfolioManager.UpdatePortfolioValueAsync(portfolioId);
            Console.WriteLine($"✓ Portfolio value updated: ${newValue:N2}");
            Console.WriteLine();

            Console.WriteLine("Fetching updated portfolio analytics...");
            var summary = await portfolioManager.GetPortfolioSummaryAsync(portfolioId);
            Console.WriteLine($"Total Portfolio Value: ${summary.TotalValue:N2}");
            Console.WriteLine($"Snapshot Date:         {summary.SnapshotDate:yyyy-MM-dd HH:mm:ss}");
            Console.WriteLine();

            Console.WriteLine("Note: The trg_UpdatePortfolioValue_OnQuoteChange trigger");
            Console.WriteLine("should have automatically updated portfolio values when quotes were inserted.");
            Console.WriteLine();

            Console.WriteLine("=== Example 3 Completed ===");
        }
    }
}
