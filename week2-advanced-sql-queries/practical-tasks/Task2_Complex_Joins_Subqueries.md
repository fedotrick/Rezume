# Практическая задача 2: Сложные JOIN и подзапросы

## Описание

Эта задача ориентирована на использование различных типов JOIN и подзапросов для анализа сложных взаимосвязей между данными.

## Требуемые таблицы

```sql
-- Clients - клиенты
-- Columns: ClientID, ClientName, Email, City, Country, RegistrationDate

-- Orders - заказы
-- Columns: OrderID, ClientID, OrderDate, OrderAmount, OrderStatus

-- OrderItems - товары в заказах
-- Columns: OrderItemID, OrderID, ProductID, Quantity, Price

-- Products - товары
-- Columns: ProductID, ProductName, Category, UnitPrice, Stock

-- Transactions - транзакции
-- Columns: TransactionID, ClientID, TransactionDate, Amount, TransactionType

-- PortfolioHoldings - акции в портфелях
-- Columns: HoldingID, PortfolioID, StockSymbol, Quantity, AcquisitionPrice, CurrentPrice

-- StockPrices - исторические цены
-- Columns: StockID, StockSymbol, TradeDate, ClosePrice, DailyChange
```

## Задача 2.1: Найти клиентов без транзакций за период

**Цель:** Определить клиентов, которые были неактивны на протяжении определенного периода.

**Требования:**
- Найти клиентов, зарегистрировавшихся до определенной даты
- Которые НЕ имели транзакций за последние 6 месяцев
- Показать информацию о клиенте и последний день активности
- Отсортировать по дате регистрации (самые давние клиенты в начале)
- Расчитать количество дней неактивности

**Ожидаемый результат:**

| ClientID | ClientName | RegistrationDate | LastActivityDate | DaysInactive | Status |
|----------|-----------|-----------------|-----------------|--------------|--------|
| 5 | Peter Parker | 2023-01-15 | 2023-06-30 | 547 | Dormant |
| 8 | Steve Rogers | 2023-02-20 | 2023-07-10 | 537 | Dormant |
| 12 | Bruce Banner | 2023-03-10 | 2023-08-15 | 532 | Dormant |

**Заготовка запроса вариант 1 (LEFT JOIN):**

```sql
SELECT 
    c.ClientID,
    c.ClientName,
    c.RegistrationDate,
    MAX(t.TransactionDate) AS LastActivityDate,
    -- Добавить расчет дней неактивности
    'Dormant' AS Status
FROM Clients c
LEFT JOIN Transactions t 
    ON c.ClientID = t.ClientID 
    AND t.TransactionDate >= DATEADD(MONTH, -6, GETDATE())
WHERE c.RegistrationDate < DATEADD(MONTH, -6, GETDATE())
    -- Условие: нет транзакций за период
GROUP BY c.ClientID, c.ClientName, c.RegistrationDate
-- HAVING для фильтрации только тех, у которых нет транзакций
ORDER BY c.RegistrationDate;
```

**Заготовка запроса вариант 2 (NOT EXISTS):**

```sql
SELECT 
    c.ClientID,
    c.ClientName,
    c.RegistrationDate,
    -- Получить последнюю дату активности
FROM Clients c
WHERE c.RegistrationDate < DATEADD(MONTH, -6, GETDATE())
    -- AND NOT EXISTS подзапрос для проверки транзакций
ORDER BY c.RegistrationDate;
```

## Задача 2.2: Рассчитать корреляции между ценными бумагами

**Цель:** Определить, какие акции часто растут/падают одновременно.

**Требования:**
- Найти пары акций, которые имеют положительное совместное движение (обе растут/падают в один день)
- Рассчитать процент совпадающих дней
- Показать только пары с совпадением > 60%
- Отсортировать по проценту совпадения в порядке убывания

**Ожидаемый результат:**

| Stock1 | Stock2 | CorrelationDays | TotalDays | CorrelationPercent |
|--------|--------|-----------------|-----------|-------------------|
| AAPL | MSFT | 45 | 60 | 75.00 |
| MSFT | GOOG | 42 | 60 | 70.00 |
| AAPL | GOOG | 36 | 60 | 60.00 |

**Заготовка запроса:**

```sql
-- Метод 1: Self Join на StockPrices
SELECT 
    s1.StockSymbol AS Stock1,
    s2.StockSymbol AS Stock2,
    COUNT(*) AS CorrelationDays,
    -- Получить total дней для каждой акции
    -- Рассчитать процент
FROM StockPrices s1
INNER JOIN StockPrices s2
    ON s1.TradeDate = s2.TradeDate
    AND s1.StockSymbol < s2.StockSymbol  -- Избежать дублей
    AND s1.DailyChange > 0  -- Обе растут
    AND s2.DailyChange > 0
WHERE s1.TradeDate >= DATEADD(MONTH, -3, GETDATE())
GROUP BY s1.StockSymbol, s2.StockSymbol
HAVING COUNT(*) > 10
ORDER BY CorrelationPercent DESC;

-- Метод 2: С подзапросом для полного периода
WITH StockPairDays AS (
    -- Получить все возможные дни для каждой пары
)
SELECT 
    Stock1,
    Stock2,
    CorrelationDays,
    TotalDays,
    (CorrelationDays * 100.0 / TotalDays) AS CorrelationPercent
FROM StockPairDays
WHERE CorrelationPercent >= 60
ORDER BY CorrelationPercent DESC;
```

## Задача 2.3: Объединить данные из нескольких источников

**Цель:** Создать единую представление с информацией о клиентах из разных таблиц.

**Требования:**
- Объединить информацию о заказах и портфелях
- Показать клиентов, которые имеют ИЛИ заказы ИЛИ портфели (FULL OUTER JOIN)
- Добавить статистику: количество заказов, сумма заказов, сумма портфеля
- Определить тип клиента (Trader, Investor, Both)
- Рассчитать общее инвестированное значение

**Ожидаемый результат:**

| ClientID | ClientName | OrderCount | TotalOrderAmount | PortfolioCount | TotalPortfolioValue | ClientType | TotalInvestment |
|----------|-----------|-----------|-----------------|----------------|-------------------|-----------|-----------------|
| 1 | Tony Stark | 5 | 25000.00 | 2 | 100000.00 | Both | 125000.00 |
| 2 | Bruce Wayne | 3 | 15000.00 | NULL | NULL | Trader | 15000.00 |
| 3 | Peter Parker | NULL | NULL | 1 | 50000.00 | Investor | 50000.00 |

**Заготовка запроса:**

```sql
WITH OrderStats AS (
    SELECT 
        ClientID,
        COUNT(DISTINCT OrderID) AS OrderCount,
        SUM(OrderAmount) AS TotalOrderAmount
    FROM Orders
    WHERE OrderDate >= DATEADD(MONTH, -12, GETDATE())
    GROUP BY ClientID
),
PortfolioStats AS (
    SELECT 
        p.ClientID,
        COUNT(DISTINCT p.PortfolioID) AS PortfolioCount,
        SUM(p.TotalValue) AS TotalPortfolioValue
    FROM Portfolios p
    GROUP BY p.ClientID
)
SELECT 
    COALESCE(c.ClientID, os.ClientID, ps.ClientID) AS ClientID,
    COALESCE(c.ClientName, 'Unknown') AS ClientName,
    COALESCE(os.OrderCount, 0) AS OrderCount,
    COALESCE(os.TotalOrderAmount, 0) AS TotalOrderAmount,
    -- Добавить portfolio stats
    -- Добавить определение типа клиента
    -- Добавить расчет общего инвестирования
FROM Clients c
-- FULL OUTER JOIN с OrderStats
-- FULL OUTER JOIN с PortfolioStats
ORDER BY TotalInvestment DESC;
```

## Задача 2.4: IN vs EXISTS производительность

**Цель:** Сравнить производительность и результаты различных подходов.

**Требования:**
- Найти всех клиентов, которые купили продукты определенной категории
- Реализовать 4 варианта: IN, EXISTS, JOIN, LEFT JOIN с HAVING
- Сравнить время выполнения для каждого варианта
- Объяснить различия в производительности

**Вариант 1: IN с подзапросом**

```sql
SELECT DISTINCT
    c.ClientID,
    c.ClientName
FROM Clients c
WHERE c.ClientID IN (
    SELECT DISTINCT o.ClientID
    FROM Orders o
    INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
    INNER JOIN Products p ON oi.ProductID = p.ProductID
    WHERE p.Category = 'Technology'
)
ORDER BY c.ClientName;
```

**Вариант 2: EXISTS с подзапросом**

```sql
SELECT DISTINCT
    c.ClientID,
    c.ClientName
FROM Clients c
WHERE EXISTS (
    SELECT 1
    FROM Orders o
    INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
    INNER JOIN Products p ON oi.ProductID = p.ProductID
    WHERE p.Category = 'Technology'
        AND o.ClientID = c.ClientID
)
ORDER BY c.ClientName;
```

**Вариант 3: INNER JOIN**

```sql
SELECT DISTINCT
    c.ClientID,
    c.ClientName
FROM Clients c
INNER JOIN Orders o ON c.ClientID = o.ClientID
INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
INNER JOIN Products p ON oi.ProductID = p.ProductID
WHERE p.Category = 'Technology'
ORDER BY c.ClientName;
```

**Вариант 4: LEFT JOIN с HAVING**

```sql
SELECT 
    c.ClientID,
    c.ClientName,
    COUNT(DISTINCT oi.OrderItemID) AS PurchaseCount
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
LEFT JOIN OrderItems oi ON o.OrderID = oi.OrderID
LEFT JOIN Products p ON oi.ProductID = p.ProductID
GROUP BY c.ClientID, c.ClientName
HAVING COUNT(DISTINCT oi.OrderItemID) > 0
    AND MAX(CASE WHEN p.Category = 'Technology' THEN 1 ELSE 0 END) = 1
ORDER BY c.ClientName;
```

**Анализ:**

```sql
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Запустить каждый вариант и сравнить:
-- SQL Server parse and compile time
-- SQL Server Execution Times (CPU time, elapsed time)
-- Physical reads, logical reads

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```

## Задача 2.5: NOT IN vs NOT EXISTS

**Цель:** Понять различия и опасности при использовании NOT IN с NULL.

**Требования:**
- Найти клиентов, которые НИКОГДА не приобретали продукты категории 'Electronics'
- Показать три способа: NOT IN, NOT EXISTS, и обсудить почему NOT IN может быть проблематичным
- Продемонстрировать проблему с NULL значениями

**Проблема с NOT IN:**

```sql
-- ❌ ПРОБЛЕМА: Если подзапрос содержит NULL, результат может быть неожиданным
SELECT ClientID, ClientName
FROM Clients
WHERE ClientID NOT IN (
    SELECT ClientID FROM Orders  -- Если здесь есть NULL, то ничего не вернется!
);
-- NULL IN (x, y, z) = UNKNOWN (не TRUE, не FALSE)
-- NOT UNKNOWN = UNKNOWN, поэтому строка НЕ включается в результат
```

**Правильное решение с NOT EXISTS:**

```sql
SELECT DISTINCT
    c.ClientID,
    c.ClientName
FROM Clients c
WHERE NOT EXISTS (
    SELECT 1
    FROM Orders o
    INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
    INNER JOIN Products p ON oi.ProductID = p.ProductID
    WHERE p.Category = 'Electronics'
        AND o.ClientID = c.ClientID
)
ORDER BY c.ClientName;
```

**Альтернатива: LEFT JOIN с проверкой NULL:**

```sql
SELECT DISTINCT
    c.ClientID,
    c.ClientName
FROM Clients c
LEFT JOIN (
    SELECT DISTINCT o.ClientID
    FROM Orders o
    INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
    INNER JOIN Products p ON oi.ProductID = p.ProductID
    WHERE p.Category = 'Electronics'
) electronics ON c.ClientID = electronics.ClientID
WHERE electronics.ClientID IS NULL
ORDER BY c.ClientName;
```

## Тестирование

```sql
-- 1. Проверьте, что результаты всех вариантов идентичны
-- 2. Сравните планы выполнения (Execution Plan)
-- 3. Проверьте производительность с разными размерами данных
-- 4. Убедитесь в правильности обработки NULL значений

-- Пример для проверки NULL:
INSERT INTO Clients (ClientID, ClientName) VALUES (999, 'Test Client');
-- Теперь выполните NOT IN и NOT EXISTS - результаты должны отличаться!
```

## Дополнительные вызовы

1. **Полнотекстовый поиск** - найти клиентов по названию с похожестью
2. **Иерархия данных** - найти все заказы клиента и все товары в этих заказах
3. **Временные окна** - найти клиентов с заказами в определенные периоды
4. **Пересечение данных** - найти товары, купленные разными категориями клиентов

## Рекомендации по оптимизации

```sql
-- 1. Используйте индексы на внешних ключах
CREATE INDEX idx_Orders_ClientID ON Orders(ClientID);
CREATE INDEX idx_OrderItems_OrderID ON OrderItems(OrderID);
CREATE INDEX idx_OrderItems_ProductID ON OrderItems(ProductID);

-- 2. Используйте EXISTS вместо IN для больших наборов данных
-- 3. Избегайте DISTINCT если возможно, используйте GROUP BY
-- 4. Проверяйте план выполнения перед использованием в production
```

---

**Мудрость:** Правильный выбор между JOIN и подзапросами может улучшить производительность в 10 раз и более!
