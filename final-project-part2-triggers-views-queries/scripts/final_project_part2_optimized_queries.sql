/*
    Final Project Part 2: Portfolio Management System
    Optimized Queries Script
    ------------------------------------------------
    This script contains five optimized queries demonstrating advanced SQL techniques:
    1. Query with window functions: 7-day moving average
    2. Query with CTE: Portfolio and transaction hierarchy
    3. Query with JOINs: Complete portfolio information
    4. Query for large data: Batch processing example (100k+ transactions)
    5. Query with subqueries: TOP 10 portfolios by ROI
*/

SET XACT_ABORT ON;
GO

/* ============================================================================
   Query 1: Moving Average Prices (Window Functions)
   ============================================================================
   Purpose: Calculate 7-day moving average for each security
   Techniques: ROW_NUMBER(), LAG(), AVG() OVER()
   Usage: Trend analysis, technical indicators
*/

CREATE OR ALTER VIEW dbo.vw_SecurityMovingAverage
AS
WITH PricedQuotes AS (
    SELECT
        q.SecurityID,
        s.Ticker,
        s.Name,
        q.QuoteDate,
        q.Price,
        ROW_NUMBER() OVER (PARTITION BY q.SecurityID ORDER BY q.QuoteDate DESC) AS RowNum,
        -- Calculate 7-day moving average
        AVG(q.Price) OVER (
            PARTITION BY q.SecurityID 
            ORDER BY q.QuoteDate 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS MA7,
        -- Calculate 30-day moving average
        AVG(q.Price) OVER (
            PARTITION BY q.SecurityID 
            ORDER BY q.QuoteDate 
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ) AS MA30,
        -- Get previous day price using LAG
        LAG(q.Price) OVER (PARTITION BY q.SecurityID ORDER BY q.QuoteDate) AS PreviousPrice,
        -- Calculate price change percentage
        ((q.Price - LAG(q.Price) OVER (PARTITION BY q.SecurityID ORDER BY q.QuoteDate)) /
         LAG(q.Price) OVER (PARTITION BY q.SecurityID ORDER BY q.QuoteDate)) * 100 AS PricePctChange
    FROM dbo.Quotes q
    JOIN dbo.Securities s ON q.SecurityID = s.SecurityID
)
SELECT
    SecurityID,
    Ticker,
    Name,
    QuoteDate,
    Price,
    MA7,
    MA30,
    PreviousPrice,
    PricePctChange,
    CASE
        WHEN Price > MA7 THEN 'ABOVE_MA7'
        WHEN Price < MA7 THEN 'BELOW_MA7'
        ELSE 'AT_MA7'
    END AS PriceTrendVsMA7
FROM PricedQuotes
WHERE RowNum <= 90; -- Last 90 days of data

GO

PRINT 'Query 1: Moving Average View created successfully.';
GO

/* ============================================================================
   Query 2: Portfolio & Transaction Hierarchy with CTE
   ============================================================================
   Purpose: Build hierarchical portfolio analysis with aggregated metrics
   Techniques: Recursive CTE, multiple CTEs for layered aggregation
   Usage: Portfolio structure analysis, drill-down reports
*/

CREATE OR ALTER VIEW dbo.vw_PortfolioTransactionHierarchy
AS
WITH PortfolioBase AS (
    -- Base CTE: Portfolio summary
    SELECT
        p.PortfolioID,
        p.Name AS PortfolioName,
        p.Owner,
        p.CreatedDate,
        COUNT(DISTINCT t.SecurityID) AS SecurityCount,
        COUNT(DISTINCT t.TransactionID) AS TransactionCount,
        MIN(t.TransactionDate) AS FirstTransactionDate,
        MAX(t.TransactionDate) AS LastTransactionDate
    FROM dbo.Portfolios p
    LEFT JOIN dbo.Transactions t ON p.PortfolioID = t.PortfolioID
    GROUP BY p.PortfolioID, p.Name, p.Owner, p.CreatedDate
),
TransactionDetails AS (
    -- Second CTE: Detailed transaction metrics by portfolio
    SELECT
        p.PortfolioID,
        COUNT(*) AS TotalTransactions,
        SUM(CASE WHEN t.Type = N'BUY' THEN 1 ELSE 0 END) AS BuyCount,
        SUM(CASE WHEN t.Type = N'SELL' THEN 1 ELSE 0 END) AS SellCount,
        SUM(CASE WHEN t.Type = N'BUY' THEN t.Quantity * t.Price ELSE 0 END) AS TotalInvested,
        SUM(CASE WHEN t.Type = N'SELL' THEN t.Quantity * t.Price ELSE 0 END) AS TotalReturns,
        AVG(t.Price) AS AvgTradePrice
    FROM dbo.Portfolios p
    LEFT JOIN dbo.Transactions t ON p.PortfolioID = t.PortfolioID
    GROUP BY p.PortfolioID
),
PortfolioWithMetrics AS (
    -- Third CTE: Combine portfolio base with transaction details
    SELECT
        pb.PortfolioID,
        pb.PortfolioName,
        pb.Owner,
        pb.CreatedDate,
        pb.SecurityCount,
        pb.TransactionCount,
        pb.FirstTransactionDate,
        pb.LastTransactionDate,
        td.TotalTransactions,
        td.BuyCount,
        td.SellCount,
        td.TotalInvested,
        td.TotalReturns,
        td.AvgTradePrice,
        CASE
            WHEN td.TotalInvested = 0 THEN 0
            ELSE ((td.TotalReturns - td.TotalInvested) / td.TotalInvested) * 100
        END AS ROI_Percentage
    FROM PortfolioBase pb
    LEFT JOIN TransactionDetails td ON pb.PortfolioID = td.PortfolioID
)
SELECT *
FROM PortfolioWithMetrics;

GO

PRINT 'Query 2: Hierarchy CTE View created successfully.';
GO

/* ============================================================================
   Query 3: Complete Portfolio Information (Complex JOINs)
   ============================================================================
   Purpose: Get complete portfolio information with all related data
   Techniques: Multiple JOINs, aggregation, subqueries for latest quotes
   Usage: Comprehensive portfolio reports, data exports
*/

CREATE OR ALTER VIEW dbo.vw_CompletePortfolioInfo
AS
SELECT
    p.PortfolioID,
    p.Name AS PortfolioName,
    p.Owner,
    p.CreatedDate,
    p.Description,
    s.SecurityID,
    s.Ticker,
    s.Name AS SecurityName,
    s.Type AS SecurityType,
    s.Sector,
    t.TransactionID,
    t.TransactionDate,
    t.Type AS TransactionType,
    t.Quantity,
    t.Price AS TransactionPrice,
    t.Notes,
    q.Price AS CurrentPrice,
    q.QuoteDate,
    q.Volume AS QuoteVolume,
    (t.Quantity * q.Price) AS CurrentPositionValue,
    (t.Quantity * t.Price) AS PositionCost,
    ((t.Quantity * q.Price) - (t.Quantity * t.Price)) AS UnrealizedGainLoss,
    al.LogID,
    al.Action,
    al.ChangeDate AS AuditChangeDate,
    al.ExecutedBy
FROM dbo.Portfolios p
LEFT JOIN dbo.Transactions t ON p.PortfolioID = t.PortfolioID
LEFT JOIN dbo.Securities s ON t.SecurityID = s.SecurityID
LEFT JOIN dbo.Quotes q ON s.SecurityID = q.SecurityID
    AND q.QuoteID = (
        SELECT MAX(q2.QuoteID)
        FROM dbo.Quotes q2
        WHERE q2.SecurityID = s.SecurityID
    )
LEFT JOIN dbo.Audit_Log al ON al.TableName = 'Transactions'
    AND CAST(al.NewValue AS NVARCHAR(MAX)) LIKE '%' + CAST(t.TransactionID AS NVARCHAR(MAX)) + '%';

GO

PRINT 'Query 3: Complete Portfolio Information View created successfully.';
GO

/* ============================================================================
   Query 4: Batch Processing for Large Datasets
   ============================================================================
   Purpose: Efficiently process large volumes of transactions (100k+)
   Techniques: Temporary table, batch processing, cursor alternatives
   Usage: Nightly batch updates, data migrations, bulk operations
   
   This is a stored procedure that demonstrates batch processing pattern.
*/

CREATE OR ALTER PROCEDURE dbo.sp_BatchProcessTransactions
    @BatchSize INT = 10000,
    @MaxBatches INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ProcessedCount INT = 0;
    DECLARE @BatchCount INT = 0;
    DECLARE @TotalTransactions INT;
    DECLARE @StartTime DATETIME2 = SYSUTCDATETIME();

    -- Create temporary table to store transaction summaries
    CREATE TABLE #TransactionBatch (
        RowNum BIGINT,
        TransactionID BIGINT,
        PortfolioID INT,
        SecurityID INT,
        Quantity DECIMAL(18,4),
        Price DECIMAL(18,4),
        TransactionDate DATETIME2,
        Type NVARCHAR(4)
    );

    -- Get total transaction count
    SELECT @TotalTransactions = COUNT(*)
    FROM dbo.Transactions;

    PRINT 'Starting batch processing of ' + CAST(@TotalTransactions AS NVARCHAR(MAX)) + ' transactions...';

    -- Insert transactions into temp table with row numbers for batching
    INSERT INTO #TransactionBatch
    SELECT
        ROW_NUMBER() OVER (ORDER BY t.TransactionID) AS RowNum,
        t.TransactionID,
        t.PortfolioID,
        t.SecurityID,
        t.Quantity,
        t.Price,
        t.TransactionDate,
        t.Type
    FROM dbo.Transactions t;

    -- Process in batches
    WHILE @BatchCount < @MaxBatches
    BEGIN
        DECLARE @BatchStart INT = (@BatchCount * @BatchSize) + 1;
        DECLARE @BatchEnd INT = (@BatchCount + 1) * @BatchSize;
        DECLARE @CurrentBatchCount INT;

        -- Get count of records in current batch
        SELECT @CurrentBatchCount = COUNT(*)
        FROM #TransactionBatch
        WHERE RowNum BETWEEN @BatchStart AND @BatchEnd;

        IF @CurrentBatchCount = 0
            BREAK;

        -- Process current batch
        CREATE TABLE #CurrentBatch (
            TransactionID BIGINT,
            PortfolioID INT,
            PositionValue DECIMAL(18,2),
            ProcessedDate DATETIME2
        );

        INSERT INTO #CurrentBatch
        SELECT
            tb.TransactionID,
            tb.PortfolioID,
            (tb.Quantity * tb.Price) AS PositionValue,
            SYSUTCDATETIME()
        FROM #TransactionBatch tb
        WHERE tb.RowNum BETWEEN @BatchStart AND @BatchEnd;

        -- Log batch completion
        INSERT INTO dbo.Audit_Log (TableName, Action, NewValue, ChangeDate, ExecutedBy)
        VALUES (
            'Transactions',
            'BATCH_PROCESSED',
            'Batch ' + CAST(@BatchCount + 1 AS NVARCHAR(MAX)) + 
            ' processed: ' + CAST(@CurrentBatchCount AS NVARCHAR(MAX)) + ' transactions',
            SYSUTCDATETIME(),
            SYSTEM_USER
        );

        SET @ProcessedCount += @CurrentBatchCount;
        SET @BatchCount += 1;

        DROP TABLE #CurrentBatch;

        PRINT 'Batch ' + CAST(@BatchCount AS NVARCHAR(MAX)) + 
              ' processed: ' + CAST(@CurrentBatchCount AS NVARCHAR(MAX)) + 
              ' transactions. Total: ' + CAST(@ProcessedCount AS NVARCHAR(MAX));
    END

    DROP TABLE #TransactionBatch;

    DECLARE @EndTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @DurationMs INT = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

    PRINT 'Batch processing completed!';
    PRINT 'Total batches: ' + CAST(@BatchCount AS NVARCHAR(MAX));
    PRINT 'Total transactions processed: ' + CAST(@ProcessedCount AS NVARCHAR(MAX));
    PRINT 'Duration (ms): ' + CAST(@DurationMs AS NVARCHAR(MAX));
END;
GO

PRINT 'Query 4: Batch Processing Procedure created successfully.';
GO

/* ============================================================================
   Query 5: TOP Portfolios by ROI (Subquery Pattern)
   ============================================================================
   Purpose: Identify top performing portfolios with detailed analysis
   Techniques: Subqueries, window functions, ranking
   Usage: Performance reports, client rankings
*/

CREATE OR ALTER VIEW dbo.vw_TopPortfoliosByROI
AS
WITH PortfolioROI AS (
    SELECT
        p.PortfolioID,
        p.Name AS PortfolioName,
        p.Owner,
        p.CreatedDate,
        COUNT(DISTINCT t.SecurityID) AS HoldingCount,
        COUNT(DISTINCT t.TransactionID) AS TransactionCount,
        SUM(CASE WHEN t.Type = N'BUY' THEN t.Quantity * t.Price ELSE 0 END) AS TotalInvested,
        SUM(CASE WHEN t.Type = N'SELL' THEN t.Quantity * t.Price ELSE 0 END) AS TotalReturns,
        ISNULL(
            SUM(
                CASE 
                    WHEN t.Type = N'BUY' THEN t.Quantity * ISNULL(q.Price, 0)
                    WHEN t.Type = N'SELL' THEN -t.Quantity * ISNULL(q.Price, 0)
                    ELSE 0
                END
            ), 0
        ) AS CurrentValue
    FROM dbo.Portfolios p
    LEFT JOIN dbo.Transactions t ON p.PortfolioID = t.PortfolioID
    LEFT JOIN dbo.Quotes q ON t.SecurityID = q.SecurityID
        AND q.QuoteID = (
            SELECT MAX(q2.QuoteID)
            FROM dbo.Quotes q2
            WHERE q2.SecurityID = t.SecurityID
        )
    GROUP BY p.PortfolioID, p.Name, p.Owner, p.CreatedDate
),
PortfolioRanked AS (
    SELECT
        PortfolioID,
        PortfolioName,
        Owner,
        CreatedDate,
        HoldingCount,
        TransactionCount,
        TotalInvested,
        TotalReturns,
        CurrentValue,
        (CurrentValue - TotalInvested) + TotalReturns AS TotalProfitLoss,
        CASE 
            WHEN TotalInvested = 0 THEN 0
            ELSE ((CurrentValue - TotalInvested + TotalReturns) / TotalInvested) * 100
        END AS ROI_Percentage,
        ROW_NUMBER() OVER (ORDER BY 
            CASE 
                WHEN TotalInvested = 0 THEN 0
                ELSE ((CurrentValue - TotalInvested + TotalReturns) / TotalInvested) * 100
            END DESC
        ) AS ROI_Rank
    FROM PortfolioROI
)
SELECT
    ROI_Rank,
    PortfolioID,
    PortfolioName,
    Owner,
    CreatedDate,
    HoldingCount,
    TransactionCount,
    TotalInvested,
    TotalReturns,
    CurrentValue,
    TotalProfitLoss,
    ROI_Percentage,
    DATEDIFF(DAY, CreatedDate, CAST(GETDATE() AS DATE)) AS DaysActive
FROM PortfolioRanked
WHERE ROI_Rank <= 10;

GO

PRINT 'Query 5: Top Portfolios by ROI View created successfully.';
GO

PRINT 'All optimized queries have been created successfully!';
GO
