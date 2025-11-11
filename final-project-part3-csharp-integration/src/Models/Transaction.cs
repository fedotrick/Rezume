using System;

namespace PortfolioManagement.Models
{
    /// <summary>
    /// Represents a buy or sell transaction for a security in a portfolio.
    /// </summary>
    public class Transaction
    {
        public long TransactionId { get; set; }
        public int PortfolioId { get; set; }
        public int SecurityId { get; set; }
        public decimal Quantity { get; set; }
        public decimal Price { get; set; }
        public DateTime TransactionDate { get; set; } = DateTime.UtcNow;
        public string Type { get; set; } = string.Empty;
        public string Notes { get; set; }

        public Portfolio Portfolio { get; set; }
        public Security Security { get; set; }
    }

    /// <summary>
    /// Represents the outcome of executing the sp_AddTransaction stored procedure.
    /// </summary>
    public class TransactionResult
    {
        public bool Success { get; set; }
        public string Message { get; set; } = string.Empty;
        public long? TransactionId { get; set; }
    }
}
