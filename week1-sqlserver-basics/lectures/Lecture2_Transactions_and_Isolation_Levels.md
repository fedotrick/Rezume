# Лекция 2: Транзакции и Уровни Изоляции

## 1. ACID Принципы

ACID - это четыре ключевых свойства, которые обеспечивают надежность транзакций в базе данных:

### 1.1 Atomicity (Атомарность)

**Определение**: Транзакция либо полностью выполняется, либо полностью откатывается. Нет частичных состояний.

**Пример**:
```sql
BEGIN TRANSACTION
    INSERT INTO Accounts VALUES (4, 'New Account', 0);
    UPDATE Accounts SET Balance = Balance - 1000 WHERE AccountID = 1;
    UPDATE Accounts SET Balance = Balance + 1000 WHERE AccountID = 4;
    
    -- Если произойдет ошибка на 3-й строке,
    -- ALL три операции откатятся (ROLLBACK)
COMMIT;

-- Либо все 3 операции выполнены, либо ни одна
```

**Гарантия**:
- SQL Server автоматически откатывает транзакцию при ошибке
- Можно использовать ROLLBACK для явного отката
- TRY-CATCH блоки для контроля

### 1.2 Consistency (Консистентность)

**Определение**: База данных переходит из одного согласованного состояния в другое. Никогда не может быть в несогласованном состоянии.

**Пример**:
```sql
-- Инвариант: сумма всех балансов должна остаться неизменной
BEGIN TRANSACTION
    -- Эта сумма была = 5000
    UPDATE Accounts SET Balance = Balance - 100 WHERE AccountID = 1;
    -- Сумма теперь = 4900
    
    -- Ошибка при обновлении счета 2
    UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 2;
    
    -- Откат всей транзакции
    -- Сумма вернулась к 5000
COMMIT;
```

**Гарантия**:
- Constraints (первичные ключи, внешние ключи, CHECK)
- Triggers для сложной логики
- Бизнес-логика приложения

### 1.3 Isolation (Изоляция)

**Определение**: Одновременно выполняемые транзакции не влияют друг на друга.

**Пример**:
```sql
-- Транзакция 1
BEGIN TRANSACTION
    SELECT @Balance = Balance FROM Accounts WHERE AccountID = 1;
    -- Видит Balance = 1000

-- Одновременно
-- Транзакция 2
BEGIN TRANSACTION
    UPDATE Accounts SET Balance = 2000 WHERE AccountID = 1;
    COMMIT;

-- Транзакция 1 все еще видит Balance = 1000 (зависит от уровня изоляции)
```

**Гарантия**: Зависит от выбранного уровня изоляции (см. ниже)

### 1.4 Durability (Долговечность)

**Определение**: После COMMIT данные сохраняются постоянно, даже если произойдет сбой.

**Пример**:
```sql
BEGIN TRANSACTION
    UPDATE Accounts SET Balance = 500 WHERE AccountID = 1;
COMMIT;  -- Данные записаны в файл журнала на диск

-- Даже если сервер упадет в следующую секунду,
-- это изменение восстановится из журнала при перезагрузке
```

**Гарантия**:
- Write-Ahead Logging (WAL)
- Все изменения сначала пишутся в лог
- Затем пишутся на диск в data файлы
- SQL Server может восстановить любое состояние

---

## 2. Уровни Изоляции (Isolation Levels)

Уровень изоляции определяет, как транзакции изолированы друг от друга.

### 2.1 READ UNCOMMITTED (Грязное чтение)

**Описание**: Самый низкий уровень изоляции. Может читать незафиксированные (грязные) данные.

**Проблема: Dirty Read**
```sql
-- Транзакция 1 (в окне 1)
BEGIN TRANSACTION
UPDATE Accounts SET Balance = 50 WHERE AccountID = 1;
WAITFOR DELAY '00:00:05';
ROLLBACK;  -- Откатываем!

-- Одновременно Транзакция 2 (в окне 2)
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
BEGIN TRANSACTION
    SELECT Balance FROM Accounts WHERE AccountID = 1;
    -- Видит Balance = 50, которое еще не закоммичено!
    -- Это "грязное" чтение
COMMIT;
```

**Характеристики**:
- ✓ Самая высокая производительность
- ✓ Минимум блокировок
- ✗ Может читать некорректные данные
- ✗ Не подходит для критичных операций

**Когда использовать**:
- Аналитические отчеты, которые могут быть приблизительными
- Мониторинг производительности
- Кэширование часто меняющихся данных

```sql
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT COUNT(*) as TotalRecords FROM Orders;
SELECT AVG(Amount) as AvgOrderAmount FROM Orders;
```

### 2.2 READ COMMITTED (Поддерживаемое чтение)

**Описание**: Может читать только закоммиченные данные. **Уровень по умолчанию в SQL Server**.

**Проблема: Non-Repeatable Read**
```sql
-- Транзакция 1 (в окне 1)
BEGIN TRANSACTION
    SELECT Balance FROM Accounts WHERE AccountID = 1;
    -- Видит Balance = 1000
    
    WAITFOR DELAY '00:00:05';
    
    SELECT Balance FROM Accounts WHERE AccountID = 1;
    -- Видит Balance = 950 (изменилось другой транзакцией!)
COMMIT;

-- Одновременно Транзакция 2 (в окне 2)
BEGIN TRANSACTION
    UPDATE Accounts SET Balance = 950 WHERE AccountID = 1;
COMMIT;
```

**Характеристики**:
- ✓ Хороший баланс производительности и безопасности
- ✓ Не читает грязные данные
- ✗ Может видеть изменения (Non-Repeatable Read)
- ✗ Может видеть новые строки (Phantom Read)

**Когда использовать**:
- Большинство операций в production
- Стандартный уровень для OLTP систем
- Когда нужна хорошая производительность без граничных случаев

```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

BEGIN TRANSACTION
    SELECT @Balance = Balance FROM Accounts WHERE AccountID = 1;
    IF @Balance > @Amount
        UPDATE Accounts SET Balance = Balance - @Amount 
        WHERE AccountID = 1;
COMMIT;
```

### 2.3 REPEATABLE READ (Воспроизводимое чтение)

**Описание**: Гарантирует, что данные прочитанные в начале транзакции останутся неизменными.

**Проблема: Phantom Read**
```sql
-- Транзакция 1 (в окне 1)
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION
    SELECT COUNT(*) FROM Orders WHERE Status = 'Pending';
    -- Видит 5 заказов
    
    WAITFOR DELAY '00:00:05';
    
    SELECT COUNT(*) FROM Orders WHERE Status = 'Pending';
    -- Видит 6 заказов! (новая строка была вставлена)
COMMIT;

-- Одновременно Транзакция 2 (в окне 2)
BEGIN TRANSACTION
    INSERT INTO Orders VALUES (999, 'Pending', 100);
COMMIT;
```

**Характеристики**:
- ✓ Не видит Non-Repeatable Reads
- ✓ Хорошо для отчетов с фиксированным набором строк
- ✗ Может видеть новые строки (Phantom Read)
- ✗ Серьезно влияет на производительность

**Когда использовать**:
- Когда важна консистентность прочитанных данных
- Финансовые отчеты
- Аудит и контроль

```sql
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

BEGIN TRANSACTION
    DECLARE @Balance1 DECIMAL = (SELECT Balance FROM Accounts WHERE AccountID = 1);
    DECLARE @Balance2 DECIMAL = (SELECT Balance FROM Accounts WHERE AccountID = 2);
    
    WAITFOR DELAY '00:00:05';
    
    -- Эти значения остаются теми же
    DECLARE @Balance1_Check DECIMAL = (SELECT Balance FROM Accounts WHERE AccountID = 1);
    DECLARE @Balance2_Check DECIMAL = (SELECT Balance FROM Accounts WHERE AccountID = 2);
    
    -- @Balance1_Check == @Balance1
    -- @Balance2_Check == @Balance2 (Гарантировано)
COMMIT;
```

### 2.4 SERIALIZABLE (Полная изоляция)

**Описание**: Самый высокий уровень изоляции. Транзакции выполняются так, как если бы они были последовательными.

**Без Phantom Read**:
```sql
-- Транзакция 1 (в окне 1)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION
    SELECT COUNT(*) FROM Orders WHERE Status = 'Pending';
    -- Видит 5 заказов
    
    WAITFOR DELAY '00:00:05';
    
    SELECT COUNT(*) FROM Orders WHERE Status = 'Pending';
    -- Видит 5 заказов (гарантировано!)
COMMIT;

-- Одновременно Транзакция 2 (в окне 2)
BEGIN TRANSACTION
    INSERT INTO Orders VALUES (999, 'Pending', 100);
    -- ЖДЕТ, пока транзакция 1 не завершится!
    -- Так как SERIALIZABLE заблокирует весь диапазон строк
COMMIT;
```

**Характеристики**:
- ✓ Полная изоляция, гарантированная консистентность
- ✗ Очень низкая производительность
- ✗ Много конфликтов и блокировок
- ✗ Высокий риск deadlock

**Когда использовать**:
- Критичные финансовые операции
- Рарно - в большинстве случаев это излишне

```sql
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

BEGIN TRANSACTION
    DECLARE @Count INT = (SELECT COUNT(*) FROM Accounts WHERE Status = 'Active');
    
    IF @Count < 100
        INSERT INTO Accounts VALUES (...);
    
    -- Гарантируется, что никто не вставит строку между SELECT и INSERT
COMMIT;
```

---

## 3. Матрица проблем изоляции

| Уровень | Dirty Read | Non-Repeatable | Phantom | Производ. | Блокировки |
|---------|-----------|-----------------|---------|-----------|-----------|
| **READ UNCOMMITTED** | ✓ | ✓ | ✓ | Максимум | Минимум |
| **READ COMMITTED** | ✗ | ✓ | ✓ | Высокая | Средние |
| **REPEATABLE READ** | ✗ | ✗ | ✓ | Низкая | Высокие |
| **SERIALIZABLE** | ✗ | ✗ | ✗ | Минимум | Максимум |

---

## 4. Примеры для каждого уровня

### 4.1 Сценарий: Перевод денег

```sql
-- Уровень READ COMMITTED (рекомендуется)
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

BEGIN TRANSACTION
    -- Получить баланс с блокировкой обновления
    SELECT @FromBalance = Balance 
    FROM Accounts WITH (UPDLOCK)
    WHERE AccountID = @FromAccount;
    
    IF @FromBalance < @Amount
    BEGIN
        ROLLBACK;
        RETURN -1;  -- Недостаточно средств
    END;
    
    -- Списать со счета
    UPDATE Accounts 
    SET Balance = Balance - @Amount,
        LastModified = GETDATE()
    WHERE AccountID = @FromAccount;
    
    -- Пополнить счет
    UPDATE Accounts 
    SET Balance = Balance + @Amount,
        LastModified = GETDATE()
    WHERE AccountID = @ToAccount;
    
    INSERT INTO TransactionLog VALUES (@FromAccount, @ToAccount, @Amount, GETDATE());
    
COMMIT;
RETURN 0;  -- Успешно
```

### 4.2 Сценарий: Отчет с суммами

```sql
-- Уровень READ UNCOMMITTED (для отчетов)
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN TRANSACTION
    SELECT 
        AccountID,
        Balance,
        LastModified
    FROM Accounts
    WHERE Status = 'Active'
    ORDER BY Balance DESC;
COMMIT;
-- Может видеть незафиксированные изменения, но это ОК для отчета
```

### 4.3 Сценарий: Бронирование места в самолете

```sql
-- Уровень SERIALIZABLE (критично)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

BEGIN TRANSACTION
    DECLARE @AvailableSeats INT = (
        SELECT COUNT(*) FROM Seats 
        WHERE FlightID = @FlightID AND Status = 'Available'
    );
    
    IF @AvailableSeats >= @RequestedSeats
    BEGIN
        UPDATE TOP (@RequestedSeats) Seats
        SET Status = 'Reserved', CustomerID = @CustomerID
        WHERE FlightID = @FlightID AND Status = 'Available';
        
        INSERT INTO Reservations VALUES (@CustomerID, @FlightID, GETDATE());
    END;
COMMIT;
```

---

## 5. Выбор правильного уровня изоляции

### 5.1 Матрица принятия решений

```
Нужна ли максимальная производительность?
├─ ДА → Много чтений, мало записей?
│       ├─ ДА → READ UNCOMMITTED
│       └─ НЕТ → READ COMMITTED (по умолчанию)
└─ НЕТ → Нужна ли гарантированная консистентность?
         ├─ ДА → Критичные данные (деньги)?
         │       ├─ ДА → SERIALIZABLE (с осторожностью)
         │       └─ НЕТ → REPEATABLE READ
         └─ НЕТ → READ COMMITTED
```

### 5.2 Рекомендации по отраслям

**Финансовые системы**:
- Основные операции: READ COMMITTED с UPDLOCK
- Отчеты: READ UNCOMMITTED
- Критичные проверки: SERIALIZABLE (редко)

**E-commerce**:
- Просмотр товаров: READ UNCOMMITTED
- Заказы: READ COMMITTED
- Инвентаризация: REPEATABLE READ

**OLAP / Data Warehouse**:
- Все операции: READ UNCOMMITTED
- Максимальная производительность важнее малых неточностей

---

## 6. Оптимизация с уровнями изоляции

### 6.1 Комбинирование уровней

```sql
-- Основная транзакция на READ COMMITTED
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

BEGIN TRANSACTION
    -- Критичная часть - нужна синхронизация
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    
    DECLARE @IsSufficientFunds BIT = CASE 
        WHEN (SELECT Balance FROM Accounts WHERE AccountID = @AccountID) >= @Amount
        THEN 1 ELSE 0 
    END;
    
    -- Вернуться к READ COMMITTED для остального
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    
    IF @IsSufficientFunds = 1
        UPDATE Accounts SET Balance = Balance - @Amount 
        WHERE AccountID = @AccountID;
COMMIT;
```

### 6.2 Использование WITH (NOLOCK)

```sql
-- Прямое переопределение блокировки
SELECT * FROM Orders WITH (NOLOCK)
WHERE OrderID = 1;
-- Эквивалентно READ UNCOMMITTED для этого запроса

-- Используется для отчетов, которые не нуждаются в точных данных
-- Максимальная производительность
```

### 6.3 Использование WITH (UPDLOCK, READCOMMITTED)

```sql
-- Явно указать тип блокировки
SELECT @Balance = Balance 
FROM Accounts WITH (UPDLOCK, READCOMMITTED)
WHERE AccountID = @AccountID;
-- Update Lock предотвращает конфликты при обновлении
```

---

## Ключевые выводы

1. **ACID принципы** - фундамент надежности БД
2. **Уровни изоляции** определяют компромисс между производительностью и безопасностью
3. **READ COMMITTED** - лучший выбор в большинстве случаев
4. **READ UNCOMMITTED** для отчетов и кэшей
5. **SERIALIZABLE** редко используется из-за производительности
6. **Комбинирование** разных уровней в одной транзакции возможно
7. **Мониторинг** блокировок критичен при выборе уровня
