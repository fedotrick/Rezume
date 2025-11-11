# Portfolio Management System Architecture

## Overview

This document describes the architecture of the Portfolio Management System database and its integration with the C#/.NET application. The database was designed in Part 1 of the final project and extended in Part 2 with triggers, views, and analytical procedures. Part 3 adds C# integration.

## ER Diagram

The logical ER structure comprises the following entities:

```
Portfolios (1) ───────< Transactions >─────── (1) Securities
      │                                      │
      │                                      └──< Quotes
      └──< Operations

Transactions ───< Audit_Log (captured via triggers)
```

### Entities

| Table        | Description                                      |
|--------------|--------------------------------------------------|
| Portfolios   | Root entity representing an investment portfolio |
| Securities   | Reference data for traded instruments            |
| Transactions | Buy/Sell transactions (child of Portfolios)      |
| Quotes       | Market price snapshots per security              |
| Operations   | Cash operations / portfolio-level events         |
| Audit_Log    | Change log populated by triggers                 |

### Relationships

- **Portfolios ↔ Transactions**: One-to-many (cascade delete)
- **Portfolios ↔ Operations**: One-to-many (cascade delete)
- **Securities ↔ Transactions**: One-to-many
- **Securities ↔ Quotes**: One-to-many (cascade delete)
- **Audit_Log** contains metadata about changes across all tables

## Schema Highlights

### Portfolios

- `PortfolioID` (PK, identity)
- Unique constraint on (`Owner`, `Name`)
- Default `CreatedDate` with UTC timestamp

### Securities

- `SecurityID` (PK, identity)
- Unique ticker code
- Type constrained to (`Stock`, `Bond`, `ETF`, `Fund`, `Other`)
- Sector column for reporting

### Transactions

- `TransactionID` (PK, big identity)
- Foreign keys to `Portfolios` and `Securities`
- Positive quantity/price constraints
- Type restricted to `BUY` or `SELL`
- Default UTC transaction date
- Indexed by `(PortfolioID, TransactionDate DESC)` for history retrieval

### Quotes

- Unique constraint on (`SecurityID`, `QuoteDate`)
- Latest quote retrieval supported through indexes and window functions

### Operations

- Captures cash flows, fees, dividends, etc.
- Amount must be non-zero

### Audit_Log

- Captures table name, action, old/new values (JSON), change date, user
- Populated via triggers defined in Part 2

## Normalization Justification

- **3rd Normal Form**: Entities are separated to avoid redundancy
- **Transactions** store only numeric values, relying on reference tables for metadata
- **Quotes** store time-series data independently for performance
- **Audit_Log** stores JSON payloads to keep main tables lean

## Indexing Strategy

| Table        | Index                                      | Purpose                                |
|--------------|--------------------------------------------|----------------------------------------|
| Securities   | `(Sector, Type)`                           | Filtering by sector/type               |
| Portfolios   | `(Owner)`                                  | Quick access by owner                  |
| Transactions | `(PortfolioID, TransactionDate DESC)`      | Portfolio history, analytics           |
| Transactions | `(SecurityID, TransactionDate DESC)`       | Security-level activity                |
| Quotes       | `(SecurityID, QuoteDate DESC)`             | Latest quote retrieval                 |
| Operations   | `(PortfolioID, OperationDate DESC)`        | Cash flow statements                   |
| Audit_Log    | `(TableName, ChangeDate DESC)`             | Efficient auditing/reporting           |

## Architecture Layers

1. **Database Layer** (Parts 1 & 2)
   - Tables, indexes, constraints
   - Stored procedures (`sp_AddTransaction`, `sp_GetPortfolioAnalytics`, etc.)
   - Triggers (audit logs, validation, portfolio updates)
   - Views for reporting (portfolio summary, performance, rankings)

2. **Service Layer** (Part 3 - ADO.NET)
   - `PortfolioManager` executes stored procedures
   - Handles output parameters, result sets, and error handling

3. **Repository Layer** (Part 3 - Entity Framework Core)
   - `PortfolioDbContext` maps tables to C# entities
   - `PortfolioRepository` exposes CRUD, filtering, and lazy/eager loading

4. **Presentation / Samples**
   - `Program.cs` interactive console menu
   - Demo workflows showcasing transactions, analytics, rebalancing, reporting

## Data Flow

1. **Transaction Ingestion**
   - Calls to `sp_AddTransaction` insert rows into `Transactions`
   - Trigger logs inserts into `Audit_Log`

2. **Quote Updates**
   - Insert into `Quotes`
   - Trigger recalculates portfolio values (`trg_UpdatePortfolioValue_OnQuoteChange`)

3. **Analytics Retrieval**
   - `sp_GetPortfolioAnalytics` returns three result sets: portfolio summary, allocation by type, and holding-level detail

4. **Rebalancing**
   - `sp_RebalancePortfolio` accepts JSON allocation targets, returning portfolio summary and action plan result sets

## Technology Stack

| Component               | Technology                                |
|-------------------------|-------------------------------------------|
| Database                | SQL Server 2019+                          |
| Integration             | .NET 8.0 (C#)                             |
| ADO.NET Provider        | Microsoft.Data.SqlClient                  |
| ORM                     | Entity Framework Core 8                   |
| Logging                 | Microsoft.Extensions.Logging.Console      |
| Serialization           | System.Text.Json                          |

## Deployment Considerations

- **Environment configuration** via `IConfiguration` and environment variables
- **Connection pooling** tuned for 10–100 concurrent connections
- **Locking/Isolation**: default isolation level `READ COMMITTED`
- **Security**:
  - Use integrated security where possible
  - Encrypt connections in production (`Encrypt=True`)
  - Use application roles for limited access

## Extension Points

- Add **REST API layer** (ASP.NET Core) using repositories
- Integrate **background services** for daily quote ingestion
- Extend **reporting** by leveraging SQL Server Reporting Services
- Implement **unit tests** with EF Core in-memory provider for repository testing

---

**Related documents:**
- [API Documentation](API_DOCUMENTATION.md)
- [C# Integration Guide](CSHARP_INTEGRATION.md)
- [Performance Report](PERFORMANCE.md)
