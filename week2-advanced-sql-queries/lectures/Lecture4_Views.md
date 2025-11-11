# Лекция 4: Представления (Views)

## 1. Основные концепции представлений

### 1.1 Что такое представление?

View (Представление) - это виртуальная таблица, созданная на основе одного или нескольких запросов к одной или нескольким базовым таблицам. View не хранит данные, а хранит определение запроса.

**Преимущества представлений:**
- Абстракция и упрощение сложных запросов
- Безопасность - ограничение доступа к определенным столбцам
- Переиспользуемость логики
- Обслуживаемость - изменение логики в одном месте
- Согласованность данных для разных пользователей

### 1.2 Типы представлений

| Тип | Описание | Использование |
|-----|---------|---------------|
| **Simple View** | На основе одной таблицы, простая логика | Абстракция простых данных |
| **Complex View** | На основе нескольких таблиц, JOINы, агрегация | Сложная бизнес-логика |
| **Indexed View** | С физическим индексом | Оптимизация производительности |
| **Partitioned View** | Объединяет данные из нескольких таблиц | Разделение данных по партициям |
| **Materialized View** | Хранит результаты физически (в SQL Server через indexed view) | Очень частые запросы |

## 2. Простые представления

### 2.1 Создание простого представления

```sql
CREATE VIEW vw_HighValueOrders AS
SELECT 
    OrderID,
    ClientID,
    OrderDate,
    OrderAmount,
    YEAR(OrderDate) AS OrderYear,
    MONTH(OrderDate) AS OrderMonth
FROM Orders
WHERE OrderAmount >= 5000;

-- Использование представления как таблицы
SELECT * FROM vw_HighValueOrders
WHERE OrderYear = 2024
ORDER BY OrderAmount DESC;
```

### 2.2 Представление для безопасности

```sql
-- Скрыть чувствительные данные
CREATE VIEW vw_PublicClientInfo AS
SELECT 
    ClientID,
    ClientName,
    RegistrationDate,
    City,
    Country
FROM Clients;
-- Важно: Email, PhoneNumber, SocialSecurityNumber не включены

-- Пользователи получают доступ только к этому представлению
SELECT * FROM vw_PublicClientInfo;
```

### 2.3 Представление для упрощения

```sql
-- Вместо сложного запроса с JOINами
CREATE VIEW vw_ClientOrderSummary AS
SELECT 
    c.ClientID,
    c.ClientName,
    c.Email,
    COUNT(o.OrderID) AS TotalOrders,
    SUM(o.OrderAmount) AS TotalSpent,
    AVG(o.OrderAmount) AS AvgOrderValue,
    MAX(o.OrderDate) AS LastOrderDate
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID, c.ClientName, c.Email;

-- Простое использование
SELECT 
    ClientName,
    TotalOrders,
    TotalSpent
FROM vw_ClientOrderSummary
WHERE TotalSpent > 50000;
```

## 3. Сложные представления

### 3.1 Представление с множественными JOINами

```sql
CREATE VIEW vw_OrderDetails AS
SELECT 
    o.OrderID,
    o.OrderDate,
    c.ClientName,
    c.City,
    p.ProductName,
    p.Category,
    oi.Quantity,
    oi.Price,
    (oi.Quantity * oi.Price) AS ItemTotal,
    o.OrderAmount
FROM Orders o
INNER JOIN Clients c ON o.ClientID = c.ClientID
INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
INNER JOIN Products p ON oi.ProductID = p.ProductID;

SELECT * FROM vw_OrderDetails
WHERE Category = 'Technology'
ORDER BY OrderDate DESC;
```

### 3.2 Представление с подзапросами

```sql
CREATE VIEW vw_ClientSegmentation AS
WITH ClientSpending AS (
    SELECT 
        ClientID,
        ClientName,
        SUM(OrderAmount) AS TotalSpent,
        COUNT(OrderID) AS OrderCount,
        MAX(OrderDate) AS LastOrderDate
    FROM Orders o
    INNER JOIN Clients c ON o.ClientID = c.ClientID
    GROUP BY o.ClientID, c.ClientName
)
SELECT 
    ClientID,
    ClientName,
    TotalSpent,
    OrderCount,
    LastOrderDate,
    CASE 
        WHEN TotalSpent >= 100000 THEN 'Platinum'
        WHEN TotalSpent >= 50000 THEN 'Gold'
        WHEN TotalSpent >= 10000 THEN 'Silver'
        ELSE 'Bronze'
    END AS ClientTier,
    DATEDIFF(DAY, LastOrderDate, GETDATE()) AS DaysSinceLastOrder
FROM ClientSpending;

SELECT * FROM vw_ClientSegmentation
WHERE ClientTier = 'Platinum';
```

### 3.3 Представление с оконными функциями

```sql
CREATE VIEW vw_SalesRanking AS
SELECT 
    SalesPersonID,
    SalesPersonName,
    SaleAmount,
    SaleDate,
    RANK() OVER (ORDER BY SaleAmount DESC) AS SaleRank,
    PERCENT_RANK() OVER (ORDER BY SaleAmount) * 100 AS PercentRank,
    SUM(SaleAmount) OVER (
        PARTITION BY YEAR(SaleDate)
        ORDER BY SaleDate
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS YearToDateSales
FROM Sales;

SELECT TOP 10 * FROM vw_SalesRanking
ORDER BY SaleRank;
```

## 4. Индексированные представления (Indexed Views)

### 4.1 Понимание индексированных представлений

Индексированное представление - это представление, которому присвоен физический индекс кластеризации. Результаты представления фактически хранятся в базе данных и обновляются при изменении базовых таблиц.

**Требования для индексированного представления:**
- VIEW должно использовать SCHEMABINDING
- Первый индекс должен быть CLUSTERED
- Не может использовать UNION, подзапросы и т.д.
- Не может использовать OUTER JOIN

### 4.2 Создание индексированного представления

```sql
CREATE VIEW vw_ProductSalesAggregated
WITH SCHEMABINDING
AS
SELECT 
    p.ProductID,
    p.ProductName,
    COUNT_BIG(*) AS SaleCount,
    SUM(CAST(oi.Quantity AS BIGINT)) AS TotalQuantity,
    SUM(CAST(oi.Quantity * oi.Price AS BIGINT)) AS TotalRevenue
FROM dbo.Products p
INNER JOIN dbo.OrderItems oi ON p.ProductID = oi.ProductID
GROUP BY p.ProductID, p.ProductName;

-- Создание индекса кластеризации
CREATE UNIQUE CLUSTERED INDEX idx_ProductSalesAgg
ON vw_ProductSalesAggregated(ProductID);

-- Опционально: создание дополнительных индексов
CREATE NONCLUSTERED INDEX idx_SaleCount
ON vw_ProductSalesAggregated(SaleCount DESC)
INCLUDE (ProductName);
```

### 4.3 Использование индексированного представления

```sql
-- Без NOEXPAND - SQL Server может использовать индекс автоматически
SELECT 
    ProductName,
    SaleCount,
    TotalRevenue
FROM vw_ProductSalesAggregated
WHERE TotalRevenue > 50000;

-- С NOEXPAND - принудительное использование индекса
SELECT 
    ProductName,
    SaleCount,
    TotalRevenue
FROM vw_ProductSalesAggregated
WITH (NOEXPAND)
WHERE SaleCount > 100;
```

### 4.4 Производительность индексированных представлений

```sql
-- Без индексированного представления: должен выполнить JOIN и GROUP BY
SET STATISTICS IO ON;
SELECT 
    p.ProductID,
    p.ProductName,
    COUNT(*) AS SaleCount,
    SUM(oi.Quantity) AS TotalQuantity,
    SUM(oi.Quantity * oi.Price) AS TotalRevenue
FROM Products p
INNER JOIN OrderItems oi ON p.ProductID = oi.ProductID
GROUP BY p.ProductID, p.ProductName;

-- С индексированным представлением: простое сканирование индекса
SELECT 
    ProductID,
    ProductName,
    SaleCount,
    TotalQuantity,
    TotalRevenue
FROM vw_ProductSalesAggregated;
SET STATISTICS IO OFF;
```

## 5. Обновление и удаление представлений

### 5.1 Изменение представления (ALTER VIEW)

```sql
ALTER VIEW vw_HighValueOrders AS
SELECT 
    OrderID,
    ClientID,
    OrderDate,
    OrderAmount,
    YEAR(OrderDate) AS OrderYear,
    MONTH(OrderDate) AS OrderMonth,
    DATEDIFF(DAY, OrderDate, GETDATE()) AS DaysOld  -- Новая колонка
FROM Orders
WHERE OrderAmount >= 5000;
```

### 5.2 Удаление представления (DROP VIEW)

```sql
-- Простое удаление
DROP VIEW vw_HighValueOrders;

-- Удаление с проверкой существования
DROP VIEW IF EXISTS vw_HighValueOrders;

-- Удаление нескольких представлений
DROP VIEW IF EXISTS vw_View1, vw_View2, vw_View3;
```

### 5.3 Вывод определения представления

```sql
-- Посмотреть определение представления
EXEC sp_helptext 'vw_HighValueOrders';

-- Или через системный каталог
SELECT 
    definition
FROM sys.sql_modules
WHERE object_id = OBJECT_ID('vw_HighValueOrders');
```

## 6. Обновляемые представления

### 6.1 Вставка данных через представление

```sql
-- Представление для добавления заказов
CREATE VIEW vw_NewOrders AS
SELECT 
    OrderID,
    ClientID,
    OrderDate,
    OrderAmount,
    OrderStatus
FROM Orders
WHERE OrderStatus = 'Pending';

-- Вставка через представление
INSERT INTO vw_NewOrders (ClientID, OrderDate, OrderAmount, OrderStatus)
VALUES (1, GETDATE(), 5000, 'Pending');
```

### 6.2 Обновление через представление

```sql
-- Обновление статуса заказов через представление
UPDATE vw_NewOrders
SET OrderStatus = 'Confirmed'
WHERE OrderDate < DATEADD(DAY, -7, GETDATE());
```

### 6.3 Сложные представления с INSTEAD OF триггерами

```sql
-- Для сложных представлений, которые невозможно обновить напрямую
CREATE VIEW vw_ComplexClientOrders AS
SELECT 
    c.ClientID,
    c.ClientName,
    o.OrderID,
    o.OrderDate,
    COUNT(oi.OrderItemID) AS ItemCount,
    SUM(oi.Quantity * oi.Price) AS OrderAmount
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
LEFT JOIN OrderItems oi ON o.OrderID = oi.OrderID
GROUP BY c.ClientID, c.ClientName, o.OrderID, o.OrderDate;

-- Триггер для вставки
CREATE TRIGGER trg_InsertClientOrder
ON vw_ComplexClientOrders
INSTEAD OF INSERT
AS
BEGIN
    INSERT INTO Orders (ClientID, OrderDate)
    SELECT DISTINCT ClientID, OrderDate
    FROM inserted;
END;
```

## 7. Представления для разных пользователей

### 7.1 Представление для финансистов

```sql
CREATE VIEW vw_FinanceReport AS
SELECT 
    c.ClientID,
    c.ClientName,
    COUNT(o.OrderID) AS TransactionCount,
    SUM(o.OrderAmount) AS TotalValue,
    AVG(o.OrderAmount) AS AvgTransaction,
    MAX(o.OrderDate) AS LastTransaction,
    CASE 
        WHEN SUM(o.OrderAmount) > 100000 THEN 'High Value'
        WHEN SUM(o.OrderAmount) > 10000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS ClientValue
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID, c.ClientName;
```

### 7.2 Представление для менеджеров продаж

```sql
CREATE VIEW vw_SalesManagerReport AS
SELECT 
    s.SalesPersonID,
    s.SalesPersonName,
    c.ClientName,
    o.OrderDate,
    o.OrderAmount,
    RANK() OVER (PARTITION BY s.SalesPersonID ORDER BY o.OrderAmount DESC) AS ClientRank,
    SUM(o.OrderAmount) OVER (PARTITION BY s.SalesPersonID) AS TotalSales
FROM SalesPersons s
LEFT JOIN Orders o ON s.SalesPersonID = o.SalesPersonID
LEFT JOIN Clients c ON o.ClientID = c.ClientID
WHERE o.OrderDate >= DATEADD(MONTH, -3, GETDATE());
```

### 7.3 Представление для аналитиков

```sql
CREATE VIEW vw_AnalyticsData AS
SELECT 
    p.ProductID,
    p.ProductName,
    p.Category,
    oi.OrderItemID,
    oi.Quantity,
    oi.Price,
    (oi.Quantity * oi.Price) AS Revenue,
    o.OrderDate,
    DATEPART(QUARTER, o.OrderDate) AS Quarter,
    YEAR(o.OrderDate) AS Year,
    c.ClientID,
    c.ClientName,
    DATEDIFF(DAY, c.RegistrationDate, o.OrderDate) AS ClientAgeAtPurchase
FROM Products p
INNER JOIN OrderItems oi ON p.ProductID = oi.ProductID
INNER JOIN Orders o ON oi.OrderID = o.OrderID
INNER JOIN Clients c ON o.ClientID = c.ClientID;
```

## 8. Best Practices для представлений

### 8.1 Рекомендации по проектированию

```sql
-- ✅ Хорошо: Четкое, простое в понимании имя
CREATE VIEW vw_ActiveClientOrders AS ...

-- ❌Плохо: Непонятное имя
CREATE VIEW v1 AS ...

-- ✅ Хорошо: Используйте префикс для типа представления
CREATE VIEW vw_HighValueOrders AS ... -- Simple view
CREATE VIEW ivw_ProductSales AS ...   -- Indexed view
CREATE VIEW vw_ClientSegmentation_Security AS ... -- Security view

-- ✅ Хорошо: Документируйте представление
EXEC sp_addextendedproperty 
    @name = N'MS_Description',
    @value = N'Показывает активные заказы клиентов за последние 30 дней',
    @level0type = N'SCHEMA', @level0name = dbo,
    @level1type = N'VIEW', @level1name = N'vw_ActiveClientOrders';
```

### 8.2 Управление зависимостями

```sql
-- Посмотреть, какие объекты зависят от представления
EXEC sp_depends 'vw_ClientOrderSummary';

-- Посмотреть, от каких объектов зависит представление
SELECT DISTINCT
    referenced_schema_name,
    referenced_entity_name
FROM sys.dm_sql_referenced_entities('dbo.vw_ClientOrderSummary', 'OBJECT');
```

### 8.3 Мониторинг представлений

```sql
-- Найти редко используемые представления
SELECT 
    OBJECT_NAME(i.object_id) AS ViewName,
    SUM(s.user_seeks) AS Seeks,
    SUM(s.user_scans) AS Scans,
    SUM(s.user_lookups) AS Lookups,
    SUM(s.user_updates) AS Updates
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s 
    ON i.object_id = s.object_id
WHERE OBJECTPROPERTY(i.object_id, 'IsView') = 1
GROUP BY i.object_id
ORDER BY (Seeks + Scans + Lookups) DESC;
```

## 9. Важные замечания

1. **Представления не хранят данные** - они хранят только определение запроса
2. **Производительность зависит от базового запроса** - сложный запрос = медленное представление
3. **Индексированные представления требуют SCHEMABINDING** - база должна быть всегда согласована
4. **Обновление через представление может быть сложным** - используйте INSTEAD OF триггеры
5. **Изменение базовой таблицы может сломать представление** - проверяйте зависимости

---

**Резюме:** Представления - мощный инструмент для абстракции, безопасности и оптимизации. Индексированные представления могут значительно улучшить производительность повторяющихся запросов. Правильная архитектура представлений облегчает обслуживание и расширяемость системы.
