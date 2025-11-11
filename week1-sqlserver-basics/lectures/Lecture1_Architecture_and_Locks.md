# Лекция 1: Архитектура SQL Server и Блокировки

## 1. Основные компоненты SQL Server

### 1.1 Уровни хранения данных
SQL Server использует иерархическую структуру для организации данных:

```
Database (БД)
├── Files (файлы данных и журнала)
├── Filegroups (группы файлов)
└── Pages (8KB страницы памяти)
    ├── Data Pages (страницы данных)
    ├── Index Pages (страницы индексов)
    ├── LOB Pages (Large Object Pages)
    └── Row Offset Array
```

### 1.2 Основные компоненты
- **Query Parser**: Проверяет синтаксис SQL запросов
- **Query Optimizer**: Выбирает оптимальный план выполнения
- **Query Executor**: Выполняет запрос
- **Storage Engine**: Управляет данными на диске
- **Buffer Manager**: Кэширует страницы в памяти
- **Lock Manager**: Управляет блокировками
- **Transaction Manager**: Управляет транзакциями

### 1.3 Архитектура памяти
```
SQL Server Memory
├── Buffer Pool (99% памяти)
│   ├── Data Pages Cache
│   └── Index Pages Cache
└── Other Caches
    ├── Plan Cache
    ├── Log Cache
    └── Procedure Cache
```

## 2. Понимание блокировок (Locks)

### 2.1 Типы блокировок в SQL Server

#### Shared Lock (S-lock) - Общая блокировка
- Используется при **чтении** данных
- Несколько процессов могут одновременно держать Shared Lock на одном ресурсе
- Несовместима с Exclusive Lock
- **Действие**: Позволяет читать, запрещает изменять

```sql
SELECT * FROM Orders WHERE OrderID = 1;
-- Держит Shared Lock на строке/странице
```

#### Exclusive Lock (X-lock) - Исключительная блокировка
- Используется при **изменении** данных (UPDATE, DELETE, INSERT)
- Только один процесс может держать Exclusive Lock
- Несовместима с любыми другими блокировками
- **Действие**: Запрещает читать и изменять другим процессам

```sql
UPDATE Orders SET Status = 'Shipped' WHERE OrderID = 1;
-- Держит Exclusive Lock до конца транзакции
```

#### Intent Lock (I-lock) - Блокировка намерения
- Используется для иерархического управления блокировками
- Типы: Intent Shared (IS), Intent Exclusive (IX), Shared with Intent Exclusive (SIX)
- **Цель**: Предотвращает эскалацию блокировок на более высоких уровнях

```sql
-- IS Lock на таблице, S Lock на строке
SELECT * FROM Orders WHERE OrderID = 1;
```

#### Update Lock (U-lock) - Блокировка обновления
- Первый этап UPDATE операции
- Позволяет читать, но запрещает другим обновлять
- Предотвращает deadlocks при UPDATE

```sql
UPDATE Orders SET Status = 'Processing'
WHERE OrderID = (SELECT TOP 1 OrderID FROM Orders 
                 WHERE Status = 'Pending');
```

### 2.2 Уровни блокировки

SQL Server может применять блокировки на разных уровнях:

| Уровень | Описание | Производительность | Параллелизм |
|---------|---------|-------------------|------------|
| **RID** | Row ID (физическая позиция) | Низкая | Высокий |
| **KEY** | Ключ индекса | Средняя | Средний |
| **PAGE** | Страница (8KB) | Средняя | Средний |
| **EXTENT** | Экстент (8 страниц) | Высокая | Низкий |
| **TABLE** | Целая таблица | Очень высокая | Очень низкий |
| **DATABASE** | Целая БД | Критическая | Минимальный |

### 2.3 Матрица совместимости блокировок

```
         S  X  U  IS IX SIX
    S   ✓  ✗  ✗  ✓  ✗  ✗
    X   ✗  ✗  ✗  ✗  ✗  ✗
    U   ✗  ✗  ✗  ✓  ✗  ✗
    IS  ✓  ✗  ✓  ✓  ✓  ✓
    IX  ✗  ✗  ✗  ✓  ✓  ✗
    SIX ✗  ✗  ✗  ✓  ✗  ✗
```

## 3. Эскалация блокировок

### 3.1 Что такое эскалация?

Эскалация блокировок - это автоматический процесс, при котором SQL Server заменяет множество мелких блокировок (RID/KEY/PAGE) на более крупные (TABLE).

### 3.2 Когда происходит эскалация?

```
Количество блокировок на таблице превышает пороги:
- 5,000 блокировок по умолчанию
- Зависит от памяти, выделенной SQL Server
- Эскалация PAGE -> TABLE
- Эскалация KEY -> TABLE (при наличии индекса)
```

### 3.3 Пример эскалации

```sql
-- Этот запрос может вызвать эскалацию:
BEGIN TRANSACTION
UPDATE Products 
SET Price = Price * 1.1 
WHERE Category = 'Electronics';

-- SQL Server начнет с KEY блокировок
-- Если их будет > 5000, произойдет эскалация на TABLE
-- Другие транзакции будут заблокированы
COMMIT;
```

### 3.4 Отключение эскалации

```sql
-- Отключить эскалацию для таблицы
ALTER TABLE Products
SET (LOCK_ESCALATION = DISABLE);

-- Разрешить эскалацию на AUTO (по умолчанию)
ALTER TABLE Products
SET (LOCK_ESCALATION = AUTO);

-- Эскалация только на TABLE (рекомендуется для большинства таблиц)
ALTER TABLE Products
SET (LOCK_ESCALATION = TABLE);
```

## 4. Deadlock (Взаимная блокировка)

### 4.1 Что такое Deadlock?

Deadlock возникает, когда две или более транзакции ждут друг друга, создавая циклическую зависимость.

### 4.2 Классический пример Deadlock

```
Транзакция 1:                 Транзакция 2:
1. Lock Table A               1. Lock Table B
2. Wait for Table B    <----  2. Wait for Table A
   (заблокирована)               (заблокирована)
                       
         DEADLOCK!
```

### 4.3 Реальный пример на SQL

**Сценарий**: Перевод денег между счетами в банке

```sql
-- Транзакция 1 (в одном окне)
BEGIN TRANSACTION
UPDATE Accounts SET Balance = Balance - 100 WHERE AccountID = 1;
WAITFOR DELAY '00:00:03';  -- Имитация задержки
UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 2;
COMMIT;

-- Транзакция 2 (в другом окне) - запустить одновременно
BEGIN TRANSACTION
UPDATE Accounts SET Balance = Balance - 100 WHERE AccountID = 2;
WAITFOR DELAY '00:00:03';  -- Имитация задержки
UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 1;
COMMIT;
```

### 4.4 Признаки Deadlock

```
Сообщение об ошибке:
"Msg 1205: Transaction (Process ID XX) was deadlocked 
on {lock | communication buffer | memory} resources with 
another process and has been chosen as the deadlock victim."
```

## 5. Реальные примеры блокировок в банковских системах

### 5.1 Сценарий: Транзит денег

```sql
-- Безопасный перевод между счетами (правильный порядок)
BEGIN TRANSACTION
    -- Всегда захватывать ресурсы в одинаковом порядке!
    UPDATE Accounts SET Balance = Balance - @Amount 
    WHERE AccountID = @FromAccount;
    
    IF @@ERROR <> 0 ROLLBACK;
    
    UPDATE Accounts SET Balance = Balance + @Amount 
    WHERE AccountID = @ToAccount;
    
    IF @@ERROR <> 0 ROLLBACK;
    ELSE COMMIT;
END;
```

### 5.2 Сценарий: Контроль лимитов

```sql
-- Проверка лимита и обновление (уязвимо для race condition)
BEGIN TRANSACTION
    SELECT @CurrentSpending = CurrentSpending 
    FROM CustomerLimits 
    WHERE CustomerID = @CustID;
    
    IF @CurrentSpending + @TransactionAmount > @DailyLimit
        ROLLBACK;
    ELSE
    BEGIN
        UPDATE CustomerLimits 
        SET CurrentSpending = CurrentSpending + @TransactionAmount
        WHERE CustomerID = @CustID;
        COMMIT;
    END;
END;
```

### 5.3 Сценарий: Проверка баланса и списание

```sql
-- Правильная реализация с использованием UPDLOCK
BEGIN TRANSACTION
    SELECT @Balance = Balance 
    FROM Accounts WITH (UPDLOCK)  -- Предотвращает другие блокировки
    WHERE AccountID = @AccountID;
    
    IF @Balance < @Amount
    BEGIN
        ROLLBACK;
        RETURN -1;  -- Недостаточно средств
    END;
    
    UPDATE Accounts 
    SET Balance = Balance - @Amount 
    WHERE AccountID = @AccountID;
    
    COMMIT;
    RETURN 0;  -- Успешно
END;
```

## 6. Как избежать Deadlock

### 6.1 Основные правила

1. **Упорядочение ресурсов**: Всегда захватывайте ресурсы в одинаковом порядке
   ```sql
   -- ✓ ПРАВИЛЬНО: всегда AccountID 1 перед AccountID 2
   UPDATE Accounts SET Balance = Balance - @Amount 
   WHERE AccountID = CASE WHEN @From < @To THEN @From ELSE @To END;
   ```

2. **Минимизация времени удержания блокировок**
   ```sql
   -- ✗ НЕПРАВИЛЬНО: длительная блокировка
   BEGIN TRANSACTION
   SELECT * FROM Orders;  -- 10,000 строк
   WAITFOR DELAY '00:00:05';
   UPDATE Orders SET Status = 'Processed';
   COMMIT;
   
   -- ✓ ПРАВИЛЬНО: быстрая операция
   BEGIN TRANSACTION
   UPDATE Orders SET Status = 'Processed' 
   WHERE OrderID = @OrderID;
   COMMIT;
   ```

3. **Уменьшение размера транзакций**
   ```sql
   -- ✗ НЕПРАВИЛЬНО: большая транзакция
   BEGIN TRANSACTION
   UPDATE Products SET Price = Price * 1.1;
   COMMIT;
   
   -- ✓ ПРАВИЛЬНО: батч-обновление
   DECLARE @BatchSize INT = 1000;
   DECLARE @ProcessedCount INT = 0;
   
   WHILE 1 = 1
   BEGIN
       BEGIN TRANSACTION
       UPDATE TOP (@BatchSize) Products 
       SET Price = Price * 1.1 
       WHERE Updated = 0;
       COMMIT;
       
       SET @ProcessedCount = @@ROWCOUNT;
       IF @ProcessedCount = 0 BREAK;
   END;
   ```

4. **Использование правильного уровня изоляции**
   ```sql
   SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
   BEGIN TRANSACTION
   SELECT * FROM Orders WHERE OrderID = 1;
   COMMIT;
   ```

5. **Обработка Deadlock с повторной попыткой**
   ```sql
   DECLARE @RetryCount INT = 0;
   DECLARE @MaxRetries INT = 3;
   
   WHILE @RetryCount < @MaxRetries
   BEGIN
       BEGIN TRY
           BEGIN TRANSACTION
           UPDATE Accounts SET Balance = Balance - @Amount 
           WHERE AccountID = @FromAccount;
           UPDATE Accounts SET Balance = Balance + @Amount 
           WHERE AccountID = @ToAccount;
           COMMIT;
           BREAK;  -- Успешно
       END TRY
       BEGIN CATCH
           IF ERROR_NUMBER() = 1205  -- Deadlock
           BEGIN
               ROLLBACK;
               SET @RetryCount = @RetryCount + 1;
               IF @RetryCount < @MaxRetries
                   WAITFOR DELAY '00:00:00.100';  -- Подождать немного
               ELSE
                   THROW;
           END
           ELSE
               THROW;
       END CATCH
   END;
   ```

### 6.2 Инструменты для обнаружения проблем

```sql
-- Просмотр текущих блокировок
SELECT 
    dt.resource_type,
    dt.request_mode,
    es.session_id,
    es.login_name,
    es.host_name,
    t.text
FROM sys.dm_tran_locks dt
INNER JOIN sys.dm_exec_sessions es ON dt.request_session_id = es.session_id
CROSS APPLY sys.dm_exec_sql_text(es.most_recent_sql_handle) t
WHERE dt.request_status = 'WAIT';

-- Просмотр информации о Deadlock
-- SQL Server создает файл deadlock graph в SQL Server Management Studio
```

## Ключевые выводы

1. **Блокировки необходимы** для целостности данных
2. **Выбор правильного типа блокировки** влияет на производительность
3. **Эскалация блокировок** может снизить производительность
4. **Deadlock можно предотвратить** правильным проектированием
5. **Тестирование под нагрузкой** важно для обнаружения проблем
6. **Мониторинг блокировок** критичен в production

---

**Рекомендуемые параметры SQL Server для оптимизации блокировок:**

```sql
-- Увеличить тайм-аут блокировки (по умолчанию -1 = бесконечно)
EXEC sp_configure 'blocked process threshold', 30;  -- 30 сек
RECONFIGURE;

-- Включить отслеживание deadlock
DBCC TRACEON (1222, -1);  -- Trace flag для детального логирования deadlock
```
