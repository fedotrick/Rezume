# Практическая Задача 4: Анализ плана запроса

## Описание задачи

Взять медленный запрос, проанализировать план выполнения и оптимизировать его с помощью индексов.

---

## Часть 1: Создание тестовой таблицы с данными

```sql
USE SQLTraining;

-- Создать таблицу
IF OBJECT_ID('SalesData', 'U') IS NOT NULL
    DROP TABLE SalesData;

CREATE TABLE SalesData (
    SaleID INT PRIMARY KEY IDENTITY(1,1),
    ProductID INT,
    CustomerID INT,
    RegionID INT,
    SaleDate DATETIME,
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    TotalAmount DECIMAL(15,2),
    OrderStatus NVARCHAR(20),
    Salesperson NVARCHAR(100),
    Notes NVARCHAR(MAX)
);

-- Заполнить 100,000 строк
DECLARE @i INT = 0;

WHILE @i < 100000
BEGIN
    INSERT INTO SalesData (
        ProductID, CustomerID, RegionID, SaleDate, Quantity,
        UnitPrice, TotalAmount, OrderStatus, Salesperson, Notes
    )
    VALUES (
        FLOOR(RAND() * 1000) + 1,
        FLOOR(RAND() * 5000) + 1,
        FLOOR(RAND() * 10) + 1,
        DATEADD(DAY, FLOOR(RAND() * 365), '2024-01-01'),
        FLOOR(RAND() * 100) + 1,
        FLOOR(RAND() * 500) + 1,
        (FLOOR(RAND() * 100) + 1) * (FLOOR(RAND() * 500) + 1),
        CASE FLOOR(RAND() * 3) WHEN 0 THEN 'Pending' WHEN 1 THEN 'Completed' ELSE 'Cancelled' END,
        CONCAT('Sales Person ', FLOOR(RAND() * 50) + 1),
        CONCAT('Notes for order ', @i)
    );
    
    SET @i = @i + 1;
    
    IF @i % 10000 = 0
        PRINT CONCAT('Inserted ', @i, ' rows');
END;

-- Проверить данные
SELECT COUNT(*) as TotalRows FROM SalesData;
SELECT TOP 10 * FROM SalesData;
```

---

## Часть 2: МЕДЛЕННЫЕ ЗАПРОСЫ (Проблемные примеры)

### Запрос 1: Table Scan вместо Index Seek

```sql
-- МЕДЛЕННЫЙ ЗАПРОС 1: Функция на столбце WHERE
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    SaleID,
    ProductID,
    CustomerID,
    TotalAmount,
    SaleDate
FROM SalesData
WHERE YEAR(SaleDate) = 2024;

-- Вывод статистики:
-- Table 'SalesData'. Scan count 1, logical reads: 400
-- CPU time = 500ms, elapsed time = 600ms
-- ❌ МЕДЛЕННО: Table Scan, 400 logical reads

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```

**Анализ плана**:
- Table Scan: SQL Server просмотрел ВСЕ строки таблицы
- Функция YEAR() не может использовать индекс
- Обработка 100,000 строк заняла 600ms

---

### Запрос 2: JOIN без индексов на FK

```sql
-- МЕДЛЕННЫЙ ЗАПРОС 2: Несколько JOIN без индексов
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    s.SaleID,
    s.ProductID,
    s.CustomerID,
    s.TotalAmount,
    s.Quantity,
    s.UnitPrice
FROM SalesData s
WHERE s.CustomerID = 123
    AND s.OrderStatus = 'Completed'
    AND s.SaleDate > '2024-06-01';

-- Вывод статистики:
-- Table 'SalesData'. Scan count 1, logical reads: 350
-- CPU time = 400ms

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```

**Анализ плана**:
- Table Scan: просмотр 100,000 строк
- Нет индекса на (CustomerID, OrderStatus, SaleDate)
- Все строки обработаны, даже не соответствующие условиям

---

### Запрос 3: Функция в SELECT вызывает многие операции

```sql
-- МЕДЛЕННЫЙ ЗАПРОС 3: Подзапросы в SELECT
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    s.SaleID,
    s.ProductID,
    s.TotalAmount,
    (SELECT COUNT(*) FROM SalesData WHERE CustomerID = s.CustomerID) as CustomerOrderCount,
    (SELECT SUM(TotalAmount) FROM SalesData WHERE CustomerID = s.CustomerID) as CustomerTotalSpent
FROM SalesData s
WHERE s.OrderStatus = 'Completed'
LIMIT 100;

-- Вывод статистики:
-- Table 'SalesData'. Scan count 100+, logical reads: 5000+
-- CPU time = 2000ms

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```

**Анализ плана**:
- Для каждой строки выполняются подзапросы
- 100 строк → 100 * 2 подзапроса = 200+ сканирований таблицы
- Очень неэффективно!

---

## Часть 3: Анализ плана запроса в SSMS

### Включение Execution Plan

```sql
-- Метод 1: Графический план (рекомендуется)
-- В SSMS: Ctrl+L или Query → Display Estimated Execution Plan
-- Выполнить запрос → увидеть план справа

-- Метод 2: Текстовый план
SET STATISTICS PROFILE ON;
SELECT * FROM SalesData WHERE CustomerID = 100;
SET STATISTICS PROFILE OFF;

-- Метод 3: Детальные метрики
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SELECT * FROM SalesData WHERE CustomerID = 100;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```

### Интерпретация плана

```
Estimated Plan (до выполнения):
├─ Clustered Index Scan (SalesData)
│  ├─ Estimated Rows: 20
│  ├─ Estimated I/O Cost: 0.012
│  └─ Estimated CPU Cost: 0.002
├─ Filter (OrderStatus = 'Completed')
│  ├─ Estimated Rows: 7
│  └─ Filter Expression: [SalesData].[OrderStatus]='Completed'
└─ Compute Scalar (вычисление)
   └─ Expression: конвертирование типов

Ключевые метрики:
- Estimated Rows: предполагаемое количество
- Actual Rows: реальное количество (если есть ошибка в статистике)
- I/O Cost: стоимость дисковых операций
- CPU Cost: стоимость процессорных операций
- Width: размер каждой строки
```

---

## Часть 4: Оптимизация с помощью индексов

### Оптимизация Запроса 1: Использование Range вместо функции

```sql
-- ОПТИМИЗИРОВАННЫЙ ЗАПРОС 1
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Вместо YEAR(SaleDate) = 2024, используем диапазон
SELECT 
    SaleID,
    ProductID,
    CustomerID,
    TotalAmount,
    SaleDate
FROM SalesData
WHERE SaleDate >= '2024-01-01' AND SaleDate < '2025-01-01';

-- Вывод статистики:
-- Table 'SalesData'. Scan count 1, logical reads: 10
-- CPU time = 50ms
-- ✓ БЫСТРО: Seek вместо Scan, 10 логических чтений

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- Шаг 1: Создать индекс на SaleDate
CREATE NONCLUSTERED INDEX IX_SalesData_SaleDate
ON SalesData(SaleDate)
INCLUDE (ProductID, CustomerID, TotalAmount);

-- Теперь запрос будет использовать Index Seek
```

**Результаты**:
- Было: 400 reads, 600ms
- Стало: 10 reads, 50ms
- **Ускорение: в 12 раз!**

---

### Оптимизация Запроса 2: Composite Index

```sql
-- ОПТИМИЗИРОВАННЫЙ ЗАПРОС 2: Composite Index
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    s.SaleID,
    s.ProductID,
    s.CustomerID,
    s.TotalAmount,
    s.Quantity,
    s.UnitPrice
FROM SalesData s
WHERE s.CustomerID = 123
    AND s.OrderStatus = 'Completed'
    AND s.SaleDate > '2024-06-01';

-- После создания индекса:
-- Table 'SalesData'. Scan count 1, logical reads: 5
-- CPU time = 10ms
-- ✓ ОЧЕНЬ БЫСТРО: Из 350 reads до 5 reads!

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- Шаг 1: Создать Composite Index
-- Порядок: Наиболее селективные столбцы первыми
CREATE NONCLUSTERED INDEX IX_SalesData_Customer_Status_Date
ON SalesData(CustomerID, OrderStatus, SaleDate DESC)
INCLUDE (ProductID, TotalAmount, Quantity, UnitPrice);
```

**Результаты**:
- Было: 350 reads, 400ms
- Стало: 5 reads, 10ms
- **Ускорение: в 40 раз!**

---

### Оптимизация Запроса 3: Избегание подзапросов

```sql
-- ОПТИМИЗИРОВАННЫЙ ЗАПРОС 3: Использование JOIN вместо подзапросов

-- НЕПРАВИЛЬНО (медленно):
SELECT 
    s.SaleID,
    s.ProductID,
    s.TotalAmount,
    (SELECT COUNT(*) FROM SalesData WHERE CustomerID = s.CustomerID) as CustomerOrderCount,
    (SELECT SUM(TotalAmount) FROM SalesData WHERE CustomerID = s.CustomerID) as CustomerTotalSpent
FROM SalesData s
WHERE s.OrderStatus = 'Completed'
LIMIT 100;

-- ПРАВИЛЬНО (быстро): Использовать GROUP BY с JOIN
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

WITH CustomerStats AS (
    SELECT 
        CustomerID,
        COUNT(*) as CustomerOrderCount,
        SUM(TotalAmount) as CustomerTotalSpent
    FROM SalesData
    GROUP BY CustomerID
)
SELECT 
    s.SaleID,
    s.ProductID,
    s.TotalAmount,
    cs.CustomerOrderCount,
    cs.CustomerTotalSpent
FROM SalesData s
JOIN CustomerStats cs ON s.CustomerID = cs.CustomerID
WHERE s.OrderStatus = 'Completed'
LIMIT 100;

-- Вывод статистики:
-- Table 'SalesData'. Scan count 2, logical reads: 50
-- CPU time = 100ms
-- ✓ НАМНОГО БЫСТРЕЕ: Из 5000+ reads до 50 reads!

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- Создать индекс на OrderStatus для быстрой фильтрации
CREATE NONCLUSTERED INDEX IX_SalesData_OrderStatus
ON SalesData(OrderStatus)
INCLUDE (CustomerID, TotalAmount);
```

**Результаты**:
- Было: 5000+ reads, 2000ms
- Стало: 50 reads, 100ms
- **Ускорение: в 20 раз!**

---

## Часть 5: Полный процесс оптимизации

### Шаг 1: Определить проблемные запросы

```sql
-- Найти дорогие запросы
SELECT TOP 10
    qs.execution_count,
    qs.total_elapsed_time / 1000000 as total_elapsed_time_sec,
    qs.total_elapsed_time / qs.execution_count / 1000 as avg_elapsed_time_ms,
    qs.total_logical_reads,
    qs.total_logical_reads / qs.execution_count as avg_logical_reads,
    SUBSTRING(st.text, 1, 100) as query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_elapsed_time DESC;
```

### Шаг 2: Анализировать план выполнения

```sql
-- Получить план для конкретного запроса
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Запрос под анализом
SELECT * FROM SalesData WHERE CustomerID = 100;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- Анализ результата:
-- - Количество logical reads
-- - Способ доступа (Scan vs Seek)
-- - Используемые индексы
-- - Узкие места (bottlenecks)
```

### Шаг 3: Создать индексы

```sql
-- Создать необходимые индексы
CREATE NONCLUSTERED INDEX IX_SalesData_CustomerID
ON SalesData(CustomerID)
INCLUDE (OrderStatus, SaleDate, TotalAmount);
```

### Шаг 4: Проверить результаты

```sql
-- Сравнить производительность до и после

-- Шаг 4a: Отключить индекс
ALTER INDEX IX_SalesData_CustomerID ON SalesData DISABLE;

SET STATISTICS IO ON;
SELECT * FROM SalesData WHERE CustomerID = 100;
SET STATISTICS IO OFF;
-- Результат: 400 reads

-- Шаг 4b: Включить индекс
ALTER INDEX IX_SalesData_CustomerID ON SalesData REBUILD;

SET STATISTICS IO ON;
SELECT * FROM SalesData WHERE CustomerID = 100;
SET STATISTICS IO OFF;
-- Результат: 5 reads

-- ✓ Ускорение: в 80 раз!
```

---

## Часть 6: Примеры реальных оптимизаций

### Пример 1: Медленный отчет

```sql
-- МЕДЛЕННЫЙ ОТЧЕТ (исходный)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    DATEPART(YEAR, s.SaleDate) as Year,
    DATEPART(MONTH, s.SaleDate) as Month,
    s.OrderStatus,
    COUNT(*) as OrderCount,
    SUM(s.TotalAmount) as TotalSales,
    AVG(s.TotalAmount) as AvgSale
FROM SalesData s
WHERE s.OrderStatus IN ('Completed', 'Pending')
GROUP BY 
    DATEPART(YEAR, s.SaleDate),
    DATEPART(MONTH, s.SaleDate),
    s.OrderStatus
ORDER BY Year, Month, OrderStatus;

-- Результаты:
-- Table 'SalesData'. Scan count 1, logical reads: 400
-- CPU time: 1000ms

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- ОПТИМИЗАЦИЯ: Создать Columnstore Index
CREATE NONCLUSTERED COLUMNSTORE INDEX IXCC_SalesData
ON SalesData(SaleDate, OrderStatus, TotalAmount);

-- ОПТИМИЗИРОВАННЫЙ ОТЧЕТ
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    DATEPART(YEAR, s.SaleDate) as Year,
    DATEPART(MONTH, s.SaleDate) as Month,
    s.OrderStatus,
    COUNT(*) as OrderCount,
    SUM(s.TotalAmount) as TotalSales,
    AVG(s.TotalAmount) as AvgSale
FROM SalesData s
WHERE s.OrderStatus IN ('Completed', 'Pending')
GROUP BY 
    DATEPART(YEAR, s.SaleDate),
    DATEPART(MONTH, s.SaleDate),
    s.OrderStatus
ORDER BY Year, Month, OrderStatus;

-- Результаты:
-- Table 'SalesData'. Scan count 1, logical reads: 10
-- CPU time: 50ms

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- ✓ Ускорение: в 20 раз благодаря Columnstore!
```

---

### Пример 2: Дорогой JOIN

```sql
-- Создать вторую таблицу для JOIN
IF OBJECT_ID('Products', 'U') IS NOT NULL
    DROP TABLE Products;

CREATE TABLE Products (
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100),
    Category NVARCHAR(50),
    Price DECIMAL(10,2)
);

-- Вставить данные
INSERT INTO Products
SELECT DISTINCT ProductID, CONCAT('Product ', ProductID), 'Category', 100
FROM SalesData;

-- МЕДЛЕННЫЙ ЗАПРОС (без индекса на FK)
SET STATISTICS IO ON;

SELECT 
    s.SaleID,
    p.ProductName,
    s.TotalAmount
FROM SalesData s
JOIN Products p ON s.ProductID = p.ProductID
WHERE s.SaleDate >= '2024-06-01';

-- Table 'SalesData'. Scan count: 1, logical reads: 400
-- Table 'Products'. Scan count: 100000, logical reads: 200000 (очень плохо!)

SET STATISTICS IO OFF;

-- ОПТИМИЗАЦИЯ: Создать индекс на FK
CREATE NONCLUSTERED INDEX IX_SalesData_ProductID
ON SalesData(ProductID)
INCLUDE (SaleDate, TotalAmount);

-- ОПТИМИЗИРОВАННЫЙ ЗАПРОС
SET STATISTICS IO ON;

SELECT 
    s.SaleID,
    p.ProductName,
    s.TotalAmount
FROM SalesData s
JOIN Products p ON s.ProductID = p.ProductID
WHERE s.SaleDate >= '2024-06-01';

-- Table 'SalesData'. Scan count: 1, logical reads: 50
-- Table 'Products'. Scan count: 1, logical reads: 5

SET STATISTICS IO OFF;

-- ✓ Ускорение: в 40 раз благодаря FK индексу!
```

---

## Часть 7: Инструменты для анализа

### Способ 1: Графический план в SSMS

```
Ctrl+L → выполнить запрос → смотреть план справа
Значки в плане:
- 🔍 Table Scan (медленно)
- ✓ Index Seek (быстро)
- 🔑 Key Lookup (среднее)
- ⬆️⬇️ Sort (может быть узким местом)
- ⊕ Join (зависит от типа)
```

### Способ 2: Ориентировочный vs Фактический план

```sql
-- Ориентировочный план (до выполнения)
SET STATISTICS PROFILE ON;
-- Выполнить запрос
SET STATISTICS PROFILE OFF;
-- Таб "Messages" показывает реальные статистики
```

### Способ 3: DMV для анализа

```sql
-- Самые дорогие запросы
SELECT TOP 10
    qs.total_elapsed_time / 1000000 as total_elapsed_time_sec,
    qs.total_logical_reads,
    qs.execution_count,
    SUBSTRING(qt.text, 1, 100) as query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_elapsed_time DESC;
```

---

## Ключевые выводы

1. **Table Scan** → медленно, нужен индекс
2. **Index Seek** → быстро, хороший выбор
3. **Key Lookup** → среднее, можно улучшить с помощью INCLUDE
4. **Функции в WHERE** → не используют индекс, используйте диапазоны
5. **Подзапросы в SELECT** → используйте JOIN или CTE
6. **Composite Index** → может ускорить в 10-40 раз
7. **Columnstore** → отличное для отчетов и аналитики

---

## Домашнее задание

1. **Найдите** 3 медленных запроса в базе SalesData
2. **Проанализируйте** план выполнения для каждого
3. **Определите** причину медленности
4. **Создайте** индексы для оптимизации
5. **Проверьте** результаты (должно быть 5-40x ускорение)
6. **Документируйте** процесс и результаты
