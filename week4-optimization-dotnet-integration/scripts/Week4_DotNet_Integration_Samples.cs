// Week 4: .NET Integration Samples
// ---------------------------------
// Этот файл содержит примеры кода для взаимодействия с SQL Server
// из .NET-приложений. Включает реализации ADO.NET репозитория,
// использование Polly для повторов, интеграцию с EF Core и сбор метрик.

using System;
using System.Collections.Generic;
using System.Data;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Polly;
using Polly.Retry;

namespace Week4.DotNet.Integration
{
    #region Domain Models

    public record PortfolioSummary(string PortfolioName, string Symbol, decimal GrossAmount, decimal TotalFees, long TradesCount);

    public record PerformancePoint(DateTime SnapshotDate, decimal CashFlow, decimal CumulativePnL);

    public record Trade(int PortfolioId, string Symbol, DateTime TradeDate, string TradeType, int Quantity, decimal Price, decimal Fees);

    #endregion

    #region Repository

    public sealed class PortfolioRepository
    {
        private static readonly int[] TransientErrorNumbers = { 4060, 40197, 40501, 40613, 49918, 49919, 49920, 10928, 10929, 18456 };

        private readonly string _connectionString;
        private readonly ILogger<PortfolioRepository> _logger;
        private readonly AsyncRetryPolicy _retryPolicy;

        public PortfolioRepository(string connectionString, ILogger<PortfolioRepository> logger)
        {
            _connectionString = connectionString ?? throw new ArgumentNullException(nameof(connectionString));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));

            _retryPolicy = Policy
                .Handle<SqlException>(ex => Array.Exists(TransientErrorNumbers, number => number == ex.Number))
                .Or<TimeoutException>()
                .WaitAndRetryAsync(3, attempt => TimeSpan.FromSeconds(Math.Pow(2, attempt)),
                    onRetry: (exception, timeSpan, retryCount, context) =>
                    {
                        _logger.LogWarning(exception, "Retry {RetryCount} after {Delay} while executing SQL command", retryCount, timeSpan);
                    });
        }

        public async Task<IReadOnlyList<PortfolioSummary>> GetPortfolioSummaryAsync(int portfolioId, CancellationToken cancellationToken = default)
        {
            const string procedureName = "dbo.usp_GetPortfolioSummary";
            var result = new List<PortfolioSummary>(capacity: 16);

            await using var connection = new SqlConnection(_connectionString);
            await connection.OpenAsync(cancellationToken).ConfigureAwait(false);

            await using var command = new SqlCommand(procedureName, connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 60
            };

            command.Parameters.Add(new SqlParameter("@PortfolioId", SqlDbType.Int) { Value = portfolioId });

            var stopwatch = Stopwatch.StartNew();

            await _retryPolicy.ExecuteAsync(async ct =>
            {
                await using var reader = await command.ExecuteReaderAsync(CommandBehavior.SequentialAccess, ct).ConfigureAwait(false);
                while (await reader.ReadAsync(ct).ConfigureAwait(false))
                {
                    var item = new PortfolioSummary(
                        PortfolioName: reader.GetString(reader.GetOrdinal("PortfolioName")),
                        Symbol: reader.GetString(reader.GetOrdinal("Symbol")),
                        GrossAmount: reader.GetDecimal(reader.GetOrdinal("GrossAmount")),
                        TotalFees: reader.GetDecimal(reader.GetOrdinal("TotalFees")),
                        TradesCount: reader.GetInt64(reader.GetOrdinal("TradesCount"))
                    );
                    result.Add(item);
                }
            }, cancellationToken).ConfigureAwait(false);

            stopwatch.Stop();
            _logger.LogInformation("{Command} executed in {Duration} ms and returned {Rows} rows", procedureName, stopwatch.ElapsedMilliseconds, result.Count);

            return result;
        }

        public async Task UpsertTradeAsync(Trade trade, CancellationToken cancellationToken = default)
        {
            if (trade is null) throw new ArgumentNullException(nameof(trade));

            const string procedureName = "dbo.usp_UpsertTrade";

            await using var connection = new SqlConnection(_connectionString);
            await connection.OpenAsync(cancellationToken).ConfigureAwait(false);

            await using var command = new SqlCommand(procedureName, connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 60
            };

            command.Parameters.AddRange(new[]
            {
                new SqlParameter("@PortfolioId", SqlDbType.Int) { Value = trade.PortfolioId },
                new SqlParameter("@Symbol", SqlDbType.NVarChar, 12) { Value = trade.Symbol },
                new SqlParameter("@TradeDate", SqlDbType.Date) { Value = trade.TradeDate },
                new SqlParameter("@TradeType", SqlDbType.Char, 4) { Value = trade.TradeType },
                new SqlParameter("@Quantity", SqlDbType.Int) { Value = trade.Quantity },
                new SqlParameter("@Price", SqlDbType.Decimal) { Precision = 18, Scale = 4, Value = trade.Price },
                new SqlParameter("@Fees", SqlDbType.Decimal) { Precision = 18, Scale = 4, Value = trade.Fees }
            });

            await _retryPolicy.ExecuteAsync(ct => command.ExecuteNonQueryAsync(ct), cancellationToken).ConfigureAwait(false);
        }

        public async Task<IReadOnlyList<PerformancePoint>> GetPerformanceHistoryAsync(int portfolioId, DateTime startDate, DateTime endDate, CancellationToken cancellationToken = default)
        {
            const string procedureName = "dbo.usp_GetPerformanceHistory";
            var result = new List<PerformancePoint>();

            await using var connection = new SqlConnection(_connectionString);
            await connection.OpenAsync(cancellationToken).ConfigureAwait(false);

            await using var command = new SqlCommand(procedureName, connection)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 60
            };

            command.Parameters.AddRange(new[]
            {
                new SqlParameter("@PortfolioId", SqlDbType.Int) { Value = portfolioId },
                new SqlParameter("@StartDate", SqlDbType.Date) { Value = startDate },
                new SqlParameter("@EndDate", SqlDbType.Date) { Value = endDate }
            });

            var stopwatch = Stopwatch.StartNew();

            await _retryPolicy.ExecuteAsync(async ct =>
            {
                await using var reader = await command.ExecuteReaderAsync(CommandBehavior.SequentialAccess, ct).ConfigureAwait(false);
                while (await reader.ReadAsync(ct).ConfigureAwait(false))
                {
                    var point = new PerformancePoint(
                        SnapshotDate: reader.GetDateTime(reader.GetOrdinal("SnapshotDate")),
                        CashFlow: reader.GetDecimal(reader.GetOrdinal("CashFlow")),
                        CumulativePnL: reader.GetDecimal(reader.GetOrdinal("CumulativePnL"))
                    );
                    result.Add(point);
                }
            }, cancellationToken).ConfigureAwait(false);

            stopwatch.Stop();
            _logger.LogInformation("{Command} executed in {Duration} ms and returned {Rows} rows", procedureName, stopwatch.ElapsedMilliseconds, result.Count);

            return result;
        }
    }

    #endregion

    #region Service Layer

    public sealed class PortfolioService
    {
        private readonly PortfolioRepository _repository;
        private readonly ILogger<PortfolioService> _logger;

        public PortfolioService(PortfolioRepository repository, ILogger<PortfolioService> logger)
        {
            _repository = repository ?? throw new ArgumentNullException(nameof(repository));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public async Task RefreshPortfolioSnapshotAsync(int portfolioId, CancellationToken cancellationToken = default)
        {
            var summaries = await _repository.GetPortfolioSummaryAsync(portfolioId, cancellationToken).ConfigureAwait(false);
            foreach (var summary in summaries)
            {
                _logger.LogInformation("Portfolio {PortfolioId} symbol {Symbol}: gross {GrossAmount} fees {Fees} trades {Trades}",
                    portfolioId, summary.Symbol, summary.GrossAmount, summary.TotalFees, summary.TradesCount);
            }
        }

        public async Task ImportTradeAsync(Trade trade, CancellationToken cancellationToken = default)
        {
            await _repository.UpsertTradeAsync(trade, cancellationToken).ConfigureAwait(false);
            _logger.LogInformation("Trade for portfolio {Portfolio} symbol {Symbol} imported", trade.PortfolioId, trade.Symbol);
        }

        public async Task PublishPerformanceAsync(int portfolioId, DateTime startDate, DateTime endDate, CancellationToken cancellationToken = default)
        {
            var history = await _repository.GetPerformanceHistoryAsync(portfolioId, startDate, endDate, cancellationToken).ConfigureAwait(false);
            foreach (var point in history)
            {
                _logger.LogInformation("{Date:yyyy-MM-dd}: cash flow {CashFlow} cumulative {Cumulative}", point.SnapshotDate, point.CashFlow, point.CumulativePnL);
            }
        }
    }

    #endregion

    #region Example Host

    public static class Program
    {
        // Пример конфигурации connection string (appsettings.json):
        // "ConnectionStrings": {
        //   "TradingDb": "Server=tcp:sqlserver.local,1433;Initial Catalog=SQLTraining;Persist Security Info=False;User ID=app_user;Password=<secret>;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Max Pool Size=200;Min Pool Size=10"
        // }

        public static async Task Main()
        {
            using var loggerFactory = LoggerFactory.Create(builder =>
            {
                builder
                    .AddFilter(level => level >= LogLevel.Information)
                    .AddConsole();
            });

            var connectionString = Environment.GetEnvironmentVariable("TRADING_DB_CONNECTION")
                                   ?? "Server=localhost;Database=SQLTraining;Integrated Security=true;TrustServerCertificate=true;";

            var repository = new PortfolioRepository(connectionString, loggerFactory.CreateLogger<PortfolioRepository>());
            var service = new PortfolioService(repository, loggerFactory.CreateLogger<PortfolioService>());

            await service.RefreshPortfolioSnapshotAsync(portfolioId: 1);

            await service.ImportTradeAsync(new Trade(1, "MSFT", DateTime.UtcNow.Date, "BUY", 100, 315.42m, 2.50m));

            var startDate = DateTime.UtcNow.Date.AddDays(-30);
            var endDate = DateTime.UtcNow.Date;
            await service.PublishPerformanceAsync(portfolioId: 1, startDate, endDate);
        }
    }

    #endregion
}
