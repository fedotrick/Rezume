/*
    Final Project Part 1: Portfolio Management System
    Stored Procedures Definition Script
    -----------------------------------------------
    This script creates the required stored procedures that encapsulate
    transactional and analytical logic for the portfolio management system.
*/

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =====================================================
   1. Procedure: sp_AddTransaction
   ===================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_AddTransaction
    @PortfolioID     INT,
    @SecurityID      INT,
    @Quantity        DECIMAL(18,4),
    @Price           DECIMAL(18,4),
    @TransactionDate DATETIME2(0) = NULL,
    @Type            NVARCHAR(4),
    @Result          NVARCHAR(20) OUTPUT,
    @TransactionID   BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @InitialTranCount INT = @@TRANCOUNT;
    DECLARE @TypeNormalized NVARCHAR(4) = UPPER(LTRIM(RTRIM(@Type)));
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @CurrentUser NVARCHAR(128) = SUSER_SNAME();
    DECLARE @AuditPayload NVARCHAR(MAX);

    SET @TransactionID = NULL;
    SET @Result = N'FAILED';

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Portfolios WHERE PortfolioID = @PortfolioID)
        BEGIN
            RAISERROR(N'Portfolio with ID %d was not found.', 16, 1, @PortfolioID);
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.Securities WHERE SecurityID = @SecurityID)
        BEGIN
            RAISERROR(N'Security with ID %d was not found.', 16, 1, @SecurityID);
        END;

        IF @Quantity IS NULL OR @Quantity <= 0
        BEGIN
            RAISERROR(N'Quantity must be greater than zero.', 16, 1);
        END;

        IF @Price IS NULL OR @Price <= 0
        BEGIN
            RAISERROR(N'Price must be greater than zero.', 16, 1);
        END;

        IF @TypeNormalized NOT IN (N'BUY', N'SELL')
        BEGIN
            RAISERROR(N'Transaction type must be either BUY or SELL.', 16, 1);
        END;

        IF @TransactionDate IS NULL
        BEGIN
            SET @TransactionDate = SYSUTCDATETIME();
        END;

        IF @InitialTranCount = 0
        BEGIN
            BEGIN TRANSACTION;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION AddTransactionSavePoint;
        END;

        INSERT INTO dbo.Transactions
        (
            PortfolioID,
            SecurityID,
            Quantity,
            Price,
            TransactionDate,
            Type
        )
        VALUES
        (
            @PortfolioID,
            @SecurityID,
            @Quantity,
            @Price,
            @TransactionDate,
            @TypeNormalized
        );

        SET @TransactionID = SCOPE_IDENTITY();

        SELECT @AuditPayload = (
            SELECT
                TransactionID   = @TransactionID,
                PortfolioID     = @PortfolioID,
                SecurityID      = @SecurityID,
                Quantity        = @Quantity,
                Price           = @Price,
                TransactionDate = @TransactionDate,
                Type            = @TypeNormalized
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        INSERT INTO dbo.Audit_Log
        (
            TableName,
            Action,
            OldValue,
            NewValue,
            ExecutedBy
        )
        VALUES
        (
            N'dbo.Transactions',
            N'INSERT',
            NULL,
            @AuditPayload,
            @CurrentUser
        );

        IF @InitialTranCount = 0
        BEGIN
            COMMIT TRANSACTION;
        END;

        SET @Result = N'SUCCESS';
    END TRY
    BEGIN CATCH
        SET @ErrorMessage = ERROR_MESSAGE();

        IF XACT_STATE() = -1
        BEGIN
            ROLLBACK TRANSACTION;
        END
        ELSE IF XACT_STATE() = 1
        BEGIN
            IF @InitialTranCount = 0
                ROLLBACK TRANSACTION;
            ELSE
                ROLLBACK TRANSACTION AddTransactionSavePoint;
        END;

        INSERT INTO dbo.Audit_Log
        (
            TableName,
            Action,
            OldValue,
            NewValue,
            ExecutedBy
        )
        VALUES
        (
            N'dbo.Transactions',
            N'ERROR',
            NULL,
            @ErrorMessage,
            @CurrentUser
        );

        SET @Result = N'FAILED';
        SET @TransactionID = NULL;
    END CATCH;
END;
GO

/* =====================================================
   2. Procedure: sp_UpdatePortfolioValue
   ===================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_UpdatePortfolioValue
    @PortfolioID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Portfolios WHERE PortfolioID = @PortfolioID)
    BEGIN
        RAISERROR(N'Portfolio with ID %d was not found.', 16, 1, @PortfolioID);
        RETURN;
    END;

    ;WITH LatestQuotes AS
    (
        SELECT q.SecurityID, q.Price
        FROM dbo.Quotes AS q
        WHERE q.QuoteDate = (
            SELECT MAX(q2.QuoteDate)
            FROM dbo.Quotes AS q2
            WHERE q2.SecurityID = q.SecurityID
        )
    ),
    Holdings AS
    (
        SELECT
            t.SecurityID,
            NetQuantity = SUM(CASE WHEN t.Type = N'BUY' THEN t.Quantity ELSE -t.Quantity END)
        FROM dbo.Transactions AS t
        WHERE t.PortfolioID = @PortfolioID
        GROUP BY t.SecurityID
    )
    SELECT
        PortfolioID    = @PortfolioID,
        PortfolioValue = CAST(ISNULL(SUM(ISNULL(h.NetQuantity, 0) * ISNULL(lq.Price, 0)), 0) AS DECIMAL(38,4)),
        SnapshotDate   = SYSUTCDATETIME()
    FROM Holdings AS h
    LEFT JOIN LatestQuotes AS lq
        ON lq.SecurityID = h.SecurityID
    OPTION (RECOMPILE);
END;
GO

/* =====================================================
   3. Procedure: sp_GetPortfolioAnalytics
   ===================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_GetPortfolioAnalytics
    @PortfolioID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Portfolios WHERE PortfolioID = @PortfolioID)
    BEGIN
        RAISERROR(N'Portfolio with ID %d was not found.', 16, 1, @PortfolioID);
        RETURN;
    END;

    DECLARE @Holdings TABLE
    (
        SecurityID    INT PRIMARY KEY,
        SecurityName  NVARCHAR(150),
        SecurityType  NVARCHAR(50),
        NetQuantity   DECIMAL(18,4),
        CurrentPrice  DECIMAL(18,4),
        MarketValue   DECIMAL(38,4)
    );

    INSERT INTO @Holdings (SecurityID, SecurityName, SecurityType, NetQuantity, CurrentPrice, MarketValue)
    SELECT
        s.SecurityID,
        s.Name,
        s.Type,
        h.NetQuantity,
        ISNULL(lq.Price, 0) AS CurrentPrice,
        CAST(h.NetQuantity * ISNULL(lq.Price, 0) AS DECIMAL(38,4)) AS MarketValue
    FROM
    (
        SELECT
            t.SecurityID,
            SUM(CASE WHEN t.Type = N'BUY' THEN t.Quantity ELSE -t.Quantity END) AS NetQuantity
        FROM dbo.Transactions AS t
        WHERE t.PortfolioID = @PortfolioID
        GROUP BY t.SecurityID
        HAVING SUM(CASE WHEN t.Type = N'BUY' THEN t.Quantity ELSE -t.Quantity END) <> 0
    ) AS h
    INNER JOIN dbo.Securities AS s
        ON s.SecurityID = h.SecurityID
    OUTER APPLY
    (
        SELECT TOP (1) q.Price
        FROM dbo.Quotes AS q
        WHERE q.SecurityID = h.SecurityID
        ORDER BY q.QuoteDate DESC
    ) AS lq;

    DECLARE @TotalValue DECIMAL(38,4) = (SELECT SUM(MarketValue) FROM @Holdings);
    DECLARE @SecuritiesCount INT = (SELECT COUNT(*) FROM @Holdings);
    DECLARE @TotalTransactions INT = (SELECT COUNT(*) FROM dbo.Transactions WHERE PortfolioID = @PortfolioID);
    DECLARE @FirstTransactionDate DATETIME2(0) = (
        SELECT MIN(TransactionDate) FROM dbo.Transactions WHERE PortfolioID = @PortfolioID);
    DECLARE @LastTransactionDate DATETIME2(0) = (
        SELECT MAX(TransactionDate) FROM dbo.Transactions WHERE PortfolioID = @PortfolioID);

    SELECT
        PortfolioID          = @PortfolioID,
        TotalValue           = ISNULL(@TotalValue, 0),
        SecuritiesHeld       = ISNULL(@SecuritiesCount, 0),
        DistinctSecurityTypes = ISNULL((SELECT COUNT(DISTINCT SecurityType) FROM @Holdings), 0),
        TotalTransactions    = @TotalTransactions,
        FirstTransactionDate = @FirstTransactionDate,
        LastTransactionDate  = @LastTransactionDate,
        SnapshotDate         = SYSUTCDATETIME()
    OPTION (RECOMPILE);

    SELECT
        SecurityType,
        SecuritiesCount = COUNT(*),
        TotalNetQuantity = SUM(NetQuantity),
        TotalMarketValue = SUM(MarketValue),
        AllocationPercent = CASE WHEN ISNULL(@TotalValue, 0) = 0 THEN 0
                                 ELSE CAST((SUM(MarketValue) / @TotalValue) * 100 AS DECIMAL(9,4)) END
    FROM @Holdings
    GROUP BY SecurityType
    ORDER BY TotalMarketValue DESC;

    SELECT
        SecurityID,
        SecurityName,
        SecurityType,
        NetQuantity,
        CurrentPrice,
        MarketValue,
        AllocationPercent = CASE WHEN ISNULL(@TotalValue, 0) = 0 THEN 0
                                 ELSE CAST((MarketValue / @TotalValue) * 100 AS DECIMAL(9,4)) END
    FROM @Holdings
    ORDER BY MarketValue DESC;
END;
GO

/* =====================================================
   4. Procedure: sp_RebalancePortfolio
   ===================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_RebalancePortfolio
    @PortfolioID      INT,
    @TargetAllocation NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Portfolios WHERE PortfolioID = @PortfolioID)
    BEGIN
        RAISERROR(N'Portfolio with ID %d was not found.', 16, 1, @PortfolioID);
        RETURN;
    END;

    IF @TargetAllocation IS NULL OR LEN(LTRIM(RTRIM(@TargetAllocation))) = 0
    BEGIN
        RAISERROR(N'Target allocation payload cannot be empty.', 16, 1);
        RETURN;
    END;

    DECLARE @Targets TABLE
    (
        SecurityID    INT PRIMARY KEY,
        TargetPercent DECIMAL(9,4)
    );

    INSERT INTO @Targets (SecurityID, TargetPercent)
    SELECT
        t.SecurityID,
        t.TargetPercent
    FROM OPENJSON(@TargetAllocation)
         WITH
         (
             SecurityID INT '$.SecurityID',
             TargetPercent DECIMAL(9,4) '$.TargetPercent'
         ) AS t
    WHERE t.SecurityID IS NOT NULL;

    IF NOT EXISTS (SELECT 1 FROM @Targets)
    BEGIN
        RAISERROR(N'No valid target allocation rows were provided.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM @Targets WHERE TargetPercent < 0)
    BEGIN
        RAISERROR(N'Target allocation cannot contain negative percentages.', 16, 1);
        RETURN;
    END;

    DECLARE @AllocationSum DECIMAL(12,4) = (SELECT SUM(TargetPercent) FROM @Targets);
    IF ABS(ISNULL(@AllocationSum, 0) - 100) > 0.01
    BEGIN
        RAISERROR(N'Sum of target allocations must equal 100%%. Current sum: %.2f', 16, 1, @AllocationSum);
        RETURN;
    END;

    IF EXISTS (
        SELECT t.SecurityID
        FROM @Targets AS t
        LEFT JOIN dbo.Securities AS s ON s.SecurityID = t.SecurityID
        WHERE s.SecurityID IS NULL
    )
    BEGIN
        RAISERROR(N'Target allocation references securities that do not exist.', 16, 1);
        RETURN;
    END;

    DECLARE @Holdings TABLE
    (
        SecurityID   INT PRIMARY KEY,
        NetQuantity  DECIMAL(18,4),
        CurrentPrice DECIMAL(18,4),
        MarketValue  DECIMAL(38,4)
    );

    INSERT INTO @Holdings (SecurityID, NetQuantity, CurrentPrice, MarketValue)
    SELECT
        h.SecurityID,
        h.NetQuantity,
        ISNULL(lq.Price, 0) AS CurrentPrice,
        CAST(h.NetQuantity * ISNULL(lq.Price, 0) AS DECIMAL(38,4)) AS MarketValue
    FROM
    (
        SELECT
            t.SecurityID,
            SUM(CASE WHEN t.Type = N'BUY' THEN t.Quantity ELSE -t.Quantity END) AS NetQuantity
        FROM dbo.Transactions AS t
        WHERE t.PortfolioID = @PortfolioID
        GROUP BY t.SecurityID
    ) AS h
    LEFT JOIN
    (
        SELECT q.SecurityID, q.Price
        FROM dbo.Quotes AS q
        WHERE q.QuoteDate = (
            SELECT MAX(q2.QuoteDate)
            FROM dbo.Quotes AS q2
            WHERE q2.SecurityID = q.SecurityID
        )
    ) AS lq
        ON lq.SecurityID = h.SecurityID;

    DECLARE @PortfolioValue DECIMAL(38,4) = (SELECT SUM(MarketValue) FROM @Holdings);
    SET @PortfolioValue = ISNULL(@PortfolioValue, 0);

    DECLARE @Plan TABLE
    (
        SecurityID            INT PRIMARY KEY,
        TargetPercent         DECIMAL(9,4),
        CurrentPercent        DECIMAL(9,4),
        CurrentValue          DECIMAL(38,4),
        TargetValue           DECIMAL(38,4),
        CurrentPrice          DECIMAL(18,4),
        NetQuantity           DECIMAL(18,4),
        QuantityToTrade       DECIMAL(18,4),
        ActionRequired        NVARCHAR(10)
    );

    INSERT INTO @Plan
    (
        SecurityID,
        TargetPercent,
        CurrentPercent,
        CurrentValue,
        TargetValue,
        CurrentPrice,
        NetQuantity,
        QuantityToTrade,
        ActionRequired
    )
    SELECT
        s.SecurityID,
        ISNULL(t.TargetPercent, 0) AS TargetPercent,
        CASE WHEN @PortfolioValue = 0 THEN 0
             ELSE CAST((ISNULL(h.MarketValue, 0) / @PortfolioValue) * 100 AS DECIMAL(9,4)) END AS CurrentPercent,
        ISNULL(h.MarketValue, 0) AS CurrentValue,
        CAST((@PortfolioValue * ISNULL(t.TargetPercent, 0)) / 100 AS DECIMAL(38,4)) AS TargetValue,
        ISNULL(
            CASE WHEN h.CurrentPrice IS NULL THEN lq.Price ELSE h.CurrentPrice END, 0
        ) AS CurrentPrice,
        ISNULL(h.NetQuantity, 0) AS NetQuantity,
        CASE
            WHEN ISNULL(
                     CASE WHEN h.CurrentPrice IS NULL THEN lq.Price ELSE h.CurrentPrice END, 0
                 ) = 0 THEN NULL
            ELSE CAST((CAST((@PortfolioValue * ISNULL(t.TargetPercent, 0)) / 100 AS DECIMAL(38,4)) - ISNULL(h.MarketValue, 0)) /
                      ISNULL(
                          CASE WHEN h.CurrentPrice IS NULL THEN lq.Price ELSE h.CurrentPrice END, 0
                      ) AS DECIMAL(18,4))
        END AS QuantityToTrade,
        CASE
            WHEN ISNULL(
                     CASE WHEN h.CurrentPrice IS NULL THEN lq.Price ELSE h.CurrentPrice END, 0
                 ) = 0 THEN N'REVIEW'
            WHEN CAST((@PortfolioValue * ISNULL(t.TargetPercent, 0)) / 100 AS DECIMAL(38,4)) - ISNULL(h.MarketValue, 0) > 0.0001 THEN N'BUY'
            WHEN CAST((@PortfolioValue * ISNULL(t.TargetPercent, 0)) / 100 AS DECIMAL(38,4)) - ISNULL(h.MarketValue, 0) < -0.0001 THEN N'SELL'
            ELSE N'HOLD'
        END AS ActionRequired
    FROM (
            SELECT SecurityID FROM @Targets
            UNION
            SELECT SecurityID FROM @Holdings
         ) AS s
    LEFT JOIN @Targets AS t
        ON t.SecurityID = s.SecurityID
    LEFT JOIN @Holdings AS h
        ON h.SecurityID = s.SecurityID
    LEFT JOIN
    (
        SELECT q.SecurityID, q.Price
        FROM dbo.Quotes AS q
        WHERE q.QuoteDate = (
            SELECT MAX(q2.QuoteDate)
            FROM dbo.Quotes AS q2
            WHERE q2.SecurityID = q.SecurityID
        )
    ) AS lq
        ON lq.SecurityID = s.SecurityID;

    SELECT
        PortfolioID     = @PortfolioID,
        CurrentValue    = @PortfolioValue,
        TargetCount     = (SELECT COUNT(*) FROM @Targets),
        HoldingsCount   = (SELECT COUNT(*) FROM @Holdings WHERE NetQuantity <> 0),
        GeneratedAt     = SYSUTCDATETIME()
    OPTION (RECOMPILE);

    SELECT
        p.SecurityID,
        sec.Ticker,
        sec.Name AS SecurityName,
        TargetPercent,
        CurrentPercent,
        CurrentValue,
        TargetValue,
        CurrentPrice,
        NetQuantity,
        QuantityToTrade,
        ActionRequired
    FROM @Plan AS p
    INNER JOIN dbo.Securities AS sec
        ON sec.SecurityID = p.SecurityID
    ORDER BY
        CASE p.ActionRequired WHEN N'SELL' THEN 1 WHEN N'BUY' THEN 2 WHEN N'HOLD' THEN 3 ELSE 4 END,
        ABS(ISNULL(p.QuantityToTrade, 0)) DESC;
END;
GO

/* =====================================================
   5. Procedure: sp_GenerateReport
   ===================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_GenerateReport
    @PortfolioID INT,
    @StartDate   DATETIME2(0),
    @EndDate     DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;

    IF @StartDate IS NULL OR @EndDate IS NULL OR @EndDate < @StartDate
    BEGIN
        RAISERROR(N'Invalid report period specified.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.Portfolios WHERE PortfolioID = @PortfolioID)
    BEGIN
        RAISERROR(N'Portfolio with ID %d was not found.', 16, 1, @PortfolioID);
        RETURN;
    END;

    DECLARE @Transactions TABLE
    (
        TransactionID   BIGINT,
        SecurityID      INT,
        Quantity        DECIMAL(18,4),
        Price           DECIMAL(18,4),
        TransactionDate DATETIME2(0),
        Type            NVARCHAR(4),
        CashFlow        DECIMAL(38,4)
    );

    INSERT INTO @Transactions
    SELECT
        t.TransactionID,
        t.SecurityID,
        t.Quantity,
        t.Price,
        t.TransactionDate,
        t.Type,
        CASE WHEN t.Type = N'BUY' THEN -1 ELSE 1 END * (t.Quantity * t.Price) AS CashFlow
    FROM dbo.Transactions AS t
    WHERE t.PortfolioID = @PortfolioID
      AND t.TransactionDate >= @StartDate
      AND t.TransactionDate <= @EndDate;

    DECLARE @TotalInvested DECIMAL(38,4) = (
        SELECT SUM(-CashFlow) FROM @Transactions WHERE CashFlow < 0);
    DECLARE @TotalProceeds DECIMAL(38,4) = (
        SELECT SUM(CashFlow) FROM @Transactions WHERE CashFlow > 0);
    DECLARE @NetCashFlow DECIMAL(38,4) = ISNULL(@TotalProceeds, 0) - ISNULL(@TotalInvested, 0);

    DECLARE @CurrentValue DECIMAL(38,4) = (
        SELECT SUM(ISNULL(h.NetQuantity, 0) * ISNULL(lq.Price, 0))
        FROM
        (
            SELECT
                t.SecurityID,
                SUM(CASE WHEN t.Type = N'BUY' THEN t.Quantity ELSE -t.Quantity END) AS NetQuantity
            FROM dbo.Transactions AS t
            WHERE t.PortfolioID = @PortfolioID
            GROUP BY t.SecurityID
        ) AS h
        LEFT JOIN
        (
            SELECT q.SecurityID, q.Price
            FROM dbo.Quotes AS q
            WHERE q.QuoteDate = (
                SELECT MAX(q2.QuoteDate)
                FROM dbo.Quotes AS q2
                WHERE q2.SecurityID = q.SecurityID
            )
        ) AS lq
            ON lq.SecurityID = h.SecurityID
    );

    DECLARE @RealizedPnL DECIMAL(38,4) = ISNULL(@NetCashFlow, 0);
    DECLARE @ROI DECIMAL(38,4) = CASE WHEN ISNULL(@TotalInvested, 0) = 0 THEN NULL
                                      ELSE (@RealizedPnL / @TotalInvested) * 100 END;

    SELECT
        PortfolioID          = @PortfolioID,
        PeriodStart          = @StartDate,
        PeriodEnd            = @EndDate,
        TotalTransactions    = (SELECT COUNT(*) FROM @Transactions),
        TotalInvested        = ISNULL(@TotalInvested, 0),
        TotalProceeds        = ISNULL(@TotalProceeds, 0),
        NetCashFlow          = ISNULL(@NetCashFlow, 0),
        CurrentPortfolioValue = ISNULL(@CurrentValue, 0),
        RealizedPnL          = ISNULL(@RealizedPnL, 0),
        ROI_Percent          = @ROI,
        GeneratedAt          = SYSUTCDATETIME()
    OPTION (RECOMPILE);

    SELECT
        txn.TransactionID,
        txn.TransactionDate,
        sec.Ticker,
        sec.Name        AS SecurityName,
        txn.Type,
        txn.Quantity,
        txn.Price,
        TransactionAmount = txn.Quantity * txn.Price,
        CashFlow          = txn.CashFlow
    FROM @Transactions AS txn
    LEFT JOIN dbo.Securities AS sec
        ON sec.SecurityID = txn.SecurityID
    ORDER BY txn.TransactionDate;

    SELECT
        OperationID,
        PortfolioID,
        Description,
        Amount,
        OperationDate,
        Category
    FROM dbo.Operations
    WHERE PortfolioID = @PortfolioID
      AND OperationDate >= @StartDate
      AND OperationDate <= @EndDate
    ORDER BY OperationDate;
END;
GO
