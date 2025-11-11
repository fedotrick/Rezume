# Лекция 3: Индексы в SQL Server

## 1. Типы индексов

SQL Server поддерживает несколько типов индексов для оптимизации производительности:

### 1.1 Clustered Index (Кластерный индекс)

**Определение**: Кластерный индекс определяет физический порядок хранения строк в таблице. Может быть только один на таблицу.

**Характеристики**:
- ✓ Очень быстрое чтение данных по ключу индекса
- ✓ Часто совпадает с первичным ключом
- ✓ Иерархия: Индексная структура содержит листовые узлы с полными данными
- ✗ Медленное обновление (требует переорганизации)
- ✗ Медленное удаление/вставка (требует сдвига блокировки)

**Структура Clustered Index**:
```
         Root Node (уровень 2)
              |
     ┌────────┼────────┐
     |                 |
  Branch 1          Branch 2
     |                 |
  ┌──┼──┐           ┌──┼──┐
  |  |  |           |  |  |
Leaf1 Leaf2       Leaf3 Leaf4
  |    |            |    |
Rows Rows          Rows Rows
```

**Пример создания**:
```sql
-- Clustered Index на первичном ключе (обычно)
CREATE CLUSTERED INDEX IX_Orders_OrderID
ON Orders(OrderID);

-- Или явно на таблице
ALTER TABLE Customers
ADD CONSTRAINT PK_Customers_CustomerID 
PRIMARY KEY CLUSTERED (CustomerID);

-- Данные физически отсортированы по CustomerID
```

**Когда использовать**:
- Первичный ключ (если часто ищут по нему)
- Колонка, по которой часто выполняют range queries (BETWEEN)
- Колонка, которая редко обновляется

### 1.2 Non-Clustered Index (Некластерный индекс)

**Определение**: Отдельная структура, которая содержит ключевые столбцы и указатели на полные строки. Может быть до 999 на одну таблицу.

**Характеристики**:
- ✓ Несколько на одной таблице
- ✓ Быстрое создание и обновление
- ✓ Гибко выбирать столбцы
- ✓ Может ускорить несколько запросов
- ✗ Использует дополнительное место на диске
- ✗ Требует обновления при изменении данных

**Структура Non-Clustered Index**:
```
Non-Clustered Index                Таблица (Clustered)
                                   
    Index Key Ptr                      |
         |                             |
    ┌────┼─────┐                      Rows
    |    |     |                       |
  Value1 Ptr  Value2 Ptr              |
    |         |                        |
    └─────┼──────────┐                |
          |          |                |
    (lookup to actual row)            |
          ↓          ↓                ↓
    ┌─────────┬─────────────────────────┐
    | Value   | Other columns...        |
    └─────────┴─────────────────────────┘
```

**Пример создания**:
```sql
-- Простой Non-Clustered Index
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID
ON Orders(CustomerID);

-- Index с INCLUDE (дополнительные колонки)
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID_Include
ON Orders(CustomerID)
INCLUDE (OrderDate, Amount);

-- Composite Index (несколько столбцов)
CREATE NONCLUSTERED INDEX IX_Orders_Customer_Date
ON Orders(CustomerID, OrderDate DESC);

-- Filtered Index (только для некоторых строк)
CREATE NONCLUSTERED INDEX IX_Orders_Active
ON Orders(OrderID)
WHERE Status = 'Active';
```

**Когда использовать**:
- Часто используемые WHERE условия
- Colums в JOIN условиях
- Columns в ORDER BY
- Columns в SELECT (покрытие запроса)

### 1.3 Covering Index (Покрывающий индекс)

**Определение**: Non-Clustered Index с дополнительными столбцами в INCLUDE, который содержит ВСЕ столбцы, нужные для запроса.

**Преимущество**: Поиск может выполниться полностью в индексе без обращения к таблице (Index Seek + Index Scan = быстро).

**Пример**:
```sql
-- Если запрос:
SELECT OrderID, Amount FROM Orders WHERE CustomerID = 5;

-- Создаем покрывающий индекс
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID_Cover
ON Orders(CustomerID)
INCLUDE (OrderID, Amount);

-- Этот запрос выполнится полностью в индексе!
-- Нет обращения к основной таблице

-- Проверить план выполнения: Index Seek → Result (без Key Lookup)
```

### 1.4 Full-Text Index

**Определение**: Индекс для полнотекстового поиска по большим текстовым полям.

**Пример**:
```sql
-- Создать Full-Text Catalog
CREATE FULLTEXT CATALOG ftCatalog AS DEFAULT;

-- Создать Full-Text Index
CREATE FULLTEXT INDEX ON Products(Description)
KEY INDEX PK_Products ON ftCatalog;

-- Использование
SELECT * FROM Products
WHERE CONTAINS(Description, 'высокая качество');
```

**Когда использовать**:
- Поиск по статьям, описаниям
- Большие текстовые поля
- Языковые анализ и фонетический поиск

### 1.5 Columnstore Index

**Определение**: Новый тип индекса, оптимизированный для OLAP (аналитические запросы), хранит данные по столбцам, а не по строкам.

**Характеристики**:
- ✓ Очень эффективен для аналитических запросов
- ✓ Сжатие данных до 10 раз
- ✓ Параллельная обработка
- ✓ Кэширование строк
- ✗ Медленнее для обновлений
- ✗ Требует больше памяти

**Пример**:
```sql
-- Clustered Columnstore Index (весь таблица)
CREATE CLUSTERED COLUMNSTORE INDEX IXCC_Sales
ON Sales;

-- Non-Clustered Columnstore Index
CREATE NONCLUSTERED COLUMNSTORE INDEX IXNCC_Sales
ON Sales(ProductID, Amount, Quantity);

-- Запрос, который выполнится быстро
SELECT 
    ProductID,
    SUM(Amount) as TotalSales,
    COUNT(*) as TransactionCount
FROM Sales
GROUP BY ProductID;
```

---

## 2. Когда использовать какой индекс

### 2.1 Матрица выбора индекса

| Сценарий | Тип индекса | Причина |
|----------|-----------|---------|
| Первичный ключ | Clustered | Быстрое чтение, часто ищут |
| WHERE CustomerID = X | Non-Clustered | Точный поиск |
| WHERE Amount BETWEEN X AND Y | Clustered или Non-Clustered | Range query |
| WHERE Name LIKE 'A%' | Non-Clustered | Поиск по началу |
| SELECT Columns для отчета | Covering (Include) | Нет обращения к таблице |
| Полнотекстовый поиск | Full-Text | Специализированный |
| Аналитические SUM, AVG, COUNT | Columnstore | Сжатие и параллелизм |
| JOIN таблиц | Non-Clustered на FK | Быстрое соединение |

### 2.2 Примеры на реальных сценариях

**Сценарий 1: E-commerce - Каталог товаров**
```sql
-- Таблица
CREATE TABLE Products (
    ProductID INT PRIMARY KEY CLUSTERED,
    CategoryID INT,
    Name NVARCHAR(255),
    Price DECIMAL(10,2),
    Stock INT,
    Description NVARCHAR(MAX),
    CreatedDate DATETIME
);

-- Индексы
-- 1. Поиск по категории
CREATE NONCLUSTERED INDEX IX_Products_CategoryID
ON Products(CategoryID)
INCLUDE (Name, Price, Stock);

-- 2. Поиск по диапазону цены
CREATE NONCLUSTERED INDEX IX_Products_Price
ON Products(Price)
INCLUDE (Name, Stock);

-- 3. Полнотекстовый поиск
CREATE FULLTEXT INDEX ON Products(Description)
KEY INDEX PK_Products ON ftCatalog;

-- Запросы, которые выполнятся быстро:
-- SELECT * FROM Products WHERE CategoryID = 5;  (использует IX_Products_CategoryID)
-- SELECT * FROM Products WHERE Price BETWEEN 100 AND 500;  (использует IX_Products_Price)
-- SELECT * FROM Products WHERE CONTAINS(Description, 'wireless');  (FT Search)
```

**Сценарий 2: Банковская система - Транзакции**
```sql
CREATE TABLE Transactions (
    TransactionID BIGINT PRIMARY KEY CLUSTERED,
    FromAccountID INT,
    ToAccountID INT,
    Amount DECIMAL(15,2),
    TransactionDate DATETIME,
    Status NVARCHAR(20)
);

-- 1. Поиск транзакций по счету (очень частый запрос)
CREATE NONCLUSTERED INDEX IX_Transactions_FromAccount
ON Transactions(FromAccountID, TransactionDate DESC);

-- 2. Поиск по дате для отчетов
CREATE NONCLUSTERED INDEX IX_Transactions_Date
ON Transactions(TransactionDate DESC)
INCLUDE (FromAccountID, ToAccountID, Amount);

-- 3. Поиск только успешных транзакций
CREATE NONCLUSTERED INDEX IX_Transactions_Success
ON Transactions(Status, TransactionDate DESC)
WHERE Status = 'Completed';

-- Часто используемые запросы:
-- SELECT * FROM Transactions WHERE FromAccountID = 123;
-- SELECT * FROM Transactions WHERE TransactionDate >= '2024-01-01' ORDER BY TransactionDate DESC;
```

---

## 3. Анализ планов запросов

### 3.1 Как включить графический план запроса

```sql
-- В SQL Server Management Studio
-- Ctrl+L или Query → Display Estimated Execution Plan

-- Или запрос вернет план как результат
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT * FROM Orders WHERE CustomerID = 5;

-- Результаты покажут:
-- Table 'Orders'. Scan count X, logical reads Y, physical reads Z
-- CPU time = X ms, elapsed time = Y ms
```

### 3.2 Основные операции в плане запроса

| Операция | Значок | Описание | Производительность |
|----------|--------|---------|-------------------|
| **Scan** | 📋 | Просмотр всех строк | Медленно (O(n)) |
| **Seek** | 🎯 | Поиск по индексу | Быстро (O(log n)) |
| **Key Lookup** | 🔑 | Поиск в кластерном индексе | Среднее |
| **Nested Loop** | 🔄 | Вложенные циклы для JOIN | Зависит |
| **Hash Join** | # | Хеш-соединение | Быстро для больших |
| **Sort** | ⬆️⬇️ | Сортировка | Может быть узким местом |

### 3.3 Анализ реального плана

```sql
-- МЕДЛЕННЫЙ ЗАПРОС (без индекса)
SELECT * FROM Orders WHERE Status = 'Pending';

-- План: 
-- ├─ Table Scan (Orders)  [Выполнено: 100% CPU, самый дорогой]
-- └─ Result              

-- Улучшение: Создать индекс
CREATE NONCLUSTERED INDEX IX_Orders_Status
ON Orders(Status);

-- Теперь план:
-- ├─ Index Seek (IX_Orders_Status)  [Выполнено: 30% CPU]
-- └─ Result

-- Еще улучшение: Покрывающий индекс
CREATE NONCLUSTERED INDEX IX_Orders_Status_Cover
ON Orders(Status)
INCLUDE (CustomerID, OrderDate, Amount);

-- Теперь план:
-- ├─ Index Scan (IX_Orders_Status_Cover)  [Выполнено: 5% CPU, нет обращений к таблице]
-- └─ Result
```

### 3.4 Проблемные паттерны в планах

**Проблема 1: Table Scan вместо Index Seek**
```sql
-- ПЛОХО: Table Scan
SELECT * FROM Customers WHERE YEAR(CreatedDate) = 2024;

-- План: Table Scan (Scan count: 1, Logical reads: 1000)

-- ХОРОШО: используйте диапазон дат
SELECT * FROM Customers 
WHERE CreatedDate >= '2024-01-01' 
  AND CreatedDate < '2025-01-01';

-- План: Index Seek (Scan count: 0, Logical reads: 10)
```

**Проблема 2: Key Lookup для каждой строки**
```sql
-- МЕДЛЕННО: Index Seek → Key Lookup → Key Lookup...
SELECT OrderID, Amount, CustomerName 
FROM Orders 
WHERE OrderID = 123;

-- Это означает, что индекс содержит только OrderID,
-- для получения CustomerName нужно обращаться к основной таблице

-- БЫСТРО: Покрывающий индекс
CREATE NONCLUSTERED INDEX IX_Orders_OrderID_Cover
ON Orders(OrderID)
INCLUDE (Amount, CustomerName);

-- Теперь: Index Seek (все данные в индексе, нет Key Lookup)
```

**Проблема 3: Sort в большом наборе данных**
```sql
-- МЕДЛЕННО: Сортировка 1 млн строк в памяти
SELECT * FROM Orders WHERE CustomerID = 5
ORDER BY OrderDate DESC;

-- БЫСТРО: Индекс уже отсортирован
CREATE NONCLUSTERED INDEX IX_Orders_Customer_Date
ON Orders(CustomerID, OrderDate DESC);

-- Теперь данные приходят уже отсортированными
```

---

## 4. Примеры создания оптимальных индексов

### 4.1 Пример 1: Таблица заказов

```sql
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY CLUSTERED,
    CustomerID INT NOT NULL,
    OrderDate DATETIME NOT NULL,
    Status NVARCHAR(20) NOT NULL,
    Amount DECIMAL(10,2),
    ShippingDate DATETIME,
    Index_column NVARCHAR(255)
);

-- Анализ типичных запросов:
-- Q1: Найти все заказы клиента
-- Q2: Найти заказы за период
-- Q3: Найти активные заказы
-- Q4: Сумма заказов по месяцам

-- ОПТИМАЛЬНЫЕ ИНДЕКСЫ:

-- Индекс 1: Для Q1 и фильтрации по статусу
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID_Status
ON Orders(CustomerID, Status)
INCLUDE (OrderDate, Amount);

-- Индекс 2: Для Q2 (заказы за период)
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate
ON Orders(OrderDate DESC)
INCLUDE (CustomerID, Amount);

-- Индекс 3: Для Q3 (активные заказы)
CREATE NONCLUSTERED INDEX IX_Orders_Active
ON Orders(Status)
WHERE Status IN ('Pending', 'Processing')
INCLUDE (CustomerID, OrderDate);

-- Если используется OLAP (аналитика), добавить Columnstore
CREATE NONCLUSTERED COLUMNSTORE INDEX IXNCC_Orders
ON Orders(CustomerID, OrderDate, Amount);
```

### 4.2 Пример 2: Таблица пользователей

```sql
CREATE TABLE Users (
    UserID INT PRIMARY KEY CLUSTERED,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    FullName NVARCHAR(255),
    CreatedDate DATETIME,
    LastLoginDate DATETIME,
    IsActive BIT,
    Department NVARCHAR(100)
);

-- ОПТИМАЛЬНЫЕ ИНДЕКСЫ:

-- Индекс 1: Поиск по Email (уникальный)
CREATE UNIQUE NONCLUSTERED INDEX IX_Users_Email
ON Users(Email);

-- Индекс 2: Поиск активных пользователей
CREATE NONCLUSTERED INDEX IX_Users_Active
ON Users(IsActive)
INCLUDE (Email, FullName, Department)
WHERE IsActive = 1;

-- Индекс 3: Поиск по дате создания
CREATE NONCLUSTERED INDEX IX_Users_CreatedDate
ON Users(CreatedDate DESC);

-- Индекс 4: Поиск по отделу и статусу
CREATE NONCLUSTERED INDEX IX_Users_Department_Active
ON Users(Department, IsActive)
INCLUDE (Email, LastLoginDate);
```

### 4.3 Пример 3: Оптимизация медленного запроса

```sql
-- ИСХОДНЫЙ МЕДЛЕННЫЙ ЗАПРОС
SELECT 
    c.CustomerID,
    c.CustomerName,
    COUNT(o.OrderID) as OrderCount,
    SUM(o.Amount) as TotalAmount,
    MAX(o.OrderDate) as LastOrder
FROM Customers c
LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
WHERE c.CreatedDate >= '2024-01-01'
GROUP BY c.CustomerID, c.CustomerName;

-- Профилирование показывает:
-- Table Scan на Customers (медленно)
-- Table Scan на Orders (очень медленно)

-- РЕШЕНИЕ 1: Индексы на ключи объединения
CREATE NONCLUSTERED INDEX IX_Customers_CreatedDate
ON Customers(CreatedDate DESC)
INCLUDE (CustomerID, CustomerName);

CREATE NONCLUSTERED INDEX IX_Orders_CustomerID
ON Orders(CustomerID)
INCLUDE (OrderDate, Amount);

-- РЕШЕНИЕ 2: Если JOIN очень часто, использовать статистику
UPDATE STATISTICS Customers;
UPDATE STATISTICS Orders;

-- РЕШЕНИЕ 3: Для OLAP - использовать Columnstore
CREATE NONCLUSTERED COLUMNSTORE INDEX IXNCC_Orders
ON Orders(CustomerID, Amount, OrderDate);
```

---

## 5. Best Practices для индексов

### 5.1 Мониторинг использования индексов

```sql
-- Найти неиспользуемые индексы (занимают место впустую)
SELECT 
    OBJECT_NAME(i.object_id) as TableName,
    i.name as IndexName,
    s.user_updates,
    s.user_seeks + s.user_scans + s.user_lookups as user_reads
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s 
    ON i.object_id = s.object_id 
    AND i.index_id = s.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    AND i.index_id > 0  -- Исключить Clustered
    AND (s.user_seeks + s.user_scans + s.user_lookups = 0 
         OR s.user_seeks + s.user_scans + s.user_lookups IS NULL)
ORDER BY s.user_updates DESC;

-- Удалить неиспользуемые индексы:
-- DROP INDEX IX_UnusedIndex ON TableName;
```

### 5.2 Фрагментация индексов

```sql
-- Проверить фрагментацию
SELECT 
    OBJECT_NAME(ips.object_id) as TableName,
    i.name as IndexName,
    ips.avg_fragmentation_in_percent as Fragmentation
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id 
    AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10
    AND ips.page_count > 1000
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- Дефрагментация
-- < 10% фрагментации: REORGANIZE
ALTER INDEX IX_Orders_CustomerID ON Orders REORGANIZE;

-- > 10% фрагментации: REBUILD (полное пересоздание)
ALTER INDEX IX_Orders_CustomerID ON Orders REBUILD;
```

### 5.3 Статистика колонок

```sql
-- Индексы основаны на статистике
-- Обновить статистику перед анализом
UPDATE STATISTICS Orders;
UPDATE STATISTICS Orders WITH FULLSCAN;  -- Более точно

-- Проверить статистику
DBCC SHOW_STATISTICS (Orders, IX_Orders_CustomerID);
```

### 5.4 Правила для создания индексов

✓ **ДА:**
- Создавайте индексы на столбцы в WHERE, JOIN, ORDER BY
- Используйте Covering Index (INCLUDE) для полноты
- Регулярно мониторьте фрагментацию
- Удаляйте неиспользуемые индексы
- Тестируйте планы запросов

✗ **НЕТ:**
- Не создавайте индексы на всех столбцах подряд
- Не используйте широкие composite индексы (> 5 столбцов)
- Не игнорируйте UPDATE/DELETE производительность
- Не забывайте, что индексы занимают место и требуют обновления
- Не создавайте индексы без анализа планов запросов

---

## Ключевые выводы

1. **Clustered Index** - один на таблицу, определяет физический порядок
2. **Non-Clustered Index** - несколько на таблицу, для ускорения поиска
3. **Covering Index** - содержит все нужные данные, нет обращений к таблице
4. **Анализ планов** - обязателен для оптимизации
5. **Баланс** между производительностью чтения и записи
6. **Мониторинг** фрагментации и неиспользуемых индексов
7. **Тестирование** под реальной нагрузкой
