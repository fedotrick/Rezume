/*
    Final Project Part 2: Portfolio Management System
    Examples and Test Cases
    ------------------------------------------------
    This script demonstrates how to use the triggers, views, and queries
    created in Part 2. All examples assume Part 1 database schema and 
    sample data have been created.
*/

SET XACT_ABORT ON;
GO

PRINT '====================================================================';
PRINT 'PART 2: TRIGGERS, VIEWS, AND QUERIES - EXAMPLES';
PRINT '====================================================================';
GO

/* ============================================================================
   SECTION 1: TRIGGER EXAMPLES
   ============================================================================
*/

PRINT '';
PRINT '--- SECTION 1: TRIGGER EXAMPLES ---';
GO

-- Example 1: Inserting a transaction to demonstrate audit logging
PRINT '';
PRINT 'Example 1.1: Testing trg_ValidateTransaction (INSERT with validation)';
GO

BEGIN TRY
    INSERT INTO dbo.Transactions (PortfolioID, SecurityID, Quantity, Price, Type, Notes)
    VALUES (1, 1, 100, 150.50, N'BUY', N'Test transaction with validation');
    
    PRINT 'Transaction inserted successfully via trigger validation.';
END TRY
BEGIN CATCH
    PRINT 'ERROR: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Example 2: Check audit log for transaction activity
PRINT '';
PRINT 'Example 1.2: Viewing Audit Log for Transactions';
GO

SELECT TOP 20
    LogID,
    TableName,
    Action,
    LEFT(NewValue, 100) AS NewValuePreview,
    LEFT(OldValue, 100) AS OldValuePreview,
    ChangeDate,
    ExecutedBy
FROM dbo.Audit_Log
WHERE TableName = 'Transactions'
ORDER BY LogID DESC;
GO

-- Example 3: Test quote update and portfolio value recalculation
PRINT '';
PRINT 'Example 1.3: Testing trg_UpdatePortfolioValue_OnQuoteChange (Quote price update)';
GO

DECLARE @NewPrice DECIMAL(18,4) = 155.75;
DECLARE @SecurityID INT = 1;
DECLARE @NewQuoteID BIGINT;

BEGIN TRY
    INSERT INTO dbo.Quotes (SecurityID, Price, QuoteDate, Volume, Source)
    VALUES (@SecurityID, @NewPrice, SYSUTCDATETIME(), 1000000, N'Example Source');
    
    SET @NewQuoteID = SCOPE_IDENTITY();
    
    PRINT 'Quote inserted successfully. Quote price updated to: $' + 
          CAST(@NewPrice AS NVARCHAR(MAX)) + ' for Security ID: ' + 
          CAST(@SecurityID AS NVARCHAR(MAX));
    
    -- Check audit log for quote update
    SELECT TOP 5
        LogID,
        TableName,
        Action,
        ChangeDate,
        ExecutedBy
    FROM dbo.Audit_Log
    WHERE TableName = 'Quotes'
    ORDER BY LogID DESC;
    
END TRY
BEGIN CATCH
    PRINT 'ERROR: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Example 4: Attempt invalid transaction (negative quantity)
PRINT '';
PRINT 'Example 1.4: Testing validation with invalid data (should fail)';
GO

BEGIN TRY
    INSERT INTO dbo.Transactions (PortfolioID, SecurityID, Quantity, Price, Type, Notes)
    VALUES (1, 1, -50, 150.50, N'BUY', N'Invalid - negative quantity');
    
    PRINT 'Transaction inserted (should not reach here if validation works).';
END TRY
BEGIN CATCH
    PRINT 'Expected validation error: ' + ERROR_MESSAGE();
END CATCH;
GO

/* ============================================================================
   SECTION 2: VIEW EXAMPLES
   ============================================================================
*/

PRINT '';
PRINT '--- SECTION 2: VIEW EXAMPLES ---';
GO

-- Example 2.1: Portfolio Summary
PRINT '';
PRINT 'Example 2.1: Portfolio Summary View';
GO

SELECT
    PortfolioID,
    PortfolioName,
    Owner,
    TotalValue,
    SecurityCount,
    PositionCount,
    LastUpdate,
    CreatedDate
FROM dbo.vw_PortfolioSummary
ORDER BY TotalValue DESC;
GO

-- Example 2.2: Portfolio Composition
PRINT '';
PRINT 'Example 2.2: Portfolio Composition View (Portfolio ID 1)';
GO

SELECT
    PortfolioID,
    Ticker,
    Name,
    Type,
    CurrentPrice,
    Quantity,
    TotalValue,
    CAST(Percentage AS DECIMAL(5,2)) AS Percentage
FROM dbo.vw_PortfolioComposition
WHERE PortfolioID = 1
ORDER BY TotalValue DESC;
GO

-- Example 2.3: Portfolio Performance
PRINT '';
PRINT 'Example 2.3: Portfolio Performance View';
GO

SELECT
    PortfolioID,
    PortfolioName,
    Owner,
    CurrentValue,
    TotalInvestment,
    ProfitLoss,
    CAST(ReturnPercentage AS DECIMAL(8,2)) AS ReturnPercentage,
    TransactionCount,
    LastTransactionDate
FROM dbo.vw_PortfolioPerformance
WHERE TotalInvestment > 0
ORDER BY ReturnPercentage DESC;
GO

-- Example 2.4: Security Ranking
PRINT '';
PRINT 'Example 2.4: Security Ranking View (Top 10 Most Traded)';
GO

SELECT TOP 10
    SecurityID,
    Ticker,
    Name,
    Type,
    Sector,
    CAST(AvgPrice AS DECIMAL(10,2)) AS AvgPrice,
    CAST(MinPrice AS DECIMAL(10,2)) AS MinPrice,
    CAST(MaxPrice AS DECIMAL(10,2)) AS MaxPrice,
    TradeCount,
    PortfoliosContaining,
    TotalVolume,
    LastQuoteDate
FROM dbo.vw_SecurityRanking
WHERE TradeCount > 0
ORDER BY TradeCount DESC;
GO

/* ============================================================================
   SECTION 3: OPTIMIZED QUERY EXAMPLES
   ============================================================================
*/

PRINT '';
PRINT '--- SECTION 3: OPTIMIZED QUERY EXAMPLES ---';
GO

-- Example 3.1: Moving Averages
PRINT '';
PRINT 'Example 3.1: Moving Average Prices (Last 30 days)';
GO

SELECT TOP 30
    Ticker,
    Name,
    QuoteDate,
    Price,
    CAST(MA7 AS DECIMAL(10,2)) AS MA7,
    CAST(MA30 AS DECIMAL(10,2)) AS MA30,
    PriceTrendVsMA7,
    CAST(PricePctChange AS DECIMAL(8,4)) AS PricePctChange
FROM dbo.vw_SecurityMovingAverage
WHERE RowNum <= 30
ORDER BY Ticker, QuoteDate DESC;
GO

-- Example 3.2: Portfolio Hierarchy
PRINT '';
PRINT 'Example 3.2: Portfolio Transaction Hierarchy';
GO

SELECT
    PortfolioID,
    PortfolioName,
    Owner,
    SecurityCount,
    TransactionCount,
    BuyCount,
    SellCount,
    CAST(TotalInvested AS DECIMAL(12,2)) AS TotalInvested,
    CAST(TotalReturns AS DECIMAL(12,2)) AS TotalReturns,
    CAST(ROI_Percentage AS DECIMAL(8,2)) AS ROI_Percentage,
    FirstTransactionDate,
    LastTransactionDate
FROM dbo.vw_PortfolioTransactionHierarchy
ORDER BY ROI_Percentage DESC;
GO

-- Example 3.3: Complete Portfolio Information
PRINT '';
PRINT 'Example 3.3: Complete Portfolio Information (Sample)';
GO

SELECT TOP 20
    PortfolioID,
    PortfolioName,
    Ticker,
    SecurityName,
    TransactionType,
    Quantity,
    CAST(TransactionPrice AS DECIMAL(10,2)) AS TransactionPrice,
    CAST(CurrentPrice AS DECIMAL(10,2)) AS CurrentPrice,
    CAST(CurrentPositionValue AS DECIMAL(12,2)) AS CurrentPositionValue,
    CAST(UnrealizedGainLoss AS DECIMAL(12,2)) AS UnrealizedGainLoss,
    TransactionDate
FROM dbo.vw_CompletePortfolioInfo
WHERE Ticker IS NOT NULL
ORDER BY PortfolioID, TransactionDate DESC;
GO

-- Example 3.4: Batch Processing
PRINT '';
PRINT 'Example 3.4: Batch Processing Example (Process all transactions)';
GO

BEGIN TRY
    EXEC dbo.sp_BatchProcessTransactions 
        @BatchSize = 5000,
        @MaxBatches = 10;
END TRY
BEGIN CATCH
    PRINT 'Error during batch processing: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Example 3.5: Top Portfolios by ROI
PRINT '';
PRINT 'Example 3.5: Top 10 Portfolios by ROI';
GO

SELECT
    ROI_Rank,
    PortfolioID,
    PortfolioName,
    Owner,
    HoldingCount,
    TransactionCount,
    CAST(TotalInvested AS DECIMAL(12,2)) AS TotalInvested,
    CAST(CurrentValue AS DECIMAL(12,2)) AS CurrentValue,
    CAST(TotalProfitLoss AS DECIMAL(12,2)) AS TotalProfitLoss,
    CAST(ROI_Percentage AS DECIMAL(8,2)) AS ROI_Percentage,
    DaysActive
FROM dbo.vw_TopPortfoliosByROI
ORDER BY ROI_Rank;
GO

/* ============================================================================
   SECTION 4: PERFORMANCE ANALYSIS - QUERY EXECUTION
   ============================================================================
*/

PRINT '';
PRINT '--- SECTION 4: PERFORMANCE ANALYSIS ---';
GO

-- Enable statistics for performance monitoring
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

PRINT '';
PRINT 'Performance Test: vw_PortfolioSummary';
GO

SELECT * FROM dbo.vw_PortfolioSummary;
GO

PRINT '';
PRINT 'Performance Test: vw_PortfolioComposition';
GO

SELECT * FROM dbo.vw_PortfolioComposition WHERE PortfolioID = 1;
GO

PRINT '';
PRINT 'Performance Test: vw_SecurityMovingAverage';
GO

SELECT TOP 50 * FROM dbo.vw_SecurityMovingAverage;
GO

PRINT '';
PRINT 'Performance Test: vw_TopPortfoliosByROI';
GO

SELECT * FROM dbo.vw_TopPortfoliosByROI;
GO

-- Disable statistics
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* ============================================================================
   SECTION 5: INDEX RECOMMENDATIONS
   ============================================================================
*/

PRINT '';
PRINT '--- SECTION 5: INDEX RECOMMENDATIONS FOR OPTIMAL PERFORMANCE ---';
GO

PRINT '
Recommended additional indexes for performance optimization:

1. On dbo.Quotes table:
   CREATE NONCLUSTERED INDEX IX_Quotes_SecurityID_QuoteDate_Price
   ON dbo.Quotes (SecurityID, QuoteDate DESC, Price)
   INCLUDE (Volume)
   Purpose: Improve performance of moving average calculations

2. On dbo.Transactions table:
   CREATE NONCLUSTERED INDEX IX_Transactions_Type_PortfolioID
   ON dbo.Transactions (Type, PortfolioID)
   INCLUDE (Quantity, Price)
   Purpose: Accelerate ROI calculations and aggregations

3. On dbo.Audit_Log table:
   CREATE NONCLUSTERED INDEX IX_AuditLog_Action_ChangeDate
   ON dbo.Audit_Log (Action, ChangeDate DESC)
   Purpose: Speed up audit report queries

4. On dbo.Portfolios table:
   CREATE NONCLUSTERED INDEX IX_Portfolios_CreatedDate
   ON dbo.Portfolios (CreatedDate DESC)
   Purpose: Optimize date-range portfolio queries
';
GO

PRINT '';
PRINT '====================================================================';
PRINT 'END OF EXAMPLES AND TESTS';
PRINT '====================================================================';
GO
