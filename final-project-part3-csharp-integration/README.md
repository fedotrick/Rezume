# Final Project Part 3: C# Integration and Documentation

## Portfolio Management System - .NET Integration

This is Part 3 of the Final Project for the Portfolio Management System. This part provides comprehensive C# integration examples using both ADO.NET and Entity Framework Core, along with complete project documentation.

## 📋 Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Components](#components)
- [Usage Examples](#usage-examples)
- [Configuration](#configuration)
- [Documentation](#documentation)
- [Best Practices](#best-practices)

## 🎯 Overview

Part 3 provides production-ready C# code that integrates with the SQL Server database created in Parts 1 and 2. It demonstrates:

- **ADO.NET integration** with stored procedures
- **Entity Framework Core** ORM implementation
- **Connection pooling** and resource management
- **Async/await patterns** for scalability
- **Error handling** and logging
- **CRUD operations** and complex queries
- **Performance optimization** techniques

## 📁 Project Structure

```
final-project-part3-csharp-integration/
├── src/
│   ├── Common/
│   │   └── ConnectionManager.cs         # Connection management and pooling
│   ├── Data/
│   │   ├── PortfolioDbContext.cs        # Entity Framework DbContext
│   │   └── PortfolioRepository.cs       # EF-based repository
│   ├── Models/
│   │   ├── Portfolio.cs                 # Portfolio entity
│   │   ├── PortfolioSummary.cs         # Analytics DTOs
│   │   ├── Transaction.cs               # Transaction entity
│   │   ├── Security.cs                  # Security entity
│   │   ├── Quote.cs                     # Quote entity
│   │   └── Operation.cs                 # Operation entity
│   ├── Services/
│   │   └── PortfolioManager.cs          # ADO.NET service layer
│   ├── Samples/
│   │   ├── Example1_CreatePortfolioAndAddTransactions.cs
│   │   ├── Example2_GetPortfolioAnalytics.cs
│   │   ├── Example3_UpdateQuotesAndRecalculateValue.cs
│   │   ├── Example4_RebalancePortfolio.cs
│   │   └── Example5_GenerateReport.cs
│   └── Program.cs                       # Main entry point
├── documentation/
│   ├── ARCHITECTURE.md                  # Database architecture details
│   ├── API_DOCUMENTATION.md            # Stored procedures reference
│   ├── CSHARP_INTEGRATION.md           # C# integration guide
│   └── PERFORMANCE.md                   # Performance metrics and optimization
├── PortfolioManagement.csproj           # Project file
└── README.md                            # This file
```

## 🔧 Prerequisites

### Required Software

- **.NET 8.0 SDK or later** - [Download](https://dotnet.microsoft.com/download)
- **SQL Server 2019 or later** (or SQL Server Express)
- **Visual Studio 2022** (recommended) or **Visual Studio Code** with C# extension

### Database Setup

Before running the C# application, you must have:

1. **Part 1 database schema** deployed (tables, indexes, constraints)
2. **Part 1 stored procedures** created (sp_AddTransaction, sp_GetPortfolioAnalytics, etc.)
3. **Part 2 triggers and views** created (optional but recommended)
4. **Sample data** loaded (recommended for testing)

## 🚀 Quick Start

### 1. Clone or Download

Navigate to the project directory:

```bash
cd final-project-part3-csharp-integration
```

### 2. Configure Connection String

Set the connection string as an environment variable:

**Windows (PowerShell):**
```powershell
$env:PORTFOLIO_DB_CONNECTION="Server=localhost;Database=PortfolioManagement;Integrated Security=true;TrustServerCertificate=true;"
```

**Linux/macOS (Bash):**
```bash
export PORTFOLIO_DB_CONNECTION="Server=localhost;Database=PortfolioManagement;User Id=sa;Password=YourPassword;TrustServerCertificate=true;"
```

Or edit `Program.cs` to set the connection string directly.

### 3. Restore Packages

```bash
dotnet restore
```

### 4. Build the Project

```bash
dotnet build
```

### 5. Run the Examples

```bash
dotnet run
```

You'll be presented with a menu to run individual examples or all examples sequentially.

## 🧩 Components

### ConnectionManager

The `ConnectionManager` class provides centralized connection management with built-in pooling support.

**Features:**
- Automatic connection pooling (enabled by default in SqlClient)
- Configurable pool sizes (default: min=5, max=100)
- IDisposable pattern for proper resource cleanup
- Configuration-based or manual connection string setup

**Usage:**
```csharp
using var connectionManager = new ConnectionManager(connectionString);
var connection = connectionManager.GetConnection();
```

### PortfolioManager (ADO.NET)

Service class for calling stored procedures using raw ADO.NET.

**Methods:**
- `GetPortfolioSummaryAsync(int portfolioId)` - Retrieves comprehensive analytics
- `AddTransactionAsync(Transaction transaction)` - Adds a buy/sell transaction
- `UpdatePortfolioValueAsync(int portfolioId)` - Recalculates portfolio value

**Advantages:**
- Maximum control over SQL execution
- Optimal performance for stored procedure calls
- Direct mapping to output parameters

### PortfolioRepository (Entity Framework)

Repository pattern implementation using Entity Framework Core.

**Methods:**
- Portfolio CRUD: `GetPortfolioByIdAsync`, `CreatePortfolioAsync`, etc.
- Security queries: `GetSecurityByTickerAsync`, `GetSecuritiesByTypeAsync`
- Transaction queries: `GetTransactionsByPortfolioAsync`
- Quote operations: `GetLatestQuoteAsync`, `BulkAddQuotesAsync`

**Advantages:**
- Strongly-typed LINQ queries
- Change tracking and automatic updates
- Navigation properties and eager loading
- Better for complex object graphs

### Models

All entity models match the database schema:
- `Portfolio`, `Security`, `Transaction`, `Quote`, `Operation`
- DTOs for stored procedure results: `PortfolioSummary`, `TransactionResult`

## 📚 Usage Examples

### Example 1: Add Transactions

Demonstrates adding buy/sell transactions using the `sp_AddTransaction` stored procedure.

```csharp
var transaction = new Transaction
{
    PortfolioId = 1,
    SecurityId = 1,
    Quantity = 100m,
    Price = 150.50m,
    Type = "BUY"
};

var result = await portfolioManager.AddTransactionAsync(transaction);
if (result.Success)
{
    Console.WriteLine($"Transaction ID: {result.TransactionId}");
}
```

### Example 2: Get Analytics

Retrieves and displays comprehensive portfolio analytics.

```csharp
var summary = await portfolioManager.GetPortfolioSummaryAsync(portfolioId);
Console.WriteLine($"Total Value: ${summary.TotalValue:N2}");
Console.WriteLine($"Securities Held: {summary.SecuritiesHeld}");
```

### Example 3: Update Quotes

Bulk uploads new quotes and triggers portfolio value recalculation.

```csharp
var quotes = new List<Quote> { /* ... */ };
await repository.BulkAddQuotesAsync(quotes);

var newValue = await portfolioManager.UpdatePortfolioValueAsync(portfolioId);
```

### Example 4: Rebalance Portfolio

Calls `sp_RebalancePortfolio` to generate an action plan for rebalancing.

```csharp
var targetAllocation = JsonSerializer.Serialize(new[]
{
    new { SecurityID = 1, TargetPercent = 40.0m },
    new { SecurityID = 2, TargetPercent = 35.0m },
    new { SecurityID = 3, TargetPercent = 25.0m }
});
```

### Example 5: Generate Report

Executes `sp_GenerateReport` and displays results in tabular format.

## ⚙️ Configuration

### Connection String Options

The connection string can be configured via:

1. **Environment variable**: `PORTFOLIO_DB_CONNECTION`
2. **appsettings.json** (add support via `IConfiguration`)
3. **Hard-coded** in `Program.cs` (not recommended for production)

### Connection Pooling Parameters

Default pooling settings (can be customized in `ConnectionStringBuilder`):
- **MinPoolSize**: 5
- **MaxPoolSize**: 100
- **ConnectionTimeout**: 30 seconds
- **MultipleActiveResultSets**: true

## 📖 Documentation

Comprehensive documentation is available in the `documentation/` folder:

- **[ARCHITECTURE.md](documentation/ARCHITECTURE.md)** - Database design and schema
- **[API_DOCUMENTATION.md](documentation/API_DOCUMENTATION.md)** - Stored procedures reference
- **[CSHARP_INTEGRATION.md](documentation/CSHARP_INTEGRATION.md)** - C# integration guide
- **[PERFORMANCE.md](documentation/PERFORMANCE.md)** - Performance metrics and optimization

## ✅ Best Practices

### 1. Always Use Parameterized Queries

All examples use parameterized queries to prevent SQL injection:
```csharp
command.Parameters.Add(new SqlParameter("@PortfolioID", SqlDbType.Int) { Value = portfolioId });
```

### 2. Use Async/Await for Scalability

All database operations are asynchronous:
```csharp
var summary = await portfolioManager.GetPortfolioSummaryAsync(portfolioId);
```

### 3. Proper Resource Disposal

Use `using` statements or `await using` for disposable resources:
```csharp
await using var connection = connectionManager.CreateConnection();
await connection.OpenAsync();
```

### 4. Structured Logging

Use `ILogger` for consistent logging:
```csharp
_logger?.LogInformation("Fetching portfolio summary for PortfolioID={PortfolioId}", portfolioId);
```

### 5. Error Handling

Always catch and handle `SqlException`:
```csharp
try
{
    await command.ExecuteNonQueryAsync();
}
catch (SqlException ex)
{
    _logger?.LogError(ex, "SQL error occurred");
    throw;
}
```

## 🔍 Testing

To test the examples:

1. **Ensure sample data exists** in your database (run Part 1 sample_data.sql)
2. **Run individual examples** to verify each component works
3. **Check the Audit_Log table** to see trigger activity
4. **Monitor performance** using SQL Server Profiler or DMVs

## 🛠 Troubleshooting

### Connection Issues

- Verify SQL Server is running
- Check firewall settings
- Ensure TCP/IP is enabled in SQL Server Configuration Manager
- Test connection string with `sqlcmd` or SQL Server Management Studio

### Build Errors

- Ensure .NET 8.0 SDK is installed: `dotnet --version`
- Restore packages: `dotnet restore`
- Clean and rebuild: `dotnet clean && dotnet build`

### Runtime Errors

- Check that all Part 1 stored procedures exist
- Verify database schema matches expected structure
- Review logs for detailed error messages

## 📄 License

This project is part of the SQL Server training final project.

## 🤝 Contributing

This is a training project. Feel free to extend it for your own learning purposes.

## 📧 Contact

For questions or issues related to this project, please refer to the course materials or contact your instructor.

---

**Related Projects:**
- [Part 1: Database Schema and Procedures](../final-project-part1-db-procedures/)
- [Part 2: Triggers, Views, and Queries](../final-project-part2-triggers-views-queries/)
