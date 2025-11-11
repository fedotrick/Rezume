using System;

namespace PortfolioManagement.Models
{
    /// <summary>
    /// Represents a quote (price snapshot) for a security at a specific date.
    /// </summary>
    public class Quote
    {
        public long QuoteID { get; set; }
        public int SecurityID { get; set; }
        public decimal Price { get; set; }
        public DateTime QuoteDate { get; set; }
        public long Volume { get; set; }
        public string Source { get; set; }

        public Security Security { get; set; }
    }
}
