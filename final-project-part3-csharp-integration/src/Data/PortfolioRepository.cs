using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using PortfolioManagement.Models;

namespace PortfolioManagement.Data
{
    /// <summary>
    /// Entity Framework based repository for portfolio management operations.
    /// Provides CRUD operations, filtering, and includes.
    /// </summary>
    public class PortfolioRepository
    {
        private readonly PortfolioDbContext _context;
        private readonly ILogger<PortfolioRepository> _logger;

        public PortfolioRepository(PortfolioDbContext context, ILogger<PortfolioRepository> logger = null)
        {
            _context = context ?? throw new ArgumentNullException(nameof(context));
            _logger = logger;
        }

        #region Portfolio CRUD

        public async Task<Portfolio> GetPortfolioByIdAsync(int portfolioId, bool includeTransactions = false, bool includeOperations = false)
        {
            _logger?.LogInformation("Fetching Portfolio with ID={PortfolioId}", portfolioId);

            IQueryable<Portfolio> query = _context.Portfolios;

            if (includeTransactions)
                query = query.Include(p => p.Transactions);

            if (includeOperations)
                query = query.Include(p => p.Operations);

            return await query.FirstOrDefaultAsync(p => p.PortfolioID == portfolioId);
        }

        public async Task<IEnumerable<Portfolio>> GetPortfoliosByOwnerAsync(string owner)
        {
            _logger?.LogInformation("Fetching portfolios for Owner={Owner}", owner);
            return await _context.Portfolios
                .Where(p => p.Owner == owner)
                .OrderByDescending(p => p.CreatedDate)
                .ToListAsync();
        }

        public async Task<IEnumerable<Portfolio>> GetAllPortfoliosAsync(int skip = 0, int take = 50)
        {
            _logger?.LogInformation("Fetching all portfolios (skip={Skip}, take={Take})", skip, take);
            return await _context.Portfolios
                .OrderByDescending(p => p.CreatedDate)
                .Skip(skip)
                .Take(take)
                .ToListAsync();
        }

        public async Task<Portfolio> CreatePortfolioAsync(Portfolio portfolio)
        {
            if (portfolio == null) throw new ArgumentNullException(nameof(portfolio));

            _logger?.LogInformation("Creating new portfolio: {Name} for Owner={Owner}", portfolio.Name, portfolio.Owner);

            portfolio.CreatedDate = DateTime.UtcNow;
            _context.Portfolios.Add(portfolio);
            await _context.SaveChangesAsync();

            _logger?.LogInformation("Portfolio created with ID={PortfolioID}", portfolio.PortfolioID);
            return portfolio;
        }

        public async Task<Portfolio> UpdatePortfolioAsync(Portfolio portfolio)
        {
            if (portfolio == null) throw new ArgumentNullException(nameof(portfolio));

            _logger?.LogInformation("Updating portfolio with ID={PortfolioID}", portfolio.PortfolioID);

            _context.Portfolios.Update(portfolio);
            await _context.SaveChangesAsync();

            return portfolio;
        }

        public async Task<bool> DeletePortfolioAsync(int portfolioId)
        {
            _logger?.LogInformation("Deleting portfolio with ID={PortfolioID}", portfolioId);

            var portfolio = await _context.Portfolios.FindAsync(portfolioId);
            if (portfolio == null)
            {
                _logger?.LogWarning("Portfolio with ID={PortfolioID} not found for deletion", portfolioId);
                return false;
            }

            _context.Portfolios.Remove(portfolio);
            await _context.SaveChangesAsync();

            _logger?.LogInformation("Portfolio with ID={PortfolioID} deleted successfully", portfolioId);
            return true;
        }

        #endregion

        #region Security CRUD

        public async Task<Security> GetSecurityByIdAsync(int securityId, bool includeQuotes = false)
        {
            _logger?.LogInformation("Fetching Security with ID={SecurityId}", securityId);

            IQueryable<Security> query = _context.Securities;

            if (includeQuotes)
                query = query.Include(s => s.Quotes.OrderByDescending(q => q.QuoteDate).Take(30));

            return await query.FirstOrDefaultAsync(s => s.SecurityID == securityId);
        }

        public async Task<Security> GetSecurityByTickerAsync(string ticker)
        {
            _logger?.LogInformation("Fetching Security with Ticker={Ticker}", ticker);
            return await _context.Securities.FirstOrDefaultAsync(s => s.Ticker == ticker);
        }

        public async Task<IEnumerable<Security>> GetSecuritiesByTypeAsync(string type)
        {
            _logger?.LogInformation("Fetching securities of Type={Type}", type);
            return await _context.Securities
                .Where(s => s.Type == type)
                .OrderBy(s => s.Name)
                .ToListAsync();
        }

        public async Task<IEnumerable<Security>> GetSecuritiesBySectorAsync(string sector)
        {
            _logger?.LogInformation("Fetching securities in Sector={Sector}", sector);
            return await _context.Securities
                .Where(s => s.Sector == sector)
                .OrderBy(s => s.Name)
                .ToListAsync();
        }

        public async Task<Security> CreateSecurityAsync(Security security)
        {
            if (security == null) throw new ArgumentNullException(nameof(security));

            _logger?.LogInformation("Creating new security: {Ticker} - {Name}", security.Ticker, security.Name);

            security.CreatedAt = DateTime.UtcNow;
            _context.Securities.Add(security);
            await _context.SaveChangesAsync();

            _logger?.LogInformation("Security created with ID={SecurityID}", security.SecurityID);
            return security;
        }

        public async Task<Security> UpdateSecurityAsync(Security security)
        {
            if (security == null) throw new ArgumentNullException(nameof(security));

            _logger?.LogInformation("Updating security with ID={SecurityID}", security.SecurityID);

            _context.Securities.Update(security);
            await _context.SaveChangesAsync();

            return security;
        }

        #endregion

        #region Transaction queries

        public async Task<IEnumerable<Transaction>> GetTransactionsByPortfolioAsync(
            int portfolioId,
            DateTime? startDate = null,
            DateTime? endDate = null,
            string type = null)
        {
            _logger?.LogInformation("Fetching transactions for PortfolioID={PortfolioId}", portfolioId);

            IQueryable<Transaction> query = _context.Transactions
                .Where(t => t.PortfolioId == portfolioId);

            if (startDate.HasValue)
                query = query.Where(t => t.TransactionDate >= startDate.Value);

            if (endDate.HasValue)
                query = query.Where(t => t.TransactionDate <= endDate.Value);

            if (!string.IsNullOrWhiteSpace(type))
                query = query.Where(t => t.Type == type.ToUpperInvariant());

            return await query.OrderByDescending(t => t.TransactionDate).ToListAsync();
        }

        public async Task<IEnumerable<Transaction>> GetTransactionsBySecurityAsync(int securityId)
        {
            _logger?.LogInformation("Fetching transactions for SecurityID={SecurityId}", securityId);
            return await _context.Transactions
                .Where(t => t.SecurityId == securityId)
                .OrderByDescending(t => t.TransactionDate)
                .ToListAsync();
        }

        #endregion

        #region Quote queries

        public async Task<Quote> GetLatestQuoteAsync(int securityId)
        {
            _logger?.LogInformation("Fetching latest quote for SecurityID={SecurityId}", securityId);
            return await _context.Quotes
                .Where(q => q.SecurityID == securityId)
                .OrderByDescending(q => q.QuoteDate)
                .FirstOrDefaultAsync();
        }

        public async Task<IEnumerable<Quote>> GetQuoteHistoryAsync(int securityId, DateTime startDate, DateTime endDate)
        {
            _logger?.LogInformation("Fetching quote history for SecurityID={SecurityId} from {StartDate} to {EndDate}",
                securityId, startDate, endDate);

            return await _context.Quotes
                .Where(q => q.SecurityID == securityId && q.QuoteDate >= startDate && q.QuoteDate <= endDate)
                .OrderBy(q => q.QuoteDate)
                .ToListAsync();
        }

        public async Task<Quote> AddQuoteAsync(Quote quote)
        {
            if (quote == null) throw new ArgumentNullException(nameof(quote));

            _logger?.LogInformation("Adding quote for SecurityID={SecurityId} on {QuoteDate}", quote.SecurityID, quote.QuoteDate);

            _context.Quotes.Add(quote);
            await _context.SaveChangesAsync();

            return quote;
        }

        public async Task<int> BulkAddQuotesAsync(IEnumerable<Quote> quotes)
        {
            if (quotes == null) throw new ArgumentNullException(nameof(quotes));

            var quoteList = quotes.ToList();
            _logger?.LogInformation("Bulk adding {Count} quotes", quoteList.Count);

            _context.Quotes.AddRange(quoteList);
            var result = await _context.SaveChangesAsync();

            _logger?.LogInformation("Bulk added {Count} quotes successfully", result);
            return result;
        }

        #endregion

        #region Operation queries

        public async Task<IEnumerable<Operation>> GetOperationsByPortfolioAsync(int portfolioId, DateTime? startDate = null, DateTime? endDate = null)
        {
            _logger?.LogInformation("Fetching operations for PortfolioID={PortfolioId}", portfolioId);

            IQueryable<Operation> query = _context.Operations
                .Where(o => o.PortfolioID == portfolioId);

            if (startDate.HasValue)
                query = query.Where(o => o.OperationDate >= startDate.Value);

            if (endDate.HasValue)
                query = query.Where(o => o.OperationDate <= endDate.Value);

            return await query.OrderByDescending(o => o.OperationDate).ToListAsync();
        }

        public async Task<Operation> AddOperationAsync(Operation operation)
        {
            if (operation == null) throw new ArgumentNullException(nameof(operation));

            _logger?.LogInformation("Adding operation for PortfolioID={PortfolioID}", operation.PortfolioID);

            operation.OperationDate = DateTime.UtcNow;
            _context.Operations.Add(operation);
            await _context.SaveChangesAsync();

            return operation;
        }

        #endregion
    }
}
