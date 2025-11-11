# Практическая задача 4: Временные таблицы для ETL

## Описание

Эта задача ориентирована на использование временных таблиц и табличных переменных для создания процессов ETL (Extract, Transform, Load) с обработкой ошибок и валидацией данных.

## Требуемые таблицы

```sql
-- RawOrderData - необработанные заказы (может быть из внешнего источника)
-- Columns: OrderID, RawClientID, RawOrderDate, RawAmount, RawStatus, SourceFile, LoadDate

-- Clients - клиенты для валидации
-- Columns: ClientID, ClientName, Email, Country

-- Products - товары для валидации
-- Columns: ProductID, ProductName, Category, Price, Stock

-- Orders - целевая таблица
-- Columns: OrderID, ClientID, OrderDate, OrderAmount, OrderStatus, ProcessedDate

-- ErrorLog - журнал ошибок
-- Columns: ErrorID, ErrorCode, ErrorMessage, SourceRecord, ErrorDate, SeverityLevel
```

## Задача 4.1: ETL процесс с временными таблицами

**Цель:** Создать полный ETL процесс для обработки заказов.

**Требования:**
- Шаг 1: Загрузить сырые данные во временную таблицу
- Шаг 2: Валидировать данные (проверить ClientID, формат даты, сумму)
- Шаг 3: Очистить и трансформировать данные
- Шаг 4: Загрузить в целевую таблицу
- Шаг 5: Логировать ошибки
- Шаг 6: Создать отчет обработки

**Заготовка процедуры:**

```sql
CREATE PROCEDURE sp_ProcessOrdersETL
    @SourceFilePath NVARCHAR(500),
    @SuccessCount INT OUTPUT,
    @ErrorCount INT OUTPUT
AS
BEGIN
    BEGIN TRY
        -- Инициализация переменных
        SET @SuccessCount = 0;
        SET @ErrorCount = 0;
        
        -- ============================================================
        -- ШАГ 1: Создание и заполнение временной таблицы сырых данных
        -- ============================================================
        CREATE TABLE #RawOrders (
            RowNum INT IDENTITY(1,1) PRIMARY KEY,
            OrderID INT,
            RawClientID NVARCHAR(50),
            RawOrderDate NVARCHAR(50),
            RawAmount NVARCHAR(50),
            RawStatus NVARCHAR(50),
            ProcessingStatus NVARCHAR(20) DEFAULT 'Pending'
        );
        
        -- Загрузить данные из источника
        INSERT INTO #RawOrders (OrderID, RawClientID, RawOrderDate, RawAmount, RawStatus)
        SELECT * FROM OPENROWSET(
            BULK @SourceFilePath,
            FORMAT = 'CSV'
        );
        
        -- ============================================================
        -- ШАГ 2: Создание таблицы валидации
        -- ============================================================
        CREATE TABLE #ValidationResults (
            RowNum INT PRIMARY KEY,
            OrderID INT,
            ClientID INT,
            OrderDate DATETIME,
            Amount DECIMAL(18,2),
            Status VARCHAR(50),
            ValidationStatus NVARCHAR(20),  -- 'Valid', 'Invalid'
            ValidationMessage NVARCHAR(500)
        );
        
        -- ============================================================
        -- ШАГ 3: Валидация данных
        -- ============================================================
        INSERT INTO #ValidationResults
        SELECT 
            ro.RowNum,
            ro.OrderID,
            CASE 
                WHEN TRY_CAST(ro.RawClientID AS INT) IS NOT NULL THEN TRY_CAST(ro.RawClientID AS INT)
                ELSE -1
            END AS ClientID,
            CASE 
                WHEN TRY_CAST(ro.RawOrderDate AS DATETIME) IS NOT NULL 
                    THEN TRY_CAST(ro.RawOrderDate AS DATETIME)
                ELSE CAST('1900-01-01' AS DATETIME)
            END AS OrderDate,
            CASE 
                WHEN TRY_CAST(ro.RawAmount AS DECIMAL(18,2)) IS NOT NULL 
                    THEN TRY_CAST(ro.RawAmount AS DECIMAL(18,2))
                ELSE 0
            END AS Amount,
            ro.RawStatus,
            CASE 
                WHEN TRY_CAST(ro.RawClientID AS INT) IS NULL THEN 'Invalid'
                WHEN TRY_CAST(ro.RawOrderDate AS DATETIME) IS NULL THEN 'Invalid'
                WHEN TRY_CAST(ro.RawAmount AS DECIMAL(18,2)) IS NULL THEN 'Invalid'
                WHEN TRY_CAST(ro.RawAmount AS DECIMAL(18,2)) <= 0 THEN 'Invalid'
                WHEN NOT EXISTS (SELECT 1 FROM Clients c WHERE c.ClientID = TRY_CAST(ro.RawClientID AS INT)) THEN 'Invalid'
                WHEN ro.RawStatus NOT IN ('Pending', 'Confirmed', 'Shipped', 'Delivered') THEN 'Invalid'
                ELSE 'Valid'
            END AS ValidationStatus,
            CASE 
                WHEN TRY_CAST(ro.RawClientID AS INT) IS NULL THEN 'Invalid ClientID format'
                WHEN TRY_CAST(ro.RawOrderDate AS DATETIME) IS NULL THEN 'Invalid date format'
                WHEN TRY_CAST(ro.RawAmount AS DECIMAL(18,2)) IS NULL THEN 'Invalid amount format'
                WHEN TRY_CAST(ro.RawAmount AS DECIMAL(18,2)) <= 0 THEN 'Amount must be positive'
                WHEN NOT EXISTS (SELECT 1 FROM Clients c WHERE c.ClientID = TRY_CAST(ro.RawClientID AS INT)) THEN 'Client not found'
                WHEN ro.RawStatus NOT IN ('Pending', 'Confirmed', 'Shipped', 'Delivered') THEN 'Invalid status'
                ELSE 'OK'
            END AS ValidationMessage
        FROM #RawOrders ro;
        
        -- ============================================================
        -- ШАГ 4: Очистка и трансформация валидных данных
        -- ============================================================
        CREATE TABLE #CleanedOrders (
            OrderID INT PRIMARY KEY,
            ClientID INT,
            OrderDate DATETIME,
            OrderAmount DECIMAL(18,2),
            OrderStatus VARCHAR(50),
            ProcessedDate DATETIME
        );
        
        INSERT INTO #CleanedOrders
        SELECT 
            OrderID,
            ClientID,
            OrderDate,
            Amount,
            Status,
            GETDATE()
        FROM #ValidationResults
        WHERE ValidationStatus = 'Valid';
        
        SET @SuccessCount = @@ROWCOUNT;
        
        -- ============================================================
        -- ШАГ 5: Загрузка валидных данных в целевую таблицу
        -- ============================================================
        INSERT INTO Orders (OrderID, ClientID, OrderDate, OrderAmount, OrderStatus, ProcessedDate)
        SELECT * FROM #CleanedOrders;
        
        -- ============================================================
        -- ШАГ 6: Логирование ошибок и невалидных записей
        -- ============================================================
        INSERT INTO ErrorLog (ErrorCode, ErrorMessage, SourceRecord, ErrorDate, SeverityLevel)
        SELECT 
            'ETL_VALIDATION_ERROR',
            ValidationMessage,
            'OrderID: ' + CAST(OrderID AS NVARCHAR(50)),
            GETDATE(),
            'WARNING'
        FROM #ValidationResults
        WHERE ValidationStatus = 'Invalid';
        
        SET @ErrorCount = @@ROWCOUNT;
        
        -- ============================================================
        -- ШАГ 7: Отчет обработки
        -- ============================================================
        SELECT 
            @SuccessCount AS ProcessedRecords,
            @ErrorCount AS ErrorRecords,
            (SELECT COUNT(*) FROM #RawOrders) AS TotalRecords,
            CAST(@SuccessCount * 100.0 / (SELECT COUNT(*) FROM #RawOrders) AS DECIMAL(5,2)) AS SuccessRate
        
        -- Очистка временных таблиц (автоматически при завершении процедуры)
        
    END TRY
    BEGIN CATCH
        -- Обработка ошибки
        INSERT INTO ErrorLog (ErrorCode, ErrorMessage, ErrorDate, SeverityLevel)
        VALUES (
            'ETL_PROCESS_ERROR',
            ERROR_MESSAGE(),
            GETDATE(),
            'ERROR'
        );
        
        THROW;
    END CATCH;
END;
```

## Задача 4.2: Сравнение производительности #Temp vs @Table

**Цель:** Измерить производительность временных таблиц и табличных переменных.

**Требования:**
- Создать два варианта одного запроса: с #TempTable и с @TableVariable
- Обработать 100,000 строк в каждом варианте
- Измерить время выполнения и использование памяти
- Сравнить планы выполнения
- Рекомендовать лучший подход

**Вариант 1: С временной таблицей (#TempTable)**

```sql
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Создание временной таблицы
CREATE TABLE #OrdersSummary (
    ClientID INT,
    OrderCount INT,
    TotalAmount DECIMAL(18,2),
    AvgAmount DECIMAL(18,2),
    LastOrderDate DATETIME,
    INDEX idx_ClientID (ClientID)
);

-- Загрузка 100,000 строк
INSERT INTO #OrdersSummary
SELECT TOP 100000
    o.ClientID,
    COUNT(*) AS OrderCount,
    SUM(o.OrderAmount) AS TotalAmount,
    AVG(o.OrderAmount) AS AvgAmount,
    MAX(o.OrderDate) AS LastOrderDate
FROM Orders o
GROUP BY o.ClientID;

-- Запрос с JOIN
SELECT 
    c.ClientName,
    os.OrderCount,
    os.TotalAmount,
    os.AvgAmount,
    os.LastOrderDate
FROM Clients c
INNER JOIN #OrdersSummary os ON c.ClientID = os.ClientID
WHERE os.OrderCount > 5
ORDER BY os.TotalAmount DESC;

DROP TABLE #OrdersSummary;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```

**Вариант 2: С табличной переменной (@TableVariable)**

```sql
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Объявление табличной переменной
DECLARE @OrdersSummary TABLE (
    ClientID INT PRIMARY KEY,
    OrderCount INT,
    TotalAmount DECIMAL(18,2),
    AvgAmount DECIMAL(18,2),
    LastOrderDate DATETIME,
    INDEX idx_ClientID (ClientID)
);

-- Загрузка 100,000 строк
INSERT INTO @OrdersSummary
SELECT TOP 100000
    o.ClientID,
    COUNT(*) AS OrderCount,
    SUM(o.OrderAmount) AS TotalAmount,
    AVG(o.OrderAmount) AS AvgAmount,
    MAX(o.OrderDate) AS LastOrderDate
FROM Orders o
GROUP BY o.ClientID;

-- Запрос с JOIN
SELECT 
    c.ClientName,
    os.OrderCount,
    os.TotalAmount,
    os.AvgAmount,
    os.LastOrderDate
FROM Clients c
INNER JOIN @OrdersSummary os ON c.ClientID = os.ClientID
WHERE os.OrderCount > 5
ORDER BY os.TotalAmount DESC;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```

**Анализ результатов:**

- **#TempTable**: Использует tempdb, может быть быстрее для больших объемов, но требует I/O
- **@TableVariable**: Всегда в памяти, быстрее для малых объемов, но без статистики для оптимизатора

**Рекомендация:**

```
Размер данных | Рекомендуемый подход
< 10,000      | @TableVariable
10,000-100,000| Зависит от конкретного случая
> 100,000     | #TempTable
```

## Задача 4.3: Обработка больших данных в батчах

**Цель:** Создать эффективный процесс обработки больших наборов данных.

**Требования:**
- Обработать данные в батчах по 5,000 строк
- Показать прогресс обработки
- Логировать начало и завершение каждого батча
- Обработать ошибки в пределах батча
- Откатить батч при ошибке

**Заготовка процедуры:**

```sql
CREATE PROCEDURE sp_ProcessLargeDataset
    @BatchSize INT = 5000,
    @MaxBatches INT = NULL
AS
BEGIN
    DECLARE @BatchCount INT = 0;
    DECLARE @ProcessedCount INT = 0;
    DECLARE @ErrorCount INT = 0;
    DECLARE @TotalRecords INT;
    
    -- Получить количество записей для обработки
    SELECT @TotalRecords = COUNT(*)
    FROM RawOrderData
    WHERE ProcessingStatus = 'Pending';
    
    CREATE TABLE #BatchProgress (
        BatchNum INT,
        StartTime DATETIME,
        EndTime DATETIME,
        RecordsProcessed INT,
        ErrorsInBatch INT,
        Status NVARCHAR(50)
    );
    
    -- Основной цикл обработки батчей
    WHILE @ProcessedCount < @TotalRecords AND (@MaxBatches IS NULL OR @BatchCount < @MaxBatches)
    BEGIN
        BEGIN TRY
            SET @BatchCount = @BatchCount + 1;
            
            -- Создание временной таблицы для текущего батча
            IF OBJECT_ID('tempdb..#CurrentBatch') IS NOT NULL
                DROP TABLE #CurrentBatch;
            
            CREATE TABLE #CurrentBatch (
                RowNum INT IDENTITY(1,1),
                OrderID INT,
                ClientID INT,
                OrderDate DATETIME,
                Amount DECIMAL(18,2)
            );
            
            -- Загрузка батча
            INSERT INTO #CurrentBatch (OrderID, ClientID, OrderDate, Amount)
            SELECT TOP (@BatchSize)
                OrderID,
                TRY_CAST(RawClientID AS INT),
                TRY_CAST(RawOrderDate AS DATETIME),
                TRY_CAST(RawAmount AS DECIMAL(18,2))
            FROM RawOrderData
            WHERE ProcessingStatus = 'Pending'
            ORDER BY OrderID;
            
            DECLARE @CurrentBatchCount INT = @@ROWCOUNT;
            
            INSERT INTO #BatchProgress VALUES (
                @BatchCount,
                GETDATE(),
                NULL,
                @CurrentBatchCount,
                0,
                'Processing'
            );
            
            -- Обработка батча в транзакции
            BEGIN TRANSACTION;
            
            -- Обработка данных
            INSERT INTO Orders (OrderID, ClientID, OrderDate, OrderAmount)
            SELECT OrderID, ClientID, OrderDate, Amount
            FROM #CurrentBatch;
            
            -- Обновление статуса
            UPDATE RawOrderData
            SET ProcessingStatus = 'Processed'
            WHERE OrderID IN (SELECT OrderID FROM #CurrentBatch);
            
            COMMIT TRANSACTION;
            
            -- Обновление прогресса
            UPDATE #BatchProgress
            SET EndTime = GETDATE(),
                Status = 'Completed'
            WHERE BatchNum = @BatchCount;
            
            SET @ProcessedCount = @ProcessedCount + @CurrentBatchCount;
            
            PRINT 'Батч ' + CAST(@BatchCount AS NVARCHAR(10)) + ' обработан. ' +
                  'Всего: ' + CAST(@ProcessedCount AS NVARCHAR(10)) + ' / ' + CAST(@TotalRecords AS NVARCHAR(10));
            
        END TRY
        BEGIN CATCH
            -- Откат батча при ошибке
            ROLLBACK TRANSACTION;
            
            UPDATE #BatchProgress
            SET EndTime = GETDATE(),
                Status = 'Error: ' + ERROR_MESSAGE(),
                ErrorsInBatch = -1
            WHERE BatchNum = @BatchCount;
            
            INSERT INTO ErrorLog (ErrorCode, ErrorMessage, ErrorDate, SeverityLevel)
            VALUES ('BATCH_ERROR', 'Batch ' + CAST(@BatchCount AS NVARCHAR(10)) + ': ' + ERROR_MESSAGE(), GETDATE(), 'ERROR');
            
            SET @ErrorCount = @ErrorCount + 1;
        END CATCH;
        
        -- Задержка между батчами для снижения нагрузки
        WAITFOR DELAY '00:00:01';
    END;
    
    -- Финальный отчет
    SELECT 
        @BatchCount AS TotalBatches,
        @ProcessedCount AS TotalProcessed,
        @ErrorCount AS FailedBatches,
        @TotalRecords - @ProcessedCount AS Remaining
    
    SELECT * FROM #BatchProgress ORDER BY BatchNum;
    
    DROP TABLE #BatchProgress;
END;
```

## Задача 4.4: Определение лучшего подхода для вашего сценария

**Цель:** Провести анализ и выбрать оптимальный подход.

**Требования:**
- Сравнить 3 подхода: CTE, #TempTable, @TableVariable
- Для каждого: измерить время, память, читаемость, поддерживаемость
- Создать выводы и рекомендации
- Документировать решение

**Сценарий: Анализ портфелей портфеля для 10,000 клиентов**

**Подход 1: CTE**

```sql
WITH ClientPortfolios AS (
    SELECT 
        p.ClientID,
        p.PortfolioID,
        p.TotalValue,
        SUM(p.TotalValue) OVER (PARTITION BY p.ClientID) AS ClientTotalValue
    FROM Portfolios p
)
SELECT 
    ClientID,
    COUNT(*) AS PortfolioCount,
    SUM(TotalValue) AS TotalValue,
    AVG(TotalValue) AS AvgPortfolioValue
FROM ClientPortfolios
GROUP BY ClientID
ORDER BY TotalValue DESC;
```

**Подход 2: Временная таблица**

```sql
CREATE TABLE #ClientPortfolios (
    ClientID INT,
    PortfolioID INT,
    TotalValue DECIMAL(18,2),
    ClientTotalValue DECIMAL(18,2),
    INDEX idx_ClientID (ClientID)
);

INSERT INTO #ClientPortfolios
SELECT 
    p.ClientID,
    p.PortfolioID,
    p.TotalValue,
    SUM(p.TotalValue) OVER (PARTITION BY p.ClientID)
FROM Portfolios p;

SELECT 
    ClientID,
    COUNT(*) AS PortfolioCount,
    MAX(ClientTotalValue) AS TotalValue,
    AVG(TotalValue) AS AvgPortfolioValue
FROM #ClientPortfolios
GROUP BY ClientID
ORDER BY TotalValue DESC;

DROP TABLE #ClientPortfolios;
```

**Подход 3: Табличная переменная**

```sql
DECLARE @ClientPortfolios TABLE (
    ClientID INT,
    PortfolioID INT,
    TotalValue DECIMAL(18,2),
    ClientTotalValue DECIMAL(18,2),
    PRIMARY KEY (ClientID, PortfolioID)
);

INSERT INTO @ClientPortfolios
SELECT 
    p.ClientID,
    p.PortfolioID,
    p.TotalValue,
    SUM(p.TotalValue) OVER (PARTITION BY p.ClientID)
FROM Portfolios p;

SELECT 
    ClientID,
    COUNT(*) AS PortfolioCount,
    MAX(ClientTotalValue) AS TotalValue,
    AVG(TotalValue) AS AvgPortfolioValue
FROM @ClientPortfolios
GROUP BY ClientID
ORDER BY TotalValue DESC;
```

## Тестирование

```sql
-- 1. Проверьте, что данные согласованы между всеми подходами
-- 2. Используйте SET STATISTICS для сравнения
-- 3. Используйте Execution Plan для анализа
-- 4. Протестируйте на разных размерах данных
-- 5. Убедитесь в правильности обработки ошибок

EXEC sp_ProcessOrdersETL 
    @SourceFilePath = 'C:\Data\orders.csv',
    @SuccessCount = @Success OUTPUT,
    @ErrorCount = @Errors OUTPUT;

SELECT @Success AS SuccessCount, @Errors AS ErrorCount;
```

## Лучший подход для этого сценария

**Рекомендация:**

- **Размер < 10k**: CTE (простота и читаемость)
- **Размер 10k-100k**: #TempTable (производительность и гибкость)
- **Размер > 100k**: #TempTable с индексами и батч-обработкой

---

**Мудрость:** Выбор между CTE, #TempTable и @TableVariable зависит от размера данных, сложности логики и требований к производительности. В этом сценарии предпочтительна временная таблица для больших объемов с возможностью создания индексов.
