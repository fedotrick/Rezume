# Практическая Задача 5: Уровни изоляции

## Описание задачи

Написать примеры для каждого уровня изоляции, показать разницу в поведении и дать рекомендации по использованию.

---

## Часть 1: Подготовка

```sql
USE SQLTraining;

-- Создать таблицу для демонстрации
IF OBJECT_ID('IsolationLevelDemo', 'U') IS NOT NULL
    DROP TABLE IsolationLevelDemo;

CREATE TABLE IsolationLevelDemo (
    ID INT PRIMARY KEY IDENTITY(1,1),
    DataValue NVARCHAR(100),
    Status NVARCHAR(20),
    CreatedDate DATETIME
);

-- Вставить тестовые данные
INSERT INTO IsolationLevelDemo VALUES
    ('Record 1', 'Active', GETDATE()),
    ('Record 2', 'Active', GETDATE()),
    ('Record 3', 'Inactive', GETDATE()),
    ('Record 4', 'Active', GETDATE()),
    ('Record 5', 'Active', GETDATE());

-- Проверить данные
SELECT * FROM IsolationLevelDemo;
```

---

## Часть 2: READ UNCOMMITTED (Грязное чтение)

### Демонстрация Dirty Read

**Сценарий:**
- Транзакция 1: Обновляет данные (но не коммитит)
- Транзакция 2: Читает ДО коммита Транзакции 1

**В окне 1 (Transaction 1):**
```sql
-- Транзакция 1: Начать обновление (но не коммитить)
BEGIN TRANSACTION
    UPDATE IsolationLevelDemo
    SET Status = 'Processing'
    WHERE ID = 1;
    
    PRINT 'Updated record 1 to Processing (NOT committed yet)';
    
    -- Оставить транзакцию открытой
    -- Не коммитить!
    WAITFOR DELAY '00:00:10';  -- Ждать 10 секунд
    
    -- Откатить в конце
    ROLLBACK;
    PRINT 'Rolled back the update';
```

**В окне 2 (Transaction 2) - Запустить во время ожидания в окне 1:**
```sql
-- Транзакция 2: Читать ДО коммита Транзакции 1
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN TRANSACTION
    SELECT * FROM IsolationLevelDemo WHERE ID = 1;
    -- Видит Status = 'Processing' (которое еще не закомичено!)
    
    PRINT 'Read dirty data: Status = Processing';
    
    WAITFOR DELAY '00:00:05';
    
    SELECT * FROM IsolationLevelDemo WHERE ID = 1;
    -- Теперь видит Status = 'Active' (откат произошел)
    
    PRINT 'Data changed after rollback!';
COMMIT;
```

**Результат:**
- READ UNCOMMITTED прочитал незафиксированные данные
- Это "грязное" чтение - данные потом откатились
- ✓ Производительность: Максимальная (минимум блокировок)
- ✗ Точность: Минимальная (может читать неправильные данные)

---

### Когда использовать READ UNCOMMITTED

```sql
-- Пример 1: Мониторинг производительности (приблизительные значения)
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN TRANSACTION
    -- Узнать примерное количество активных заказов
    SELECT COUNT(*) as ApproximateActiveOrders
    FROM IsolationLevelDemo
    WHERE Status = 'Active';
    -- Может быть не совсем точно, но очень быстро
COMMIT;

-- Пример 2: Отчет, не требующий абсолютной точности
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN TRANSACTION
    SELECT 
        ID,
        DataValue,
        Status,
        CreatedDate
    FROM IsolationLevelDemo
    WHERE Status = 'Active'
    ORDER BY CreatedDate DESC;
COMMIT;
```

---

## Часть 3: READ COMMITTED (Поддерживаемое чтение)

### Демонстрация Non-Repeatable Read

**Сценарий:**
- Транзакция 1: Читает значение, затем читает снова
- Транзакция 2 (одновременно): Изменяет это значение

**В окне 1 (Transaction 1):**
```sql
-- Транзакция 1: Читать два раза
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

BEGIN TRANSACTION
    -- Первое чтение
    SELECT Status FROM IsolationLevelDemo WHERE ID = 1;
    PRINT 'First read: Status = Active';
    
    WAITFOR DELAY '00:00:05';
    
    -- Второе чтение
    SELECT Status FROM IsolationLevelDemo WHERE ID = 1;
    PRINT 'Second read: Status = ??? (может измениться!)';
    
COMMIT;
```

**В окне 2 (Transaction 2) - Запустить во время ожидания:**
```sql
-- Транзакция 2: Изменить значение
BEGIN TRANSACTION
    UPDATE IsolationLevelDemo
    SET Status = 'Inactive'
    WHERE ID = 1;
    PRINT 'Updated Status to Inactive';
COMMIT;
```

**Результат:**
- Транзакция 1 видит разные значения при повторном чтении
- Это "Non-Repeatable Read" - не повторяемое чтение
- ✓ Не читает грязные данные
- ✗ Может видеть изменения других транзакций

---

### Когда использовать READ COMMITTED

```sql
-- Это уровень по умолчанию в SQL Server
-- Рекомендуется для большинства приложений

-- Пример 1: Обновление со проверкой баланса
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

BEGIN TRANSACTION
    -- Проверить текущее значение
    DECLARE @CurrentValue INT;
    SELECT @CurrentValue = COUNT(*) FROM IsolationLevelDemo WHERE Status = 'Active';
    
    -- Использовать значение
    IF @CurrentValue > 0
    BEGIN
        UPDATE IsolationLevelDemo SET Status = 'Processing' WHERE Status = 'Active';
    END
COMMIT;

-- Пример 2: Перевод денег (типичный сценарий)
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

BEGIN TRANSACTION
    -- Получить баланс
    DECLARE @Balance INT;
    SELECT @Balance = COUNT(*) FROM IsolationLevelDemo WHERE Status = 'Active';
    
    -- Проверить и обновить
    IF @Balance > 2
    BEGIN
        UPDATE IsolationLevelDemo SET Status = 'Inactive' WHERE ID = 1;
        UPDATE IsolationLevelDemo SET Status = 'Active' WHERE ID = 3;
    END
COMMIT;
```

---

## Часть 4: REPEATABLE READ

### Демонстрация Phantom Read

**Сценарий:**
- Транзакция 1: Читает набор строк, читает снова
- Транзакция 2 (одновременно): Вставляет новые строки

**В окне 1 (Transaction 1):**
```sql
-- Транзакция 1: Читать активные записи дважды
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

BEGIN TRANSACTION
    -- Первое чтение
    SELECT COUNT(*) as ActiveCount FROM IsolationLevelDemo 
    WHERE Status = 'Active';
    PRINT 'First count: 5 records';
    
    WAITFOR DELAY '00:00:05';
    
    -- Второе чтение
    SELECT COUNT(*) as ActiveCount FROM IsolationLevelDemo 
    WHERE Status = 'Active';
    PRINT 'Second count: ??? (может быть больше!)';
    
COMMIT;
```

**В окне 2 (Transaction 2) - Запустить во время ожидания:**
```sql
-- Транзакция 2: Вставить новую запись
BEGIN TRANSACTION
    INSERT INTO IsolationLevelDemo VALUES ('New Record', 'Active', GETDATE());
    PRINT 'Inserted new Active record';
COMMIT;
```

**Результат:**
- Транзакция 1 видит НОВУЮ строку, которой не было раньше
- Это "Phantom Read" - фантомное чтение
- ✓ Не видит Non-Repeatable Reads
- ✗ Может видеть новые строки

---

### Когда использовать REPEATABLE READ

```sql
-- Используется редко, для специальных случаев

-- Пример: Отчет с гарантией, что читанные строки не изменятся
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

BEGIN TRANSACTION
    -- Получить начальное состояние
    DECLARE @InitialCount INT;
    SELECT @InitialCount = COUNT(*) FROM IsolationLevelDemo 
    WHERE Status = 'Active';
    
    WAITFOR DELAY '00:00:05';
    
    -- Обработать
    -- Гарантированно, что эти 5 строк остались теми же
    -- (но могли быть добавлены новые строки)
    
    DECLARE @FinalCount INT;
    SELECT @FinalCount = COUNT(*) FROM IsolationLevelDemo 
    WHERE Status = 'Active';
    
    -- @FinalCount может быть > @InitialCount (Phantom Read)
    
COMMIT;
```

---

## Часть 5: SERIALIZABLE (Полная изоляция)

### Демонстрация отсутствия Phantom Read

**Сценарий:**
- Транзакция 1: Читает активные записи дважды
- Транзакция 2 (одновременно): ЖДЕТ, пока Транзакция 1 не завершится

**В окне 1 (Transaction 1):**
```sql
-- Транзакция 1: Полная изоляция
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

BEGIN TRANSACTION
    -- Первое чтение
    DECLARE @Count1 INT;
    SELECT @Count1 = COUNT(*) FROM IsolationLevelDemo 
    WHERE Status = 'Active';
    PRINT CONCAT('First count: ', @Count1, ' records');
    
    WAITFOR DELAY '00:00:05';
    
    -- Второе чтение
    DECLARE @Count2 INT;
    SELECT @Count2 = COUNT(*) FROM IsolationLevelDemo 
    WHERE Status = 'Active';
    PRINT CONCAT('Second count: ', @Count2, ' records');
    
    -- @Count1 == @Count2 (гарантировано!)
    
COMMIT;

PRINT 'Transaction completed';
```

**В окне 2 (Transaction 2) - Запустить и смотреть, что произойдет:**
```sql
-- Транзакция 2: Попытка вставить
BEGIN TRANSACTION
    PRINT 'Attempting to insert...';
    INSERT INTO IsolationLevelDemo VALUES ('Another Record', 'Active', GETDATE());
    PRINT 'Inserted (это займет время - будет ждать)';
COMMIT;

-- ⚠️ ВНИМАНИЕ: Эта транзакция ЖДЕТ, пока Транзакция 1 не завершится
-- Это называется "блокировкой диапазона" (Range Lock)
```

**Результат:**
- Транзакция 2 блокируется и ждет
- После COMMIT Транзакции 1, Транзакция 2 выполняется
- Гарантированно нет Phantom Reads
- ✗ Производительность: Очень низкая
- ✗ Много deadlock конфликтов

---

### Когда использовать SERIALIZABLE

```sql
-- Используется ОЧЕНЬ редко - только для критичных операций

-- Пример: Критичная финансовая операция
-- Гарантировать абсолютную консистентность
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

BEGIN TRANSACTION
    -- Проверить лимит
    DECLARE @DailyLimit DECIMAL(15,2) = 10000;
    DECLARE @TodaySpent DECIMAL(15,2);
    
    SELECT @TodaySpent = SUM(CAST(DataValue AS DECIMAL(10,2)))
    FROM IsolationLevelDemo
    WHERE Status = 'Active'
        AND CreatedDate >= CAST(GETDATE() AS DATE);
    
    IF @TodaySpent + 1000 <= @DailyLimit
    BEGIN
        -- Выполнить операцию
        -- Гарантировано, что никто не добавил между SELECT и UPDATE
        INSERT INTO IsolationLevelDemo VALUES ('Transaction', 'Active', GETDATE());
    END
COMMIT;

-- ⚠️ ВНИМАНИЕ: Эта транзакция займет ОЧЕНЬ много времени
-- Используйте только если действительно нужна абсолютная гарантия
```

---

## Часть 6: Практические примеры для каждого уровня

### Сценарий 1: Отчет по продажам

```sql
-- КАКОЙ УРОВЕНЬ ИСПОЛЬЗОВАТЬ? READ UNCOMMITTED
-- Причина: Отчет не требует абсолютной точности
-- Преимущество: Максимальная производительность

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN TRANSACTION
    SELECT 
        ID,
        DataValue,
        Status,
        COUNT(*) OVER (PARTITION BY Status) as CountByStatus
    FROM IsolationLevelDemo
    WHERE Status = 'Active';
COMMIT;

-- Может видеть:
-- - Незафиксированные обновления
-- - Новые строки, добавленные другими
-- - Но очень быстро!
```

---

### Сценарий 2: Проверка баланса и транзакция

```sql
-- КАКОЙ УРОВЕНЬ ИСПОЛЬЗОВАТЬ? READ COMMITTED
-- Причина: Хороший баланс между производительностью и безопасностью
-- Преимущество: Не читает грязные данные

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

BEGIN TRANSACTION
    -- Получить баланс
    DECLARE @CurrentBalance INT;
    SELECT @CurrentBalance = COUNT(*) FROM IsolationLevelDemo 
    WHERE Status = 'Active';
    
    -- Проверить
    IF @CurrentBalance > 0
    BEGIN
        -- Выполнить транзакцию
        UPDATE IsolationLevelDemo SET Status = 'Processing' 
        WHERE ID = 1;
    END
COMMIT;

-- Гарантии:
-- - Не видит незафиксированные данные ✓
-- - Может видеть изменения других транзакций ✓
-- - Хорошая производительность ✓
```

---

### Сценарий 3: Синхронизация данных

```sql
-- КАКОЙ УРОВЕНЬ ИСПОЛЬЗОВАТЬ? REPEATABLE READ
-- Причина: Нужно гарантировать, что читанные данные не изменятся
-- Преимущество: Защита от Non-Repeatable Reads

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

BEGIN TRANSACTION
    -- Получить текущие активные
    CREATE TABLE #ActiveRecords (ID INT);
    INSERT INTO #ActiveRecords
    SELECT ID FROM IsolationLevelDemo WHERE Status = 'Active';
    
    -- Обработать (гарантировано, что они не изменятся)
    WAITFOR DELAY '00:00:05';
    
    UPDATE IsolationLevelDemo SET Status = 'Synced'
    WHERE ID IN (SELECT ID FROM #ActiveRecords);
    
    DROP TABLE #ActiveRecords;
COMMIT;

-- Гарантии:
-- - Читанные строки не могут быть изменены другими ✓
-- - Новые строки могут быть добавлены (Phantom Reads) ✓
```

---

### Сценарий 4: Критичная финансовая операция

```sql
-- КАКОЙ УРОВЕНЬ ИСПОЛЬЗОВАТЬ? SERIALIZABLE
-- Причина: Абсолютная гарантия консистентности
-- Преимущество: Полная изоляция

SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

BEGIN TRANSACTION
    -- Критичная операция
    DECLARE @ActiveCount INT;
    SELECT @ActiveCount = COUNT(*) FROM IsolationLevelDemo 
    WHERE Status = 'Active';
    
    IF @ActiveCount > 3
    BEGIN
        UPDATE IsolationLevelDemo SET Status = 'Confirmed'
        WHERE Status = 'Active' AND ID = 1;
    END
COMMIT;

-- Гарантии:
-- - Полная изоляция от других транзакций ✓
-- - Никакие Phantom Reads не возможны ✓
-- - Очень медленная производительность ✗
-- - Высокий риск deadlock ✗
```

---

## Часть 7: Таблица сравнения

```sql
-- Создать таблицу для демонстрации

CREATE TABLE #IsolationComparison (
    IsolationLevel NVARCHAR(30),
    DirtyRead NVARCHAR(20),
    NonRepeatableRead NVARCHAR(20),
    PhantomRead NVARCHAR(20),
    Performance NVARCHAR(20),
    UseCase NVARCHAR(100)
);

INSERT INTO #IsolationComparison VALUES
('READ UNCOMMITTED', 'Possible', 'Possible', 'Possible', 'Very Fast', 'Reports, Monitoring'),
('READ COMMITTED', 'No', 'Possible', 'Possible', 'Fast', 'Most Applications'),
('REPEATABLE READ', 'No', 'No', 'Possible', 'Slow', 'Data Sync'),
('SERIALIZABLE', 'No', 'No', 'No', 'Very Slow', 'Critical Operations');

SELECT * FROM #IsolationComparison;

DROP TABLE #IsolationComparison;
```

---

## Часть 8: Рекомендации по выбору

```sql
-- Матрица принятия решений

/*
Нужна ли максимальная производительность?
├─ ДА → READ UNCOMMITTED (для отчетов, кэша)
│
└─ НЕТ → Нужна ли гарантия, что данные не изменятся?
    ├─ ДА → Критичные данные (деньги)?
    │      ├─ ДА → SERIALIZABLE (редко, используй READ COMMITTED + UPDLOCK)
    │      └─ НЕТ → REPEATABLE READ (редко)
    │
    └─ НЕТ → READ COMMITTED (рекомендуется в 99% случаев)
*/

-- ОБЩИЕ РЕКОМЕНДАЦИИ:

-- 1️⃣ Используйте READ COMMITTED в 99% случаев
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- 2️⃣ Используйте READ UNCOMMITTED для отчетов, которые могут быть приблизительными
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- 3️⃣ Используйте REPEATABLE READ редко, и только если действительно нужно
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- 4️⃣ Избегайте SERIALIZABLE - вместо этого используйте READ COMMITTED + UPDLOCK
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT * FROM IsolationLevelDemo WITH (UPDLOCK) WHERE ID = 1;

-- 5️⃣ Тестируйте под нагрузкой
-- 6️⃣ Мониторьте deadlock
-- 7️⃣ Оптимизируйте индексы
```

---

## Ключевые выводы

| Уровень | Dirty Read | Non-Repeatable | Phantom | Производ. | Рекомендация |
|---------|-----------|-----------------|---------|-----------|-------------|
| **READ UNCOMMITTED** | ✓ | ✓ | ✓ | Макс | Отчеты |
| **READ COMMITTED** | ✗ | ✓ | ✓ | Высокая | **Используйте это** |
| **REPEATABLE READ** | ✗ | ✗ | ✓ | Низкая | Редко |
| **SERIALIZABLE** | ✗ | ✗ | ✗ | Минимум | Почти никогда |

---

## Домашнее задание

1. **Создайте** окна для демонстрации каждого уровня изоляции
2. **Выполните** примеры Dirty Read, Non-Repeatable Read, Phantom Read
3. **Измерьте** производительность для каждого уровня
4. **Определите** когда использовать каждый уровень
5. **Документируйте** результаты

---

## Дополнительные команды

```sql
-- Проверить текущий уровень изоляции
SELECT 'Current Isolation Level: ' + 
    CASE @@TRANCOUNT 
        WHEN 0 THEN 'Outside transaction'
        ELSE 'In transaction'
    END;

-- Просмотреть блокировки
SELECT 
    request_session_id,
    resource_type,
    request_mode,
    request_status
FROM sys.dm_tran_locks;

-- Очистить все открытые транзакции
ROLLBACK;
```
