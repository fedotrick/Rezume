using System;
using System.Collections.Generic;

namespace PortfolioManagement.Models
{
    /// <summary>
    /// Represents the aggregate analytics for a specific portfolio as returned by the sp_GetPortfolioAnalytics procedure.
    /// </summary>
    public class PortfolioSummary
    {
        public int PortfolioId { get; set; }
        public decimal TotalValue { get; set; }
        public int SecuritiesHeld { get; set; }
        public int DistinctSecurityTypes { get; set; }
        public int TotalTransactions { get; set; }
        public DateTime? FirstTransactionDate { get; set; }
        public DateTime? LastTransactionDate { get; set; }
        public DateTime SnapshotDate { get; set; }
        public IList<PortfolioTypeAllocation> AllocationByType { get; set; } = new List<PortfolioTypeAllocation>();
        public IList<PortfolioHolding> Holdings { get; set; } = new List<PortfolioHolding>();
    }

    /// <summary>
    /// Composition analytics grouped by security type.
    /// </summary>
    public class PortfolioTypeAllocation
    {
        public string SecurityType { get; set; }
        public int SecuritiesCount { get; set; }
        public decimal TotalNetQuantity { get; set; }
        public decimal TotalMarketValue { get; set; }
        public decimal AllocationPercent { get; set; }
    }

    /// <summary>
    /// Detailed information about a single portfolio holding.
    /// </summary>
    public class PortfolioHolding
    {
        public int SecurityId { get; set; }
        public string SecurityName { get; set; }
        public string SecurityType { get; set; }
        public decimal NetQuantity { get; set; }
        public decimal CurrentPrice { get; set; }
        public decimal MarketValue { get; set; }
        public decimal AllocationPercent { get; set; }
    }
}
