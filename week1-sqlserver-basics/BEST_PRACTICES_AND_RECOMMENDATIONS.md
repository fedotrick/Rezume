# SQL Server: Best Practices и Рекомендации

## 1. Рекомендации для Блокировок

### ✓ DO: Правильные практики

```sql
-- 1. Использовать правильный тип блокировки
-- Для чтения - Shared Lock (S)
SELECT * FROM Accounts WHERE AccountID = 1;

-- Для обновления - Exclusive Lock (X)
UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 1;

-- 2. Минимизировать время удержания блокировок
BEGIN TRANSACTION
    -- Быстрая операция
    UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 1;
COMMIT;  -- Отпустить блокировку сразу

-- 3. Упорядочивать доступ к ресурсам
-- Всегда обновлять AccountID 1, потом AccountID 2
UPDATE Accounts SET Balance = Balance - 100 WHERE AccountID = 1;
UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 2;
```

### ✗ DON'T: Неправильные практики

```sql
-- 1. НЕ держать блокировки в цикле
BEGIN TRANSACTION
    WHILE @i < 1000
    BEGIN
        UPDATE Accounts SET Balance = Balance + 1 WHERE AccountID = @i;
        SET @i = @i + 1;
    END
COMMIT;  -- Блокировка удерживалась на все 1000 операций!

-- 2. НЕ использовать SERIALIZABLE для всех запросов
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT * FROM Orders;  -- Очень медленно!

-- 3. НЕ игнорировать deadlock ошибки
BEGIN TRANSACTION
    UPDATE A SET X = 1;
    UPDATE B SET Y = 2;
COMMIT;  -- Если deadlock, весь код упадет!
```

---

## 2. Рекомендации для Транзакций

### ✓ DO: Правильные практики

```sql
-- 1. Использовать TRY-CATCH для обработки ошибок
BEGIN TRY
    BEGIN TRANSACTION
        -- Логика
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK;
    -- Обработать ошибку
END CATCH;

-- 2. Проверять XACT_STATE() при сложных операциях
BEGIN CATCH
    IF XACT_STATE() = -1
        ROLLBACK;
    ELSE IF XACT_STATE() = 1
        ROLLBACK;
END CATCH;

-- 3. Использовать SAVE TRANSACTION для частичного отката
BEGIN TRANSACTION
    -- Часть 1
    SAVE TRANSACTION SavePoint1;
    
    -- Часть 2
    BEGIN TRY
        -- может быть ошибка
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION SavePoint1;
    END CATCH;
COMMIT;

-- 4. Обрабатывать Deadlock с повторной попыткой
DECLARE @RetryCount INT = 0;
WHILE @RetryCount < 3
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION
            -- Логика
        COMMIT;
        SET @RetryCount = 3;  -- Выход из цикла
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 1205 AND @RetryCount < 2
        BEGIN
            ROLLBACK;
            SET @RetryCount = @RetryCount + 1;
            WAITFOR DELAY '00:00:00.100';
        END
        ELSE
            THROW;
    END CATCH;
END;
```

### ✗ DON'T: Неправильные практики

```sql
-- 1. НЕ использовать COMMIT/ROLLBACK без TRY-CATCH
BEGIN TRANSACTION
    UPDATE Accounts SET Balance = Balance - 1000000;
    -- Если ошибка, никто не откатит!
COMMIT;

-- 2. НЕ игнорировать @@TRANCOUNT
BEGIN TRANSACTION
    BEGIN TRANSACTION  -- Вложенная транзакция!
        UPDATE Accounts SET Balance = 1;
    COMMIT;  -- Только отмечает конец, не коммитит!
ROLLBACK;  -- Откатывает ВСЁ

-- 3. НЕ смешивать разные уровни изоляции
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION
    SELECT * FROM Orders;
    -- Не меняйте уровень изоляции в середине!
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
COMMIT;

-- 4. НЕ хранить данные в курсорах в транзакции
BEGIN TRANSACTION
    DECLARE cur CURSOR FOR SELECT * FROM Orders;
    OPEN cur;
    -- Транзакция открыта, блокировка удерживается
    -- Может быть медленно!
COMMIT;
```

---

## 3. Рекомендации для Индексов

### ✓ DO: Правильные практики

```sql
-- 1. Создавать индексы на столбцы в WHERE, JOIN, ORDER BY
-- WHERE
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID ON Orders(CustomerID);

-- JOIN
CREATE NONCLUSTERED INDEX IX_Details_OrderID ON OrderDetails(OrderID);

-- ORDER BY
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate ON Orders(OrderDate DESC);

-- 2. Использовать INCLUDE для покрытия запроса
CREATE NONCLUSTERED INDEX IX_Orders_Customer_Cover
ON Orders(CustomerID)
INCLUDE (OrderDate, Amount);  -- Все данные в индексе!

-- 3. Создавать Filtered Index для часто фильтруемых подмножеств
CREATE NONCLUSTERED INDEX IX_Orders_Active
ON Orders(OrderID)
WHERE Status = 'Active';

-- 4. Регулярно проверять фрагментацию
SELECT 
    OBJECT_NAME(ips.object_id) as TableName,
    i.name as IndexName,
    ips.avg_fragmentation_in_percent as Fragmentation
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id;

-- 5. Дефрагментировать при необходимости
ALTER INDEX IX_Orders_CustomerID ON Orders REBUILD;  -- > 10% фрагментации
ALTER INDEX IX_Orders_CustomerID ON Orders REORGANIZE;  -- < 10% фрагментации
```

### ✗ DON'T: Неправильные практики

```sql
-- 1. НЕ создавать индексы на всех столбцах подряд
CREATE NONCLUSTERED INDEX IX_AllColumns ON Orders(
    CustomerID, OrderDate, Amount, Status, Salesperson, Notes
);  -- Слишком широкий индекс, занимает много места!

-- 2. НЕ игнорировать UPDATE/DELETE производительность
-- Индексы ускоряют SELECT, но замедляют INSERT/UPDATE/DELETE
CREATE NONCLUSTERED INDEX IX1 ON Orders(C1);
CREATE NONCLUSTERED INDEX IX2 ON Orders(C2);
CREATE NONCLUSTERED INDEX IX3 ON Orders(C3);
-- ... 50 индексов на одну таблицу
-- UPDATE займет ОЧЕНЬ много времени!

-- 3. НЕ использовать функции в индексируемых столбцах
-- НЕПРАВИЛЬНО:
SELECT * FROM Orders WHERE YEAR(OrderDate) = 2024;
-- Индекс на OrderDate НЕ используется!

-- ПРАВИЛЬНО:
SELECT * FROM Orders WHERE OrderDate >= '2024-01-01' AND OrderDate < '2025-01-01';

-- 4. НЕ забывать ANALYZE для больших изменений данных
-- После массивного INSERT/DELETE/UPDATE
EXEC sp_updatestats;
-- Обновить статистику
```

---

## 4. Рекомендации для Уровней Изоляции

### ✓ DO: Правильные практики

```sql
-- 1. Использовать READ COMMITTED по умолчанию
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- 2. Использовать READ UNCOMMITTED для отчетов
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
BEGIN TRANSACTION
    SELECT COUNT(*) FROM Orders WHERE Status = 'Completed';
COMMIT;

-- 3. Комбинировать READ COMMITTED с UPDLOCK для критичных операций
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION
    SELECT @Balance = Balance FROM Accounts WITH (UPDLOCK) 
    WHERE AccountID = 1;
    
    IF @Balance > 1000
        UPDATE Accounts SET Balance = Balance - 1000 WHERE AccountID = 1;
COMMIT;

-- 4. Тестировать под нагрузкой для выбора оптимального уровня
-- Профилировать перед выбором REPEATABLE READ или SERIALIZABLE

-- 5. Мониторить deadlock при использовании SERIALIZABLE
DBCC TRACEON(1222, -1);  -- Включить логирование deadlock
```

### ✗ DON'T: Неправильные практики

```sql
-- 1. НЕ использовать SERIALIZABLE для всех операций
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT * FROM Orders WHERE OrderID = 1;  -- ОЧЕНЬ медленно!

-- 2. НЕ менять уровень изоляции в середине транзакции
BEGIN TRANSACTION
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    SELECT * FROM Orders;
COMMIT;

-- 3. НЕ использовать REPEATABLE READ без необходимости
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT COUNT(*) FROM Orders;  -- Нет необходимости

-- 4. НЕ игнорировать deadlock ошибки
BEGIN TRANSACTION
    -- Может быть deadlock, но мы его не обрабатываем!
    UPDATE Orders SET Status = 'Processed';
COMMIT;
```

---

## 5. Рекомендации для Производительности

### Оптимизация запросов

```sql
-- 1. Использовать INDEX HINTS для явного указания индекса
SELECT * FROM Orders WITH (INDEX(IX_Orders_CustomerID))
WHERE CustomerID = 1;

-- 2. Использовать NOLOCK для отчетов (эквивалент READ UNCOMMITTED)
SELECT * FROM Orders WITH (NOLOCK)
WHERE OrderDate >= '2024-01-01';

-- 3. Использовать READPAST для пропуска заблокированных строк
SELECT TOP 1000 * FROM Orders WITH (READPAST)
WHERE Status = 'Pending';

-- 4. Использовать выборку батчей для больших операций
DECLARE @BatchSize INT = 1000;
DECLARE @Processed INT = 0;

WHILE 1 = 1
BEGIN
    BEGIN TRANSACTION
    UPDATE TOP (@BatchSize) Orders 
    SET Status = 'Processed'
    WHERE Status = 'Pending';
    
    SET @Processed = @@ROWCOUNT;
    COMMIT;
    
    IF @Processed = 0 BREAK;
    WAITFOR DELAY '00:00:00.100';
END;

-- 5. Использовать параметризованные запросы (безопасность + производительность)
EXEC sp_executesql 
    N'SELECT * FROM Orders WHERE CustomerID = @CustID',
    N'@CustID INT',
    @CustID = 1;
```

### Мониторинг производительности

```sql
-- 1. Найти дорогие запросы
SELECT TOP 10
    qs.total_elapsed_time / 1000000 as total_elapsed_time_sec,
    qs.execution_count,
    qs.total_logical_reads,
    SUBSTRING(st.text, 1, 100) as query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_elapsed_time DESC;

-- 2. Найти неиспользуемые индексы
SELECT 
    OBJECT_NAME(i.object_id) as TableName,
    i.name as IndexName,
    s.user_updates,
    s.user_seeks + s.user_scans + s.user_lookups as user_reads
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s 
    ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE s.user_seeks + s.user_scans + s.user_lookups IS NULL
    AND i.index_id > 0;

-- 3. Найти индексы с высокой фрагментацией
SELECT 
    OBJECT_NAME(ips.object_id) as TableName,
    i.name as IndexName,
    ips.avg_fragmentation_in_percent as Fragmentation
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id
WHERE ips.avg_fragmentation_in_percent > 10
ORDER BY ips.avg_fragmentation_in_percent DESC;
```

---

## 6. Рекомендации для Design

### Архитектура данных

```sql
-- 1. Использовать Clustered Index на первичном ключе
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY CLUSTERED,  -- ✓ Хороший выбор
    CustomerID INT,
    OrderDate DATETIME
);

-- 2. Нормализовать базу данных для избежания deadlock
-- ПЛОХО: Все данные в одной таблице
CREATE TABLE MegaTable (
    ID INT,
    Field1, Field2, ..., Field1000
);

-- ХОРОШО: Разделить на отдельные таблицы
CREATE TABLE Orders (OrderID INT PRIMARY KEY, CustomerID INT);
CREATE TABLE OrderDetails (OrderID INT, ProductID INT);

-- 3. Использовать последовательный доступ к ресурсам
-- Функция для упорядочивания IDs
CREATE FUNCTION fn_OrderIDs(@ID1 INT, @ID2 INT)
RETURNS TABLE
AS RETURN
SELECT 
    CASE WHEN @ID1 < @ID2 THEN @ID1 ELSE @ID2 END as FirstID,
    CASE WHEN @ID1 < @ID2 THEN @ID2 ELSE @ID1 END as SecondID;

-- Использование:
SELECT @FirstID = FirstID, @SecondID = SecondID 
FROM fn_OrderIDs(@ID1, @ID2);

UPDATE Accounts SET Balance = Balance - 100 WHERE AccountID = @FirstID;
UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = @SecondID;
```

---

## 7. Контрольный список для Code Review

### Перед развертыванием в production

```
☐ Все запросы имеют индексы?
☐ Нет N+1 queries?
☐ TRY-CATCH для всех транзакций?
☐ Обработка deadlock?
☐ Правильный уровень изоляции?
☐ Нет SELECT *?
☐ Параметризованные запросы (не SQL injection)?
☐ Логирование ошибок?
☐ Тестирование под нагрузкой?
☐ План выполнения анализирован?
☐ Нет N-ary indеxes (> 5 столбцов)?
☐ Статистика обновлена?
☐ Fragmentation < 10%?
☐ Backup и recovery план?
☐ Мониторинг блокировок в place?
```

---

## 8. Шпаргалка по командам

```sql
-- Блокировки
SELECT * FROM sys.dm_tran_locks;
DBCC TRACEON(1222, -1);
DBCC TRACEOFF(1222, -1);

-- Транзакции
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;
COMMIT;
ROLLBACK;
SAVE TRANSACTION Savepoint1;
ROLLBACK TRANSACTION Savepoint1;

-- Индексы
CREATE NONCLUSTERED INDEX IX_Name ON Table(Columns);
ALTER INDEX IX_Name ON Table REBUILD;
ALTER INDEX IX_Name ON Table REORGANIZE;
DROP INDEX IX_Name ON Table;

-- Статистика
UPDATE STATISTICS Orders;
DBCC SHOW_STATISTICS(Orders, IX_Orders_CustomerID);

-- План выполнения
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SET STATISTICS PROFILE ON;

-- Производительность
sp_helpindex TableName;
sp_spaceused TableName;
sp_who;
sp_who2;
```

---

## Итоговые рекомендации

### Для небольших приложений (< 1 млн записей)
1. READ COMMITTED по умолчанию
2. Индексы на столбцы в WHERE, JOIN, ORDER BY
3. TRY-CATCH для ошибок
4. Профилировать перед оптимизацией

### Для средних приложений (1М - 100М записей)
1. READ UNCOMMITTED для отчетов
2. Composite индексы с INCLUDE
3. Фильтрованные индексы для подмножеств
4. Мониторинг deadlock
5. Оптимизация планов запросов

### Для больших приложений (> 100М записей)
1. Партиционирование таблиц
2. Columnstore индексы для аналитики
3. Выборка батчами (batch operations)
4. Read replicas для отчетов
5. Архивирование старых данных
6. Специалист по БД в команде

### Golden Rules

1. **Тестировать перед production**
2. **Мониторить в production**
3. **Профилировать перед оптимизацией**
4. **Измерять результаты**
5. **Документировать решения**
