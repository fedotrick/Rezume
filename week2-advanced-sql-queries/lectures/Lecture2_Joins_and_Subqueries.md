# Лекция 2: Различные типы JOIN и подзапросы

## 1. Основные типы JOIN

### 1.1 INNER JOIN

Возвращает только те строки, где есть совпадения в обеих таблицах.

**Синтаксис:**
```sql
SELECT column_list
FROM table1
INNER JOIN table2
    ON table1.key = table2.key;
```

**Пример:**
```sql
SELECT 
    c.ClientID,
    c.ClientName,
    o.OrderID,
    o.OrderDate,
    o.OrderAmount
FROM Clients c
INNER JOIN Orders o
    ON c.ClientID = o.ClientID
WHERE o.OrderAmount > 1000;
```

**Результат:** Только клиенты, которые имеют заказы

```
ClientID | ClientName   | OrderID | OrderDate  | OrderAmount
1        | Tony Stark   | 101     | 2024-01-05 | 5000.00
1        | Tony Stark   | 103     | 2024-01-10 | 2500.00
2        | Bruce Wayne  | 102     | 2024-01-08 | 3000.00
```

### 1.2 LEFT JOIN (LEFT OUTER JOIN)

Возвращает все строки из левой таблицы и совпадающие строки из правой. NULL для несовпадающих.

**Синтаксис:**
```sql
SELECT column_list
FROM table1
LEFT JOIN table2
    ON table1.key = table2.key;
```

**Пример:**
```sql
SELECT 
    c.ClientID,
    c.ClientName,
    c.RegistrationDate,
    o.OrderID,
    o.OrderDate,
    o.OrderAmount
FROM Clients c
LEFT JOIN Orders o
    ON c.ClientID = o.ClientID
ORDER BY c.ClientID;
```

**Результат:** Все клиенты, включая тех без заказов

```
ClientID | ClientName   | RegistrationDate | OrderID | OrderDate  | OrderAmount
1        | Tony Stark   | 2024-01-01      | 101     | 2024-01-05 | 5000.00
1        | Tony Stark   | 2024-01-01      | 103     | 2024-01-10 | 2500.00
2        | Bruce Wayne  | 2024-01-02      | 102     | 2024-01-08 | 3000.00
3        | Peter Parker | 2024-01-03      | NULL    | NULL       | NULL
```

### 1.3 RIGHT JOIN (RIGHT OUTER JOIN)

Возвращает все строки из правой таблицы и совпадающие строки из левой.

**Пример:**
```sql
SELECT 
    p.ProductID,
    p.ProductName,
    oi.OrderItemID,
    oi.Quantity,
    oi.Price
FROM Products p
RIGHT JOIN OrderItems oi
    ON p.ProductID = oi.ProductID;
```

**Результат:** Все товары в заказах, включая товары без информации о продукте (если возможно)

### 1.4 FULL OUTER JOIN

Возвращает все строки из обеих таблиц, заполняя NULL там, где нет совпадений.

**Пример:**
```sql
SELECT 
    c.ClientID,
    c.ClientName,
    p.PortfolioID,
    p.PortfolioName,
    p.TotalValue
FROM Clients c
FULL OUTER JOIN Portfolios p
    ON c.ClientID = p.ClientID
ORDER BY c.ClientID, p.PortfolioID;
```

**Результат:**
```
ClientID | ClientName   | PortfolioID | PortfolioName      | TotalValue
1        | Tony Stark   | 1           | Growth Portfolio   | 50000.00
1        | Tony Stark   | 2           | Income Portfolio   | 30000.00
2        | Bruce Wayne  | 3           | Aggressive        | 100000.00
3        | Peter Parker | NULL        | NULL              | NULL
NULL     | NULL         | 4           | Test Portfolio    | 10000.00
```

### 1.5 CROSS JOIN

Возвращает декартово произведение (все возможные комбинации).

**Пример:**
```sql
SELECT 
    s.StockSymbol,
    q.QuarterName,
    NULL AS revenue
FROM Stocks s
CROSS JOIN Quarters q;
```

**Результат:** Каждый акция + каждый квартал = все комбинации

```
StockSymbol | QuarterName | revenue
AAPL        | Q1          | NULL
AAPL        | Q2          | NULL
AAPL        | Q3          | NULL
MSFT        | Q1          | NULL
MSFT        | Q2          | NULL
...
```

## 2. Продвинутые техники JOIN

### 2.1 Самоприсоединение (Self Join)

Соединение таблицы с самой собой для сравнения строк.

```sql
SELECT 
    e1.EmployeeID,
    e1.EmployeeName,
    e1.ManagerID,
    e2.EmployeeName AS ManagerName,
    e2.Department AS ManagerDepartment
FROM Employees e1
LEFT JOIN Employees e2
    ON e1.ManagerID = e2.EmployeeID;
```

**Результат:**
```
EmployeeID | EmployeeName | ManagerID | ManagerName   | ManagerDepartment
1          | Alice        | 5         | Bob           | Management
2          | Charlie      | 5         | Bob           | Management
5          | Bob          | NULL      | NULL          | NULL
```

### 2.2 Множественные JOIN

```sql
SELECT 
    o.OrderID,
    o.OrderDate,
    c.ClientName,
    p.ProductName,
    oi.Quantity,
    oi.Price,
    (oi.Quantity * oi.Price) AS item_total
FROM Orders o
INNER JOIN Clients c
    ON o.ClientID = c.ClientID
INNER JOIN OrderItems oi
    ON o.OrderID = oi.OrderID
INNER JOIN Products p
    ON oi.ProductID = p.ProductID
WHERE o.OrderDate >= '2024-01-01'
ORDER BY o.OrderID;
```

### 2.3 JOIN с агрегацией

```sql
SELECT 
    c.ClientID,
    c.ClientName,
    COUNT(o.OrderID) AS order_count,
    SUM(o.OrderAmount) AS total_spent,
    AVG(o.OrderAmount) AS avg_order_value,
    MAX(o.OrderDate) AS last_order_date
FROM Clients c
LEFT JOIN Orders o
    ON c.ClientID = o.ClientID
GROUP BY c.ClientID, c.ClientName
HAVING COUNT(o.OrderID) > 0
ORDER BY total_spent DESC;
```

## 3. Подзапросы (Subqueries)

### 3.1 Подзапросы в SELECT

```sql
SELECT 
    c.ClientID,
    c.ClientName,
    c.RegistrationDate,
    (SELECT COUNT(*) FROM Orders WHERE ClientID = c.ClientID) AS order_count,
    (SELECT SUM(OrderAmount) FROM Orders WHERE ClientID = c.ClientID) AS total_spent
FROM Clients c;
```

**Примечание:** Каждый подзапрос выполняется для каждой строки - может быть медленно!

### 3.2 Подзапросы в WHERE

#### Одно значение (одна строка, один столбец)

```sql
SELECT 
    ClientID,
    ClientName,
    RegistrationDate
FROM Clients
WHERE RegistrationDate = (
    SELECT MIN(RegistrationDate) FROM Clients
);
```

#### Несколько значений с IN

```sql
SELECT 
    ClientID,
    ClientName,
    TotalInvested
FROM Clients
WHERE ClientID IN (
    SELECT DISTINCT ClientID 
    FROM Portfolios 
    WHERE TotalValue > 100000
);
```

#### Проверка существования с EXISTS

```sql
SELECT 
    c.ClientID,
    c.ClientName
FROM Clients c
WHERE EXISTS (
    SELECT 1 FROM Orders o WHERE o.ClientID = c.ClientID
);
```

### 3.3 Подзапросы в FROM (Derived Tables)

```sql
SELECT 
    top_clients.ClientID,
    top_clients.ClientName,
    top_clients.total_spent,
    top_clients.avg_order_value
FROM (
    SELECT 
        c.ClientID,
        c.ClientName,
        SUM(o.OrderAmount) AS total_spent,
        AVG(o.OrderAmount) AS avg_order_value,
        COUNT(o.OrderID) AS order_count
    FROM Clients c
    LEFT JOIN Orders o ON c.ClientID = o.ClientID
    GROUP BY c.ClientID, c.ClientName
) top_clients
WHERE top_clients.total_spent > 50000
ORDER BY top_clients.total_spent DESC;
```

### 3.4 Коррелированные подзапросы

Подзапрос, который ссылается на колонны из внешнего запроса.

```sql
SELECT 
    ClientID,
    ClientName,
    TotalInvested,
    (SELECT AVG(TotalValue) 
     FROM Portfolios p 
     WHERE p.ClientID = Clients.ClientID) AS client_avg_portfolio
FROM Clients;
```

**Как это работает:**
1. Для каждого клиента из внешнего запроса
2. Вычисляется среднее портфолио этого клиента
3. Результат добавляется к каждой строке

## 4. IN vs EXISTS

### 4.1 IN - Проверка принадлежности

```sql
SELECT 
    ClientID,
    ClientName
FROM Clients
WHERE ClientID IN (1, 2, 3, 5);

-- С подзапросом
SELECT 
    ClientID,
    ClientName
FROM Clients
WHERE ClientID IN (
    SELECT ClientID FROM VIP_Clients
);
```

**Как работает IN:**
1. Вычисляет весь подзапрос
2. Проверяет, есть ли значение в полученном списке

### 4.2 EXISTS - Проверка существования

```sql
SELECT 
    c.ClientID,
    c.ClientName
FROM Clients c
WHERE EXISTS (
    SELECT 1 FROM VIP_Clients v WHERE v.ClientID = c.ClientID
);
```

**Как работает EXISTS:**
1. Для каждой строки внешнего запроса
2. Проверяет, вернет ли подзапрос хотя бы одну строку
3. Останавливается после первого совпадения (более эффективно)

### 4.3 IN vs EXISTS - Производительность

```sql
-- ❌ IN - обрабатывает весь подзапрос
SELECT * FROM Clients
WHERE ClientID IN (
    SELECT ClientID FROM Orders WHERE OrderAmount > 5000
);

-- ✅ EXISTS - останавливается при первом совпадении, лучше для NOT
SELECT c.* FROM Clients c
WHERE EXISTS (
    SELECT 1 FROM Orders o 
    WHERE o.ClientID = c.ClientID AND o.OrderAmount > 5000
);

-- NOT IN может быть медленнее с NULL значениями
-- ✅ NOT EXISTS предпочтительнее
SELECT c.* FROM Clients c
WHERE NOT EXISTS (
    SELECT 1 FROM Orders o WHERE o.ClientID = c.ClientID
);
```

## 5. Реальные сценарии

### 5.1 Сценарий 1: Клиенты без транзакций за период

```sql
SELECT 
    c.ClientID,
    c.ClientName,
    c.RegistrationDate,
    c.AccountStatus,
    MAX(o.OrderDate) AS last_order_date
FROM Clients c
LEFT JOIN Orders o
    ON c.ClientID = o.ClientID 
    AND o.OrderDate >= '2024-01-01'
GROUP BY c.ClientID, c.ClientName, c.RegistrationDate, c.AccountStatus
HAVING MAX(o.OrderDate) IS NULL
    AND c.RegistrationDate < '2024-01-01'
ORDER BY c.RegistrationDate;
```

### 5.2 Сценарий 2: Корреляции между ценными бумагами

```sql
-- Определить акции, которые часто растут одновременно
SELECT 
    s1.StockSymbol AS symbol1,
    s2.StockSymbol AS symbol2,
    COUNT(*) AS correlation_days,
    (COUNT(*) * 100.0 / 
        (SELECT COUNT(*) FROM StockPrices WHERE StockSymbol = s1.StockSymbol)) 
        AS correlation_percent
FROM StockPrices s1
INNER JOIN StockPrices s2
    ON s1.TradeDate = s2.TradeDate
    AND s1.StockSymbol < s2.StockSymbol
    AND s1.DailyChange > 0
    AND s2.DailyChange > 0
WHERE s1.TradeDate >= '2024-01-01'
GROUP BY s1.StockSymbol, s2.StockSymbol
HAVING COUNT(*) > 50
ORDER BY correlation_percent DESC;
```

### 5.3 Сценарий 3: Объединение данных из нескольких источников

```sql
SELECT 
    COALESCE(p.PortfolioID, b.BudgetID) AS entity_id,
    CASE 
        WHEN p.PortfolioID IS NOT NULL THEN 'Portfolio'
        WHEN b.BudgetID IS NOT NULL THEN 'Budget'
    END AS entity_type,
    COALESCE(p.PortfolioName, b.BudgetName) AS entity_name,
    COALESCE(p.TotalValue, 0) AS portfolio_value,
    COALESCE(b.AllocatedAmount, 0) AS budget_amount,
    (COALESCE(p.TotalValue, 0) + COALESCE(b.AllocatedAmount, 0)) AS total_value
FROM Portfolios p
FULL OUTER JOIN Budgets b
    ON p.ClientID = b.ClientID
ORDER BY entity_id;
```

## 6. Оптимизация JOIN и подзапросов

### 6.1 Рекомендации по производительности

| Операция | Сценарий | Лучший вариант |
|----------|----------|----------------|
| **Проверка существования** | Проверить наличие записи | EXISTS |
| **Получение одного значения** | COUNT, SUM на всех строках | JOIN вместо подзапроса |
| **Фильтрация с большим набором значений** | 1000+ значений | JOIN вместо IN |
| **Проверка несовпадения** | NOT операция | NOT EXISTS вместо NOT IN |
| **Множественные условия** | Несколько условий соединения | Явный JOIN вместо WHERE условий |

### 6.2 Примеры оптимизации

```sql
-- ❌ Медленно: множественные подзапросы в SELECT
SELECT 
    c.ClientID,
    c.ClientName,
    (SELECT COUNT(*) FROM Orders WHERE ClientID = c.ClientID) AS orders,
    (SELECT SUM(Amount) FROM Transactions WHERE ClientID = c.ClientID) AS total,
    (SELECT MAX(OrderDate) FROM Orders WHERE ClientID = c.ClientID) AS last_order
FROM Clients c;

-- ✅ Быстро: один JOIN с агрегацией
SELECT 
    c.ClientID,
    c.ClientName,
    COUNT(DISTINCT o.OrderID) AS orders,
    SUM(t.Amount) AS total,
    MAX(o.OrderDate) AS last_order
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
LEFT JOIN Transactions t ON c.ClientID = t.ClientID
GROUP BY c.ClientID, c.ClientName;

-- ❌ Медленно: NOT IN с NULL
SELECT * FROM Clients
WHERE ClientID NOT IN (SELECT ClientID FROM BlackList);  -- Если NULL, вернет ничего!

-- ✅ Быстро: NOT EXISTS
SELECT c.* FROM Clients c
WHERE NOT EXISTS (SELECT 1 FROM BlackList b WHERE b.ClientID = c.ClientID);
```

### 6.3 Проверка плана выполнения

```sql
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    c.ClientID,
    c.ClientName,
    COUNT(o.OrderID) AS order_count
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID, c.ClientName;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```

## 7. Важные замечания

1. **NULL в JOIN** - строки с NULL не совпадают даже друг с другом (используйте ISNULL)
2. **ON vs WHERE** - условия в ON применяются ДО JOIN, в WHERE ДО фильтрации результата
3. **LEFT JOIN с фильтром** - всегда используйте ON для фильтра, не WHERE!
4. **Порядок таблиц в CROSS JOIN** - не важен (CROSS JOIN коммутативен)
5. **Подзапросы во время выполнения** - каждый запрос выполняется отдельно

---

**Резюме:** Правильный выбор JOIN и подзапросов критичен для производительности. EXISTS обычно быстрее IN, JOIN часто быстрее подзапросов, а понимание порядка выполнения - ключ к оптимизации.
