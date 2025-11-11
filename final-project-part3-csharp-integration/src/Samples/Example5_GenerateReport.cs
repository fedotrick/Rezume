using System;
using System.Data;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using PortfolioManagement.Common;

namespace PortfolioManagement.Samples
{
    /// <summary>
    /// Example 5: Generate portfolio report for a specific time period using sp_GenerateReport
    /// </summary>
    public class Example5_GenerateReport
    {
        private readonly string _connectionString;

        public Example5_GenerateReport(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task RunAsync()
        {
            Console.WriteLine("=== Example 5: Generate Portfolio Report ===");
            Console.WriteLine();

            var portfolioId = 1;
            var startDate = DateTime.UtcNow.AddMonths(-3);
            var endDate = DateTime.UtcNow;

            Console.WriteLine($"Generating report for Portfolio ID: {portfolioId}");
            Console.WriteLine($"Period: {startDate:yyyy-MM-dd} to {endDate:yyyy-MM-dd}");
            Console.WriteLine();

            using var connectionManager = new ConnectionManager(_connectionString);
            await using var connection = connectionManager.CreateConnection();
            await connection.OpenAsync().ConfigureAwait(false);

            await using var command = new SqlCommand("dbo.sp_GenerateReport", connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 60
            };

            command.Parameters.Add(new SqlParameter("@PortfolioID", SqlDbType.Int) { Value = portfolioId });
            command.Parameters.Add(new SqlParameter("@StartDate", SqlDbType.DateTime2) { Value = startDate });
            command.Parameters.Add(new SqlParameter("@EndDate", SqlDbType.DateTime2) { Value = endDate });

            var dataTable = new DataTable();

            await using var reader = await command.ExecuteReaderAsync().ConfigureAwait(false);

            if (reader.HasRows)
            {
                dataTable.Load(reader);

                Console.WriteLine($"Report generated successfully! Rows: {dataTable.Rows.Count}");
                Console.WriteLine();

                if (dataTable.Rows.Count > 0 && dataTable.Columns.Count > 0)
                {
                    for (int i = 0; i < dataTable.Columns.Count; i++)
                    {
                        Console.Write($"{dataTable.Columns[i].ColumnName,-20}");
                    }
                    Console.WriteLine();
                    Console.WriteLine(new string('-', dataTable.Columns.Count * 20));

                    var rowCount = Math.Min(10, dataTable.Rows.Count);
                    for (int i = 0; i < rowCount; i++)
                    {
                        var row = dataTable.Rows[i];
                        for (int j = 0; j < dataTable.Columns.Count; j++)
                        {
                            var value = row[j];
                            var displayValue = value == DBNull.Value ? "NULL" : value.ToString();
                            if (displayValue.Length > 18)
                                displayValue = displayValue.Substring(0, 17) + "…";
                            Console.Write($"{displayValue,-20}");
                        }
                        Console.WriteLine();
                    }

                    if (dataTable.Rows.Count > 10)
                    {
                        Console.WriteLine($"... and {dataTable.Rows.Count - 10} more rows");
                    }
                }

                Console.WriteLine();
                Console.WriteLine("Optional: Export to Excel or CSV");
                Console.WriteLine("You can use libraries like EPPlus, ClosedXML, or CsvHelper to export the DataTable.");
            }
            else
            {
                Console.WriteLine("No data returned by the report procedure.");
            }

            Console.WriteLine();
            Console.WriteLine("=== Example 5 Completed ===");
        }
    }
}
