/*
    Final Project Part 1: Portfolio Management System
    Example Queries and Procedure Executions
    -----------------------------------------------
    Сценарий демонстрирует последовательность чтения данных и вызова
    хранимых процедур после развёртывания схемы и загрузки примеров.
*/

-- 1. Предварительный обзор данных справочников и сделок
SELECT * FROM dbo.Securities ORDER BY SecurityID;
SELECT * FROM dbo.Portfolios ORDER BY PortfolioID;
SELECT * FROM dbo.Transactions ORDER BY TransactionDate;
SELECT * FROM dbo.Quotes ORDER BY SecurityID, QuoteDate DESC;
SELECT * FROM dbo.Operations ORDER BY OperationDate;

-- 2. Добавление новой сделки через процедуру
DECLARE @Result NVARCHAR(20),
        @TransactionID BIGINT;

EXEC dbo.sp_AddTransaction
    @PortfolioID     = 1,
    @SecurityID      = 2,
    @Quantity        = 5.75,
    @Price           = 345.10,
    @TransactionDate = '2024-05-10T11:05:00',
    @Type            = N'BUY',
    @Result          = @Result OUTPUT,
    @TransactionID   = @TransactionID OUTPUT;

SELECT @Result AS ExecutionResult, @TransactionID AS NewTransactionID;
SELECT * FROM dbo.Transactions WHERE TransactionID = @TransactionID;

-- 3. Расчет текущей стоимости портфеля
EXEC dbo.sp_UpdatePortfolioValue @PortfolioID = 1;

-- 4. Комплексная аналитика по портфелю
EXEC dbo.sp_GetPortfolioAnalytics @PortfolioID = 1;

-- 5. План ребалансировки портфеля (JSON-целевое распределение)
DECLARE @TargetAllocation NVARCHAR(MAX) = N'[
  {"SecurityID": 1, "TargetPercent": 40.0},
  {"SecurityID": 2, "TargetPercent": 40.0},
  {"SecurityID": 4, "TargetPercent": 20.0}
]';

EXEC dbo.sp_RebalancePortfolio
    @PortfolioID = 1,
    @TargetAllocation = @TargetAllocation;

-- 6. Генерация отчёта за квартал
EXEC dbo.sp_GenerateReport
    @PortfolioID = 1,
    @StartDate   = '2024-01-01T00:00:00',
    @EndDate     = '2024-03-31T23:59:59';

-- 7. Просмотр аудита операций
SELECT TOP (50) *
FROM dbo.Audit_Log
ORDER BY ChangeDate DESC;
