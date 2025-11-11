# Лекция 3: Расширенные возможности T-SQL

## 1. Управление потоком выполнения

### 1.1 Условные операторы

#### IF/ELSE

```sql
IF EXISTS (SELECT 1 FROM dbo.Portfolios WHERE TotalValue < 0)
BEGIN
    PRINT 'Есть портфели с отрицательной стоимостью.';
END
ELSE
BEGIN
    PRINT 'Все портфели в положительной зоне.';
END;
```

#### CASE

```sql
SELECT
    p.PortfolioID,
    p.PortfolioName,
    p.TotalValue,
    CASE
        WHEN p.TotalValue >= 1000000 THEN 'Premium'
        WHEN p.TotalValue >= 250000 THEN 'Gold'
        WHEN p.TotalValue >= 50000 THEN 'Silver'
        ELSE 'Starter'
    END AS Tier
FROM dbo.Portfolios p;
```

**Рекомендации:**
- Используйте `CASE` внутри выражений, `IF/ELSE` — для управляющих конструкций.
- Предпочитайте `CASE` в `ORDER BY`, чтобы избежать дублирования запросов.

### 1.2 Операторы выбора

```sql
DECLARE @Mode NVARCHAR(20) = 'OVERNIGHT';

SELECT
    CASE @Mode
        WHEN 'INTRADAY'   THEN 'Используем последние котировки'
        WHEN 'OVERNIGHT'  THEN 'Используем закрытие предыдущего дня'
        WHEN 'HISTORICAL' THEN 'Используем архивные данные'
        ELSE 'Режим не распознан'
    END AS Message;
```

## 2. Циклы и итерации

### 2.1 WHILE

```sql
DECLARE @CurrentDate DATE = '2024-01-01';
DECLARE @EndDate     DATE = EOMONTH(@CurrentDate);

WHILE @CurrentDate <= @EndDate
BEGIN
    EXEC dbo.usp_RecalculateDailyPnL @BusinessDate = @CurrentDate;
    SET @CurrentDate = DATEADD(DAY, 1, @CurrentDate);
END;
```

**Лайфхаки:**
- Избегайте бесконечных циклов, добавляйте защитный счётчик итераций.
- Рассматривайте использование табличных конструкций вместо циклов, если задача допускает set-based подход.

### 2.2 BREAK и CONTINUE

```sql
DECLARE @Attempts INT = 0;
WHILE (@Attempts < 5)
BEGIN
    SET @Attempts += 1;

    IF EXISTS (SELECT 1 FROM dbo.BatchQueue WHERE Status = 'READY')
    BEGIN
        EXEC dbo.usp_ProcessBatch;
        BREAK;
    END

    WAITFOR DELAY '00:00:05';
END;
```

## 3. Обработка ошибок

### 3.1 TRY/CATCH + THROW

```sql
BEGIN TRY
    EXEC dbo.usp_AddTransaction
        @ClientID = 101,
        @PortfolioID = 18,
        @InstrumentCode = N'AAPL',
        @TradeDate = SYSDATETIME(),
        @Quantity = 250,
        @Price = 187.34,
        @TraderLogin = SUSER_SNAME();
END TRY
BEGIN CATCH
    DECLARE @ErrorMessage NVARCHAR(4000) = CONCAT('Ошибка добавления сделки: ', ERROR_MESSAGE());
    THROW 51000, @ErrorMessage, 1;
END CATCH;
```

### 3.2 Системные функции ошибок

| Функция | Описание |
|---------|----------|
| `ERROR_NUMBER()` | Код ошибки |
| `ERROR_SEVERITY()` | Серьёзность |
| `ERROR_STATE()` | Состояние |
| `ERROR_PROCEDURE()` | Имя процедуры |
| `ERROR_LINE()` | Номер строки |
| `ERROR_MESSAGE()` | Текст ошибки |

Используйте их внутри CATCH для логирования: `EXEC dbo.usp_LogError ...`.

### 3.3 XACT_STATE()

```sql
BEGIN TRY
    BEGIN TRAN;
    -- DML
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() = -1 -- транзакция сломана
        ROLLBACK;
    ELSE IF XACT_STATE() = 1
        COMMIT; -- допустимое состояние

    THROW;
END CATCH;
```

## 4. Динамический SQL

### 4.1 EXECUTE

```sql
DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM dbo.Portfolios WHERE TotalValue > 1000000';
EXEC (@SQL);
```

**Недостатки:** отсутствие параметризации, риск SQL-инъекций, плохая повторная компиляция.

### 4.2 sp_executesql с параметрами

```sql
DECLARE
    @SQL NVARCHAR(MAX) = N'SELECT PortfolioID, PortfolioName, TotalValue
                           FROM dbo.Portfolios
                           WHERE PortfolioName LIKE @Pattern
                             AND TotalValue >= @MinValue;';

DECLARE
    @ParamDef NVARCHAR(200) = N'@Pattern NVARCHAR(200), @MinValue DECIMAL(18,2)';

EXEC sp_executesql
    @SQL,
    @ParamDef,
    @Pattern = N'%Growth%',
    @MinValue = 250000;
```

### 4.3 Динамическая генерация фильтров

Шаблон: формируем список условий на основе входных параметров.

```sql
CREATE OR ALTER PROCEDURE dbo.usp_SearchTransactions
    @ClientID      INT = NULL,
    @DateFrom      DATE = NULL,
    @DateTo        DATE = NULL,
    @MinAmount     DECIMAL(18,2) = NULL,
    @MaxAmount     DECIMAL(18,2) = NULL,
    @Instrument    NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SQL NVARCHAR(MAX) = N'SELECT TransactionID, ClientID, PortfolioID, Amount, TradeDate
                                   FROM dbo.Transactions WHERE 1 = 1';
    DECLARE @Params NVARCHAR(400) = N'@ClientID INT, @DateFrom DATE, @DateTo DATE,
                                      @MinAmount DECIMAL(18,2), @MaxAmount DECIMAL(18,2),
                                      @Instrument NVARCHAR(50)';

    IF @ClientID IS NOT NULL SET @SQL += N' AND ClientID = @ClientID';
    IF @DateFrom IS NOT NULL SET @SQL += N' AND TradeDate >= @DateFrom';
    IF @DateTo   IS NOT NULL SET @SQL += N' AND TradeDate <= @DateTo';
    IF @MinAmount IS NOT NULL SET @SQL += N' AND Amount >= @MinAmount';
    IF @MaxAmount IS NOT NULL SET @SQL += N' AND Amount <= @MaxAmount';
    IF @Instrument IS NOT NULL SET @SQL += N' AND InstrumentCode = @Instrument';

    EXEC sp_executesql
        @SQL,
        @Params,
        @ClientID,
        @DateFrom,
        @DateTo,
        @MinAmount,
        @MaxAmount,
        @Instrument;
END;
GO
```

### 4.4 Защита от SQL-инъекций

- Валидируйте имена столбцов/таблиц через whitelisting
- Избегайте конкатенации пользовательского ввода напрямую в SQL-строку
- Используйте `QUOTENAME()` для идентификаторов

```sql
DECLARE @OrderBy NVARCHAR(128) = CASE
    WHEN @SortColumn = 'Amount' THEN QUOTENAME(@SortColumn)
    WHEN @SortColumn = 'TradeDate' THEN QUOTENAME(@SortColumn)
    ELSE QUOTENAME('TransactionID')
END;
```

## 5. Работа с курсорами

### 5.1 Когда курсоры оправданы

- Необходимость пошаговой обработки, зависящей от результата предыдущей итерации
- Вычисления с побочными эффектами (вызовы внешних сервисов)
- Обновление нескольких связанных таблиц при строгом порядке

### 5.2 Типы курсоров

| Тип | Характеристики |
|-----|----------------|
| `STATIC` | Делает снимок данных, не видит изменения |
| `FAST_FORWARD` | Быстрый, только для чтения, однонаправленный |
| `KEYSET` | Видит изменения данных, но не новые строки |
| `DYNAMIC` | Полностью динамический, но самый тяжёлый |

### 5.3 Пример курсора

```sql
DECLARE PortfolioCursor CURSOR FAST_FORWARD FOR
    SELECT PortfolioID
    FROM dbo.Portfolios
    WHERE IsActive = 1;

DECLARE @PortfolioID INT;

OPEN PortfolioCursor;
FETCH NEXT FROM PortfolioCursor INTO @PortfolioID;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.usp_RecalculatePortfolio @PortfolioID = @PortfolioID;
    FETCH NEXT FROM PortfolioCursor INTO @PortfolioID;
END;

CLOSE PortfolioCursor;
DEALLOCATE PortfolioCursor;
```

**Совет:** по возможности заменяйте курсоры таблицами и пакетной обработкой.

## 6. Табличные типы и временные таблицы

### 6.1 Табличные переменные

```sql
DECLARE @Rebalance TABLE
(
    PortfolioID   INT,
    StockSymbol   NVARCHAR(20),
    TargetWeight  DECIMAL(5,2)
);
```

Плюсы: простая область видимости, автоматическое удаление. Минусы: ограниченная статистика (улучшена в SQL Server 2019).

### 6.2 Временные таблицы

```sql
CREATE TABLE #PortfolioPnL
(
    PortfolioID INT,
    TradeDate   DATE,
    PnL         DECIMAL(18,2)
);
```

Плюсы: полноценная статистика и индексы, минусы: требуется управление жизненным циклом.

## 7. Служебные возможности

### 7.1 OUTPUT-параметры в DML

```sql
DECLARE @Audit TABLE
(
    TransactionID INT,
    Amount        DECIMAL(18,2)
);

INSERT INTO dbo.Transactions
OUTPUT inserted.TransactionID, inserted.Amount INTO @Audit
SELECT ...
FROM ...;
```

### 7.2 MERGE (использовать аккуратно)

```sql
MERGE dbo.DailyPositions AS target
USING #ComputedPositions AS source
    ON target.PortfolioID = source.PortfolioID AND target.TradeDate = source.TradeDate
WHEN MATCHED THEN
    UPDATE SET target.MarketValue = source.MarketValue,
               target.CreatedAt = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET THEN
    INSERT (PortfolioID, TradeDate, MarketValue)
    VALUES (source.PortfolioID, source.TradeDate, source.MarketValue);
```

> Начиная с SQL Server 2022, рекомендуется рассмотреть альтернативы `MERGE` или включить `HINT = RECOMPILE` из-за известных багов.

## 8. Практические сценарии

### 8.1 Шаблон пакетной обработки

```sql
DECLARE @BatchSize INT = 500;
DECLARE @Offset    INT = 0;
DECLARE @Rows      INT = 1;

WHILE @Rows > 0
BEGIN
    WITH cte AS (
        SELECT TransactionID
        FROM dbo.Transactions
        WHERE Processed = 0
        ORDER BY TransactionID
        OFFSET @Offset ROWS FETCH NEXT @BatchSize ROWS ONLY
    )
    UPDATE t
    SET    Processed = 1
    FROM dbo.Transactions t
    JOIN cte ON t.TransactionID = cte.TransactionID;

    SET @Rows = @@ROWCOUNT;
    SET @Offset += @BatchSize;
END;
```

### 8.2 Отложенное выполнение с динамическим SQL

```sql
CREATE OR ALTER PROCEDURE dbo.usp_ExecutePortfolioReport
    @PortfolioID INT,
    @ReportType  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Params NVARCHAR(100) = N'@PortfolioID INT';

    SET @SQL = CASE @ReportType
        WHEN 'PERFORMANCE' THEN N'SELECT * FROM dbo.fn_GetPortfolioPerformance(@PortfolioID)'
        WHEN 'ALLOCATION'  THEN N'SELECT * FROM dbo.fn_GetPortfolioAllocation(@PortfolioID)'
        WHEN 'RISKS'       THEN N'SELECT * FROM dbo.fn_GetPortfolioRisk(@PortfolioID)'
        ELSE N'SELECT ''Неизвестный тип отчёта'' AS Message'
    END;

    EXEC sp_executesql @SQL, @Params, @PortfolioID = @PortfolioID;
END;
GO
```

## 9. Контрольный список

| Раздел | Вопросы |
|--------|---------|
| Условия | Есть ли единообразие в `CASE` и `IF`? |
| Циклы | Реализованы ли защиты от бесконечных итераций? |
| Ошибки | Используется ли `TRY/CATCH` и корректный `THROW`? |
| Динамический SQL | Выполнена ли параметризация и whitelisting? |
| Курсоры | Обосновано ли их применение? |

## 10. Отладка и профилирование

- `SET STATISTICS IO/TIME ON` для анализа запросов
- Extended Events: `error_reported`, `rpc_completed`, `sql_statement_completed`
- Dynamic Management Views: `sys.dm_exec_requests`, `sys.dm_exec_query_stats`

Расширенный T-SQL позволяет строить адаптивную, отказоустойчивую логику в SQL Server. На следующей лекции мы рассмотрим XML-подходы, которые часто применяются для интеграции и пакетной загрузки данных.
