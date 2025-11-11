using System;

namespace PortfolioManagement.Models
{
    /// <summary>
    /// Represents an operational cash flow related to a portfolio.
    /// </summary>
    public class Operation
    {
        public long OperationID { get; set; }
        public int PortfolioID { get; set; }
        public string Description { get; set; }
        public decimal Amount { get; set; }
        public DateTime OperationDate { get; set; }
        public string Category { get; set; }

        public Portfolio Portfolio { get; set; }
    }
}
