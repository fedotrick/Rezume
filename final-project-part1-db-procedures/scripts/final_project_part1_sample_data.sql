/*
    Final Project Part 1: Portfolio Management System
    Sample Data Population Script
    -----------------------------------------------
    This script populates the database with representative sample data for
    securities, portfolios, transactions, quotes, and operations to support
    testing of stored procedures and analytics.
*/

SET XACT_ABORT ON;
GO

/* Optional cleanup for repeatable execution */
DELETE FROM dbo.Audit_Log;
DELETE FROM dbo.Operations;
DELETE FROM dbo.Quotes;
DELETE FROM dbo.Transactions;
DELETE FROM dbo.Portfolios;
DELETE FROM dbo.Securities;
GO

DECLARE @Security_AAPL INT,
        @Security_MSFT INT,
        @Security_TSLA INT,
        @Security_US10 INT,
        @Security_GOVT INT;

INSERT INTO dbo.Securities (Ticker, Name, Type, Sector)
VALUES (N'AAPL', N'Apple Inc.', N'Stock', N'Technology');
SET @Security_AAPL = SCOPE_IDENTITY();

INSERT INTO dbo.Securities (Ticker, Name, Type, Sector)
VALUES (N'MSFT', N'Microsoft Corporation', N'Stock', N'Technology');
SET @Security_MSFT = SCOPE_IDENTITY();

INSERT INTO dbo.Securities (Ticker, Name, Type, Sector)
VALUES (N'TSLA', N'Tesla Inc.', N'Stock', N'Automotive');
SET @Security_TSLA = SCOPE_IDENTITY();

INSERT INTO dbo.Securities (Ticker, Name, Type, Sector)
VALUES (N'US10Y', N'U.S. Treasury 10Y', N'Bond', N'Government');
SET @Security_US10 = SCOPE_IDENTITY();

INSERT INTO dbo.Securities (Ticker, Name, Type, Sector)
VALUES (N'GOVT', N'iShares U.S. Treasury Bond ETF', N'ETF', N'Government');
SET @Security_GOVT = SCOPE_IDENTITY();
GO

DECLARE @Portfolio_Growth INT,
        @Portfolio_Income INT,
        @Portfolio_Balanced INT;

INSERT INTO dbo.Portfolios (Name, Owner, Description)
VALUES (N'Growth Portfolio', N'Anna Petrova', N'High growth equity focus');
SET @Portfolio_Growth = SCOPE_IDENTITY();

INSERT INTO dbo.Portfolios (Name, Owner, Description)
VALUES (N'Income Portfolio', N'Oleg Ivanov', N'Fixed income and dividend focus');
SET @Portfolio_Income = SCOPE_IDENTITY();

INSERT INTO dbo.Portfolios (Name, Owner, Description)
VALUES (N'Balanced Portfolio', N'Maria Smirnova', N'Mix of equities and bonds');
SET @Portfolio_Balanced = SCOPE_IDENTITY();
GO

/* Transactions: 12 sample records */
INSERT INTO dbo.Transactions (PortfolioID, SecurityID, Quantity, Price, TransactionDate, Type)
VALUES
    (@Portfolio_Growth,   @Security_AAPL,  50.0000, 175.2500, '2024-01-10T10:15:00', N'BUY'),
    (@Portfolio_Growth,   @Security_MSFT,  40.0000, 320.5000, '2024-01-12T11:20:00', N'BUY'),
    (@Portfolio_Growth,   @Security_TSLA,  15.0000, 250.0000, '2024-02-05T09:45:00', N'BUY'),
    (@Portfolio_Growth,   @Security_AAPL,  10.0000, 185.3000, '2024-03-15T14:05:00', N'SELL'),
    (@Portfolio_Growth,   @Security_TSLA,   5.0000, 265.7500, '2024-04-01T15:30:00', N'SELL'),
    (@Portfolio_Growth,   @Security_MSFT,  20.0000, 335.1000, '2024-04-18T12:40:00', N'BUY'),
    (@Portfolio_Income,   @Security_US10, 100.0000,  98.4500, '2024-01-05T13:25:00', N'BUY'),
    (@Portfolio_Income,   @Security_GOVT, 200.0000, 103.2000, '2024-02-02T09:10:00', N'BUY'),
    (@Portfolio_Income,   @Security_US10,  50.0000,  99.1000, '2024-03-08T10:55:00', N'SELL'),
    (@Portfolio_Balanced, @Security_AAPL,  20.0000, 170.0000, '2024-01-20T16:20:00', N'BUY'),
    (@Portfolio_Balanced, @Security_GOVT, 120.0000, 102.5000, '2024-02-12T11:45:00', N'BUY'),
    (@Portfolio_Balanced, @Security_MSFT,  15.0000, 310.2500, '2024-03-22T14:50:00', N'BUY');
GO

/* Operations: 6 sample records */
INSERT INTO dbo.Operations (PortfolioID, Description, Amount, OperationDate, Category)
VALUES
    (@Portfolio_Growth,   N'Initial funding',           25000.00, '2024-01-01T09:00:00', N'Deposit'),
    (@Portfolio_Growth,   N'Rebalancing commission',     -150.00, '2024-04-02T09:30:00', N'Commission'),
    (@Portfolio_Income,   N'Initial funding',           40000.00, '2024-01-02T09:15:00', N'Deposit'),
    (@Portfolio_Income,   N'Interest payout reinvest',   500.00,  '2024-03-01T12:00:00', N'Income'),
    (@Portfolio_Balanced, N'Initial funding',           30000.00, '2024-01-03T10:00:00', N'Deposit'),
    (@Portfolio_Balanced, N'Annual maintenance fee',    -120.00,  '2024-03-31T08:30:00', N'Fee');
GO

/* Quotes: 25 sample records across securities and dates */
INSERT INTO dbo.Quotes (SecurityID, Price, QuoteDate, Volume, Source)
VALUES
    (@Security_AAPL, 173.9800, '2024-01-02T16:00:00', 81000000, N'NASDAQ'),
    (@Security_AAPL, 176.4200, '2024-02-01T16:00:00', 78500000, N'NASDAQ'),
    (@Security_AAPL, 182.1500, '2024-03-01T16:00:00', 72000000, N'NASDAQ'),
    (@Security_AAPL, 189.6000, '2024-04-01T16:00:00', 69000000, N'NASDAQ'),
    (@Security_AAPL, 191.2500, '2024-05-01T16:00:00', 65000000, N'NASDAQ'),
    (@Security_MSFT, 318.5000, '2024-01-02T16:00:00', 28000000, N'NASDAQ'),
    (@Security_MSFT, 322.1500, '2024-02-01T16:00:00', 27000000, N'NASDAQ'),
    (@Security_MSFT, 330.9000, '2024-03-01T16:00:00', 26000000, N'NASDAQ'),
    (@Security_MSFT, 338.4500, '2024-04-01T16:00:00', 25500000, N'NASDAQ'),
    (@Security_MSFT, 342.8000, '2024-05-01T16:00:00', 25000000, N'NASDAQ'),
    (@Security_TSLA, 247.6000, '2024-01-02T16:00:00', 54000000, N'NASDAQ'),
    (@Security_TSLA, 255.9000, '2024-02-01T16:00:00', 53000000, N'NASDAQ'),
    (@Security_TSLA, 262.3000, '2024-03-01T16:00:00', 52000000, N'NASDAQ'),
    (@Security_TSLA, 268.7500, '2024-04-01T16:00:00', 51000000, N'NASDAQ'),
    (@Security_TSLA, 272.1500, '2024-05-01T16:00:00', 50000000, N'NASDAQ'),
    (@Security_US10,  98.6500, '2024-01-02T16:00:00', 120000, N'CBOT'),
    (@Security_US10,  99.0500, '2024-02-01T16:00:00', 125000, N'CBOT'),
    (@Security_US10,  99.3200, '2024-03-01T16:00:00', 118000, N'CBOT'),
    (@Security_US10,  99.5800, '2024-04-01T16:00:00', 122000, N'CBOT'),
    (@Security_US10,  99.7100, '2024-05-01T16:00:00', 119000, N'CBOT'),
    (@Security_GOVT, 102.1500, '2024-01-02T16:00:00',  90000, N'NYSE Arca'),
    (@Security_GOVT, 103.0500, '2024-02-01T16:00:00',  95000, N'NYSE Arca'),
    (@Security_GOVT, 103.4200, '2024-03-01T16:00:00',  96000, N'NYSE Arca'),
    (@Security_GOVT, 103.8800, '2024-04-01T16:00:00',  94000, N'NYSE Arca'),
    (@Security_GOVT, 104.1200, '2024-05-01T16:00:00',  93000, N'NYSE Arca');
GO

PRINT 'Sample data for the portfolio management system has been created successfully.';
GO
