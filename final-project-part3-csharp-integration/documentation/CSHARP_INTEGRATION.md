# C# Integration Guide

This guide explains how to integrate the Portfolio Management System database (Parts 1 & 2) with .NET applications. It covers both ADO.NET and Entity Framework Core approaches, configuration, error handling, and best practices.

## Table of Contents

- [Connection String Configuration](#connection-string-configuration)
- [Using ConnectionManager](#using-connectionmanager)
- [ADO.NET Integration (PortfolioManager)](#adonet-integration-portfoliomanager)
- [Entity Framework Integration (PortfolioRepository)](#entity-framework-integration-portfoliorepository)
- [Error Handling](#error-handling)
- [Performance Considerations](#performance-considerations)
- [Best Practices](#best-practices)
- [Deployment to Production](#deployment-to-production)

---

## Connection String Configuration

### Option 1: Environment Variable (Recommended)

Set the `PORTFOLIO_DB_CONNECTION` environment variable:

**Windows (PowerShell):**
```powershell
$env:PORTFOLIO_DB_CONNECTION="Server=localhost;Database=PortfolioManagement;Integrated Security=true;TrustServerCertificate=true;"
```

**Linux/macOS (Bash):**
```bash
export PORTFOLIO_DB_CONNECTION="Server=localhost;Database=PortfolioManagement;User Id=sa;Password=YourPassword;TrustServerCertificate=true;"
```

In your C# code:
```csharp
var connectionString = Environment.GetEnvironmentVariable("PORTFOLIO_DB_CONNECTION")
    ?? throw new InvalidOperationException("Connection string not configured.");
```

### Option 2: appsettings.json

Create `appsettings.json`:
```json
{
  "ConnectionStrings": {
    "PortfolioDb": "Server=localhost;Database=PortfolioManagement;Integrated Security=true;TrustServerCertificate=true;"
  }
}
```

Load in your code:
```csharp
var configuration = new ConfigurationBuilder()
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", optional: false)
    .Build();

var connectionString = configuration.GetConnectionString("PortfolioDb");
```

### Option 3: Connection String Builder

Programmatically build the connection string:
```csharp
var connectionString = ConnectionStringBuilder.Build(
    server: "localhost",
    database: "PortfolioManagement",
    integratedSecurity: true,
    minPoolSize: 10,
    maxPoolSize: 100,
    connectionTimeout: 30,
    encrypt: true,
    trustServerCertificate: true
);
```

### Recommended Connection String Parameters

| Parameter                  | Value       | Purpose                                      |
|----------------------------|-------------|----------------------------------------------|
| Pooling                    | true        | Enable connection pooling (default)          |
| Min Pool Size              | 5–10        | Minimum connections in pool                  |
| Max Pool Size              | 50–100      | Maximum connections in pool                  |
| Connection Timeout         | 30          | Seconds before connection attempt fails      |
| MultipleActiveResultSets   | true        | Allow multiple result sets per connection    |
| Encrypt                    | true        | Encrypt connection (recommended)             |
| TrustServerCertificate     | true/false  | Trust server certificate (dev: true)         |

---

## Using ConnectionManager

The `ConnectionManager` class simplifies database connection management.

### Basic Usage

```csharp
using var connectionManager = new ConnectionManager(connectionString);
var connection = connectionManager.GetConnection();
```

### IDisposable Pattern

`ConnectionManager` implements `IDisposable`:
```csharp
using (var connectionManager = new ConnectionManager(connectionString))
{
    var connection = connectionManager.GetConnection();
    // Use connection
} // Automatically disposed
```

### Configuration-Based Construction

```csharp
var connectionManager = new ConnectionManager(configuration, "PortfolioDb");
```

### Creating Short-Lived Connections

For one-off operations, create new connections:
```csharp
await using var connection = connectionManager.CreateConnection();
await connection.OpenAsync();
// Use connection
```

---

## ADO.NET Integration (PortfolioManager)

The `PortfolioManager` class uses raw ADO.NET to call stored procedures.

### Setup

```csharp
using var connectionManager = new ConnectionManager(connectionString);
var portfolioManager = new PortfolioManager(connectionManager, logger);
```

### Adding a Transaction

```csharp
var transaction = new Transaction
{
    PortfolioId = 1,
    SecurityId = 1,
    Quantity = 100m,
    Price = 150.50m,
    TransactionDate = DateTime.UtcNow,
    Type = "BUY",
    Notes = "Initial purchase"
};

var result = await portfolioManager.AddTransactionAsync(transaction);

if (result.Success)
{
    Console.WriteLine($"Success! Transaction ID: {result.TransactionId}");
}
else
{
    Console.WriteLine($"Failed: {result.Message}");
}
```

**Key Points:**
- `sp_AddTransaction` returns `@Result` and `@TransactionID` as output parameters
- The method returns a `TransactionResult` DTO
- Validation errors are caught and returned in `Message`

### Retrieving Portfolio Summary

```csharp
var summary = await portfolioManager.GetPortfolioSummaryAsync(portfolioId);

Console.WriteLine($"Total Value: ${summary.TotalValue:N2}");
Console.WriteLine($"Securities Held: {summary.SecuritiesHeld}");

foreach (var holding in summary.Holdings.OrderByDescending(h => h.MarketValue).Take(10))
{
    Console.WriteLine($"{holding.SecurityName}: ${holding.MarketValue:N2} ({holding.AllocationPercent:N2}%)");
}
```

**Key Points:**
- `sp_GetPortfolioAnalytics` returns 3 result sets
- Use `await reader.NextResultAsync()` to move between result sets
- DTOs map column names to C# properties

### Updating Portfolio Value

```csharp
var newValue = await portfolioManager.UpdatePortfolioValueAsync(portfolioId);
Console.WriteLine($"Updated portfolio value: ${newValue:N2}");
```

---

## Entity Framework Integration (PortfolioRepository)

The `PortfolioRepository` class uses EF Core for object-relational mapping.

### Setup DbContext

```csharp
var optionsBuilder = new DbContextOptionsBuilder<PortfolioDbContext>();
optionsBuilder.UseSqlServer(connectionString);

await using var context = new PortfolioDbContext(optionsBuilder.Options);
var repository = new PortfolioRepository(context, logger);
```

### Dependency Injection (recommended)

In `Startup.cs` or `Program.cs`:
```csharp
services.AddDbContext<PortfolioDbContext>(options =>
    options.UseSqlServer(configuration.GetConnectionString("PortfolioDb")));

services.AddScoped<PortfolioRepository>();
```

### Querying Portfolios

```csharp
// Get by ID with navigation properties
var portfolio = await repository.GetPortfolioByIdAsync(1, includeTransactions: true);

// Get all portfolios for an owner
var portfolios = await repository.GetPortfoliosByOwnerAsync("john.doe@example.com");

// Paginated query
var allPortfolios = await repository.GetAllPortfoliosAsync(skip: 0, take: 50);
```

### Creating Entities

```csharp
var newPortfolio = new Portfolio
{
    Name = "Retirement Portfolio",
    Owner = "jane.smith@example.com",
    Description = "Long-term retirement investments"
};

var created = await repository.CreatePortfolioAsync(newPortfolio);
Console.WriteLine($"Created portfolio with ID: {created.PortfolioID}");
```

### Querying Securities

```csharp
// Get by ticker
var security = await repository.GetSecurityByTickerAsync("AAPL");

// Get by type
var stocks = await repository.GetSecuritiesByTypeAsync("Stock");

// Get by sector
var techStocks = await repository.GetSecuritiesBySectorAsync("Technology");
```

### Transactions and Quotes

```csharp
// Get transactions for a portfolio
var transactions = await repository.GetTransactionsByPortfolioAsync(
    portfolioId: 1,
    startDate: DateTime.UtcNow.AddMonths(-1),
    endDate: DateTime.UtcNow,
    type: "BUY"
);

// Get latest quote
var latestQuote = await repository.GetLatestQuoteAsync(securityId: 1);

// Bulk add quotes
var quotes = new List<Quote>
{
    new Quote { SecurityID = 1, Price = 152.30m, QuoteDate = DateTime.UtcNow, Volume = 25000000, Source = "API" },
    // ... more quotes
};
await repository.BulkAddQuotesAsync(quotes);
```

---

## Error Handling

### Catching SqlException

Always wrap database calls in `try/catch` and handle `SqlException`:

```csharp
try
{
    var summary = await portfolioManager.GetPortfolioSummaryAsync(portfolioId);
}
catch (SqlException ex)
{
    logger.LogError(ex, "Database error occurred: {Message}", ex.Message);
    
    switch (ex.Number)
    {
        case 2: // Connection timeout
        case 53:
            Console.WriteLine("Unable to connect to database. Check connection string.");
            break;
        case 547: // Foreign key violation
            Console.WriteLine("Referenced entity does not exist.");
            break;
        case 2627: // Unique constraint violation
        case 2601:
            Console.WriteLine("Duplicate value detected.");
            break;
        default:
            Console.WriteLine($"Database error: {ex.Message}");
            break;
    }
}
catch (Exception ex)
{
    logger.LogError(ex, "Unexpected error: {Message}", ex.Message);
}
```

### Handling RAISERROR from Stored Procedures

When a stored procedure executes `RAISERROR`, it throws `SqlException`:

```csharp
try
{
    var result = await portfolioManager.AddTransactionAsync(transaction);
}
catch (SqlException ex) when (ex.Number == 50000) // User-defined error
{
    Console.WriteLine($"Validation error: {ex.Message}");
}
```

### Entity Framework Exceptions

```csharp
try
{
    await repository.CreatePortfolioAsync(portfolio);
}
catch (DbUpdateException ex)
{
    if (ex.InnerException is SqlException sqlEx)
    {
        if (sqlEx.Number == 2627 || sqlEx.Number == 2601)
        {
            Console.WriteLine("Duplicate portfolio name for this owner.");
        }
    }
}
```

---

## Performance Considerations

### Use Async/Await

Always use async methods for database operations:
```csharp
var summary = await portfolioManager.GetPortfolioSummaryAsync(portfolioId);
```

Benefits:
- Frees up threads while waiting on I/O
- Improves application scalability
- Essential for web applications under load

### Connection Pooling

Connection pooling is enabled by default. Best practices:
- **Do not disable pooling** unless you have a specific reason
- Set `Min Pool Size` based on expected concurrent load
- Set `Max Pool Size` to prevent connection exhaustion
- Use `using` statements to return connections to the pool promptly

### Batch Operations

For bulk inserts:
```csharp
var quotes = GenerateQuotes(count: 10000);
await repository.BulkAddQuotesAsync(quotes);
```

EF Core will batch these into multiple `INSERT` statements automatically.

### Avoid SELECT N+1

Use `.Include()` to eagerly load related data:
```csharp
// Bad: N+1 queries
var portfolios = await context.Portfolios.ToListAsync();
foreach (var portfolio in portfolios)
{
    var transactions = portfolio.Transactions.ToList(); // Separate query each time
}

// Good: Single query with JOIN
var portfolios = await context.Portfolios
    .Include(p => p.Transactions)
    .ToListAsync();
```

### Execute Raw SQL When Needed

For complex queries or performance-critical operations, use raw SQL:
```csharp
var results = await context.Portfolios
    .FromSqlRaw("EXEC dbo.sp_GetPortfolioAnalytics @PortfolioID = {0}", portfolioId)
    .ToListAsync();
```

---

## Best Practices

### 1. Always Use Parameterized Queries

Never concatenate user input into SQL strings:
```csharp
// NEVER do this:
var command = new SqlCommand($"SELECT * FROM Portfolios WHERE Owner = '{owner}'");

// ALWAYS do this:
var command = new SqlCommand("SELECT * FROM Portfolios WHERE Owner = @Owner");
command.Parameters.Add(new SqlParameter("@Owner", SqlDbType.NVarChar) { Value = owner });
```

### 2. Dispose Resources Properly

Use `using` or `await using`:
```csharp
await using var connection = connectionManager.CreateConnection();
await connection.OpenAsync();
// Use connection
// Automatically disposed when scope exits
```

### 3. Use ILogger for Logging

Inject `ILogger` and log key events:
```csharp
_logger?.LogInformation("Fetching portfolio summary for PortfolioID={PortfolioId}", portfolioId);
```

### 4. Handle NULL Values

Check for `DBNull.Value` when reading from `SqlDataReader`:
```csharp
var description = reader.IsDBNull(reader.GetOrdinal("Description"))
    ? null
    : reader.GetString(reader.GetOrdinal("Description"));
```

### 5. Test with Real Data Volumes

Ensure your queries perform well with production-like data volumes. Test with 10k+, 100k+, 1M+ rows.

### 6. Use Transactions for Multi-Step Operations

```csharp
await using var transaction = await context.Database.BeginTransactionAsync();
try
{
    await repository.CreatePortfolioAsync(portfolio);
    await repository.AddOperationAsync(operation);
    await transaction.CommitAsync();
}
catch
{
    await transaction.RollbackAsync();
    throw;
}
```

### 7. Validate Input Before Calling Database

Check inputs in application code to reduce round-trips:
```csharp
if (transaction.Quantity <= 0)
{
    return new TransactionResult { Success = false, Message = "Quantity must be positive." };
}
```

---

## Deployment to Production

### 1. Connection String Security

- **Never hard-code credentials** in source code
- Use environment variables, Azure Key Vault, AWS Secrets Manager, or similar
- Encrypt connection strings in configuration files

### 2. Enable Encryption

Set `Encrypt=True` in production connection strings:
```
Server=prod.database.windows.net;Database=PortfolioManagement;User Id=produser;Password=***;Encrypt=True;TrustServerCertificate=False;
```

### 3. Connection Pooling Tuning

Monitor connection pool metrics and adjust:
- `Min Pool Size`: Set to expected minimum concurrent load
- `Max Pool Size`: Set to maximum tolerable connections (often 50-200)

### 4. Enable Logging

Configure logging to capture SQL errors:
```csharp
builder.Services.AddLogging(config =>
{
    config.AddConsole();
    config.AddApplicationInsights();
    config.SetMinimumLevel(LogLevel.Information);
});
```

### 5. Health Checks

Implement health checks for database connectivity:
```csharp
services.AddHealthChecks()
    .AddSqlServer(
        connectionString: configuration.GetConnectionString("PortfolioDb"),
        name: "portfolio-db",
        timeout: TimeSpan.FromSeconds(5)
    );
```

### 6. Retry Policies

Implement retry logic for transient failures:
```csharp
services.AddDbContext<PortfolioDbContext>(options =>
    options.UseSqlServer(
        connectionString,
        sqlOptions => sqlOptions.EnableRetryOnFailure(
            maxRetryCount: 3,
            maxRetryDelay: TimeSpan.FromSeconds(5),
            errorNumbersToAdd: null
        )
    )
);
```

---

## Summary

- Use `ConnectionManager` for managing database connections with pooling.
- `PortfolioManager` (ADO.NET) provides direct access to stored procedures for optimal performance.
- `PortfolioRepository` (EF Core) provides strongly-typed CRUD and LINQ queries.
- Always use async/await, parameterized queries, and proper error handling.
- Test with realistic data volumes and monitor performance in production.

---

**Related Documents:**
- [Architecture](ARCHITECTURE.md)
- [API Documentation](API_DOCUMENTATION.md)
- [Performance Report](PERFORMANCE.md)
