# Лучшие практики и рекомендации для продвинутых SQL запросов

## Содержание
1. [Оконные функции](#оконные-функции)
2. [JOINs и подзапросы](#joins-и-подзапросы)
3. [CTE и временные объекты](#cte-и-временные-объекты)
4. [Представления](#представления)
5. [Общие рекомендации](#общие-рекомендации)
6. [Анти-паттерны](#анти-паттерны)
7. [Чек-лист оптимизации](#чек-лист-оптимизации)

---

## Оконные функции

### ✅ Лучшие практики

#### 1. Используйте PARTITION BY для логического разбиения
```sql
-- ✅ ХОРОШО: Ясная логика разбиения по портфелям
SELECT 
    PortfolioID,
    StockSymbol,
    CurrentPrice,
    RANK() OVER (PARTITION BY PortfolioID ORDER BY CurrentPrice DESC) AS price_rank
FROM PortfolioHoldings;

-- ❌ ПЛОХО: Ранжирование без контекста
SELECT 
    StockSymbol,
    CurrentPrice,
    RANK() OVER (ORDER BY CurrentPrice DESC) AS price_rank
FROM PortfolioHoldings;
```

#### 2. Явно определяйте ROWS для скользящих окон
```sql
-- ✅ ХОРОШО: Явное определение окна (последние 20 дней)
SELECT 
    TradeDate,
    ClosePrice,
    AVG(ClosePrice) OVER (
        ORDER BY TradeDate
        ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) AS sma_20
FROM StockPrices
WHERE StockSymbol = 'AAPL';

-- ❌ ПЛОХО: Неопределенное окно по умолчанию
SELECT 
    TradeDate,
    ClosePrice,
    AVG(ClosePrice) OVER (ORDER BY TradeDate) AS avg_price
FROM StockPrices;
```

#### 3. Кэшируйте результаты оконных функций с CTE
```sql
-- ✅ ХОРОШО: CTE для повторного использования
WITH PriceStats AS (
    SELECT 
        StockSymbol,
        TradeDate,
        ClosePrice,
        AVG(ClosePrice) OVER (PARTITION BY StockSymbol ORDER BY TradeDate 
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS sma_20
    FROM StockPrices
)
SELECT 
    *,
    ClosePrice - sma_20 AS deviation
FROM PriceStats
WHERE sma_20 IS NOT NULL;

-- ❌ ПЛОХО: Повторная вычисление оконных функций
SELECT 
    StockSymbol,
    ClosePrice,
    AVG(ClosePrice) OVER (...) AS sma_20,
    ClosePrice - AVG(ClosePrice) OVER (...) AS deviation
FROM StockPrices;
```

#### 4. Используйте ROWS BETWEEN для граничных случаев
```sql
-- ✅ ХОРОШО: Обработка первых и последних строк
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    FIRST_VALUE(ClosePrice) OVER (
        PARTITION BY StockSymbol 
        ORDER BY TradeDate
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS year_open,
    LAST_VALUE(ClosePrice) OVER (
        PARTITION BY StockSymbol 
        ORDER BY TradeDate
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS year_close
FROM StockPrices;
```

### ⚠️ Распространенные ошибки

| Ошибка | Проблема | Решение |
|--------|----------|--------|
| **Забыли PARTITION BY** | Все строки объединяются в одно окно | Добавьте PARTITION BY для логического разбиения |
| **ROWS BY DEFAULT** | Окно от начала до текущей строки | Используйте ROWS BETWEEN UNBOUNDED для полного окна |
| **Вложенные оконные функции** | Медленно и сложно | Используйте CTE для кэширования |
| **NULL в ORDER BY** | NULL упорядочиваются в начале | Используйте NULLS LAST/FIRST (если поддерживается) |

### 📊 Таблица сложности

| Функция | Сложность | Рекомендация |
|---------|-----------|-------------|
| ROW_NUMBER, RANK | O(n log n) | Быстро даже на больших наборах |
| LAG, LEAD | O(n) | Очень быстро |
| SUM, AVG с ROWS | O(n*m) где m - размер окна | Осторожно на больших окнах |
| NTILE | O(n log n) | Быстро |

---

## JOINs и подзапросы

### ✅ Лучшие практики

#### 1. Используйте EXISTS вместо IN для больших наборов данных
```sql
-- ✅ ХОРОШО: EXISTS останавливается при первом совпадении
SELECT c.*
FROM Clients c
WHERE EXISTS (
    SELECT 1 FROM Orders o 
    WHERE o.ClientID = c.ClientID 
    AND o.OrderAmount > 5000
);

-- ❌ ПЛОХО: IN обрабатывает весь подзапрос
SELECT c.*
FROM Clients c
WHERE ClientID IN (
    SELECT ClientID FROM Orders WHERE OrderAmount > 5000
);
```

#### 2. Используйте JOIN вместо подзапросов в SELECT
```sql
-- ✅ ХОРОШО: JOIN позволяет оптимизатору выбрать лучший план
SELECT 
    c.ClientName,
    COUNT(o.OrderID) AS order_count,
    SUM(o.OrderAmount) AS total_spent
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID, c.ClientName;

-- ❌ ПЛОХО: Подзапрос в SELECT выполняется для каждой строки
SELECT 
    c.ClientID,
    c.ClientName,
    (SELECT COUNT(*) FROM Orders WHERE ClientID = c.ClientID) AS order_count,
    (SELECT SUM(OrderAmount) FROM Orders WHERE ClientID = c.ClientID) AS total_spent
FROM Clients c;
```

#### 3. Будьте осторожны с LEFT JOIN условиями
```sql
-- ✅ ХОРОШО: Фильтр в ON для LEFT JOIN
SELECT 
    c.ClientName,
    COUNT(o.OrderID) AS recent_orders
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
    AND o.OrderDate >= DATEADD(MONTH, -6, GETDATE())
GROUP BY c.ClientID, c.ClientName;

-- ❌ ПЛОХО: Фильтр в WHERE превращает LEFT JOIN в INNER JOIN
SELECT 
    c.ClientName,
    COUNT(o.OrderID) AS recent_orders
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
WHERE o.OrderDate >= DATEADD(MONTH, -6, GETDATE())
GROUP BY c.ClientID, c.ClientName;
```

#### 4. Проверьте для NULL в SELF JOINs
```sql
-- ✅ ХОРОШО: Обработка NULL менеджеров
SELECT 
    e1.EmployeeName,
    COALESCE(e2.EmployeeName, 'No Manager') AS ManagerName
FROM Employees e1
LEFT JOIN Employees e2 ON e1.ManagerID = e2.EmployeeID;

-- ❌ ПЛОХО: NULL фильтруется
SELECT 
    e1.EmployeeName,
    e2.EmployeeName AS ManagerName
FROM Employees e1
INNER JOIN Employees e2 ON e1.ManagerID = e2.EmployeeID;
```

#### 5. Избегайте NOT IN с NULL
```sql
-- ✅ ХОРОШО: NOT EXISTS безопасен с NULL
SELECT c.*
FROM Clients c
WHERE NOT EXISTS (
    SELECT 1 FROM BlackList b WHERE b.ClientID = c.ClientID
);

-- ❌ ПЛОХО: NOT IN может вернуть неожиданные результаты с NULL
SELECT c.*
FROM Clients c
WHERE ClientID NOT IN (SELECT ClientID FROM BlackList);
-- Если BlackList содержит NULL, ничего не вернется!
```

### 📊 Сравнение производительности

```sql
-- Тестовые данные: 100,000 клиентов, 1,000,000 заказов

Операция                          | Время (мс) | Рекомендация
----------------------------------|-----------|-------------
EXISTS (коррелированный)          | 150       | Лучший выбор
IN (большой подзапрос)            | 800       | Избегать
INNER JOIN                        | 200       | Хороший выбор
LEFT JOIN + WHERE                 | 1000      | Неправильное использование
LEFT JOIN + ON условие            | 200       | Правильное использование
NOT EXISTS                        | 200       | Лучший выбор для NOT
NOT IN с NULL                     | 0 результатов | ОПАСНО!
```

---

## CTE и временные объекты

### ✅ Лучшие практики

#### 1. Используйте CTE для читаемости при среднем размере данных
```sql
-- ✅ ХОРОШО: Читаемая структура
WITH ClientSpending AS (
    -- Шаг 1: Рассчитать расходы по клиентам
    SELECT 
        ClientID,
        SUM(OrderAmount) AS total_spent
    FROM Orders
    GROUP BY ClientID
),
TopClients AS (
    -- Шаг 2: Отфильтровать топ 10
    SELECT TOP 10 * FROM ClientSpending
    WHERE total_spent > 0
    ORDER BY total_spent DESC
)
SELECT * FROM TopClients;
```

#### 2. Используйте #TempTable для больших объемов данных (>100k)
```sql
-- ✅ ХОРОШО: Производительность с большими объемами
CREATE TABLE #LargeDataset (
    ClientID INT,
    OrderCount INT,
    TotalSpent DECIMAL(18,2),
    INDEX idx_client (ClientID)
);

INSERT INTO #LargeDataset
SELECT TOP 100000
    o.ClientID,
    COUNT(*) AS OrderCount,
    SUM(o.OrderAmount) AS TotalSpent
FROM Orders o
GROUP BY o.ClientID;

-- Запросы к временной таблице
SELECT * FROM #LargeDataset WHERE TotalSpent > 50000;

DROP TABLE #LargeDataset;
```

#### 3. Используйте @TableVariable для малых объемов (<10k)
```sql
-- ✅ ХОРОШО: Память и производительность для малых данных
DECLARE @ClientIds TABLE (
    ClientID INT PRIMARY KEY,
    ClientName VARCHAR(100)
);

INSERT INTO @ClientIds
SELECT TOP 1000 ClientID, ClientName
FROM Clients
WHERE RegistrationDate >= DATEADD(MONTH, -3, GETDATE());

SELECT * FROM @ClientIds WHERE ClientID > 100;
```

#### 4. Установите MAXRECURSION для рекурсивных CTE
```sql
-- ✅ ХОРОШО: Явное ограничение глубины
WITH EmployeeHierarchy AS (
    SELECT EmployeeID, ManagerID, 1 AS level
    FROM Employees WHERE ManagerID IS NULL
    
    UNION ALL
    
    SELECT e.EmployeeID, e.ManagerID, eh.level + 1
    FROM Employees e
    INNER JOIN EmployeeHierarchy eh ON e.ManagerID = eh.EmployeeID
    WHERE eh.level < 50  -- Явное ограничение
)
SELECT * FROM EmployeeHierarchy
OPTION (MAXRECURSION 100);  -- Также явное ограничение
```

### ⚠️ Распространенные ошибки

| Ошибка | Проблема | Решение |
|--------|----------|--------|
| **Бесконечная рекурсия** | Программа зависает | Добавьте WHERE уровень < N |
| **CTE для 1M+ строк** | Медленно | Используйте #TempTable |
| **Множественные вложенные CTE** | Сложно читать | Разбейте на несколько запросов |
| **@TableVariable без индекса** | Медленно на JOIN | Добавьте PRIMARY KEY |

### 📋 Рекомендуемые размеры данных

| Размер данных | Рекомендуемый подход | Причина |
|---------------|-------------------|---------|
| < 1,000 | @TableVariable или CTE | Скорость и простота |
| 1,000-100,000 | CTE или #TempTable | Зависит от запроса |
| > 100,000 | #TempTable | Производительность и масштабируемость |
| Очень частые запросы | Материализованное представление | Кэширование результатов |

---

## Представления

### ✅ Лучшие практики

#### 1. Используйте префиксы для типа представления
```sql
-- ✅ ХОРОШО: Четкое именование
CREATE VIEW vw_Finance_ClientSummary AS ...     -- Обычное представление
CREATE VIEW ivw_ProductSales AS ...             -- Индексированное представление
CREATE VIEW vw_Admin_AllData AS ...             -- Для администраторов

-- ❌ ПЛОХО: Неясное назначение
CREATE VIEW Report1 AS ...
CREATE VIEW ClientView AS ...
```

#### 2. Добавляйте документацию
```sql
-- ✅ ХОРОШО: Документированное представление
CREATE VIEW vw_Finance_ClientSummary AS
SELECT ...;

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Shows financial metrics for all clients. Updated hourly.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'VIEW', @level1name = N'vw_Finance_ClientSummary';
```

#### 3. Используйте индексированные представления осторожно
```sql
-- ✅ ХОРОШО: С SCHEMABINDING и правильной структурой
CREATE VIEW vw_ProductSalesAgg
WITH SCHEMABINDING
AS
SELECT 
    p.ProductID,
    p.ProductName,
    COUNT_BIG(*) AS SaleCount,
    SUM(CAST(oi.Quantity AS BIGINT)) AS TotalQuantity,
    SUM(CAST(oi.Price * oi.Quantity AS BIGINT)) AS TotalRevenue
FROM dbo.Products p
INNER JOIN dbo.OrderItems oi ON p.ProductID = oi.ProductID
GROUP BY p.ProductID, p.ProductName;

-- Создание уникального кластеризованного индекса
CREATE UNIQUE CLUSTERED INDEX idx_ProductSalesAgg
ON vw_ProductSalesAgg(ProductID);
```

#### 4. Используйте WITH (NOEXPAND) для принудительного использования индекса
```sql
-- ✅ ХОРОШО: Принудительное использование индекса
SELECT TOP 100 *
FROM vw_ProductSalesAgg
WITH (NOEXPAND)
WHERE TotalRevenue > 100000
ORDER BY TotalRevenue DESC;
```

#### 5. Управляйте зависимостями
```sql
-- ✅ ХОРОШО: Проверка зависимостей перед изменением
EXEC sp_depends 'vw_FinancialReport';

SELECT DISTINCT
    referenced_schema_name,
    referenced_entity_name
FROM sys.dm_sql_referenced_entities('dbo.vw_FinancialReport', 'OBJECT');

-- Проверка объектов, зависящих от представления
SELECT * FROM sys.sql_dependencies
WHERE referenced_major_id = OBJECT_ID('vw_FinancialReport');
```

### ⚠️ Анти-паттерны представлений

| Анти-паттерн | Проблема | Решение |
|-------------|----------|--------|
| **Представление на представлении** | Сложность и производительность | Используйте одно представление или CTE |
| **Очень сложное представление** |难читаемость | Разбейте на несколько представлений |
| **Индексированное представление для редких запросов** | Пустая трата памяти | Используйте обычное представление |
| **Обновление представления без INSTEAD OF триггера** | Неправильные результаты | Создайте триггер или используйте обычную таблицу |

---

## Общие рекомендации

### 🎯 Иерархия оптимизации

1. **Выбор правильного типа объекта** (CTE vs #Temp vs @Table)
2. **Индексирование** (колонок в JOIN и WHERE)
3. **Минимизация окна данных** (PARTITION BY, WHERE условия)
4. **Избегание н operativeых операций** (LIKE %, OR, NOT IN)
5. **Кэширование результатов** (материализованные представления)

### 📊 Контрольный список производительности

```sql
-- Перед использованием в production:

-- 1. Проверьте план выполнения
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
-- Запустите ваш запрос
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- 2. Проверьте использование памяти
DBCC MEMORYSTATUS;

-- 3. Проверьте использование CPU
-- SELECT * FROM sys.dm_exec_requests;

-- 4. Протестируйте на максимальном наборе данных
-- Используйте TOP с постепенным увеличением
SELECT TOP 1000 * FROM LargeTable;
SELECT TOP 10000 * FROM LargeTable;
SELECT TOP 100000 * FROM LargeTable;
```

### 🔍 Мониторинг и поддерживаемость

```sql
-- Найти неиспользуемые представления
SELECT 
    OBJECT_NAME(i.object_id) AS view_name,
    SUM(s.user_seeks) + SUM(s.user_scans) + SUM(s.user_lookups) AS usage_count
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s 
    ON i.object_id = s.object_id
WHERE OBJECTPROPERTY(i.object_id, 'IsView') = 1
GROUP BY i.object_id
ORDER BY usage_count;

-- Найти самые медленные запросы
SELECT TOP 20
    qt.text,
    qs.execution_count,
    qs.total_elapsed_time / 1000000 AS total_time_sec,
    qs.total_elapsed_time / qs.execution_count / 1000 AS avg_time_ms
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_elapsed_time DESC;
```

---

## Анти-паттерны

### ❌ Избегайте

#### 1. Множественные подзапросы в SELECT (N+1 Problem)
```sql
-- ❌ ПЛОХО: Выполняется 1 + N раз
SELECT 
    ClientID,
    (SELECT COUNT(*) FROM Orders WHERE ClientID = c.ClientID) AS order_count,
    (SELECT SUM(OrderAmount) FROM Orders WHERE ClientID = c.ClientID) AS total,
    (SELECT MAX(OrderDate) FROM Orders WHERE ClientID = c.ClientID) AS last_date
FROM Clients c;

-- ✅ ХОРОШО: Выполняется один раз
SELECT 
    c.ClientID,
    COUNT(o.OrderID) AS order_count,
    SUM(o.OrderAmount) AS total,
    MAX(o.OrderDate) AS last_date
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID;
```

#### 2. Динамический SQL без параметризации
```sql
-- ❌ ПЛОХО: SQL Injection опасность
DECLARE @SQL NVARCHAR(MAX) = 'SELECT * FROM Clients WHERE ClientID = ' + @ClientID;
EXEC sp_executesql @SQL;

-- ✅ ХОРОШО: Параметризованный запрос
SELECT * FROM Clients WHERE ClientID = @ClientID;
```

#### 3. DISTINCT БЕЗ необходимости
```sql
-- ❌ ПЛОХО: Дополнительное сканирование для удаления дублей
SELECT DISTINCT
    c.ClientID,
    c.ClientName
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID;

-- ✅ ХОРОШО: GROUP BY если нужны уникальные строки
SELECT 
    c.ClientID,
    c.ClientName
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID, c.ClientName;
```

#### 4. Функции в WHERE условиях
```sql
-- ❌ ПЛОХО: Не может использовать индекс
SELECT * FROM Orders
WHERE YEAR(OrderDate) = 2024;

-- ✅ ХОРОШО: Может использовать индекс
SELECT * FROM Orders
WHERE OrderDate >= '2024-01-01' AND OrderDate < '2025-01-01';
```

---

## Чек-лист оптимизации

### 📋 Перед написанием запроса

- [ ] Вы знаете точные требования?
- [ ] Вы определили нужный размер результирующего набора?
- [ ] Вы решили будете ли добавлять фильтры?

### 📋 При написании запроса

- [ ] Правильно ли выбран тип JOIN?
- [ ] Используете ли вы EXISTS вместо IN где нужно?
- [ ] Правильно ли использованы условия в ON для LEFT JOIN?
- [ ] Есть ли необходимые индексы?
- [ ] Хорошее ли имя для CTE/представления?

### 📋 После написания запроса

- [ ] Вы проверили план выполнения?
- [ ] Вы измерили время выполнения?
- [ ] Вы протестировали на максимальном наборе данных?
- [ ] Вы добавили необходимые индексы?
- [ ] Вы задокументировали сложные части?
- [ ] Вы выполнили code review?

### 📋 В production

- [ ] Вы мониторите использование запроса?
- [ ] Вы имеете план действий при деградации производительности?
- [ ] Вы регулярно пересчитываете статистику?
- [ ] Вы документируете изменения для других разработчиков?

---

## Заключение

Помните:
1. **Читаемость важна** - будущий вы будет благодарен
2. **Тестируйте на реальных данных** - не на тестовых
3. **Профилируйте все** - не угадывайте
4. **Документируйте решения** - особенно "странные" на первый взгляд
5. **Изучайте планы выполнения** - это окно в ум SQL Server

**Happy coding! 🚀**
