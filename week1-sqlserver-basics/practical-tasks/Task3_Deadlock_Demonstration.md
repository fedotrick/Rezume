# Практическая Задача 3: Демонстрация Deadlock

## Описание задачи

Создать сценарий deadlock, показать как его обнаружить и продемонстрировать способы его избежания.

---

## Часть 1: Подготовка окружения

```sql
USE SQLTraining;

-- Создать таблицы для демонстрации
IF OBJECT_ID('DeadlockDemo', 'U') IS NOT NULL
    DROP TABLE DeadlockDemo;

IF OBJECT_ID('DeadlockDemo_Order', 'U') IS NOT NULL
    DROP TABLE DeadlockDemo_Order;

-- Таблица 1: Счета
CREATE TABLE DeadlockDemo (
    AccountID INT PRIMARY KEY,
    AccountName NVARCHAR(50),
    Balance DECIMAL(10,2)
);

-- Таблица 2: Заказы
CREATE TABLE DeadlockDemo_Order (
    OrderID INT PRIMARY KEY,
    AccountID INT,
    OrderAmount DECIMAL(10,2)
);

-- Вставить данные
INSERT INTO DeadlockDemo VALUES 
    (1, 'Account A', 1000),
    (2, 'Account B', 2000);

INSERT INTO DeadlockDemo_Order VALUES
    (1, 1, 100),
    (2, 2, 200);

-- Проверить данные
SELECT * FROM DeadlockDemo;
SELECT * FROM DeadlockDemo_Order;
```

---

## Часть 2: Создание Deadlock сценария

### Сценарий 1: Классический циклический deadlock

**Описание**: 
- Транзакция 1: Обновляет Account 1, затем ждет Account 2
- Транзакция 2: Обновляет Account 2, затем ждет Account 1
- Результат: Обе транзакции ждут друг друга

**Инструкции для выполнения:**

1. **В окне 1 (Query Window 1):**
```sql
-- Транзакция 1
PRINT 'Transaction 1 starting...';

BEGIN TRANSACTION Tx1;
    PRINT 'Tx1: Updating Account 1...';
    UPDATE DeadlockDemo 
    SET Balance = Balance - 100 
    WHERE AccountID = 1;
    
    PRINT 'Tx1: Waiting 5 seconds...';
    WAITFOR DELAY '00:00:05';
    
    PRINT 'Tx1: Attempting to update Account 2...';
    UPDATE DeadlockDemo 
    SET Balance = Balance + 100 
    WHERE AccountID = 2;
    
    PRINT 'Tx1: Successfully updated Account 2';
COMMIT TRANSACTION Tx1;

PRINT 'Transaction 1 committed';
```

2. **В окне 2 (Query Window 2) - Запустить сразу после начала транзакции 1:**
```sql
-- Транзакция 2
PRINT 'Transaction 2 starting...';

BEGIN TRANSACTION Tx2;
    PRINT 'Tx2: Updating Account 2...';
    UPDATE DeadlockDemo 
    SET Balance = Balance - 200 
    WHERE AccountID = 2;
    
    PRINT 'Tx2: Waiting 5 seconds...';
    WAITFOR DELAY '00:00:05';
    
    PRINT 'Tx2: Attempting to update Account 1...';
    UPDATE DeadlockDemo 
    SET Balance = Balance + 200 
    WHERE AccountID = 1;
    
    PRINT 'Tx2: Successfully updated Account 1';
COMMIT TRANSACTION Tx2;

PRINT 'Transaction 2 committed';
```

**Результат**: 
- Одна из транзакций получит ошибку:
  ```
  Msg 1205: Transaction (Process ID XX) was deadlocked on 
  {lock | communication buffer | memory} resources with another 
  process and has been chosen as the deadlock victim.
  ```
- SQL Server автоматически выберет одну транзакцию как "жертву" deadlock
- Эта транзакция откатится (ROLLBACK)

---

## Часть 3: Обнаружение Deadlock

### Способ 1: Просмотр сообщения об ошибке

```sql
-- В окне с ошибкой deadlock вы увидите:
-- Msg 1205 - это номер ошибки deadlock
-- Process ID (PID) - какой процесс был выбран жертвой
```

### Способ 2: Включение логирования Deadlock

```sql
-- Включить trace flag для детального логирования deadlock
DBCC TRACEON (1222, -1);

PRINT 'Deadlock trace enabled';

-- В SQL Server Management Studio:
-- Management → SQL Server Logs → смотреть deadlock information
-- Или в Application Event Viewer на сервере

-- Отключить
DBCC TRACEOFF (1222, -1);
```

### Способ 3: Использование Extended Events (продвинуто)

```sql
-- Создать session для отслеживания deadlock
IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name = 'DeadlockMonitor')
    DROP EVENT SESSION DeadlockMonitor ON SERVER;

CREATE EVENT SESSION DeadlockMonitor ON SERVER
ADD EVENT sqlserver.xml_deadlock_report(
    ACTION (sqlserver.sql_text, sqlserver.tsql_stack)
)
ADD TARGET package0.event_file(
    SET filename = N'C:\DeadlockMonitor.xel'
);

-- Запустить session
ALTER EVENT SESSION DeadlockMonitor ON SERVER
STATE = START;

-- Проверить статус
SELECT * FROM sys.dm_xe_sessions WHERE name = 'DeadlockMonitor';
```

### Способ 4: Запрос активных блокировок в реальном времени

```sql
-- Просмотреть текущие блокировки
SELECT 
    dt.request_session_id,
    dt.resource_type,
    dt.request_mode,
    dt.request_status,
    es.login_name,
    es.host_name,
    t.text as SQL_Command
FROM sys.dm_tran_locks dt
INNER JOIN sys.dm_exec_sessions es 
    ON dt.request_session_id = es.session_id
CROSS APPLY sys.dm_exec_sql_text(es.most_recent_sql_handle) t
WHERE dt.request_status = 'WAIT'
    OR dt.request_status = 'GRANT'
ORDER BY dt.request_session_id;

-- Эта таблица показывает:
-- request_session_id: ID сессии
-- resource_type: что блокировано (KEY, PAGE, TABLE, etc)
-- request_mode: тип блокировки (S, X, U, etc)
-- request_status: WAIT (ожидает), GRANT (имеет)
-- SQL_Command: текущий SQL запрос
```

### Способ 5: Просмотр информации о deadlock графике

```sql
-- В SSMS после deadlock:
-- 1. Открыть SQL Server Management Studio
-- 2. Меню: Windows → Error List
-- 3. Или: Management → SQL Server Logs
-- 4. Открыть файл deadlock graph
-- 5. Просмотреть визуальное представление deadlock
```

---

## Часть 4: Способы избежать Deadlock

### Способ 1: Упорядочение доступа к ресурсам

**Проблема**: Разный порядок доступа к ресурсам в разных транзакциях

**Решение**: Всегда доступаться к ресурсам в одинаковом порядке

```sql
-- НЕПРАВИЛЬНО (может привести к deadlock)
-- Транзакция 1
BEGIN TRANSACTION
    UPDATE Account SET Balance = Balance - 100 WHERE AccountID = 1;
    UPDATE Account SET Balance = Balance + 100 WHERE AccountID = 2;
COMMIT;

-- Транзакция 2 (обратный порядок)
BEGIN TRANSACTION
    UPDATE Account SET Balance = Balance - 100 WHERE AccountID = 2;
    UPDATE Account SET Balance = Balance + 100 WHERE AccountID = 1;
COMMIT;

-- ПРАВИЛЬНО (нет deadlock)
-- Обе транзакции используют одинаковый порядок (меньший ID первым)
-- Транзакция 1
BEGIN TRANSACTION
    UPDATE Account SET Balance = Balance - 100 
    WHERE AccountID = CASE WHEN 1 < 2 THEN 1 ELSE 2 END;
    UPDATE Account SET Balance = Balance + 100 
    WHERE AccountID = CASE WHEN 1 < 2 THEN 2 ELSE 1 END;
COMMIT;

-- Транзакция 2 (тот же порядок)
BEGIN TRANSACTION
    UPDATE Account SET Balance = Balance - 100 
    WHERE AccountID = CASE WHEN 2 < 1 THEN 2 ELSE 1 END;
    UPDATE Account SET Balance = Balance + 100 
    WHERE AccountID = CASE WHEN 2 < 1 THEN 1 ELSE 2 END;
COMMIT;
```

### Способ 2: Использование UPDLOCK и READPAST

**Идея**: Контролировать тип блокировки для предотвращения конфликтов

```sql
-- Правильный способ для перевода денег
DECLARE @FromAccountID INT = 1;
DECLARE @ToAccountID INT = 2;
DECLARE @Amount DECIMAL(10,2) = 100;

BEGIN TRANSACTION
    -- Получить блокировку обновления (UPDLOCK)
    DECLARE @FromBalance DECIMAL(10,2);
    SELECT @FromBalance = Balance 
    FROM DeadlockDemo WITH (UPDLOCK)  -- Предотвращает конфликты
    WHERE AccountID = @FromAccountID;
    
    IF @FromBalance >= @Amount
    BEGIN
        UPDATE DeadlockDemo 
        SET Balance = Balance - @Amount 
        WHERE AccountID = @FromAccountID;
        
        UPDATE DeadlockDemo 
        SET Balance = Balance + @Amount 
        WHERE AccountID = @ToAccountID;
    END
COMMIT;

-- READPAST: Пропустить заблокированные строки
SELECT * FROM DeadlockDemo WITH (READPAST)
WHERE AccountID IN (1, 2);
-- Это не заблокирует запрос, даже если строки заблокированы другой транзакцией
```

### Способ 3: Использование SERIALIZABLE уровня изоляции (с осторожностью)

```sql
-- SERIALIZABLE предотвращает deadlock, но очень медленный
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

BEGIN TRANSACTION
    -- Весь диапазон данных будет заблокирован
    UPDATE DeadlockDemo 
    SET Balance = Balance - 100 
    WHERE AccountID = 1;
    
    UPDATE DeadlockDemo 
    SET Balance = Balance + 100 
    WHERE AccountID = 2;
COMMIT;

-- Вернуться к READ COMMITTED
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

### Способ 4: Минимизация времени транзакции

**Идея**: Чем меньше времени открыта транзакция, тем меньше вероятность конфликта

```sql
-- НЕПРАВИЛЬНО (длительная транзакция)
BEGIN TRANSACTION
    SELECT * FROM DeadlockDemo;
    WAITFOR DELAY '00:00:10';  -- 10 секунд!
    UPDATE DeadlockDemo SET Balance = Balance + 100 WHERE AccountID = 1;
COMMIT;

-- ПРАВИЛЬНО (короткая транзакция)
-- Подготовить данные ДО транзакции
DECLARE @Data TABLE (AccountID INT, Balance DECIMAL(10,2));
INSERT INTO @Data SELECT AccountID, Balance FROM DeadlockDemo;

-- Обработать данные
DECLARE @NewBalance DECIMAL(10,2) = (SELECT Balance FROM @Data WHERE AccountID = 1) + 100;

-- Короткая транзакция только для обновления
BEGIN TRANSACTION
    UPDATE DeadlockDemo SET Balance = @NewBalance WHERE AccountID = 1;
COMMIT;
```

### Способ 5: Обработка deadlock с повторной попыткой

```sql
-- Сценарий: Транзакция с автоматической повторной попыткой при deadlock
CREATE PROCEDURE sp_SafeTransfer
    @FromAccountID INT,
    @ToAccountID INT,
    @Amount DECIMAL(10,2)
AS
BEGIN
    DECLARE @MaxRetries INT = 3;
    DECLARE @RetryCount INT = 0;
    DECLARE @Success BIT = 0;
    
    WHILE @RetryCount < @MaxRetries AND @Success = 0
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION
                -- Всегда обновлять в порядке возрастания ID
                DECLARE @FirstID INT = CASE WHEN @FromAccountID < @ToAccountID 
                                            THEN @FromAccountID ELSE @ToAccountID END;
                DECLARE @SecondID INT = CASE WHEN @FromAccountID < @ToAccountID 
                                             THEN @ToAccountID ELSE @FromAccountID END;
                
                IF @FromAccountID = @FirstID
                BEGIN
                    -- Списать
                    UPDATE DeadlockDemo 
                    SET Balance = Balance - @Amount 
                    WHERE AccountID = @FirstID;
                    
                    -- Пополнить
                    UPDATE DeadlockDemo 
                    SET Balance = Balance + @Amount 
                    WHERE AccountID = @SecondID;
                END
                ELSE
                BEGIN
                    -- Пополнить
                    UPDATE DeadlockDemo 
                    SET Balance = Balance + @Amount 
                    WHERE AccountID = @FirstID;
                    
                    -- Списать
                    UPDATE DeadlockDemo 
                    SET Balance = Balance - @Amount 
                    WHERE AccountID = @SecondID;
                END
            COMMIT;
            
            SET @Success = 1;
            PRINT CONCAT('Transfer successful on attempt ', @RetryCount + 1);
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK;
            
            IF ERROR_NUMBER() = 1205  -- Deadlock
            BEGIN
                SET @RetryCount = @RetryCount + 1;
                
                IF @RetryCount < @MaxRetries
                BEGIN
                    PRINT CONCAT('Deadlock detected. Retry attempt ', @RetryCount);
                    WAITFOR DELAY '00:00:00.100';
                END
                ELSE
                BEGIN
                    PRINT 'Max retries exceeded after deadlock';
                    THROW;
                END
            END
            ELSE
            BEGIN
                PRINT CONCAT('Other error: ', ERROR_MESSAGE());
                THROW;
            END
        END CATCH
    END;
END;

-- Использование процедуры
EXEC sp_SafeTransfer @FromAccountID = 1, @ToAccountID = 2, @Amount = 50;
```

---

## Часть 5: Тестирование решений

### Тест 1: Сравнение вероятности deadlock

```sql
-- Создать таблицу для статистики
IF OBJECT_ID('DeadlockStats', 'U') IS NOT NULL
    DROP TABLE DeadlockStats;

CREATE TABLE DeadlockStats (
    TestID INT PRIMARY KEY IDENTITY(1,1),
    TestName NVARCHAR(100),
    TotalAttempts INT,
    DeadlockCount INT,
    SuccessRate DECIMAL(5,2)
);

-- Тест 1: Неупорядоченный доступ
DECLARE @Attempts INT = 0;
DECLARE @Deadlocks INT = 0;

WHILE @Attempts < 100
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION
            UPDATE DeadlockDemo SET Balance = Balance - 10 WHERE AccountID = 2;
            WAITFOR DELAY '00:00:00.001';
            UPDATE DeadlockDemo SET Balance = Balance + 10 WHERE AccountID = 1;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 1205
            SET @Deadlocks = @Deadlocks + 1;
        ROLLBACK;
    END CATCH
    
    SET @Attempts = @Attempts + 1;
END;

INSERT INTO DeadlockStats VALUES (
    'Unordered Access',
    @Attempts,
    @Deadlocks,
    ((100 - @Deadlocks) * 100.0 / 100)
);

-- Тест 2: Упорядоченный доступ
SET @Attempts = 0;
SET @Deadlocks = 0;

WHILE @Attempts < 100
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION
            UPDATE DeadlockDemo SET Balance = Balance - 10 WHERE AccountID = 1;
            WAITFOR DELAY '00:00:00.001';
            UPDATE DeadlockDemo SET Balance = Balance + 10 WHERE AccountID = 2;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 1205
            SET @Deadlocks = @Deadlocks + 1;
        ROLLBACK;
    END CATCH
    
    SET @Attempts = @Attempts + 1;
END;

INSERT INTO DeadlockStats VALUES (
    'Ordered Access',
    @Attempts,
    @Deadlocks,
    ((100 - @Deadlocks) * 100.0 / 100)
);

-- Просмотреть результаты
SELECT * FROM DeadlockStats;
```

---

## Ключевые выводы

### Как создать Deadlock
1. Две транзакции блокируют ресурсы в разном порядке
2. Каждая транзакция ждет ресурс, который держит другая
3. Циклическая зависимость → deadlock

### Как обнаружить Deadlock
1. **Ошибка 1205** в SQL Server
2. **Extended Events** для мониторинга
3. **dm_tran_locks** для анализа блокировок
4. **Deadlock Graph** в SSMS

### Как избежать Deadlock
1. **Упорядочить доступ** к ресурсам в одинаковом порядке
2. **Минимизировать** время удержания блокировок
3. **Использовать** UPDLOCK для контроля
4. **Обработать** deadlock с повторной попыткой
5. **Тестировать** под нагрузкой

### Best Practices
- ✓ Всегда обновлять ресурсы в одинаковом порядке
- ✓ Держать транзакции короткими
- ✓ Использовать соответствующий уровень изоляции
- ✓ Мониторить deadlock в production
- ✗ Не использовать SERIALIZABLE для всего
- ✗ Не игнорировать deadlock ошибки

---

## Домашнее задание

1. **Создайте** свой сценарий deadlock
2. **Обнаружьте** его используя различные методы
3. **Примените** каждый способ избежать deadlock
4. **Протестируйте** какой способ наиболее эффективен
5. **Документируйте** результаты
