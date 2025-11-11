# Лекция 1: Хранимые процедуры (Stored Procedures)

## 1. Введение

Хранимые процедуры — это объекты базы данных, содержащие предварительно скомпилированный T-SQL-код. Они позволяют инкапсулировать бизнес-логику на уровне базы данных, снижать нагрузку на сеть и обеспечивать повторное использование операций.

### 1.1 Преимущества процедур

- Повышенная производительность благодаря повторному использованию планов выполнения
- Единая точка управления логикой и валидаций
- Сокращение сетевого трафика (передаются параметры, а не большие SQL-строки)
- Улучшение безопасности за счёт ограничения прав на таблицы и выдачи EXECUTE на процедуру

## 2. Синтаксис и структура

```sql
CREATE OR ALTER PROCEDURE dbo.usp_CreateTransaction
    @ClientID       INT,
    @PortfolioID    INT,
    @TransactionDate DATE,
    @Amount         DECIMAL(18,2),
    @Description    NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- бизнес-логика
END;
GO
```

### 2.1 Общие рекомендации по оформлению

1. Используйте `CREATE OR ALTER`, чтобы упростить деплой.
2. Всегда добавляйте `SET NOCOUNT ON` в начале тела.
3. Группируйте параметры по типу (ключи, значения, флаги) и сортируйте логично.
4. Применяйте схемы (например, `dbo.`) для явного указания владельца.

### 2.2 Структура "скелета" процедуры

```sql
CREATE OR ALTER PROCEDURE dbo.usp_Template
    @Param1 INT,
    @Param2 NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @TranStarted BIT = 0;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @TranStarted = 1;
        END

        -- Основная логика

        IF @TranStarted = 1 AND @@TRANCOUNT > 0
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @TranStarted = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_LogError
            @ProcedureName = OBJECT_NAME(@@PROCID),
            @ErrorNumber = ERROR_NUMBER(),
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE(),
            @ErrorLine = ERROR_LINE();

        THROW; -- повторно бросаем ошибку для вызывающего кода
    END CATCH
END;
GO
```

## 3. Работа с параметрами

### 3.1 Входные параметры

- Используйте типы, соответствующие столбцам таблиц (`INT`, `DECIMAL(18,2)`, `UNIQUEIDENTIFIER`)
- Задавайте значения по умолчанию для необязательных параметров
- Проверяйте диапазоны и бизнес-правила

```sql
IF (@Amount <= 0)
BEGIN
    THROW 50010, 'Сумма транзакции должна быть положительной.', 1;
END;
```

### 3.2 OUTPUT-параметры

```sql
CREATE OR ALTER PROCEDURE dbo.usp_CreateClient
    @ClientName      NVARCHAR(200),
    @InitialDeposit  DECIMAL(18,2),
    @ClientID        INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Clients (ClientName, InvestmentAmount)
    VALUES (@ClientName, @InitialDeposit);

    SET @ClientID = SCOPE_IDENTITY();
END;
GO
```

**Вызов:**

```sql
DECLARE @NewClientID INT;
EXEC dbo.usp_CreateClient
    @ClientName = N'Carol Danvers',
    @InitialDeposit = 250000,
    @ClientID = @NewClientID OUTPUT;
SELECT @NewClientID AS ClientID;
```

### 3.3 Возвращаемые значения через `RETURN`

`RETURN` используется для передачи кода статуса (целое число). Принято возвращать 0 при успехе и ненулевые значения при ошибках валидации.

```sql
CREATE OR ALTER PROCEDURE dbo.usp_DeletePortfolio
    @PortfolioID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Portfolios WHERE PortfolioID = @PortfolioID)
        RETURN 10; -- портфель не найден

    DELETE FROM dbo.PortfolioHoldings WHERE PortfolioID = @PortfolioID;
    DELETE FROM dbo.Portfolios WHERE PortfolioID = @PortfolioID;

    RETURN 0;
END;
GO
```

**Вызов:**

```sql
DECLARE @Status INT;
EXEC @Status = dbo.usp_DeletePortfolio @PortfolioID = 12;
IF @Status <> 0
BEGIN
    PRINT CONCAT('Удаление не выполнено. Код: ', @Status);
END;
```

### 3.4 Возврат наборов результатов

Процедура может возвращать один или несколько SELECT-запросов. Избегайте непредсказуемого количества наборов, чтобы клиентское приложение знало ожидаемую структуру.

```sql
CREATE OR ALTER PROCEDURE dbo.usp_GetPortfolioSummary
    @PortfolioID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.PortfolioID, p.PortfolioName, p.TotalValue
    FROM dbo.Portfolios p
    WHERE p.PortfolioID = @PortfolioID;

    SELECT ph.StockSymbol,
           ph.Quantity,
           ph.CurrentPrice,
           ph.Quantity * ph.CurrentPrice AS PositionValue
    FROM dbo.PortfolioHoldings ph
    WHERE ph.PortfolioID = @PortfolioID;
END;
```

## 4. Обработка ошибок с TRY/CATCH

### 4.1 Шаблон обработки

```sql
BEGIN TRY
    -- Основная логика
END TRY
BEGIN CATCH
    DECLARE @ErrorNumber   INT = ERROR_NUMBER();
    DECLARE @ErrorMessage  NVARCHAR(2048) = ERROR_MESSAGE();
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrorState    INT = ERROR_STATE();
    DECLARE @ErrorLine     INT = ERROR_LINE();

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    EXEC dbo.usp_LogError
        @ProcedureName = OBJECT_NAME(@@PROCID),
        @ErrorNumber = @ErrorNumber,
        @ErrorMessage = @ErrorMessage,
        @ErrorSeverity = @ErrorSeverity,
        @ErrorState = @ErrorState,
        @ErrorLine = @ErrorLine;

    THROW;
END CATCH;
```

### 4.2 Ведение журнала ошибок

Создайте таблицу `dbo.ProcedureErrorLog` и вспомогательную процедуру `dbo.usp_LogError`, чтобы стандартизировать логирование.

```sql
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
```

```sql
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
```

## 5. Логирование и отладка

### 5.1 Трассировка действий

Используйте таблицы-логи и `RAISERROR`/`THROW` с низкой серьёзностью для отладки в dev-среде.

```sql
RAISERROR('Начало расчёта портфеля %d', 10, 1, @PortfolioID) WITH NOWAIT;
```

### 5.2 Корреляция запросов

Передавайте `@CorrelationID UNIQUEIDENTIFIER` в процедуру для связывания действий в логах приложений и БД.

### 5.3 Отладка

- Используйте `PRINT` и `SELECT` только в дев-среде
- Для боевых сценариев логируйте данные в табличные переменные и просматривайте результаты после тестового запуска

## 6. Оптимизация

### 6.1 Планирование индексов

В процедурах часто встречаются фильтры по входным параметрам. Обеспечьте наличие соответствующих индексов, чтобы избежать сканов.

### 6.2 Параметрический сникер

Используйте `OPTION (RECOMPILE)` для проблемных запросов с сильно варьирующимися параметрами или применяйте шаблон "проверка распределения".

```sql
IF @PortfolioSize > 1000
BEGIN
    -- запрос с фильтрами
    SELECT ...
    FROM ...
    OPTION (RECOMPILE);
END
ELSE
BEGIN
    SELECT ...
    FROM ...;
END;
```

### 6.3 Разделение логики

Вынесите повторно используемые операции в отдельные процедуры и вызывайте их через `EXEC`. Это улучшает читаемость и упрощает тестирование.

## 7. Практические примеры

### 7.1 Создание транзакции с валидацией

```sql
CREATE OR ALTER PROCEDURE dbo.usp_AddTransaction
    @ClientID        INT,
    @PortfolioID     INT,
    @InstrumentCode  NVARCHAR(50),
    @TradeDate       DATE,
    @Quantity        DECIMAL(18,4),
    @Price           DECIMAL(18,4),
    @TraderLogin     NVARCHAR(100),
    @CorrelationID   UNIQUEIDENTIFIER = NULL,
    @StatusMessage   NVARCHAR(4000) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TranStarted BIT = 0;
    DECLARE @Amount DECIMAL(19,4) = @Quantity * @Price;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @TranStarted = 1;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.Portfolios WHERE PortfolioID = @PortfolioID)
        BEGIN
            SET @StatusMessage = N'Портфель не найден.';
            RETURN 20;
        END

        IF @Amount = 0
        BEGIN
            SET @StatusMessage = N'Сумма сделки не может быть нулевой.';
            RETURN 30;
        END

        INSERT INTO dbo.Transactions
        (
            ClientID,
            PortfolioID,
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
            @ClientID,
            @PortfolioID,
            @InstrumentCode,
            @TradeDate,
            @Quantity,
            @Price,
            @Amount,
            @TraderLogin,
            @CorrelationID
        );

        SET @StatusMessage = N'Транзакция успешно добавлена.';

        IF @TranStarted = 1 AND @@TRANCOUNT > 0
            COMMIT TRANSACTION;

        RETURN 0;
    END TRY
    BEGIN CATCH
        IF @TranStarted = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @StatusMessage = ERROR_MESSAGE();

        EXEC dbo.usp_LogError
            @ProcedureName = OBJECT_NAME(@@PROCID),
            @ErrorNumber = ERROR_NUMBER(),
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE(),
            @ErrorLine = ERROR_LINE(),
            @CorrelationID = @CorrelationID;

        RETURN ERROR_NUMBER();
    END CATCH
END;
GO
```

### 7.2 Процедура с OUTPUT-таблицей

```sql
CREATE OR ALTER PROCEDURE dbo.usp_GetTopNHoldings
    @PortfolioID INT,
    @TopN        INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@TopN)
        ph.StockSymbol,
        ph.Quantity,
        ph.CurrentPrice,
        ph.Quantity * ph.CurrentPrice AS PositionValue
    FROM dbo.PortfolioHoldings ph
    WHERE ph.PortfolioID = @PortfolioID
    ORDER BY PositionValue DESC;
END;
GO
```

## 8. Контрольная памятка

| Тема | Вопросы для проверки |
|------|----------------------|
| Параметры | Используются ли типы, совпадающие с таблицами? Есть ли значения по умолчанию? |
| Ошибки | Есть ли TRY/CATCH, логирование и возврат статуса? |
| Транзакции | Избегаем ли вложенных открытий? Проверяется ли `@@TRANCOUNT`? |
| Производительность | Включён ли `SET NOCOUNT ON`? Есть ли индексы под фильтры? |
| Безопасность | Процедура ограничивает доступ к базовым таблицам? |

Продолжайте практику, создавая процедуры для типовых операций: расчёт показателей портфеля, массовые обновления, интеграцию событий. В следующих лекциях мы расширим подходы триггерами, динамическим T-SQL и обработкой XML.
