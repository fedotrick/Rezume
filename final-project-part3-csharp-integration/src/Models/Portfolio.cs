using System;
using System.Collections.Generic;

namespace PortfolioManagement.Models
{
    /// <summary>
    /// Represents a portfolio entity within the portfolio management system.
    /// </summary>
    public class Portfolio
    {
        public int PortfolioID { get; set; }
        public string Name { get; set; }
        public string Owner { get; set; }
        public DateTime CreatedDate { get; set; }
        public string Description { get; set; }

        public ICollection<Transaction> Transactions { get; set; } = new HashSet<Transaction>();
        public ICollection<Operation> Operations { get; set; } = new HashSet<Operation>();
    }
}
