using System;
using System.Data;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using PortfolioManagement.Common;
using PortfolioManagement.Models;

namespace PortfolioManagement.Services
{
    /// <summary>
    /// ADO.NET based service for interacting with portfolio management stored procedures.
    /// </summary>
    public class PortfolioManager
    {
        private readonly ConnectionManager _connectionManager;
        private readonly ILogger<PortfolioManager> _logger;

        public PortfolioManager(ConnectionManager connectionManager, ILogger<PortfolioManager> logger = null)
        {
            _connectionManager = connectionManager ?? throw new ArgumentNullException(nameof(connectionManager));
            _logger = logger;
        }

        #region GetPortfolioSummary

        public PortfolioSummary GetPortfolioSummary(int portfolioId)
        {
            return GetPortfolioSummaryAsync(portfolioId).GetAwaiter().GetResult();
        }

        public async Task<PortfolioSummary> GetPortfolioSummaryAsync(int portfolioId)
        {
            _logger?.LogInformation("Fetching portfolio summary for PortfolioID={PortfolioId}", portfolioId);

            await using var connection = _connectionManager.CreateConnection();
            await connection.OpenAsync().ConfigureAwait(false);

            await using var command = new SqlCommand("dbo.sp_GetPortfolioAnalytics", connection)
            {
                CommandType = CommandType.StoredProcedure
            };
            command.Parameters.Add(new SqlParameter("@PortfolioID", SqlDbType.Int) { Value = portfolioId });

            var summary = new PortfolioSummary();
            try
            {
                await using var reader = await command.ExecuteReaderAsync(CommandBehavior.CloseConnection).ConfigureAwait(false);

                if (await reader.ReadAsync().ConfigureAwait(false))
                {
                    summary.PortfolioId = reader.GetInt32(reader.GetOrdinal("PortfolioID"));
                    summary.TotalValue = reader.GetFieldValue<decimal>(reader.GetOrdinal("TotalValue"));
                    summary.SecuritiesHeld = reader.GetInt32(reader.GetOrdinal("SecuritiesHeld"));
                    summary.DistinctSecurityTypes = reader.GetInt32(reader.GetOrdinal("DistinctSecurityTypes"));
                    summary.TotalTransactions = reader.GetInt32(reader.GetOrdinal("TotalTransactions"));
                    summary.FirstTransactionDate = reader.IsDBNull(reader.GetOrdinal("FirstTransactionDate"))
                        ? null
                        : reader.GetDateTime(reader.GetOrdinal("FirstTransactionDate"));
                    summary.LastTransactionDate = reader.IsDBNull(reader.GetOrdinal("LastTransactionDate"))
                        ? null
                        : reader.GetDateTime(reader.GetOrdinal("LastTransactionDate"));
                    summary.SnapshotDate = reader.GetDateTime(reader.GetOrdinal("SnapshotDate"));
                }

                if (await reader.NextResultAsync().ConfigureAwait(false))
                {
                    while (await reader.ReadAsync().ConfigureAwait(false))
                    {
                        summary.AllocationByType.Add(new PortfolioTypeAllocation
                        {
                            SecurityType = reader.GetString(reader.GetOrdinal("SecurityType")),
                            SecuritiesCount = reader.GetInt32(reader.GetOrdinal("SecuritiesCount")),
                            TotalNetQuantity = reader.GetFieldValue<decimal>(reader.GetOrdinal("TotalNetQuantity")),
                            TotalMarketValue = reader.GetFieldValue<decimal>(reader.GetOrdinal("TotalMarketValue")),
                            AllocationPercent = reader.GetFieldValue<decimal>(reader.GetOrdinal("AllocationPercent"))
                        });
                    }
                }

                if (await reader.NextResultAsync().ConfigureAwait(false))
                {
                    while (await reader.ReadAsync().ConfigureAwait(false))
                    {
                        summary.Holdings.Add(new PortfolioHolding
                        {
                            SecurityId = reader.GetInt32(reader.GetOrdinal("SecurityID")),
                            SecurityName = reader.GetString(reader.GetOrdinal("SecurityName")),
                            SecurityType = reader.GetString(reader.GetOrdinal("SecurityType")),
                            NetQuantity = reader.GetFieldValue<decimal>(reader.GetOrdinal("NetQuantity")),
                            CurrentPrice = reader.GetFieldValue<decimal>(reader.GetOrdinal("CurrentPrice")),
                            MarketValue = reader.GetFieldValue<decimal>(reader.GetOrdinal("MarketValue")),
                            AllocationPercent = reader.GetFieldValue<decimal>(reader.GetOrdinal("AllocationPercent"))
                        });
                    }
                }

                _logger?.LogInformation("Successfully fetched analytics for PortfolioID={PortfolioId}", portfolioId);
            }
            catch (SqlException ex)
            {
                _logger?.LogError(ex, "SQL error while executing sp_GetPortfolioAnalytics for PortfolioID={PortfolioId}", portfolioId);
                throw;
            }

            return summary;
        }

        #endregion

        #region AddTransaction

        public TransactionResult AddTransaction(Transaction transaction)
        {
            return AddTransactionAsync(transaction).GetAwaiter().GetResult();
        }

        public async Task<TransactionResult> AddTransactionAsync(Transaction transaction)
        {
            if (transaction == null) throw new ArgumentNullException(nameof(transaction));

            _logger?.LogInformation("Adding transaction for PortfolioID={PortfolioId}, SecurityID={SecurityId}, Type={Type}",
                transaction.PortfolioId, transaction.SecurityId, transaction.Type);

            await using var connection = _connectionManager.CreateConnection();
            await connection.OpenAsync().ConfigureAwait(false);

            await using var command = new SqlCommand("dbo.sp_AddTransaction", connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.AddRange(new[]
            {
                new SqlParameter("@PortfolioID", SqlDbType.Int) { Value = transaction.PortfolioId },
                new SqlParameter("@SecurityID", SqlDbType.Int) { Value = transaction.SecurityId },
                new SqlParameter("@Quantity", SqlDbType.Decimal)
                {
                    Precision = 18,
                    Scale = 4,
                    Value = transaction.Quantity
                },
                new SqlParameter("@Price", SqlDbType.Decimal)
                {
                    Precision = 18,
                    Scale = 4,
                    Value = transaction.Price
                },
                new SqlParameter("@TransactionDate", SqlDbType.DateTime2)
                {
                    Value = transaction.TransactionDate == default ? (object)DBNull.Value : transaction.TransactionDate
                },
                new SqlParameter("@Type", SqlDbType.NVarChar, 4) { Value = transaction.Type?.ToUpperInvariant() ?? (object)DBNull.Value }
            });

            var resultParam = new SqlParameter("@Result", SqlDbType.NVarChar, 20)
            {
                Direction = ParameterDirection.Output
            };
            var transactionIdParam = new SqlParameter("@TransactionID", SqlDbType.BigInt)
            {
                Direction = ParameterDirection.Output
            };

            command.Parameters.Add(resultParam);
            command.Parameters.Add(transactionIdParam);

            try
            {
                await command.ExecuteNonQueryAsync().ConfigureAwait(false);

                var result = (resultParam.Value as string) ?? string.Empty;
                var success = string.Equals(result, "SUCCESS", StringComparison.OrdinalIgnoreCase);
                var transactionId = transactionIdParam.Value == DBNull.Value ? (long?)null : (long)transactionIdParam.Value;

                _logger?.LogInformation("sp_AddTransaction executed with result={Result}, TransactionID={TransactionId}", result, transactionId);

                return new TransactionResult
                {
                    Success = success,
                    Message = result,
                    TransactionId = transactionId
                };
            }
            catch (SqlException ex)
            {
                _logger?.LogError(ex, "SQL error while executing sp_AddTransaction for PortfolioID={PortfolioId}", transaction.PortfolioId);
                return new TransactionResult
                {
                    Success = false,
                    Message = ex.Message,
                    TransactionId = null
                };
            }
        }

        #endregion

        #region UpdatePortfolioValue

        public decimal UpdatePortfolioValue(int portfolioId)
        {
            return UpdatePortfolioValueAsync(portfolioId).GetAwaiter().GetResult();
        }

        public async Task<decimal> UpdatePortfolioValueAsync(int portfolioId)
        {
            _logger?.LogInformation("Updating portfolio value for PortfolioID={PortfolioId}", portfolioId);

            await using var connection = _connectionManager.CreateConnection();
            await connection.OpenAsync().ConfigureAwait(false);

            await using var command = new SqlCommand("dbo.sp_UpdatePortfolioValue", connection)
            {
                CommandType = CommandType.StoredProcedure
            };
            command.Parameters.Add(new SqlParameter("@PortfolioID", SqlDbType.Int) { Value = portfolioId });

            try
            {
                await using var reader = await command.ExecuteReaderAsync(CommandBehavior.CloseConnection).ConfigureAwait(false);
                if (await reader.ReadAsync().ConfigureAwait(false))
                {
                    var portfolioValue = reader.GetFieldValue<decimal>(reader.GetOrdinal("PortfolioValue"));
                    _logger?.LogInformation("Portfolio value updated for PortfolioID={PortfolioId}. New Value={PortfolioValue}",
                        portfolioId, portfolioValue);
                    return portfolioValue;
                }

                _logger?.LogWarning("sp_UpdatePortfolioValue returned no result set for PortfolioID={PortfolioId}", portfolioId);
                return 0m;
            }
            catch (SqlException ex)
            {
                _logger?.LogError(ex, "SQL error while executing sp_UpdatePortfolioValue for PortfolioID={PortfolioId}", portfolioId);
                throw;
            }
        }

        #endregion
    }
}
