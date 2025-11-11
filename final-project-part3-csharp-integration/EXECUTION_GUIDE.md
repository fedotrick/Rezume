# Execution Guide for Part 3: C# Integration

This guide provides step-by-step instructions for setting up and running the C# integration examples for the Portfolio Management System.

## Prerequisites Checklist

Before proceeding, ensure you have completed:

- ✅ **Part 1**: Database schema and stored procedures deployed
- ✅ **Part 2**: Triggers and views created (optional but recommended)
- ✅ **Sample Data**: At least 3 portfolios, 5 securities, and some transactions loaded
- ✅ **.NET 8.0 SDK**: Installed and accessible via `dotnet` command
- ✅ **SQL Server**: Running and accessible from your development machine

## Step 1: Environment Preparation

### 1.1 Verify .NET Installation

```bash
dotnet --version
```

Expected output: `8.0.x` or later

If not installed, download from: https://dotnet.microsoft.com/download

### 1.2 Verify Database Setup

Connect to your SQL Server instance using SSMS or sqlcmd and run:

```sql
USE PortfolioManagement;
GO

-- Check if Part 1 stored procedures exist
SELECT name FROM sys.procedures WHERE schema_id = SCHEMA_ID('dbo')
ORDER BY name;

-- Expected: sp_AddTransaction, sp_GetPortfolioAnalytics, sp_RebalancePortfolio, sp_GenerateReport, sp_UpdatePortfolioValue

-- Check if sample data exists
SELECT COUNT(*) AS PortfolioCount FROM dbo.Portfolios;
SELECT COUNT(*) AS SecurityCount FROM dbo.Securities;
SELECT COUNT(*) AS TransactionCount FROM dbo.Transactions;

-- All counts should be > 0 for meaningful testing
```

### 1.3 Test Database Connection

```bash
# Windows (Integrated Security)
sqlcmd -S localhost -d PortfolioManagement -Q "SELECT @@VERSION"

# Linux/macOS (SQL Authentication)
sqlcmd -S localhost -U sa -P YourPassword -d PortfolioManagement -Q "SELECT @@VERSION"
```

## Step 2: Configure Connection String

### Option A: Environment Variable (Recommended)

**Windows (PowerShell):**
```powershell
$env:PORTFOLIO_DB_CONNECTION="Server=localhost;Database=PortfolioManagement;Integrated Security=true;TrustServerCertificate=true;"
```

**Linux/macOS (Bash):**
```bash
export PORTFOLIO_DB_CONNECTION="Server=localhost;Database=PortfolioManagement;User Id=sa;Password=YourPassword;TrustServerCertificate=true;"
```

To make it permanent on Linux/macOS, add to `~/.bashrc` or `~/.zshrc`.

### Option B: Edit Program.cs

Open `src/Program.cs` and modify line 13:
```csharp
var connectionString = Environment.GetEnvironmentVariable("PORTFOLIO_DB_CONNECTION")
    ?? "Server=YOUR_SERVER;Database=PortfolioManagement;Integrated Security=true;TrustServerCertificate=true;";
```

## Step 3: Navigate to Project Directory

```bash
cd final-project-part3-csharp-integration
```

## Step 4: Restore NuGet Packages

```bash
dotnet restore
```

Expected output:
```
Restore completed in X ms for .../PortfolioManagement.csproj.
```

If you encounter network errors, configure a NuGet proxy or use a mirror.

## Step 5: Build the Project

```bash
dotnet build
```

Expected output:
```
Build succeeded.
    0 Warning(s)
    0 Error(s)
```

If build fails:
- Verify .NET SDK version
- Check for missing dependencies
- Ensure project file `PortfolioManagement.csproj` is present

## Step 6: Run the Application

```bash
dotnet run
```

You should see an interactive menu:

```
=== Portfolio Management Integration Examples ===
Available examples:
1 - Create portfolio and add transactions
2 - Get portfolio analytics
3 - Update quotes and recalculate value
4 - Rebalance portfolio
5 - Generate portfolio report
A - Run all examples sequentially

Select an option (default A):
```

### Running Individual Examples

Press the number corresponding to the example you want to run:
- `1` → Example 1: Create Portfolio and Add Transactions
- `2` → Example 2: Get Portfolio Analytics
- `3` → Example 3: Update Quotes and Recalculate Value
- `4` → Example 4: Rebalance Portfolio
- `5` → Example 5: Generate Portfolio Report
- `A` or Enter → Run all examples sequentially

### Expected Output for Example 1

```
=== Example 1: Create Portfolio and Add Transactions ===

Adding BUY transaction: 100 shares at $150.50
✓ Transaction added successfully! TransactionID: 123

Adding BUY transaction: 50 shares at $280.75
✓ Transaction added successfully! TransactionID: 124

Adding SELL transaction: 30 shares at $155.25
✓ Transaction added successfully! TransactionID: 125

=== Example 1 Completed ===
```

### Expected Output for Example 2

```
=== Example 2: Get Portfolio Analytics ===

Fetching analytics for Portfolio ID: 1
------------------------------------------------------------
Portfolio ID:              1
Total Value:               $25,450.75
Securities Held:           3
Distinct Security Types:   2
Total Transactions:        15
First Transaction Date:    2024-01-15
Last Transaction Date:     2024-11-11
Snapshot Date:             2024-11-11 14:23:45

Allocation by Type:
Type            Count   Net Quantity    Market Value  Allocation %
-------------------------------------------------------------------
Stock              2           120.00       15,230.00       59.87%
ETF                1            85.00       10,220.75       40.13%

Top Holdings:
Security                  Type       Quantity       Price    Market Value  Allocation %
---------------------------------------------------------------------------------------
Apple Inc.                Stock        100.00      152.30       15,230.00       59.87%
...
```

## Step 7: Verify Results in Database

After running examples, verify data changes:

```sql
-- Check newly added transactions
SELECT TOP 10 * FROM dbo.Transactions ORDER BY TransactionDate DESC;

-- Check audit log for trigger activity
SELECT TOP 10 * FROM dbo.Audit_Log ORDER BY ChangeDate DESC;

-- Check latest quotes
SELECT TOP 10 * FROM dbo.Quotes ORDER BY QuoteDate DESC;
```

## Troubleshooting

### Issue: "Connection could not be established"

**Symptoms:**
```
Unhandled exception. Microsoft.Data.SqlClient.SqlException (0x80131904):
A network-related or instance-specific error occurred...
```

**Solutions:**
1. Verify SQL Server is running:
   ```bash
   # Windows
   services.msc  # Check "SQL Server (MSSQLSERVER)"
   
   # Linux
   sudo systemctl status mssql-server
   ```

2. Check firewall allows SQL Server port (default 1433)

3. Verify TCP/IP is enabled:
   - Open SQL Server Configuration Manager
   - Navigate to "SQL Server Network Configuration" → "Protocols for MSSQLSERVER"
   - Ensure "TCP/IP" is enabled

4. Test connection string:
   ```bash
   sqlcmd -S localhost -d PortfolioManagement -Q "SELECT 1"
   ```

### Issue: "Invalid object name 'dbo.sp_AddTransaction'"

**Symptoms:**
```
SqlException: Could not find stored procedure 'dbo.sp_AddTransaction'.
```

**Solution:**
- Re-run Part 1 stored procedure creation script:
  ```bash
  sqlcmd -S localhost -d PortfolioManagement -i ../final-project-part1-db-procedures/scripts/final_project_part1_procedures.sql
  ```

### Issue: "The certificate chain was issued by an authority that is not trusted"

**Symptoms:**
```
SqlException: A connection was successfully established with the server, but then an error occurred...
```

**Solution:**
- Add `TrustServerCertificate=true;` to connection string (for development only)
- In production, use valid SSL certificates

### Issue: "Portfolio with ID X was not found"

**Symptoms:**
```
SqlException: Portfolio with ID 1 was not found.
```

**Solution:**
- Insert sample data from Part 1:
  ```bash
  sqlcmd -S localhost -d PortfolioManagement -i ../final-project-part1-db-procedures/scripts/final_project_part1_sample_data.sql
  ```

### Issue: Build Errors

**Symptoms:**
```
error CS0246: The type or namespace name 'Microsoft' could not be found
```

**Solution:**
1. Restore packages:
   ```bash
   dotnet clean
   dotnet restore
   ```

2. Ensure NuGet packages are downloaded:
   ```bash
   dotnet nuget locals all --clear
   dotnet restore
   ```

3. Verify .NET SDK compatibility:
   ```bash
   dotnet --list-sdks
   ```

## Running in Visual Studio

1. Open `PortfolioManagement.csproj` in Visual Studio 2022
2. Set connection string in `src/Program.cs` or environment variables
3. Press F5 to run with debugging
4. Output will appear in Console window

## Running in Visual Studio Code

1. Open folder in VS Code
2. Install "C# Dev Kit" extension if not already installed
3. Open `src/Program.cs`
4. Press F5 → Select ".NET Core" → Select "Console App"
5. Output appears in Debug Console

## Next Steps

After successfully running the examples:

1. **Explore the Code**: Review `src/Services/PortfolioManager.cs` and `src/Data/PortfolioRepository.cs`
2. **Modify Examples**: Change portfolio IDs, transaction amounts, etc.
3. **Create Your Own**: Write custom examples using the provided services
4. **Read Documentation**: Review `documentation/` folder for in-depth guides
5. **Performance Testing**: Run with larger datasets to test scalability

## Production Deployment Checklist

Before deploying to production:

- [ ] Use secure connection strings (encrypted, stored in Key Vault)
- [ ] Enable connection encryption (`Encrypt=True`)
- [ ] Configure proper connection pooling limits
- [ ] Implement health checks
- [ ] Add structured logging (Serilog, NLog, etc.)
- [ ] Implement retry policies for transient failures
- [ ] Set up monitoring and alerting
- [ ] Review and optimize stored procedure execution plans
- [ ] Test with production-like data volumes
- [ ] Implement proper error handling and user feedback

---

**Need Help?**

- Review [C# Integration Guide](documentation/CSHARP_INTEGRATION.md)
- Check [API Documentation](documentation/API_DOCUMENTATION.md)
- Refer to [Architecture Document](documentation/ARCHITECTURE.md)
- Review [Performance Metrics](documentation/PERFORMANCE.md)
