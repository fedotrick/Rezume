# Portfolio Management Stored Procedure Reference

This document describes the stored procedures provided in Parts 1 and 2 of the Final Project and shows how they are consumed by the C# integration layer introduced in Part 3.

All stored procedures reside in the `dbo` schema. Use `EXEC dbo.<ProcedureName>` when calling manually.

---

## 1. `sp_AddTransaction`

**Purpose:** Inserts a BUY or SELL transaction, validates inputs, and writes audit records.

**Signature:**
```sql
CREATE OR ALTER PROCEDURE dbo.sp_AddTransaction
    @PortfolioID     INT,
    @SecurityID      INT,
    @Quantity        DECIMAL(18,4),
    @Price           DECIMAL(18,4),
    @TransactionDate DATETIME2(0) = NULL,
    @Type            NVARCHAR(4),
    @Result          NVARCHAR(20) OUTPUT,
    @TransactionID   BIGINT OUTPUT
```

**Validation:**
- Portfolio and security must exist
- Quantity and price must be > 0
- Type must be `BUY` or `SELL`

**Result:**
- Inserts row into `Transactions`
- Creates audit entry in `Audit_Log`
- Returns `@TransactionID` and `@Result` (`SUCCESS`/`FAILED`)

**C# Usage:**
```csharp
var transaction = new Transaction { /* ... */ };
var result = await portfolioManager.AddTransactionAsync(transaction);
if (result.Success)
{
    Console.WriteLine($"Transaction ID: {result.TransactionId}");
}
```

**Error Handling:**
- Throws `SqlException` on validation errors
- Caught and logged in `PortfolioManager.AddTransactionAsync`

---

## 2. `sp_UpdatePortfolioValue`

**Purpose:** Calculates current market value for a portfolio using latest quotes.

**Signature:**
```sql
CREATE OR ALTER PROCEDURE dbo.sp_UpdatePortfolioValue
    @PortfolioID INT
```

**Result Set:**
| Column          | Type           | Description                                  |
|-----------------|----------------|----------------------------------------------|
| PortfolioID     | INT            | Portfolio identifier                          |
| PortfolioValue  | DECIMAL(38,4)  | Calculated market value                      |
| SnapshotDate    | DATETIME2(0)   | Timestamp of calculation                     |

**C# Usage:**
```csharp
var value = await portfolioManager.UpdatePortfolioValueAsync(portfolioId);
Console.WriteLine($"Portfolio value: {value:N2}");
```

**Notes:**
- Uses latest quote per security via OUTER APPLY
- Utilizes `OPTION (RECOMPILE)` for optimal plans

---

## 3. `sp_GetPortfolioAnalytics`

**Purpose:** Returns comprehensive analytics for a portfolio including totals, allocation, and holdings.

**Signature:**
```sql
CREATE OR ALTER PROCEDURE dbo.sp_GetPortfolioAnalytics
    @PortfolioID INT
```

**Result Sets:**
1. **Summary** (single row)
   | Column                  | Type           | Description                                  |
   |-------------------------|----------------|----------------------------------------------|
   | PortfolioID             | INT            | Portfolio identifier                          |
   | TotalValue              | DECIMAL(38,4)  | Total market value                           |
   | SecuritiesHeld          | INT            | Count of held securities                      |
   | DistinctSecurityTypes   | INT            | Count of distinct security types              |
   | TotalTransactions       | INT            | Total transactions                            |
   | FirstTransactionDate    | DATETIME2(0)   | Earliest transaction date                     |
   | LastTransactionDate     | DATETIME2(0)   | Latest transaction date                       |
   | SnapshotDate            | DATETIME2(0)   | Timestamp of analytics snapshot               |

2. **Allocation by Type** (rows per security type)
   | Column            | Type           |
   |-------------------|----------------|
   | SecurityType      | NVARCHAR(50)   |
   | SecuritiesCount   | INT            |
   | TotalNetQuantity  | DECIMAL(18,4)  |
   | TotalMarketValue  | DECIMAL(38,4)  |
   | AllocationPercent | DECIMAL(9,4)   |

3. **Holdings** (rows per security)
   | Column            | Type          |
   |-------------------|---------------|
   | SecurityID        | INT           |
   | SecurityName      | NVARCHAR(150) |
   | SecurityType      | NVARCHAR(50)  |
   | NetQuantity       | DECIMAL(18,4) |
   | CurrentPrice      | DECIMAL(18,4) |
   | MarketValue       | DECIMAL(38,4) |
   | AllocationPercent | DECIMAL(9,4)  |

**C# Usage:**
```csharp
var summary = await portfolioManager.GetPortfolioSummaryAsync(portfolioId);
foreach (var holding in summary.Holdings)
{
    Console.WriteLine($"{holding.SecurityName}: {holding.MarketValue:N2}");
}
```

**Notes:**
- Uses table variables and OUTER APPLY for latest prices
- Calculation excludes zero net quantity holdings

---

## 4. `sp_RebalancePortfolio`

**Purpose:** Generates a rebalancing plan based on target allocation JSON payload.

**Signature:**
```sql
CREATE OR ALTER PROCEDURE dbo.sp_RebalancePortfolio
    @PortfolioID      INT,
    @TargetAllocation NVARCHAR(MAX)
```

**Parameters:**
- `@TargetAllocation` is a JSON array such as:
  ```json
  [
    { "SecurityID": 1, "TargetPercent": 40.0 },
    { "SecurityID": 2, "TargetPercent": 35.0 },
    { "SecurityID": 3, "TargetPercent": 25.0 }
  ]
  ```

**Result Sets:**
1. **Plan Summary** (single row)
   | Column           | Description                         |
   |------------------|-------------------------------------|
   | PortfolioID      | Portfolio identifier                |
   | CurrentValue     | Current portfolio value             |
   | TargetValue      | Sum of target values                |
   | TotalBuyValue    | Total value recommended to buy      |
   | TotalSellValue   | Total value recommended to sell     |
   | NetInvestment    | Net cash required (buy - sell)      |
   | TargetCount      | Count of target allocation entries  |
   | HoldingsCount    | Count of existing holdings          |
   | GeneratedAt      | Timestamp of plan generation        |

2. **Action Plan** (rows per security)
   | Column            | Description                                         |
   |-------------------|-----------------------------------------------------|
   | SecurityID        | Security identifier                                 |
   | Ticker            | Security ticker                                     |
   | SecurityName      | Security name                                       |
   | TargetPercent     | Target allocation percentage                        |
   | CurrentPercent    | Current allocation percentage                       |
   | TargetValue       | Monetary value target                               |
   | CurrentValue      | Current monetary exposure                           |
   | QuantityToTrade   | Quantity to buy/sell (NULL if price missing)        |
   | ActionRequired    | `BUY`, `SELL`, `HOLD`, or `REVIEW`                   |
   | CurrentPrice      | Latest price used for calculations                  |

**C# Usage:**
```csharp
var targetAllocation = JsonSerializer.Serialize(new[] { ... });
await using var command = new SqlCommand("dbo.sp_RebalancePortfolio", connection)
{
    CommandType = CommandType.StoredProcedure
};
command.Parameters.Add(new SqlParameter("@TargetAllocation", SqlDbType.NVarChar, -1) { Value = targetAllocation });
```

**Notes:**
- Validates allocation sums to 100%
- Ensures referenced securities exist
- Provides actionable BUY/SELL quantities

---

## 5. `sp_GenerateReport`

**Purpose:** Generates a period performance report including transactions, cash flows, and ROI metrics.

**Signature:**
```sql
CREATE OR ALTER PROCEDURE dbo.sp_GenerateReport
    @PortfolioID INT,
    @StartDate   DATETIME2(0),
    @EndDate     DATETIME2(0)
```

**Result Sets:**
1. **Report Summary** (single row)
   | Column                 | Description                                    |
   |------------------------|------------------------------------------------|
   | PortfolioID            | Portfolio identifier                           |
   | PeriodStart            | Start of reporting period                      |
   | PeriodEnd              | End of reporting period                        |
   | TotalTransactions      | Count of transactions in period                |
   | TotalInvested          | Sum of BUY amounts                             |
   | TotalProceeds          | Sum of SELL amounts                            |
   | NetCashFlow            | Proceeds - Invested                            |
   | CurrentPortfolioValue  | Current market value                           |
   | RealizedPnL            | Net realized profit/loss                       |
   | ROI_Percent            | ROI based on invested capital                  |
   | GeneratedAt            | Timestamp of report generation                 |

2. **Transactions Detail** (rows per transaction)
   | Column          | Description                          |
   |-----------------|--------------------------------------|
   | TransactionID   | Transaction identifier               |
   | TransactionDate | Date/time of transaction             |
   | Ticker          | Security ticker                      |
   | SecurityName    | Security name                        |
   | Type            | `BUY` or `SELL`                      |
   | Quantity        | Quantity traded                      |
   | Price           | Trade price                          |
   | TransactionAmount | Quantity × Price                   |
   | CashFlow        | Positive (SELL) or negative (BUY)    |

3. **Operations Detail** (rows per operation)
   | Column        | Description                           |
   |---------------|---------------------------------------|
   | OperationID   | Operation identifier                  |
   | Description   | Operation description                 |
   | Amount        | Monetary amount                       |
   | OperationDate | Date/time of operation                |
   | Category      | Optional category label               |

**C# Usage:**
```csharp
await using var command = new SqlCommand("dbo.sp_GenerateReport", connection)
{
    CommandType = CommandType.StoredProcedure
};
command.Parameters.Add(new SqlParameter("@StartDate", SqlDbType.DateTime2) { Value = start });
command.Parameters.Add(new SqlParameter("@EndDate", SqlDbType.DateTime2) { Value = end });
var dataTable = new DataTable();
await using var reader = await command.ExecuteReaderAsync();
if (reader.HasRows) dataTable.Load(reader);
```

**Notes:**
- Validates period range and portfolio existence
- Uses table variables and calculated columns for ROI metrics

---

## Usage Guidelines

- Always use parameterized commands in C# integration to avoid SQL injection.
- Wrap stored procedure calls in `try/catch` to handle `SqlException`.
- For large result sets, stream data using `SqlDataReader` instead of `DataTable`.
- Ensure SQL Server permissions allow executing these stored procedures.

---

**Related Documents:**
- [Architecture](ARCHITECTURE.md)
- [C# Integration Guide](CSHARP_INTEGRATION.md)
- [Performance Report](PERFORMANCE.md)
