using System;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using PortfolioManagement.Common;
using PortfolioManagement.Models;
using PortfolioManagement.Services;

namespace PortfolioManagement.Samples
{
    /// <summary>
    /// Example 1: Creating a portfolio and adding transactions using ADO.NET
    /// </summary>
    public class Example1_CreatePortfolioAndAddTransactions
    {
        private readonly string _connectionString;
        private readonly ILogger<PortfolioManager> _logger;

        public Example1_CreatePortfolioAndAddTransactions(string connectionString, ILogger<PortfolioManager> logger = null)
        {
            _connectionString = connectionString;
            _logger = logger;
        }

        public async Task RunAsync()
        {
            Console.WriteLine("=== Example 1: Create Portfolio and Add Transactions ===");
            Console.WriteLine();

            using var connectionManager = new ConnectionManager(_connectionString);
            var portfolioManager = new PortfolioManager(connectionManager, _logger);

            var transaction1 = new Transaction
            {
                PortfolioId = 1,
                SecurityId = 1,
                Quantity = 100m,
                Price = 150.50m,
                Type = "BUY",
                Notes = "Initial purchase of AAPL"
            };

            Console.WriteLine($"Adding BUY transaction: {transaction1.Quantity} shares at ${transaction1.Price}");
            var result1 = await portfolioManager.AddTransactionAsync(transaction1);

            if (result1.Success)
            {
                Console.WriteLine($"✓ Transaction added successfully! TransactionID: {result1.TransactionId}");
            }
            else
            {
                Console.WriteLine($"✗ Transaction failed: {result1.Message}");
                return;
            }

            Console.WriteLine();

            var transaction2 = new Transaction
            {
                PortfolioId = 1,
                SecurityId = 2,
                Quantity = 50m,
                Price = 280.75m,
                Type = "BUY",
                Notes = "Purchase of MSFT"
            };

            Console.WriteLine($"Adding BUY transaction: {transaction2.Quantity} shares at ${transaction2.Price}");
            var result2 = await portfolioManager.AddTransactionAsync(transaction2);

            if (result2.Success)
            {
                Console.WriteLine($"✓ Transaction added successfully! TransactionID: {result2.TransactionId}");
            }
            else
            {
                Console.WriteLine($"✗ Transaction failed: {result2.Message}");
                return;
            }

            Console.WriteLine();

            var transaction3 = new Transaction
            {
                PortfolioId = 1,
                SecurityId = 1,
                Quantity = 30m,
                Price = 155.25m,
                Type = "SELL",
                Notes = "Partial sale of AAPL"
            };

            Console.WriteLine($"Adding SELL transaction: {transaction3.Quantity} shares at ${transaction3.Price}");
            var result3 = await portfolioManager.AddTransactionAsync(transaction3);

            if (result3.Success)
            {
                Console.WriteLine($"✓ Transaction added successfully! TransactionID: {result3.TransactionId}");
            }
            else
            {
                Console.WriteLine($"✗ Transaction failed: {result3.Message}");
            }

            Console.WriteLine();
            Console.WriteLine("=== Example 1 Completed ===");
        }
    }
}
