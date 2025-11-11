/*
    Final Project Part 2: Portfolio Management System
    Views Script
    ------------------------------------------------
    This script creates four views for portfolio analysis:
    1. vw_PortfolioSummary - Portfolio overview with key metrics
    2. vw_PortfolioComposition - Detailed portfolio composition with percentages
    3. vw_PortfolioPerformance - Performance metrics and returns
    4. vw_SecurityRanking - Security ranking by activity and popularity
*/

SET XACT_ABORT ON;
GO

/* ============================================================================
   View 1: vw_PortfolioSummary
   ============================================================================
   Aggregated information for each portfolio
   Fields: PortfolioID, PortfolioName, Owner, TotalValue, SecurityCount, 
           PositionCount, LastUpdate, CreatedDate
*/

CREATE OR ALTER VIEW dbo.vw_PortfolioSummary
AS
SELECT
    p.PortfolioID,
    p.Name AS PortfolioName,
    p.Owner,
    ISNULL(
        SUM(
            CASE 
                WHEN t.Type = N'BUY' THEN t.Quantity * q.Price
                WHEN t.Type = N'SELL' THEN -t.Quantity * q.Price
                ELSE 0
            END
        ), 0
    ) AS TotalValue,
    COUNT(DISTINCT t.SecurityID) AS SecurityCount,
    COUNT(DISTINCT t.TransactionID) AS PositionCount,
    MAX(COALESCE(q.QuoteDate, t.TransactionDate)) AS LastUpdate,
    p.CreatedDate
FROM dbo.Portfolios p
LEFT JOIN dbo.Transactions t ON p.PortfolioID = t.PortfolioID
LEFT JOIN dbo.Quotes q ON t.SecurityID = q.SecurityID
    AND q.QuoteID = (
        SELECT MAX(QuoteID)
        FROM dbo.Quotes q2
        WHERE q2.SecurityID = t.SecurityID
    )
GROUP BY
    p.PortfolioID,
    p.Name,
    p.Owner,
    p.CreatedDate;
GO

PRINT 'View [vw_PortfolioSummary] created successfully.';
GO

/* ============================================================================
   View 2: vw_PortfolioComposition
   ============================================================================
   Detailed composition of each portfolio with percentage distribution
   Fields: PortfolioID, SecurityID, Ticker, Name, Type, CurrentPrice,
           Quantity, TotalValue, Percentage
*/

CREATE OR ALTER VIEW dbo.vw_PortfolioComposition
AS
WITH PortfolioTotals AS (
    SELECT
        p.PortfolioID,
        ISNULL(
            SUM(
                CASE 
                    WHEN t.Type = N'BUY' THEN t.Quantity * ISNULL(q.Price, 0)
                    WHEN t.Type = N'SELL' THEN -t.Quantity * ISNULL(q.Price, 0)
                    ELSE 0
                END
            ), 0
        ) AS PortfolioTotalValue
    FROM dbo.Portfolios p
    LEFT JOIN dbo.Transactions t ON p.PortfolioID = t.PortfolioID
    LEFT JOIN dbo.Quotes q ON t.SecurityID = q.SecurityID
        AND q.QuoteID = (
            SELECT MAX(QuoteID)
            FROM dbo.Quotes q2
            WHERE q2.SecurityID = t.SecurityID
        )
    GROUP BY p.PortfolioID
),
SecurityPositions AS (
    SELECT
        p.PortfolioID,
        s.SecurityID,
        s.Ticker,
        s.Name,
        s.Type,
        ISNULL(q.Price, 0) AS CurrentPrice,
        ISNULL(
            SUM(
                CASE 
                    WHEN t.Type = N'BUY' THEN t.Quantity
                    WHEN t.Type = N'SELL' THEN -t.Quantity
                    ELSE 0
                END
            ), 0
        ) AS Quantity,
        ISNULL(q.Price, 0) * ISNULL(
            SUM(
                CASE 
                    WHEN t.Type = N'BUY' THEN t.Quantity
                    WHEN t.Type = N'SELL' THEN -t.Quantity
                    ELSE 0
                END
            ), 0
        ) AS TotalValue
    FROM dbo.Portfolios p
    CROSS JOIN dbo.Securities s
    LEFT JOIN dbo.Transactions t ON p.PortfolioID = t.PortfolioID
        AND s.SecurityID = t.SecurityID
    LEFT JOIN dbo.Quotes q ON s.SecurityID = q.SecurityID
        AND q.QuoteID = (
            SELECT MAX(QuoteID)
            FROM dbo.Quotes q2
            WHERE q2.SecurityID = s.SecurityID
        )
    GROUP BY p.PortfolioID, s.SecurityID, s.Ticker, s.Name, s.Type, q.Price
    HAVING ISNULL(
        SUM(
            CASE 
                WHEN t.Type = N'BUY' THEN t.Quantity
                WHEN t.Type = N'SELL' THEN -t.Quantity
                ELSE 0
            END
        ), 0
    ) <> 0
)
SELECT
    sp.PortfolioID,
    sp.SecurityID,
    sp.Ticker,
    sp.Name,
    sp.Type,
    sp.CurrentPrice,
    sp.Quantity,
    sp.TotalValue,
    CASE 
        WHEN pt.PortfolioTotalValue = 0 THEN 0
        ELSE (sp.TotalValue / pt.PortfolioTotalValue) * 100
    END AS Percentage
FROM SecurityPositions sp
JOIN PortfolioTotals pt ON sp.PortfolioID = pt.PortfolioID;
GO

PRINT 'View [vw_PortfolioComposition] created successfully.';
GO

/* ============================================================================
   View 3: vw_PortfolioPerformance
   ============================================================================
   Portfolio performance metrics including profit/loss and returns
   Fields: PortfolioID, PortfolioName, CurrentValue, InitialValue, 
           ProfitLoss, ReturnPercentage, TransactionCount, LastTransactionDate
*/

CREATE OR ALTER VIEW dbo.vw_PortfolioPerformance
AS
WITH PortfolioMetrics AS (
    SELECT
        p.PortfolioID,
        p.Name AS PortfolioName,
        p.Owner,
        p.CreatedDate,
        -- Current Value: Current holdings valued at latest quotes
        ISNULL(
            SUM(
                CASE 
                    WHEN t.Type = N'BUY' THEN t.Quantity * ISNULL(q.Price, 0)
                    WHEN t.Type = N'SELL' THEN -t.Quantity * ISNULL(q.Price, 0)
                    ELSE 0
                END
            ), 0
        ) AS CurrentValue,
        -- Initial Value: Sum of all investments (BUY transactions)
        ISNULL(
            SUM(
                CASE 
                    WHEN t.Type = N'BUY' THEN t.Quantity * t.Price
                    ELSE 0
                END
            ), 0
        ) AS TotalInvestment,
        -- Realized Gains/Losses: Difference between sell and buy prices
        ISNULL(
            SUM(
                CASE 
                    WHEN t.Type = N'SELL' THEN t.Quantity * t.Price
                    ELSE 0
                END
            ), 0
        ) -
        ISNULL(
            SUM(
                CASE 
                    WHEN t.Type = N'BUY' THEN t.Quantity * t.Price
                    ELSE 0
                END
            ), 0
        ) AS RealizedGainLoss,
        COUNT(DISTINCT t.TransactionID) AS TransactionCount,
        MAX(t.TransactionDate) AS LastTransactionDate
    FROM dbo.Portfolios p
    LEFT JOIN dbo.Transactions t ON p.PortfolioID = t.PortfolioID
    LEFT JOIN dbo.Quotes q ON t.SecurityID = q.SecurityID
        AND q.QuoteID = (
            SELECT MAX(QuoteID)
            FROM dbo.Quotes q2
            WHERE q2.SecurityID = t.SecurityID
        )
    GROUP BY p.PortfolioID, p.Name, p.Owner, p.CreatedDate
)
SELECT
    PortfolioID,
    PortfolioName,
    Owner,
    CurrentValue,
    TotalInvestment,
    (CurrentValue - TotalInvestment) + RealizedGainLoss AS ProfitLoss,
    CASE 
        WHEN TotalInvestment = 0 THEN 0
        ELSE ((CurrentValue - TotalInvestment + RealizedGainLoss) / TotalInvestment) * 100
    END AS ReturnPercentage,
    TransactionCount,
    LastTransactionDate,
    CreatedDate
FROM PortfolioMetrics;
GO

PRINT 'View [vw_PortfolioPerformance] created successfully.';
GO

/* ============================================================================
   View 4: vw_SecurityRanking
   ============================================================================
   Security ranking by activity and popularity
   Fields: SecurityID, Ticker, Name, Type, Sector, AvgPrice, MinPrice, 
           MaxPrice, TradeCount, PortfoliosContaining, TotalVolume
*/

CREATE OR ALTER VIEW dbo.vw_SecurityRanking
AS
SELECT
    s.SecurityID,
    s.Ticker,
    s.Name,
    s.Type,
    s.Sector,
    ISNULL(AVG(q.Price), 0) AS AvgPrice,
    ISNULL(MIN(q.Price), 0) AS MinPrice,
    ISNULL(MAX(q.Price), 0) AS MaxPrice,
    COUNT(DISTINCT t.TransactionID) AS TradeCount,
    COUNT(DISTINCT t.PortfolioID) AS PortfoliosContaining,
    ISNULL(SUM(q.Volume), 0) AS TotalVolume,
    MAX(q.QuoteDate) AS LastQuoteDate,
    COUNT(DISTINCT q.QuoteDate) AS QuoteDateCount
FROM dbo.Securities s
LEFT JOIN dbo.Transactions t ON s.SecurityID = t.SecurityID
LEFT JOIN dbo.Quotes q ON s.SecurityID = q.SecurityID
GROUP BY
    s.SecurityID,
    s.Ticker,
    s.Name,
    s.Type,
    s.Sector;
GO

PRINT 'View [vw_SecurityRanking] created successfully.';
GO

PRINT 'All views have been created successfully!';
GO
