/* ========================================================
   Week 3: Stored Procedures, Triggers, Advanced T-SQL
   Готовый набор шаблонов для лекций и практики
   ======================================================== */

/* --------------------------------------------------------
   0. Базовые таблицы и объекты (создаются при необходимости)
   -------------------------------------------------------- */
IF OBJECT_ID('dbo.ProcedureErrorLog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProcedureErrorLog
    (
        ErrorLogID     INT IDENTITY(1,1) PRIMARY KEY,
        ErrorDate      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        ProcedureName  SYSNAME NULL,
        ErrorNumber    INT NOT NULL,
        ErrorSeverity  INT NOT NULL,
        ErrorState     INT NOT NULL,
        ErrorLine      INT NOT NULL,
        ErrorMessage   NVARCHAR(4000) NOT NULL,
        CorrelationID  UNIQUEIDENTIFIER NULL
    );
END;
GO

IF OBJECT_ID('dbo.TransactionAudit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TransactionAudit
    (
        AuditID        BIGINT IDENTITY(1,1) PRIMARY KEY,
        TransactionID  INT NULL,
        PortfolioID    INT NOT NULL,
        ClientID       INT NOT NULL,
        OperationType  NVARCHAR(20) NOT NULL,
        StatusCode     INT NOT NULL,
        StatusMessage  NVARCHAR(4000) NULL,
        TraderLogin    NVARCHAR(128) NULL,
        CorrelationID  UNIQUEIDENTIFIER NULL,
        CreatedAt      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID('dbo.PortfolioChangeLog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PortfolioChangeLog
    (
        ChangeLogID    BIGINT IDENTITY(1,1) PRIMARY KEY,
        PortfolioID    INT NOT NULL,
        OperationType  NVARCHAR(10) NOT NULL,
        ChangedColumns NVARCHAR(4000) NULL,
        OldValues      NVARCHAR(MAX) NULL,
        NewValues      NVARCHAR(MAX) NULL,
        ChangedBy      NVARCHAR(128) NOT NULL,
        ChangedAt      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        CorrelationID  UNIQUEIDENTIFIER NULL
    );
END;
GO

IF OBJECT_ID('dbo.DynamicQueryLog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.DynamicQueryLog
    (
        ExecID      BIGINT IDENTITY(1,1) PRIMARY KEY,
        ExecutedAt  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        ExecutedBy  NVARCHAR(128) NOT NULL,
        QueryText   NVARCHAR(MAX) NOT NULL,
        Parameters  NVARCHAR(MAX) NULL
    );
END;
GO

IF OBJECT_ID('dbo.TradeImportQueue', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TradeImportQueue
    (
        ImportID      INT IDENTITY(1,1) PRIMARY KEY,
        Payload       XML NOT NULL,
        SourceSystem  NVARCHAR(100) NOT NULL,
        ReceivedAt    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        Status        NVARCHAR(30) NOT NULL DEFAULT 'NEW',
        ErrorMessage  NVARCHAR(2000) NULL
    );
END;
GO

IF OBJECT_ID('dbo.TradeImportItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TradeImportItems
    (
        ImportID        INT NOT NULL,
        ExternalTradeID NVARCHAR(50) NOT NULL,
        ClientID        INT NOT NULL,
        PortfolioID     INT NOT NULL,
        InstrumentCode  NVARCHAR(50) NOT NULL,
        TradeDate       DATE NOT NULL,
        Quantity        DECIMAL(18,4) NOT NULL,
        Price           DECIMAL(18,4) NOT NULL,
        Amount          DECIMAL(19,4) NOT NULL,
        Trader          NVARCHAR(100) NULL,
        CorrelationID   UNIQUEIDENTIFIER NULL,
        CreatedAt       DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID('dbo.TradeImportErrors', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TradeImportErrors
    (
        ErrorID         BIGINT IDENTITY(1,1) PRIMARY KEY,
        ImportID        INT NOT NULL,
        TradeExternalID NVARCHAR(50) NULL,
        ErrorCode       NVARCHAR(50) NOT NULL,
        ErrorMessage    NVARCHAR(2000) NOT NULL,
        CreatedAt       DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

/* --------------------------------------------------------
   1. Стандартная процедура логирования ошибок
   -------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_LogError
    @ProcedureName SYSNAME,
    @ErrorNumber   INT,
    @ErrorMessage  NVARCHAR(4000),
    @ErrorSeverity INT,
    @ErrorState    INT,
    @ErrorLine     INT,
    @CorrelationID UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.ProcedureErrorLog
    (
        ProcedureName,
        ErrorNumber,
        ErrorSeverity,
        ErrorState,
        ErrorLine,
        ErrorMessage,
        CorrelationID
    )
    VALUES
    (
        @ProcedureName,
        @ErrorNumber,
        @ErrorSeverity,
        @ErrorState,
        @ErrorLine,
        @ErrorMessage,
        @CorrelationID
    );
END;
GO

/* --------------------------------------------------------
   2. Процедура добавления транзакции с валидацией и логированием
   -------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AddPortfolioTransaction
    @PortfolioID     INT,
    @ClientID        INT,
    @InstrumentCode  NVARCHAR(50),
    @TradeDate       DATETIME2,
    @Quantity        DECIMAL(18,4),
    @Price           DECIMAL(18,4),
    @TraderLogin     NVARCHAR(100),
    @CorrelationID   UNIQUEIDENTIFIER = NULL,
    @StatusCode      INT OUTPUT,
    @StatusMessage   NVARCHAR(4000) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TranStarted BIT = 0;
    DECLARE @TransactionID INT;
    DECLARE @Amount DECIMAL(19,4) = @Quantity * @Price;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @TranStarted = 1;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Portfolios p
            WHERE p.PortfolioID = @PortfolioID
              AND p.IsActive = 1
        )
        BEGIN
            SET @StatusCode = 10;
            SET @StatusMessage = N'Портфель не найден или неактивен.';
            IF @TranStarted = 1 ROLLBACK;
            RETURN;
        END;

        IF EXISTS (
            SELECT 1
            FROM dbo.Portfolios p
            WHERE p.PortfolioID = @PortfolioID
              AND p.ClientID <> @ClientID
        )
        BEGIN
            SET @StatusCode = 20;
            SET @StatusMessage = N'Клиент не совпадает с владельцем портфеля.';
            IF @TranStarted = 1 ROLLBACK;
            RETURN;
        END;

        IF @Quantity <= 0 OR @Price <= 0
        BEGIN
            SET @StatusCode = 30;
            SET @StatusMessage = N'Количество и цена должны быть положительными.';
            IF @TranStarted = 1 ROLLBACK;
            RETURN;
        END;

        IF @TradeDate > SYSUTCDATETIME()
        BEGIN
            SET @StatusCode = 40;
            SET @StatusMessage = N'Дата сделки не может быть в будущем.';
            IF @TranStarted = 1 ROLLBACK;
            RETURN;
        END;

        INSERT INTO dbo.Transactions
        (
            PortfolioID,
            ClientID,
            InstrumentCode,
            TradeDate,
            Quantity,
            Price,
            Amount,
            TraderLogin,
            CorrelationID
        )
        VALUES
        (
            @PortfolioID,
            @ClientID,
            @InstrumentCode,
            @TradeDate,
            @Quantity,
            @Price,
            @Amount,
            @TraderLogin,
            @CorrelationID
        );

        SET @TransactionID = SCOPE_IDENTITY();

        INSERT INTO dbo.TransactionAudit
        (
            TransactionID,
            PortfolioID,
            ClientID,
            OperationType,
            StatusCode,
            StatusMessage,
            TraderLogin,
            CorrelationID
        )
        VALUES
        (
            @TransactionID,
            @PortfolioID,
            @ClientID,
            'INSERT',
            0,
            N'Транзакция успешно добавлена.',
            @TraderLogin,
            @CorrelationID
        );

        SET @StatusCode = 0;
        SET @StatusMessage = N'Транзакция успешно добавлена.';

        IF @TranStarted = 1
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @TranStarted = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_LogError
            @ProcedureName = OBJECT_NAME(@@PROCID),
            @ErrorNumber = ERROR_NUMBER(),
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE(),
            @ErrorLine = ERROR_LINE(),
            @CorrelationID = @CorrelationID;

        SET @StatusCode = ERROR_NUMBER();
        SET @StatusMessage = ERROR_MESSAGE();

        THROW;
    END CATCH
END;
GO

/* --------------------------------------------------------
   3. Триггер для аудита портфелей
   -------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.tr_Portfolios_ChangeAudit
ON dbo.Portfolios
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF TRIGGER_NESTLEVEL() > 1
        RETURN;

    ;WITH Changes AS (
        SELECT
            COALESCE(i.PortfolioID, d.PortfolioID) AS PortfolioID,
            CASE
                WHEN i.PortfolioID IS NOT NULL AND d.PortfolioID IS NULL THEN 'INSERT'
                WHEN i.PortfolioID IS NOT NULL AND d.PortfolioID IS NOT NULL THEN 'UPDATE'
                ELSE 'DELETE'
            END AS OperationType,
            attr.ColumnName,
            attr.OldValue,
            attr.NewValue,
            COALESCE(i.CorrelationID, d.CorrelationID) AS CorrelationID
        FROM inserted i
        FULL OUTER JOIN deleted d ON i.PortfolioID = d.PortfolioID
        CROSS APPLY (
            VALUES
                ('PortfolioName', d.PortfolioName, i.PortfolioName),
                ('ClientID', CAST(d.ClientID AS NVARCHAR(50)), CAST(i.ClientID AS NVARCHAR(50))),
                ('TotalValue', CAST(d.TotalValue AS NVARCHAR(50)), CAST(i.TotalValue AS NVARCHAR(50))),
                ('RiskProfile', d.RiskProfile, i.RiskProfile),
                ('IsActive', CAST(d.IsActive AS NVARCHAR(5)), CAST(i.IsActive AS NVARCHAR(5)))
        ) AS attr (ColumnName, OldValue, NewValue)
        WHERE ISNULL(attr.OldValue, '') <> ISNULL(attr.NewValue, '')
    )
    INSERT INTO dbo.PortfolioChangeLog
    (
        PortfolioID,
        OperationType,
        ChangedColumns,
        OldValues,
        NewValues,
        ChangedBy,
        CorrelationID
    )
    SELECT
        c.PortfolioID,
        c.OperationType,
        STRING_AGG(c.ColumnName, ',') WITHIN GROUP (ORDER BY c.ColumnName) AS ChangedColumns,
        STRING_AGG(CONCAT(c.ColumnName, '=', ISNULL(c.OldValue, 'NULL')), '; ') WITHIN GROUP (ORDER BY c.ColumnName) AS OldValues,
        STRING_AGG(CONCAT(c.ColumnName, '=', ISNULL(c.NewValue, 'NULL')), '; ') WITHIN GROUP (ORDER BY c.ColumnName) AS NewValues,
        SUSER_SNAME(),
        c.CorrelationID
    FROM Changes c
    GROUP BY c.PortfolioID, c.OperationType, c.CorrelationID;
END;
GO

/* --------------------------------------------------------
   4. Процедура обработки XML импорта сделок
   -------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ProcessTradeImport
    @ImportID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Payload XML;
    DECLARE @BatchId UNIQUEIDENTIFIER;
    DECLARE @Source NVARCHAR(100);
    DECLARE @SuccessCount INT = 0;
    DECLARE @ErrorCount INT = 0;

    BEGIN TRY
        SELECT
            @Payload = Payload,
            @Source = SourceSystem
        FROM dbo.TradeImportQueue WITH (UPDLOCK, HOLDLOCK)
        WHERE ImportID = @ImportID;

        IF @Payload IS NULL
        BEGIN
            UPDATE dbo.TradeImportQueue
            SET Status = 'FAILED',
                ErrorMessage = N'Пакет не найден или пуст.'
            WHERE ImportID = @ImportID;
            THROW 52010, 'XML пакет не найден.', 1;
        END;

        SET @BatchId = @Payload.value('(/Trades/@batchId)[1]', 'UNIQUEIDENTIFIER');

        IF @Payload.exist('/Trades/Trade') = 0
        BEGIN
            UPDATE dbo.TradeImportQueue
            SET Status = 'FAILED',
                ErrorMessage = N'XML не содержит элементов Trade.'
            WHERE ImportID = @ImportID;
            THROW 52011, 'XML не содержит элементов Trade.', 1;
        END;

        BEGIN TRANSACTION;

        ;WITH Trades AS (
            SELECT
                @ImportID AS ImportID,
                @BatchId AS CorrelationID,
                t.X.value('@id', 'NVARCHAR(50)') AS ExternalTradeID,
                t.X.value('(ClientID/text())[1]', 'INT') AS ClientID,
                t.X.value('(PortfolioID/text())[1]', 'INT') AS PortfolioID,
                t.X.value('(Instrument/text())[1]', 'NVARCHAR(50)') AS InstrumentCode,
                t.X.value('(TradeDate/text())[1]', 'DATE') AS TradeDate,
                t.X.value('(Quantity/text())[1]', 'DECIMAL(18,4)') AS Quantity,
                t.X.value('(Price/text())[1]', 'DECIMAL(18,4)') AS Price,
                t.X.value('(Trader/text())[1]', 'NVARCHAR(100)') AS Trader
            FROM @Payload.nodes('/Trades/Trade') AS t(X)
        )
        INSERT INTO dbo.TradeImportItems
        (
            ImportID,
            ExternalTradeID,
            ClientID,
            PortfolioID,
            InstrumentCode,
            TradeDate,
            Quantity,
            Price,
            Amount,
            Trader,
            CorrelationID
        )
        SELECT
            t.ImportID,
            t.ExternalTradeID,
            t.ClientID,
            t.PortfolioID,
            t.InstrumentCode,
            t.TradeDate,
            t.Quantity,
            t.Price,
            t.Quantity * t.Price,
            t.Trader,
            t.CorrelationID
        FROM Trades t
        WHERE t.Quantity > 0
          AND t.Price > 0;

        SET @SuccessCount = @@ROWCOUNT;

        INSERT INTO dbo.TradeImportErrors
        (
            ImportID,
            TradeExternalID,
            ErrorCode,
            ErrorMessage
        )
        SELECT
            t.ImportID,
            t.ExternalTradeID,
            'VALIDATION',
            CASE
                WHEN t.Quantity <= 0 THEN 'Quantity must be greater than zero.'
                WHEN t.Price <= 0 THEN 'Price must be greater than zero.'
                ELSE 'Unknown validation error.'
            END
        FROM Trades t
        WHERE t.Quantity <= 0 OR t.Price <= 0;

        SET @ErrorCount = @@ROWCOUNT;

        UPDATE dbo.TradeImportQueue
        SET Status = CASE
                WHEN @SuccessCount > 0 AND @ErrorCount = 0 THEN 'PROCESSED'
                WHEN @SuccessCount > 0 AND @ErrorCount > 0 THEN 'PROCESSED_WITH_ERRORS'
                WHEN @SuccessCount = 0 AND @ErrorCount > 0 THEN 'FAILED'
                ELSE Status
            END,
            ErrorMessage = CASE WHEN @ErrorCount > 0 THEN N'Обнаружены ошибки в сделках.' ELSE NULL END
        WHERE ImportID = @ImportID;

        COMMIT TRANSACTION;

        SELECT
            @ImportID AS ImportID,
            @BatchId AS BatchId,
            @Source AS SourceSystem,
            @SuccessCount AS SuccessCount,
            @ErrorCount AS ErrorCount,
            SUM(Amount) AS TotalAmount
        FROM dbo.TradeImportItems
        WHERE ImportID = @ImportID;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        UPDATE dbo.TradeImportQueue
        SET Status = 'FAILED',
            ErrorMessage = ERROR_MESSAGE()
        WHERE ImportID = @ImportID;

        EXEC dbo.usp_LogError
            @ProcedureName = OBJECT_NAME(@@PROCID),
            @ErrorNumber = ERROR_NUMBER(),
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE(),
            @ErrorLine = ERROR_LINE(),
            @CorrelationID = @BatchId;

        THROW;
    END CATCH
END;
GO

/* --------------------------------------------------------
   5. Динамический поиск по транзакциям
   -------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_SearchTransactionsDynamic
    @ClientName    NVARCHAR(200) = NULL,
    @PortfolioName NVARCHAR(200) = NULL,
    @InstrumentCode NVARCHAR(50) = NULL,
    @DateFrom      DATE = NULL,
    @DateTo        DATE = NULL,
    @MinAmount     DECIMAL(18,2) = NULL,
    @MaxAmount     DECIMAL(18,2) = NULL,
    @TraderLogin   NVARCHAR(100) = NULL,
    @SourceSystem  NVARCHAR(50) = NULL,
    @SortColumn    NVARCHAR(30) = 'TradeDate',
    @SortDirection NVARCHAR(4) = 'DESC',
    @PageNumber    INT = 1,
    @PageSize      INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderColumn NVARCHAR(128) = CASE @SortColumn
        WHEN 'TradeDate' THEN QUOTENAME('TradeDate')
        WHEN 'Amount' THEN QUOTENAME('Amount')
        WHEN 'ClientName' THEN QUOTENAME('ClientName')
        WHEN 'PortfolioName' THEN QUOTENAME('PortfolioName')
        ELSE QUOTENAME('TradeDate')
    END;

    DECLARE @OrderDirection NVARCHAR(4) = CASE WHEN UPPER(@SortDirection) = 'ASC' THEN 'ASC' ELSE 'DESC' END;
    DECLARE @Offset INT = (@PageNumber - 1) * @PageSize;

    DECLARE @SQL NVARCHAR(MAX) = N'
        SELECT
            t.TransactionID,
            c.ClientName,
            p.PortfolioName,
            t.InstrumentCode,
            t.TradeDate,
            t.Amount,
            t.TraderLogin,
            t.SourceSystem,
            COUNT(*) OVER() AS TotalCount
        FROM dbo.Transactions t
        INNER JOIN dbo.Clients c ON c.ClientID = t.ClientID
        INNER JOIN dbo.Portfolios p ON p.PortfolioID = t.PortfolioID
        WHERE 1 = 1';

    DECLARE @ParamDef NVARCHAR(MAX) = N'
        @ClientName NVARCHAR(200),
        @PortfolioName NVARCHAR(200),
        @InstrumentCode NVARCHAR(50),
        @DateFrom DATE,
        @DateTo DATE,
        @MinAmount DECIMAL(18,2),
        @MaxAmount DECIMAL(18,2),
        @TraderLogin NVARCHAR(100),
        @SourceSystem NVARCHAR(50),
        @Offset INT,
        @PageSize INT';

    IF @ClientName IS NOT NULL
        SET @SQL += N' AND c.ClientName LIKE @ClientName';
    IF @PortfolioName IS NOT NULL
        SET @SQL += N' AND p.PortfolioName LIKE @PortfolioName';
    IF @InstrumentCode IS NOT NULL
        SET @SQL += N' AND t.InstrumentCode = @InstrumentCode';
    IF @DateFrom IS NOT NULL
        SET @SQL += N' AND t.TradeDate >= @DateFrom';
    IF @DateTo IS NOT NULL
        SET @SQL += N' AND t.TradeDate <= @DateTo';
    IF @MinAmount IS NOT NULL
        SET @SQL += N' AND t.Amount >= @MinAmount';
    IF @MaxAmount IS NOT NULL
        SET @SQL += N' AND t.Amount <= @MaxAmount';
    IF @TraderLogin IS NOT NULL
        SET @SQL += N' AND t.TraderLogin = @TraderLogin';
    IF @SourceSystem IS NOT NULL
        SET @SQL += N' AND t.SourceSystem = @SourceSystem';

    SET @SQL += N' ORDER BY ' + @OrderColumn + ' ' + @OrderDirection +
                N' OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;';

    DECLARE @Params NVARCHAR(MAX) = (
        SELECT STRING_ESCAPE(CONCAT('ClientName=', ISNULL(@ClientName, 'NULL'), '; ',
                                   'PortfolioName=', ISNULL(@PortfolioName, 'NULL'), '; ',
                                   'InstrumentCode=', ISNULL(@InstrumentCode, 'NULL'), '; ',
                                   'DateFrom=', ISNULL(CONVERT(NVARCHAR(30), @DateFrom, 120), 'NULL'), '; ',
                                   'DateTo=', ISNULL(CONVERT(NVARCHAR(30), @DateTo, 120), 'NULL'), '; ',
                                   'MinAmount=', ISNULL(CONVERT(NVARCHAR(30), @MinAmount), 'NULL'), '; ',
                                   'MaxAmount=', ISNULL(CONVERT(NVARCHAR(30), @MaxAmount), 'NULL'), '; ',
                                   'TraderLogin=', ISNULL(@TraderLogin, 'NULL'), '; ',
                                   'SourceSystem=', ISNULL(@SourceSystem, 'NULL'), '; ',
                                   'SortColumn=', @OrderColumn, '; ',
                                   'SortDirection=', @OrderDirection, '; ',
                                   'PageNumber=', @PageNumber, '; ',
                                   'PageSize=', @PageSize
        ), 'json'));

    INSERT INTO dbo.DynamicQueryLog
    (
        ExecutedBy,
        QueryText,
        Parameters
    )
    VALUES
    (
        SUSER_SNAME(),
        @SQL,
        @Params
    );

    EXEC sp_executesql
        @SQL,
        @ParamDef,
        @ClientName = CASE WHEN @ClientName IS NOT NULL THEN '%' + @ClientName + '%' ELSE NULL END,
        @PortfolioName = CASE WHEN @PortfolioName IS NOT NULL THEN '%' + @PortfolioName + '%' ELSE NULL END,
        @InstrumentCode = @InstrumentCode,
        @DateFrom = @DateFrom,
        @DateTo = @DateTo,
        @MinAmount = @MinAmount,
        @MaxAmount = @MaxAmount,
        @TraderLogin = @TraderLogin,
        @SourceSystem = @SourceSystem,
        @Offset = @Offset,
        @PageSize = @PageSize;
END;
GO

/* --------------------------------------------------------
   6. Процедура пересчёта стоимости портфеля (упрощённая)
   -------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_RecalculatePortfolioValue
    @PortfolioID INT,
    @AsOfDate DATE,
    @RunMode NVARCHAR(20),
    @ForceRecalc BIT = 0,
    @StatusMessage NVARCHAR(4000) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TranStarted BIT = 0;
    DECLARE @ReturnCode INT = 0;
    DECLARE @LastCalculatedAt DATETIME2(3);
    DECLARE @TotalMarketValue DECIMAL(18,2) = 0;
    DECLARE @FXAdjustments DECIMAL(18,2) = 0;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Portfolios WHERE PortfolioID = @PortfolioID AND IsActive = 1)
        BEGIN
            SET @StatusMessage = N'Портфель не найден или неактивен.';
            RETURN 10;
        END;

        SELECT @LastCalculatedAt = LastCalculatedAt
        FROM dbo.Portfolios
        WHERE PortfolioID = @PortfolioID;

        IF @ForceRecalc = 0 AND @LastCalculatedAt IS NOT NULL AND DATEDIFF(MINUTE, @LastCalculatedAt, SYSUTCDATETIME()) < 60
        BEGIN
            SET @StatusMessage = N'Пересчёт выполнен менее часа назад.';
            RETURN 11;
        END;

        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @TranStarted = 1;
        END;

        CREATE TABLE #Holdings
        (
            RowNum INT IDENTITY(1,1) PRIMARY KEY,
            HoldingID INT,
            PortfolioID INT,
            StockSymbol NVARCHAR(20),
            Quantity DECIMAL(18,4),
            CurrentPrice DECIMAL(18,4),
            CurrencyCode NVARCHAR(10)
        );

        INSERT INTO #Holdings (HoldingID, PortfolioID, StockSymbol, Quantity, CurrentPrice, CurrencyCode)
        SELECT
            h.HoldingID,
            h.PortfolioID,
            h.StockSymbol,
            h.Quantity,
            h.CurrentPrice,
            h.CurrencyCode
        FROM dbo.PortfolioHoldings h
        WHERE h.PortfolioID = @PortfolioID;

        DECLARE @Row INT = 1;
        DECLARE @RowCount INT = (SELECT COUNT(*) FROM #Holdings);

        WHILE @Row <= @RowCount
        BEGIN
            DECLARE @Quantity DECIMAL(18,4);
            DECLARE @Price DECIMAL(18,4);
            DECLARE @Currency NVARCHAR(10);
            DECLARE @MarketValue DECIMAL(18,4);

            SELECT
                @Quantity = Quantity,
                @Price = CurrentPrice,
                @Currency = CurrencyCode
            FROM #Holdings
            WHERE RowNum = @Row;

            SET @MarketValue = @Quantity * @Price;
            SET @TotalMarketValue += @MarketValue;

            IF @Currency <> 'USD'
            BEGIN
                DECLARE @Rate DECIMAL(18,8) = ISNULL((
                    SELECT TOP 1 Rate
                    FROM dbo.CurrencyRates
                    WHERE FromCurrency = @Currency AND ToCurrency = 'USD'
                      AND RateDate <= @AsOfDate
                    ORDER BY RateDate DESC
                ), 1);

                SET @FXAdjustments += @MarketValue * (@Rate - 1);
            END;

            SET @Row += 1;
        END;

        UPDATE dbo.Portfolios
        SET TotalValue = @TotalMarketValue + @FXAdjustments,
            LastCalculatedAt = SYSUTCDATETIME()
        WHERE PortfolioID = @PortfolioID;

        INSERT INTO dbo.TransactionAudit
        (
            TransactionID,
            PortfolioID,
            ClientID,
            OperationType,
            StatusCode,
            StatusMessage,
            TraderLogin,
            CorrelationID
        )
        SELECT NULL,
               p.PortfolioID,
               p.ClientID,
               'VALUATION',
               0,
               CONCAT(N'Рассчитана стоимость: ', FORMAT(@TotalMarketValue + @FXAdjustments, 'N2')),
               SUSER_SNAME(),
               NULL
        FROM dbo.Portfolios p
        WHERE p.PortfolioID = @PortfolioID;

        SET @StatusMessage = N'Расчёт завершён успешно.';

        IF @TranStarted = 1
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @TranStarted = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_LogError
            @ProcedureName = OBJECT_NAME(@@PROCID),
            @ErrorNumber = ERROR_NUMBER(),
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE(),
            @ErrorLine = ERROR_LINE();

        SET @StatusMessage = ERROR_MESSAGE();
        RETURN ERROR_NUMBER();
    END CATCH
END;
GO

/* ========================================================
   Конец файла
   ======================================================== */
