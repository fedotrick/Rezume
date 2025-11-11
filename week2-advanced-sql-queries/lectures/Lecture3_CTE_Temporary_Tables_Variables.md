# Лекция 3: CTE, Временные таблицы и Переменные

## 1. Common Table Expressions (CTE)

### 1.1 Основные концепции CTE

Common Table Expression (CTE) - это именованный временный результирующий набор, определяемый с помощью клауза WITH. CTE существует только в рамках одного SELECT, INSERT, UPDATE или DELETE запроса.

**Синтаксис:**
```sql
WITH cte_name AS (
    -- Определение CTE
    SELECT column1, column2, ...
    FROM table_name
    WHERE conditions
)
SELECT * FROM cte_name;
```

### 1.2 Простой CTE пример

```sql
WITH HighValueOrders AS (
    SELECT 
        OrderID,
        ClientID,
        OrderDate,
        OrderAmount
    FROM Orders
    WHERE OrderAmount > 5000
)
SELECT 
    ClientID,
    COUNT(*) AS high_value_count,
    SUM(OrderAmount) AS total_amount
FROM HighValueOrders
GROUP BY ClientID
ORDER BY total_amount DESC;
```

**Что происходит:**
1. CTE `HighValueOrders` фильтрует заказы > 5000
2. Основной запрос группирует и подсчитывает эти заказы

### 1.3 Множественные CTE

```sql
WITH ClientStats AS (
    SELECT 
        ClientID,
        ClientName,
        COUNT(OrderID) AS order_count,
        SUM(OrderAmount) AS total_spent
    FROM Clients c
    LEFT JOIN Orders o ON c.ClientID = o.ClientID
    GROUP BY c.ClientID, c.ClientName
),
TopClients AS (
    SELECT TOP 10
        ClientID,
        ClientName,
        order_count,
        total_spent
    FROM ClientStats
    WHERE order_count > 0
    ORDER BY total_spent DESC
)
SELECT 
    ClientID,
    ClientName,
    order_count,
    total_spent,
    total_spent * 0.1 AS loyalty_reward
FROM TopClients;
```

**Структура:**
- `ClientStats` - первый CTE с статистикой
- `TopClients` - второй CTE, использующий первый
- Основной SELECT использует второй CTE

## 2. Рекурсивные CTE

### 2.1 Понимание рекурсии в CTE

Рекурсивные CTE состоят из двух частей:
1. **Anchor member (якорь)** - базовый запрос
2. **Recursive member (рекурсивный член)** - запрос, ссылающийся на CTE

```sql
WITH RECURSIVE cte_name AS (
    -- ЯКОРЬ: базовый запрос
    SELECT ... FROM table_name
    WHERE conditions
    
    UNION ALL
    
    -- РЕКУРСИЯ: ссылка на CTE
    SELECT ... FROM table_name
    INNER JOIN cte_name ON conditions
)
SELECT * FROM cte_name;
```

### 2.2 Пример: Иерархия сотрудников

```sql
WITH EmployeeHierarchy AS (
    -- Якорь: начальники (не имеют менеджера)
    SELECT 
        EmployeeID,
        EmployeeName,
        ManagerID,
        Department,
        1 AS hierarchy_level
    FROM Employees
    WHERE ManagerID IS NULL
    
    UNION ALL
    
    -- Рекурсия: подчиненные каждого начальника
    SELECT 
        e.EmployeeID,
        e.EmployeeName,
        e.ManagerID,
        e.Department,
        eh.hierarchy_level + 1
    FROM Employees e
    INNER JOIN EmployeeHierarchy eh
        ON e.ManagerID = eh.EmployeeID
)
SELECT 
    EmployeeID,
    EmployeeName,
    ManagerID,
    Department,
    hierarchy_level,
    REPLICATE('  ', hierarchy_level - 1) + EmployeeName AS hierarchy_tree
FROM EmployeeHierarchy
ORDER BY hierarchy_level, Department, EmployeeName;
```

**Результат:**
```
EmployeeID | EmployeeName | ManagerID | Department | hierarchy_level | hierarchy_tree
1          | Bob          | NULL      | Management | 1               | Bob
2          | Alice        | 1         | Sales      | 2               |   Alice
3          | Charlie      | 1         | IT         | 2               |   Charlie
4          | David        | 2         | Sales      | 3               |     David
```

### 2.3 Пример: Финансовая иерархия портфелей

```sql
WITH PortfolioHierarchy AS (
    -- Якорь: главные портфели
    SELECT 
        PortfolioID,
        PortfolioName,
        ParentPortfolioID,
        TotalValue,
        1 AS level
    FROM Portfolios
    WHERE ParentPortfolioID IS NULL
    
    UNION ALL
    
    -- Рекурсия: подпортфели
    SELECT 
        p.PortfolioID,
        p.PortfolioName,
        p.ParentPortfolioID,
        p.TotalValue,
        ph.level + 1
    FROM Portfolios p
    INNER JOIN PortfolioHierarchy ph
        ON p.ParentPortfolioID = ph.PortfolioID
    WHERE ph.level < 10  -- Предотвращение бесконечной рекурсии
)
SELECT 
    PortfolioID,
    REPLICATE('  ', level - 1) + PortfolioName AS portfolio_tree,
    TotalValue,
    level
FROM PortfolioHierarchy
ORDER BY level, PortfolioID;
```

### 2.4 Пример: Генерация дат

```sql
WITH DateSeries AS (
    -- Якорь: начальная дата
    SELECT CAST('2024-01-01' AS DATE) AS date_val
    
    UNION ALL
    
    -- Рекурсия: добавляем по одному дню
    SELECT DATEADD(DAY, 1, date_val)
    FROM DateSeries
    WHERE date_val < '2024-12-31'
)
SELECT * FROM DateSeries;
```

### 2.5 MAXRECURSION - Контроль глубины рекурсии

```sql
WITH RECURSIVE cte_name AS (
    -- ... определение CTE
)
SELECT * FROM cte_name
OPTION (MAXRECURSION 32767);  -- Максимум 32767 уровней
```

## 3. Временные таблицы

### 3.1 Локальные временные таблицы (#temp)

Существуют только в рамках текущей сессии.

```sql
-- Создание локальной временной таблицы
CREATE TABLE #TempHighValueOrders (
    OrderID INT PRIMARY KEY,
    ClientID INT,
    OrderDate DATETIME,
    OrderAmount DECIMAL(18,2)
);

-- Заполнение временной таблицы
INSERT INTO #TempHighValueOrders
SELECT 
    OrderID,
    ClientID,
    OrderDate,
    OrderAmount
FROM Orders
WHERE OrderAmount > 5000;

-- Использование временной таблицы
SELECT 
    ClientID,
    COUNT(*) AS order_count,
    SUM(OrderAmount) AS total
FROM #TempHighValueOrders
GROUP BY ClientID;

-- Удаление временной таблицы (опционально)
DROP TABLE #TempHighValueOrders;
```

### 3.2 Глобальные временные таблицы (##temp)

Видны всем сессиям, удаляются при закрытии последней сессии.

```sql
CREATE TABLE ##GlobalTempTable (
    ID INT,
    Name VARCHAR(100),
    Value DECIMAL(18,2)
);

INSERT INTO ##GlobalTempTable VALUES (1, 'Item1', 100.00);

-- Доступна из других сессий
SELECT * FROM ##GlobalTempTable;

DROP TABLE ##GlobalTempTable;
```

### 3.3 Временные таблицы в процедурах

```sql
CREATE PROCEDURE sp_AnalyzeClientSegments
AS
BEGIN
    -- Создание временной таблицы
    CREATE TABLE #ClientSegments (
        ClientID INT,
        ClientName VARCHAR(100),
        TotalSpent DECIMAL(18,2),
        OrderCount INT,
        Segment VARCHAR(50)
    );
    
    -- Заполнение временной таблицы
    INSERT INTO #ClientSegments
    SELECT 
        c.ClientID,
        c.ClientName,
        SUM(o.OrderAmount) AS TotalSpent,
        COUNT(o.OrderID) AS OrderCount,
        CASE 
            WHEN SUM(o.OrderAmount) > 50000 THEN 'VIP'
            WHEN SUM(o.OrderAmount) > 10000 THEN 'Premium'
            ELSE 'Standard'
        END AS Segment
    FROM Clients c
    LEFT JOIN Orders o ON c.ClientID = o.ClientID
    GROUP BY c.ClientID, c.ClientName;
    
    -- Использование результатов
    SELECT 
        Segment,
        COUNT(*) AS client_count,
        SUM(TotalSpent) AS segment_total
    FROM #ClientSegments
    GROUP BY Segment;
    
    -- Автоматически удаляется при завершении процедуры
END;
```

## 4. Табличные переменные

### 4.1 Синтаксис и использование

```sql
DECLARE @ClientTransactions TABLE (
    RowNum INT PRIMARY KEY IDENTITY(1,1),
    TransactionID INT,
    ClientID INT,
    TransactionDate DATETIME,
    Amount DECIMAL(18,2)
);

INSERT INTO @ClientTransactions
SELECT 
    TransactionID,
    ClientID,
    TransactionDate,
    Amount
FROM Transactions
WHERE ClientID = 1;

SELECT * FROM @ClientTransactions
WHERE Amount > 1000
ORDER BY TransactionDate DESC;
```

### 4.2 Табличные переменные с индексами

```sql
DECLARE @Products TABLE (
    ProductID INT PRIMARY KEY,
    ProductName VARCHAR(100),
    Category VARCHAR(50),
    Price DECIMAL(18,2),
    INDEX idx_category (Category)
);

INSERT INTO @Products
SELECT ProductID, ProductName, Category, Price
FROM Products
WHERE Price > 100;

SELECT * FROM @Products
WHERE Category = 'Technology';
```

## 5. Сравнение: CTE vs Temp Table vs Table Variable

| Особенность | CTE | Temp Table | Table Variable |
|-------------|-----|-----------|-----------------|
| **Область видимости** | Один запрос | Вся сессия | Вся процедура |
| **Производительность** | Быстро для простых | Средняя | Быстро для малых |
| **Сложность** | Простые и рекурсивные | Любая | Простые |
| **Индексы** | Нет | Да | Да (ограниченно) |
| **Статистика** | Нет | Да | Нет |
| **Память** | В памяти | На диске | В памяти |
| **Масштабируемость** | Хорошо | Лучше | Плохо |
| **Использование в JOIN** | Да | Да | Да |

## 6. Практические примеры

### 6.1 CTE для пошагового анализа

```sql
WITH MonthlyRevenue AS (
    SELECT 
        DATEPART(MONTH, OrderDate) AS month,
        YEAR(OrderDate) AS year,
        SUM(OrderAmount) AS revenue
    FROM Orders
    GROUP BY YEAR(OrderDate), DATEPART(MONTH, OrderDate)
),
RevenueWithTrend AS (
    SELECT 
        month,
        year,
        revenue,
        LAG(revenue) OVER (ORDER BY year, month) AS prev_month_revenue,
        revenue - LAG(revenue) OVER (ORDER BY year, month) AS revenue_change,
        (revenue - LAG(revenue) OVER (ORDER BY year, month)) * 100.0 / 
            LAG(revenue) OVER (ORDER BY year, month) AS pct_change
    FROM MonthlyRevenue
)
SELECT 
    DATEFROMPARTS(year, month, 1) AS month_date,
    revenue,
    revenue_change,
    pct_change
FROM RevenueWithTrend
WHERE pct_change IS NOT NULL
ORDER BY year, month;
```

### 6.2 Временная таблица для ETL процесса

```sql
-- Шаг 1: Подготовка исходных данных
CREATE TABLE #SourceData (
    RecordID INT PRIMARY KEY,
    RawValue VARCHAR(MAX),
    ProcessStatus VARCHAR(50) DEFAULT 'Pending'
);

INSERT INTO #SourceData (RecordID, RawValue)
SELECT * FROM ExternalDataSource;

-- Шаг 2: Валидация
UPDATE #SourceData
SET ProcessStatus = 'Invalid'
WHERE RawValue NOT LIKE '[0-9]%' OR LEN(RawValue) = 0;

-- Шаг 3: Обработка валидных записей
INSERT INTO ProcessedData
SELECT 
    RecordID,
    CAST(RawValue AS DECIMAL(18,2)) AS ProcessedValue,
    GETDATE() AS ProcessDate
FROM #SourceData
WHERE ProcessStatus = 'Pending';

-- Шаг 4: Логирование ошибок
INSERT INTO ErrorLog
SELECT 
    RecordID,
    RawValue,
    GETDATE(),
    'Invalid format'
FROM #SourceData
WHERE ProcessStatus = 'Invalid';

DROP TABLE #SourceData;
```

### 6.3 Табличная переменная в функции

```sql
CREATE FUNCTION GetClientPortfolioSummary(@ClientID INT)
RETURNS @PortfolioSummary TABLE (
    PortfolioID INT,
    PortfolioName VARCHAR(100),
    HoldingCount INT,
    TotalValue DECIMAL(18,2),
    AverageYield DECIMAL(5,2)
)
AS
BEGIN
    DECLARE @Holdings TABLE (
        HoldingID INT,
        StockSymbol VARCHAR(10),
        Quantity INT,
        CurrentPrice DECIMAL(18,2)
    );
    
    INSERT INTO @Holdings
    SELECT HoldingID, StockSymbol, Quantity, CurrentPrice
    FROM PortfolioHoldings
    WHERE PortfolioID IN (
        SELECT PortfolioID FROM Portfolios WHERE ClientID = @ClientID
    );
    
    INSERT INTO @PortfolioSummary
    SELECT 
        p.PortfolioID,
        p.PortfolioName,
        COUNT(h.HoldingID),
        SUM(h.Quantity * h.CurrentPrice),
        AVG(p.YieldPercent)
    FROM Portfolios p
    LEFT JOIN @Holdings h ON p.PortfolioID IN (SELECT PortfolioID FROM Portfolios WHERE ClientID = @ClientID)
    WHERE p.ClientID = @ClientID
    GROUP BY p.PortfolioID, p.PortfolioName, p.YieldPercent;
    
    RETURN;
END;
```

## 7. Best Practices и рекомендации

### 7.1 Когда использовать каждый подход

```sql
-- ✅ Используй CTE когда:
-- - Логика сложная, но результат небольшой
-- - Нужна читаемость и структура
-- - Рекурсивность требуется
WITH cte AS (SELECT ...) SELECT ...

-- ✅ Используй Temp Table когда:
-- - Большой набор данных (100k+ строк)
-- - Нужны индексы для множественных запросов
-- - Требуется сложная обработка в процедуре
CREATE TABLE #Temp (...)

-- ✅ Используй Table Variable когда:
-- - Малый набор данных (<10k строк)
-- - Функция, не процедура
-- - Не нужна статистика для оптимизатора
DECLARE @Table TABLE (...)
```

### 7.2 Оптимизация рекурсивных CTE

```sql
-- ❌ Без ограничения глубины (бесконечный цикл возможен)
WITH cte AS (
    SELECT ... UNION ALL SELECT ... FROM cte
)

-- ✅ С явным ограничением
WITH cte AS (
    SELECT ... WHERE depth < 10
    UNION ALL
    SELECT ... FROM cte WHERE depth < 10
)
OPTION (MAXRECURSION 10);
```

## 8. Важные замечания

1. **CTE видна только в одном запросе** - используй VIEW для повторного использования
2. **Временные таблицы требуют DROP** - не забудь очистить
3. **Табличные переменные не параллелизируются** - SQL Server игнорирует параллельность
4. **Рекурсивные CTE максимум 100 уровней по умолчанию** - используй OPTION (MAXRECURSION N)
5. **Статистика для temp tables** - запрашивается автоматически, для табличных переменных нет

---

**Резюме:** Выбор между CTE, временными таблицами и табличными переменными зависит от размера данных, сложности логики и контекста использования. CTE отличная для читаемости, temp tables для больших объемов, таблич
ные переменные для функций.
