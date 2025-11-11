using System;
using System.Collections.Generic;

namespace PortfolioManagement.Models
{
    /// <summary>
    /// Represents the Security entity mapped to dbo.Securities table.
    /// </summary>
    public class Security
    {
        public int SecurityID { get; set; }
        public string Ticker { get; set; }
        public string Name { get; set; }
        public string Type { get; set; }
        public string Sector { get; set; }
        public DateTime CreatedAt { get; set; }

        public ICollection<Transaction> Transactions { get; set; } = new HashSet<Transaction>();
        public ICollection<Quote> Quotes { get; set; } = new HashSet<Quote>();
    }
}
