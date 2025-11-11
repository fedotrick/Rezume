# Практическая задача 5: Представления для бизнес-логики

## Описание

Эта задача ориентирована на создание системы представлений для различных пользователей с разными потребностями, включая индексированные представления для оптимизации и применение в реальных бизнес-сценариях.

## Требуемые таблицы

```sql
-- Clients - клиенты
-- Columns: ClientID, ClientName, Email, City, Country, RegistrationDate, ClientType

-- Portfolios - портфели
-- Columns: PortfolioID, ClientID, PortfolioName, CreatedDate, TotalValue, Status

-- PortfolioHoldings - активы в портфелях
-- Columns: HoldingID, PortfolioID, StockSymbol, Quantity, AcquisitionPrice, CurrentPrice, AcquisitionDate

-- StockPrices - исторические цены
-- Columns: StockID, StockSymbol, TradeDate, OpenPrice, ClosePrice, HighPrice, LowPrice, Volume

-- Orders - заказы
-- Columns: OrderID, ClientID, OrderDate, OrderAmount, OrderStatus, CreatedDate

-- Transactions - транзакции
-- Columns: TransactionID, ClientID, TransactionDate, Amount, TransactionType, Commission

-- AuditLog - журнал аудита
-- Columns: AuditID, ObjectName, ActionType, ChangedBy, ChangeDate, OldValue, NewValue
```

## Задача 5.1: Система представлений для разных пользователей

**Цель:** Создать различные представления для финансистов, менеджеров и аналитиков.

### 5.1.1 Представление для финансистов

**Цель:** Получить финансовый отчет для управления кассой.

```sql
CREATE VIEW vw_Finance_ClientFinancialReport AS
SELECT 
    c.ClientID,
    c.ClientName,
    c.ClientType,
    c.City,
    c.Country,
    COUNT(DISTINCT o.OrderID) AS TransactionCount,
    SUM(o.OrderAmount) AS TotalTransactionValue,
    AVG(o.OrderAmount) AS AvgTransactionValue,
    MIN(o.OrderDate) AS FirstOrderDate,
    MAX(o.OrderDate) AS LastOrderDate,
    DATEDIFF(DAY, MAX(o.OrderDate), GETDATE()) AS DaysSinceLastOrder,
    SUM(t.Commission) AS TotalCommissionPaid,
    CASE 
        WHEN SUM(o.OrderAmount) > 100000 THEN 'Platinum'
        WHEN SUM(o.OrderAmount) > 50000 THEN 'Gold'
        WHEN SUM(o.OrderAmount) > 10000 THEN 'Silver'
        ELSE 'Bronze'
    END AS ClientTier,
    (SELECT SUM(TotalValue) FROM Portfolios p WHERE p.ClientID = c.ClientID) AS TotalPortfolioValue
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
LEFT JOIN Transactions t ON c.ClientID = t.ClientID
GROUP BY c.ClientID, c.ClientName, c.ClientType, c.City, c.Country;

-- Использование
SELECT 
    ClientName,
    TransactionCount,
    TotalTransactionValue,
    TotalCommissionPaid,
    ClientTier
FROM vw_Finance_ClientFinancialReport
WHERE ClientTier IN ('Gold', 'Platinum')
ORDER BY TotalTransactionValue DESC;
```

### 5.1.2 Представление для менеджеров продаж

**Цель:** Получить информацию для управления продажами.

```sql
CREATE VIEW vw_Sales_ClientActivity AS
SELECT 
    c.ClientID,
    c.ClientName,
    c.Email,
    c.City,
    c.RegistrationDate,
    COUNT(o.OrderID) AS OrdersThisMonth,
    SUM(o.OrderAmount) AS SalesThisMonth,
    (SELECT COUNT(*) FROM Orders o2 
     WHERE o2.ClientID = c.ClientID AND MONTH(o2.OrderDate) = MONTH(DATEADD(MONTH, -1, GETDATE()))) AS OrdersLastMonth,
    (SELECT SUM(OrderAmount) FROM Orders o2 
     WHERE o2.ClientID = c.ClientID AND MONTH(o2.OrderDate) = MONTH(DATEADD(MONTH, -1, GETDATE()))) AS SalesLastMonth,
    MAX(o.OrderDate) AS LastContactDate,
    CASE 
        WHEN COUNT(o.OrderID) = 0 AND DATEDIFF(DAY, c.RegistrationDate, GETDATE()) > 180 THEN 'Dormant'
        WHEN COUNT(o.OrderID) >= 5 THEN 'Active'
        WHEN COUNT(o.OrderID) > 0 THEN 'Regular'
        ELSE 'New'
    END AS ClientStatus
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID 
    AND o.OrderDate >= DATEADD(MONTH, -1, GETDATE())
GROUP BY c.ClientID, c.ClientName, c.Email, c.City, c.RegistrationDate;

-- Использование
SELECT 
    ClientName,
    Email,
    City,
    OrdersThisMonth,
    SalesThisMonth,
    ClientStatus
FROM vw_Sales_ClientActivity
WHERE ClientStatus IN ('Dormant', 'New')
ORDER BY LastContactDate;
```

### 5.1.3 Представление для аналитиков

**Цель:** Получить данные для аналитических моделей.

```sql
CREATE VIEW vw_Analytics_ClientBehavior AS
SELECT 
    c.ClientID,
    c.ClientName,
    c.ClientType,
    DATEDIFF(DAY, c.RegistrationDate, GETDATE()) AS ClientAgeInDays,
    COUNT(DISTINCT o.OrderID) AS TotalOrders,
    COUNT(DISTINCT YEAR(o.OrderDate)) AS ActiveYears,
    SUM(o.OrderAmount) AS LifetimeValue,
    AVG(o.OrderAmount) AS AvgOrderValue,
    STDEV(o.OrderAmount) AS StdevOrderValue,
    MAX(o.OrderAmount) AS MaxOrderValue,
    MIN(o.OrderAmount) FILTER (WHERE o.OrderAmount > 0) AS MinOrderValue,
    DATEDIFF(DAY, MIN(o.OrderDate), MAX(o.OrderDate)) AS CustomerLifespan,
    (SELECT COUNT(*) FROM Portfolios p WHERE p.ClientID = c.ClientID) AS PortfolioCount,
    (SELECT SUM(Quantity) FROM PortfolioHoldings ph 
     INNER JOIN Portfolios p ON ph.PortfolioID = p.PortfolioID 
     WHERE p.ClientID = c.ClientID) AS TotalAssets
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID, c.ClientName, c.ClientType, c.RegistrationDate;

-- Использование - примеры для аналитики
-- Клиенты с растущей активностью
SELECT 
    ClientName,
    TotalOrders,
    LifetimeValue,
    ClientAgeInDays,
    LifetimeValue / NULLIF(ClientAgeInDays, 0) AS DailyAvgSpend
FROM vw_Analytics_ClientBehavior
WHERE TotalOrders > 10
ORDER BY DailyAvgSpend DESC;
```

## Задача 5.2: Индексированное представление для оптимизации

**Цель:** Создать индексированное представление для быстрого доступа к часто используемым данным.

**Требования:**
- Использовать SCHEMABINDING
- Создать UNIQUE CLUSTERED INDEX
- Добавить дополнительные индексы для часто используемых критериев
- Сравнить производительность с обычным представлением

### 5.2.1 Создание индексированного представления

```sql
CREATE VIEW vw_IV_PortfolioPerformance
WITH SCHEMABINDING
AS
SELECT 
    p.PortfolioID,
    p.PortfolioName,
    c.ClientID,
    c.ClientName,
    COUNT_BIG(*) AS HoldingCount,
    SUM(CAST(ph.Quantity AS BIGINT)) AS TotalQuantity,
    SUM(CAST(ph.Quantity * ph.CurrentPrice AS BIGINT)) AS TotalCurrentValue,
    SUM(CAST(ph.Quantity * ph.AcquisitionPrice AS BIGINT)) AS TotalAcquisitionValue,
    SUM(CAST(ph.Quantity * (ph.CurrentPrice - ph.AcquisitionPrice) AS BIGINT)) AS TotalGainLoss
FROM dbo.Portfolios p
INNER JOIN dbo.Clients c ON p.ClientID = c.ClientID
INNER JOIN dbo.PortfolioHoldings ph ON p.PortfolioID = ph.PortfolioID
GROUP BY p.PortfolioID, p.PortfolioName, c.ClientID, c.ClientName;

-- Создание уникального кластеризованного индекса (ОБЯЗАТЕЛЕН для индексированного представления)
CREATE UNIQUE CLUSTERED INDEX idx_IV_PortfolioPerformance_PK
ON vw_IV_PortfolioPerformance(PortfolioID);

-- Дополнительные индексы для оптимизации частых запросов
CREATE NONCLUSTERED INDEX idx_IV_ClientID
ON vw_IV_PortfolioPerformance(ClientID)
INCLUDE (PortfolioName, TotalCurrentValue);

CREATE NONCLUSTERED INDEX idx_IV_TotalValue
ON vw_IV_PortfolioPerformance(TotalCurrentValue DESC)
INCLUDE (ClientName, HoldingCount);
```

### 5.2.2 Использование индексированного представления

```sql
-- SQL Server может использовать индекс автоматически
SELECT 
    PortfolioName,
    ClientName,
    HoldingCount,
    TotalCurrentValue,
    TotalGainLoss,
    CAST(TotalGainLoss * 100.0 / TotalAcquisitionValue AS DECIMAL(5,2)) AS ReturnPercent
FROM vw_IV_PortfolioPerformance
WHERE ClientID = 1
ORDER BY TotalCurrentValue DESC;

-- С NOEXPAND - принудительное использование индекса
SELECT TOP 10
    PortfolioName,
    ClientName,
    TotalCurrentValue,
    TotalGainLoss
FROM vw_IV_PortfolioPerformance
WITH (NOEXPAND)
WHERE TotalCurrentValue > 100000
ORDER BY TotalCurrentValue DESC;
```

### 5.2.3 Сравнение производительности

```sql
-- Тест 1: Обычное представление (без индекса)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Запрос на обычное представление
SELECT TOP 100 * FROM vw_Sales_ClientActivity WHERE City = 'New York';

-- Результаты: logical reads, CPU time, elapsed time

-- Тест 2: Индексированное представление
SELECT TOP 100 * FROM vw_IV_PortfolioPerformance WITH (NOEXPAND) WHERE ClientID = 1;

-- Результаты: должны быть значительно ниже

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```

## Задача 5.3: Представления для разных уровней безопасности

**Цель:** Создать представления, которые ограничивают видимость данных по ролям.

### 5.3.1 Представление для администраторов (полный доступ)

```sql
CREATE VIEW vw_Admin_AllClientData AS
SELECT 
    c.*,
    COUNT(o.OrderID) AS OrderCount,
    SUM(o.OrderAmount) AS TotalSpent,
    (SELECT COUNT(*) FROM Transactions t WHERE t.ClientID = c.ClientID) AS TransactionCount
FROM dbo.Clients c
LEFT JOIN dbo.Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID, c.ClientName, c.Email, c.City, c.Country, c.RegistrationDate, c.ClientType;
```

### 5.3.2 Представление для менеджеров (только их клиенты)

```sql
CREATE VIEW vw_Manager_AssignedClients AS
SELECT 
    c.ClientID,
    c.ClientName,
    c.Email,
    c.City,
    c.Country,
    COUNT(o.OrderID) AS OrderCount,
    SUM(o.OrderAmount) AS TotalSpent
FROM dbo.Clients c
LEFT JOIN dbo.Orders o ON c.ClientID = o.ClientID
-- WHERE SUSER_NAME() = c.AssignedManager  -- Фильтр по пользователю
GROUP BY c.ClientID, c.ClientName, c.Email, c.City, c.Country;
```

### 5.3.3 Представление для клиентов (только их данные)

```sql
CREATE VIEW vw_Client_MyPortfolios AS
SELECT 
    p.PortfolioID,
    p.PortfolioName,
    COUNT(ph.HoldingID) AS HoldingCount,
    SUM(ph.Quantity * ph.CurrentPrice) AS CurrentValue,
    SUM(ph.Quantity * (ph.CurrentPrice - ph.AcquisitionPrice)) AS GainLoss
FROM dbo.Portfolios p
LEFT JOIN dbo.PortfolioHoldings ph ON p.PortfolioID = ph.PortfolioID
WHERE p.ClientID = CAST(SESSION_CONTEXT(N'ClientID') AS INT)  -- Использование SESSION_CONTEXT для безопасности
GROUP BY p.PortfolioID, p.PortfolioName;
```

## Задача 5.4: Материализованные представления

**Цель:** Создать материализованные представления для часто используемых запросов.

### 5.4.1 Таблица для материализации

```sql
-- Таблица для хранения результатов материализованного представления
CREATE TABLE MaterializedView_ClientSummary (
    ClientID INT PRIMARY KEY,
    ClientName VARCHAR(100),
    OrderCount INT,
    TotalSpent DECIMAL(18,2),
    AvgOrderValue DECIMAL(18,2),
    LastOrderDate DATETIME,
    PortfolioValue DECIMAL(18,2),
    LastRefreshDate DATETIME,
    RefreshCount INT
);

-- Индексы для быстрого поиска
CREATE INDEX idx_TotalSpent ON MaterializedView_ClientSummary(TotalSpent DESC);
CREATE INDEX idx_LastOrderDate ON MaterializedView_ClientSummary(LastOrderDate DESC);
```

### 5.4.2 Процедура обновления материализованного представления

```sql
CREATE PROCEDURE sp_RefreshMaterializedView_ClientSummary
    @IncrementalUpdate BIT = 0
AS
BEGIN
    IF @IncrementalUpdate = 0
    BEGIN
        -- Полное обновление
        TRUNCATE TABLE MaterializedView_ClientSummary;
    END;
    
    -- Обновление/вставка данных
    MERGE MaterializedView_ClientSummary AS target
    USING (
        SELECT 
            c.ClientID,
            c.ClientName,
            COUNT(o.OrderID) AS OrderCount,
            SUM(o.OrderAmount) AS TotalSpent,
            AVG(o.OrderAmount) AS AvgOrderValue,
            MAX(o.OrderDate) AS LastOrderDate,
            (SELECT SUM(TotalValue) FROM Portfolios p WHERE p.ClientID = c.ClientID) AS PortfolioValue,
            GETDATE() AS LastRefreshDate,
            0 AS RefreshCount
        FROM Clients c
        LEFT JOIN Orders o ON c.ClientID = o.ClientID
        GROUP BY c.ClientID, c.ClientName
    ) AS source
    ON target.ClientID = source.ClientID
    WHEN MATCHED THEN
        UPDATE SET
            OrderCount = source.OrderCount,
            TotalSpent = source.TotalSpent,
            AvgOrderValue = source.AvgOrderValue,
            LastOrderDate = source.LastOrderDate,
            PortfolioValue = source.PortfolioValue,
            LastRefreshDate = source.LastRefreshDate,
            RefreshCount = RefreshCount + 1
    WHEN NOT MATCHED THEN
        INSERT VALUES (
            source.ClientID,
            source.ClientName,
            source.OrderCount,
            source.TotalSpent,
            source.AvgOrderValue,
            source.LastOrderDate,
            source.PortfolioValue,
            source.LastRefreshDate,
            1
        );
    
    PRINT 'Materialized view refreshed at ' + CONVERT(VARCHAR(23), GETDATE(), 121);
END;

-- Планирование обновления каждый час
-- EXEC sp_RefreshMaterializedView_ClientSummary @IncrementalUpdate = 0;
```

### 5.4.3 Использование материализованного представления

```sql
-- Очень быстрый запрос, так как данные уже вычислены
SELECT TOP 20 
    ClientName,
    OrderCount,
    TotalSpent,
    AvgOrderValue,
    PortfolioValue,
    LastRefreshDate
FROM MaterializedView_ClientSummary
WHERE TotalSpent > 50000
ORDER BY TotalSpent DESC;
```

## Задача 5.5: Оптимизация запросов через представления

**Цель:** Показать, как правильные представления могут оптимизировать запросы.

### 5.5.1 Сложный запрос БЕЗ представления

```sql
-- ❌ Медленно и сложно для чтения
SELECT 
    c.ClientID,
    c.ClientName,
    SUM(o.OrderAmount) AS TotalSpent,
    COUNT(DISTINCT o.OrderID) AS OrderCount,
    COUNT(DISTINCT p.PortfolioID) AS PortfolioCount,
    SUM(ph.Quantity * ph.CurrentPrice) AS PortfolioValue,
    AVG(o.OrderAmount) AS AvgOrder,
    MAX(o.OrderDate) AS LastOrder
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
LEFT JOIN Portfolios p ON c.ClientID = p.ClientID
LEFT JOIN PortfolioHoldings ph ON p.PortfolioID = ph.PortfolioID
GROUP BY c.ClientID, c.ClientName
HAVING SUM(o.OrderAmount) > 50000;
```

### 5.5.2 Оптимизированный запрос С представлениями

```sql
-- ✅ Быстро, просто и легко поддерживать
SELECT 
    odc.ClientID,
    odc.ClientName,
    odc.OrderCount,
    odc.TotalSpent,
    odc.AvgOrderValue,
    odc.ClientTier,
    pp.HoldingCount,
    pp.TotalCurrentValue
FROM vw_Finance_ClientFinancialReport odc
LEFT JOIN vw_IV_PortfolioPerformance pp ON odc.ClientID = pp.ClientID
WHERE odc.TotalSpent > 50000
ORDER BY odc.TotalSpent DESC;
```

## Тестирование

```sql
-- 1. Проверьте, что все представления работают
SELECT * FROM vw_Finance_ClientFinancialReport LIMIT 10;
SELECT * FROM vw_Sales_ClientActivity LIMIT 10;
SELECT * FROM vw_Analytics_ClientBehavior LIMIT 10;

-- 2. Проверьте индексированное представление
SELECT * FROM vw_IV_PortfolioPerformance WITH (NOEXPAND) LIMIT 10;

-- 3. Проверьте безопасность
-- Попробуйте обновить данные через представление (должно быть невозможно или ограничено)

-- 4. Проверьте производительность материализованного представления
EXEC sp_RefreshMaterializedView_ClientSummary;
SELECT * FROM MaterializedView_ClientSummary LIMIT 10;

-- 5. Сравните планы выполнения
SET STATISTICS IO ON;
-- Запрос с представлением
-- Запрос без представления
SET STATISTICS IO OFF;
```

## Дополнительные вызовы

1. **Триггеры для представлений** - создать INSTEAD OF триггеры для обновления через представление
2. **Динамические представления** - создать представления, которые фильтруют по ролям пользователя
3. **Представления для отчетов** - создать набор представлений для различных управленческих отчетов
4. **Мониторинг представлений** - отследить использование представлений и их производительность

## Best Practices

```sql
-- ✅ Хорошо: Ясное имя с префиксом
CREATE VIEW vw_Finance_RevenueReport AS ...
CREATE VIEW vw_Sales_ClientList AS ...
CREATE VIEW ivw_ProductSummary AS ...  -- Индексированное представление

-- ❌ Плохо: Непонятное имя
CREATE VIEW v1 AS ...
CREATE VIEW report AS ...

-- ✅ Хорошо: С документацией
EXEC sp_addextendedproperty 
    @name = N'MS_Description',
    @value = N'Shows financial summary for all clients',
    @level0type = N'SCHEMA', @level0name = dbo,
    @level1type = N'VIEW', @level1name = N'vw_Finance_ClientFinancialReport';

-- ✅ Хорошо: Индексированные представления для часто используемых данных
-- ❌ Плохо: Индексированные представления для редко используемых данных (пустая трата памяти)
```

---

**Мудрость:** Хорошо спроектированная система представлений может значительно упростить разработку, улучшить безопасность и оптимизировать производительность приложения. Используйте индексированные представления для критических аналитических запросов, которые выполняются часто.
