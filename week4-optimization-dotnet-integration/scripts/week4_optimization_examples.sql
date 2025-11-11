/*
    Week 4: Optimization & .NET Integration Examples
    ------------------------------------------------
    Этот скрипт разворачивает учебную схему для работы с финансовыми данными,
    демонстрирует сценарии оптимизации запросов, партиционирования, batch-обработки
    и предоставляет хранимые процедуры для интеграции с C# приложением.
*/

USE SQLTraining;
GO

/* =====================================================
   Section 0. Подготовка схемы и данных
   ===================================================== */

IF OBJECT_ID('dbo.TradesFact', 'U') IS NOT NULL DROP TABLE dbo.TradesFact;
IF OBJECT_ID('dbo.TradesStage', 'U') IS NOT NULL DROP TABLE dbo.TradesStage;
IF OBJECT_ID('dbo.TradeAnalytics', 'U') IS NOT NULL DROP TABLE dbo.TradeAnalytics;
IF OBJECT_ID('dbo.Portfolios', 'U') IS NOT NULL DROP TABLE dbo.Portfolios;
IF OBJECT_ID('dbo.PortfolioPerformance', 'U') IS NOT NULL DROP TABLE dbo.PortfolioPerformance;
IF OBJECT_ID('dbo.PortfolioHoldings', 'U') IS NOT NULL DROP TABLE dbo.PortfolioHoldings;
IF OBJECT_ID('dbo.FxRates', 'U') IS NOT NULL DROP TABLE dbo.FxRates;
GO

CREATE TABLE dbo.Portfolios
(
    PortfolioId    INT IDENTITY PRIMARY KEY,
    PortfolioName  NVARCHAR(100) NOT NULL,
    Strategy       NVARCHAR(50)  NOT NULL,
    BaseCurrency   CHAR(3)       NOT NULL
);

CREATE TABLE dbo.PortfolioHoldings
(
    PortfolioId  INT          NOT NULL,
    Symbol       NVARCHAR(12) NOT NULL,
    AssetClass   NVARCHAR(20) NOT NULL,
    TargetWeight DECIMAL(9,6) NOT NULL,
    CONSTRAINT PK_PortfolioHoldings PRIMARY KEY (PortfolioId, Symbol),
    CONSTRAINT FK_PortfolioHoldings_Portfolios FOREIGN KEY (PortfolioId) REFERENCES dbo.Portfolios(PortfolioId)
);

CREATE TABLE dbo.FxRates
(
    RateDate    DATE        NOT NULL,
    Currency    CHAR(3)     NOT NULL,
    RateToBase  DECIMAL(18,8) NOT NULL,
    CONSTRAINT PK_FxRates PRIMARY KEY (RateDate, Currency)
);
GO

INSERT INTO dbo.Portfolios (PortfolioName, Strategy, BaseCurrency)
VALUES
('Global Equity', 'Growth', 'USD'),
('Balanced Income', 'Income', 'USD'),
('Emerging Markets', 'Aggressive', 'EUR');

INSERT INTO dbo.PortfolioHoldings (PortfolioId, Symbol, AssetClass, TargetWeight)
VALUES
(1, 'AAPL', 'Equity', 0.25),
(1, 'MSFT', 'Equity', 0.25),
(1, 'GOOG', 'Equity', 0.25),
(1, 'TLT',  'Bond',   0.25),
(2, 'VTI',  'Equity', 0.40),
(2, 'BND',  'Bond',   0.40),
(2, 'GLD',  'Commodity', 0.20);
GO

/* =====================================================
   Section 1. Scenario: Slow Query Analysis
   ===================================================== */

IF OBJECT_ID('dbo.TradesFact', 'U') IS NOT NULL DROP TABLE dbo.TradesFact;
GO

CREATE TABLE dbo.TradesFact
(
    TradeId        BIGINT IDENTITY PRIMARY KEY,
    PortfolioId    INT           NOT NULL,
    Symbol         NVARCHAR(12)  NOT NULL,
    TradeDate      DATE          NOT NULL,
    TradeType      CHAR(4)       NOT NULL, -- BUY / SELL
    Quantity       INT           NOT NULL,
    Price          DECIMAL(18,4) NOT NULL,
    Fees           DECIMAL(18,4) NOT NULL,
    ProcessedFlag  BIT           NOT NULL DEFAULT 0,
    CreatedAt      DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE INDEX IX_TradesFact_PortfolioId ON dbo.TradesFact (PortfolioId);
GO

;WITH n AS (
    SELECT TOP (500000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.objects o CROSS JOIN sys.objects o2
)
INSERT INTO dbo.TradesFact (PortfolioId, Symbol, TradeDate, TradeType, Quantity, Price, Fees)
SELECT
    ((rn % 3) + 1) AS PortfolioId,
    CASE WHEN rn % 3 = 0 THEN 'AAPL' WHEN rn % 3 = 1 THEN 'MSFT' ELSE 'GOOG' END,
    DATEADD(DAY, - (rn % 365), CAST(GETDATE() AS DATE)) AS TradeDate,
    CASE WHEN rn % 2 = 0 THEN 'BUY' ELSE 'SELL' END,
    (rn % 1000) + 1 AS Quantity,
    100 + (rn % 50) AS Price,
    0.02 * ((rn % 1000) + 1) AS Fees
FROM n;
GO

/* Step 1: Baseline query (предполагаемый медленный запрос) */
-- Включите Actual Execution Plan перед выполнением (CTRL+M)
-- Ожидается последовательное сканирование и key lookup'ы
SELECT
    p.PortfolioName,
    t.Symbol,
    SUM(t.Quantity * t.Price) AS GrossAmount,
    SUM(t.Fees) AS TotalFees,
    COUNT(*) AS TradesCount
FROM dbo.TradesFact t
JOIN dbo.Portfolios p ON p.PortfolioId = t.PortfolioId
WHERE t.TradeDate BETWEEN DATEADD(DAY, -90, CAST(GETDATE() AS DATE)) AND CAST(GETDATE() AS DATE)
GROUP BY p.PortfolioName, t.Symbol
ORDER BY GrossAmount DESC;
GO

/* Step 2: Index proposal */
CREATE NONCLUSTERED INDEX IX_TradesFact_PortfolioId_TradeDate_Symbol
ON dbo.TradesFact (PortfolioId, TradeDate, Symbol)
INCLUDE (Quantity, Price, Fees);
GO

/* Step 3: Optimized query */
-- Теперь план должен использовать Index Seek + параллельный Hash Match
SET STATISTICS IO, TIME ON;
SELECT
    p.PortfolioName,
    t.Symbol,
    SUM(t.Quantity * t.Price) AS GrossAmount,
    SUM(t.Fees) AS TotalFees,
    COUNT_BIG(*) AS TradesCount
FROM dbo.TradesFact t WITH (INDEX(IX_TradesFact_PortfolioId_TradeDate_Symbol))
JOIN dbo.Portfolios p ON p.PortfolioId = t.PortfolioId
WHERE t.TradeDate >= DATEADD(DAY, -90, CAST(GETDATE() AS DATE))
GROUP BY p.PortfolioName, t.Symbol
ORDER BY GrossAmount DESC;
SET STATISTICS IO, TIME OFF;
GO

/* =====================================================
   Section 2. Scenario: Big Data Processing & Partitioning
   ===================================================== */

IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'PS_TradesByMonth')
BEGIN
    DROP TABLE IF EXISTS dbo.TradesFactPartitioned;
    DROP PARTITION SCHEME PS_TradesByMonth;
    DROP PARTITION FUNCTION PF_TradesByMonth;
END;
GO

CREATE PARTITION FUNCTION PF_TradesByMonth (DATE)
AS RANGE RIGHT FOR VALUES ('2023-01-01', '2023-04-01', '2023-07-01', '2023-10-01', '2024-01-01');
GO

CREATE PARTITION SCHEME PS_TradesByMonth
AS PARTITION PF_TradesByMonth
TO ([PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY]);
GO

CREATE TABLE dbo.TradesFactPartitioned
(
    TradeId        BIGINT IDENTITY PRIMARY KEY,
    PortfolioId    INT           NOT NULL,
    Symbol         NVARCHAR(12)  NOT NULL,
    TradeDate      DATE          NOT NULL,
    TradeType      CHAR(4)       NOT NULL,
    Quantity       INT           NOT NULL,
    Price          DECIMAL(18,4) NOT NULL,
    Fees           DECIMAL(18,4) NOT NULL,
    ProcessedFlag  BIT           NOT NULL DEFAULT 0,
    InsertedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
)
ON PS_TradesByMonth (TradeDate);
GO

CREATE TABLE dbo.TradesStage
(
    PortfolioId    INT,
    Symbol         NVARCHAR(12),
    TradeDate      DATE,
    TradeType      CHAR(4),
    Quantity       INT,
    Price          DECIMAL(18,4),
    Fees           DECIMAL(18,4)
);
GO

CREATE TABLE dbo.TradeAnalytics
(
    SnapshotDate   DATE          NOT NULL,
    PortfolioId    INT           NOT NULL,
    Symbol         NVARCHAR(12)  NOT NULL,
    GrossAmount    DECIMAL(28,4) NOT NULL,
    TotalFees      DECIMAL(28,4) NOT NULL,
    TradesCount    BIGINT        NOT NULL,
    CONSTRAINT PK_TradeAnalytics PRIMARY KEY (SnapshotDate, PortfolioId, Symbol)
);
GO

/* Batch processing template */
DECLARE @BatchSize INT = 20000;
WHILE 1 = 1
BEGIN
    WITH BatchRows AS (
        SELECT TOP (@BatchSize)
            PortfolioId,
            Symbol,
            TradeDate,
            TradeType,
            Quantity,
            Price,
            Fees
        FROM dbo.TradesStage WITH (READPAST)
        ORDER BY TradeDate
    )
    INSERT INTO dbo.TradesFactPartitioned (PortfolioId, Symbol, TradeDate, TradeType, Quantity, Price, Fees)
    SELECT * FROM BatchRows;

    IF @@ROWCOUNT = 0 BREAK;

    DELETE B
    FROM BatchRows B; -- Очистка обработанного батча
END;
GO

/* Daily aggregates */
INSERT INTO dbo.TradeAnalytics (SnapshotDate, PortfolioId, Symbol, GrossAmount, TotalFees, TradesCount)
SELECT
    CAST(t.TradeDate AS DATE) AS SnapshotDate,
    t.PortfolioId,
    t.Symbol,
    SUM(t.Quantity * t.Price) AS GrossAmount,
    SUM(t.Fees) AS TotalFees,
    COUNT_BIG(*) AS TradesCount
FROM dbo.TradesFactPartitioned t
GROUP BY CAST(t.TradeDate AS DATE), t.PortfolioId, t.Symbol;
GO

/* Archive example */
-- Переносим самый старый раздел (до 2023-01-01) в архивную таблицу
IF OBJECT_ID('dbo.TradesFactArchive', 'U') IS NULL
BEGIN
    SELECT TOP (0) *
    INTO dbo.TradesFactArchive
    FROM dbo.TradesFactPartitioned;
END;
GO

ALTER TABLE dbo.TradesFactPartitioned SWITCH PARTITION 1 TO dbo.TradesFactArchive;
GO

/* =====================================================
   Section 3. Scenario: Stored Procedures for .NET Integration
   ===================================================== */

IF OBJECT_ID('dbo.usp_UpsertTrade', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_UpsertTrade;
IF OBJECT_ID('dbo.usp_GetPortfolioSummary', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_GetPortfolioSummary;
IF OBJECT_ID('dbo.usp_GetPerformanceHistory', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_GetPerformanceHistory;
GO

CREATE PROCEDURE dbo.usp_UpsertTrade
    @PortfolioId INT,
    @Symbol NVARCHAR(12),
    @TradeDate DATE,
    @TradeType CHAR(4),
    @Quantity INT,
    @Price DECIMAL(18,4),
    @Fees DECIMAL(18,4)
AS
BEGIN
    SET NOCOUNT ON;
    MERGE dbo.TradesFactPartitioned AS target
    USING (SELECT @PortfolioId AS PortfolioId, @Symbol AS Symbol, @TradeDate AS TradeDate, @TradeType AS TradeType) AS source
        ON target.PortfolioId = source.PortfolioId
       AND target.Symbol = source.Symbol
       AND target.TradeDate = source.TradeDate
       AND target.TradeType = source.TradeType
    WHEN MATCHED THEN
        UPDATE SET Quantity = @Quantity, Price = @Price, Fees = @Fees
    WHEN NOT MATCHED THEN
        INSERT (PortfolioId, Symbol, TradeDate, TradeType, Quantity, Price, Fees)
        VALUES (@PortfolioId, @Symbol, @TradeDate, @TradeType, @Quantity, @Price, @Fees);
END;
GO

CREATE PROCEDURE dbo.usp_GetPortfolioSummary
    @PortfolioId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (100)
        p.PortfolioName,
        t.Symbol,
        SUM(t.Quantity * t.Price) AS GrossAmount,
        SUM(t.Fees) AS TotalFees,
        COUNT_BIG(*) AS TradesCount
    FROM dbo.TradesFactPartitioned t
    JOIN dbo.Portfolios p ON p.PortfolioId = t.PortfolioId
    WHERE t.PortfolioId = @PortfolioId
    GROUP BY p.PortfolioName, t.Symbol
    ORDER BY GrossAmount DESC;
END;
GO

CREATE PROCEDURE dbo.usp_GetPerformanceHistory
    @PortfolioId INT,
    @StartDate DATE,
    @EndDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    WITH DailyPnL AS (
        SELECT
            CAST(TradeDate AS DATE) AS SnapshotDate,
            SUM(CASE WHEN TradeType = 'SELL' THEN Quantity * Price ELSE - Quantity * Price END) AS CashFlow
        FROM dbo.TradesFactPartitioned
        WHERE PortfolioId = @PortfolioId
          AND TradeDate BETWEEN @StartDate AND @EndDate
        GROUP BY CAST(TradeDate AS DATE)
    )
    SELECT
        SnapshotDate,
        CashFlow,
        SUM(CashFlow) OVER (ORDER BY SnapshotDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativePnL
    FROM DailyPnL
    ORDER BY SnapshotDate;
END;
GO

/* =====================================================
   Section 4. Scenario: Reporting Views
   ===================================================== */

IF OBJECT_ID('dbo.vw_PortfolioNavDaily', 'V') IS NOT NULL DROP VIEW dbo.vw_PortfolioNavDaily;
GO

CREATE VIEW dbo.vw_PortfolioNavDaily
AS
SELECT
    t.PortfolioId,
    CAST(t.TradeDate AS DATE) AS TradeDate,
    SUM(t.Quantity * t.Price - t.Fees) AS NetAssetValue
FROM dbo.TradesFactPartitioned t
GROUP BY t.PortfolioId, CAST(t.TradeDate AS DATE);
GO

IF OBJECT_ID('dbo.vw_PortfolioPerformance', 'V') IS NOT NULL DROP VIEW dbo.vw_PortfolioPerformance;
GO

CREATE VIEW dbo.vw_PortfolioPerformance
AS
WITH Nav AS (
    SELECT
        PortfolioId,
        TradeDate,
        NetAssetValue,
        LAG(NetAssetValue) OVER (PARTITION BY PortfolioId ORDER BY TradeDate) AS PrevNav
    FROM dbo.vw_PortfolioNavDaily
)
SELECT
    PortfolioId,
    TradeDate,
    NetAssetValue,
    PrevNav,
    CASE WHEN PrevNav IS NULL OR PrevNav = 0 THEN NULL
         ELSE (NetAssetValue - PrevNav) / PrevNav END AS DailyReturn
FROM Nav;
GO

/* =====================================================
   Section 5. Execution Plan Tips
   ===================================================== */

-- Пример анализа плана (Manual annotation)
-- 1. Извлеките plan из запроса Section 1 Step 1 (Estimated)
-- 2. Проверьте оператор Hash Match: Estimated Rows vs Actual Rows
-- 3. Убедитесь, что Index Seek заменил Table Scan после создания индекса
-- 4. Проверяйте warnings: Missing Index, No Join Predicate, Spill Level

/* =====================================================
   Готово. Используйте планировщик SQL Agent/DevOps для автоматизации шагов.
   Дополнительные инструкции в лекциях и практических заданиях недели 4.
   ===================================================== */
