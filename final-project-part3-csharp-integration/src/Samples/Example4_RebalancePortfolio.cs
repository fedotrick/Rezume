using System;
using System.Data;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using PortfolioManagement.Common;

namespace PortfolioManagement.Samples
{
    /// <summary>
    /// Example 4: Portfolio rebalancing using sp_RebalancePortfolio stored procedure.
    /// </summary>
    public class Example4_RebalancePortfolio
    {
        private readonly string _connectionString;

        public Example4_RebalancePortfolio(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task RunAsync()
        {
            Console.WriteLine("=== Example 4: Portfolio Rebalancing ===");
            Console.WriteLine();

            var targetAllocation = JsonSerializer.Serialize(new[]
            {
                new { SecurityID = 1, TargetPercent = 40.0m },
                new { SecurityID = 2, TargetPercent = 35.0m },
                new { SecurityID = 3, TargetPercent = 25.0m }
            });

            Console.WriteLine("Target Allocation JSON:");
            Console.WriteLine(targetAllocation);
            Console.WriteLine();

            using var connectionManager = new ConnectionManager(_connectionString);
            await using var connection = connectionManager.CreateConnection();
            await connection.OpenAsync().ConfigureAwait(false);

            await using var command = new SqlCommand("dbo.sp_RebalancePortfolio", connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(new SqlParameter("@PortfolioID", SqlDbType.Int) { Value = 1 });
            command.Parameters.Add(new SqlParameter("@TargetAllocation", SqlDbType.NVarChar, -1) { Value = targetAllocation });

            await using var reader = await command.ExecuteReaderAsync().ConfigureAwait(false);

            Console.WriteLine("Rebalance Summary:");
            Console.WriteLine(new string('-', 80));

            if (await reader.ReadAsync().ConfigureAwait(false))
            {
                Console.WriteLine($"PortfolioID:        {reader["PortfolioID"]}");
                Console.WriteLine($"CurrentValue:       {reader["CurrentValue"]:N2}");
                Console.WriteLine($"TargetValue:        {reader["TargetValue"]:N2}");
                Console.WriteLine($"TotalBuyValue:      {reader["TotalBuyValue"]:N2}");
                Console.WriteLine($"TotalSellValue:     {reader["TotalSellValue"]:N2}");
                Console.WriteLine($"NetInvestment:      {reader["NetInvestment"]:N2}");
            }

            Console.WriteLine();

            if (await reader.NextResultAsync().ConfigureAwait(false))
            {
                Console.WriteLine("Action Plan:");
                Console.WriteLine("{0,-10} {1,12} {2,12} {3,12} {4,12} {5,12}",
                    "Security", "Target %", "Current %", "Action", "Qty Trade", "Current Px");
                Console.WriteLine(new string('-', 80));

                while (await reader.ReadAsync().ConfigureAwait(false))
                {
                    Console.WriteLine("{0,-10} {1,12:N2} {2,12:N2} {3,12} {4,12:N2} {5,12:N2}",
                        reader["SecurityID"],
                        reader["TargetPercent"],
                        reader["CurrentPercent"],
                        reader["ActionRequired"],
                        reader["QuantityToTrade"],
                        reader["CurrentPrice"]);
                }
            }

            Console.WriteLine();
            Console.WriteLine("=== Example 4 Completed ===");
        }
    }
}
