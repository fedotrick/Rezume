# Практическая Задача 2: Работа с транзакциями

## Описание задачи

Написать код с явным управлением транзакциями, обработкой ошибок (TRY-CATCH), использованием ROLLBACK и COMMIT в различных сценариях.

---

## Часть 1: Создание тестовой таблицы

```sql
USE SQLTraining;

-- Создать таблицу Accounts для примеров банковских операций
IF OBJECT_ID('Accounts', 'U') IS NOT NULL
    DROP TABLE Accounts;

CREATE TABLE Accounts (
    AccountID INT PRIMARY KEY IDENTITY(1,1),
    AccountNumber NVARCHAR(20) UNIQUE NOT NULL,
    AccountHolder NVARCHAR(100) NOT NULL,
    Balance DECIMAL(15,2) NOT NULL,
    Currency NVARCHAR(3),
    Status NVARCHAR(20),
    CreatedDate DATETIME,
    LastModified DATETIME
);

-- Вставить тестовые данные
INSERT INTO Accounts (AccountNumber, AccountHolder, Balance, Currency, Status, CreatedDate, LastModified)
VALUES 
    ('ACC001', 'Alice Johnson', 5000.00, 'USD', 'Active', GETDATE(), GETDATE()),
    ('ACC002', 'Bob Smith', 3000.00, 'USD', 'Active', GETDATE(), GETDATE()),
    ('ACC003', 'Charlie Brown', 1000.00, 'USD', 'Inactive', GETDATE(), GETDATE()),
    ('ACC004', 'Diana Prince', 10000.00, 'USD', 'Active', GETDATE(), GETDATE());

-- Проверить данные
SELECT * FROM Accounts;
```

---

## Часть 2: Базовые транзакции

### Пример 1: Простая транзакция с COMMIT

```sql
-- Сценарий: Обновление баланса
BEGIN TRANSACTION
    UPDATE Accounts 
    SET Balance = Balance + 500,
        LastModified = GETDATE()
    WHERE AccountID = 1;
    
    PRINT 'Updated Account 1: +500';

COMMIT;

-- Проверить результат
SELECT AccountID, Balance FROM Accounts WHERE AccountID = 1;
-- Баланс увеличился на 500
```

### Пример 2: Простая транзакция с ROLLBACK

```sql
-- Сценарий: Попытка обновления, но откат
BEGIN TRANSACTION
    UPDATE Accounts 
    SET Balance = Balance - 2000,
        LastModified = GETDATE()
    WHERE AccountID = 1;
    
    PRINT 'Attempted to withdraw 2000 from Account 1';

-- Откатить транзакцию
ROLLBACK;

-- Проверить результат
SELECT AccountID, Balance FROM Accounts WHERE AccountID = 1;
-- Баланс остался без изменений
```

### Пример 3: Транзакция с условием

```sql
-- Сценарий: Перевод денег между счетами (простой вариант)
DECLARE @Amount DECIMAL(10,2) = 500;

BEGIN TRANSACTION
    -- Списать со счета 1
    UPDATE Accounts 
    SET Balance = Balance - @Amount,
        LastModified = GETDATE()
    WHERE AccountID = 1;
    
    -- Пополнить счет 2
    UPDATE Accounts 
    SET Balance = Balance + @Amount,
        LastModified = GETDATE()
    WHERE AccountID = 2;
    
    PRINT 'Transfer complete: 500 from Account 1 to Account 2';

COMMIT;

-- Проверить результаты
SELECT AccountID, Balance FROM Accounts WHERE AccountID IN (1, 2);
```

---

## Часть 3: Обработка ошибок (TRY-CATCH)

### Пример 1: Базовый TRY-CATCH

```sql
-- Сценарий: Проверка баланса и списание с обработкой ошибок
DECLARE @Amount DECIMAL(10,2) = 6000;
DECLARE @FromAccountID INT = 1;
DECLARE @ErrorCode INT = 0;

BEGIN TRY
    BEGIN TRANSACTION
        -- Получить текущий баланс
        DECLARE @CurrentBalance DECIMAL(15,2);
        SELECT @CurrentBalance = Balance 
        FROM Accounts 
        WHERE AccountID = @FromAccountID;
        
        -- Проверить достаточность средств
        IF @CurrentBalance < @Amount
        BEGIN
            THROW 51001, 'Insufficient funds', 1;
        END;
        
        -- Списать
        UPDATE Accounts 
        SET Balance = Balance - @Amount,
            LastModified = GETDATE()
        WHERE AccountID = @FromAccountID;
        
        PRINT CONCAT('Successfully withdrew ', @Amount, ' from Account ', @FromAccountID);
    COMMIT;
END TRY
BEGIN CATCH
    ROLLBACK;
    
    SET @ErrorCode = ERROR_NUMBER();
    
    PRINT 'ERROR OCCURRED:';
    PRINT CONCAT('Error Code: ', ERROR_NUMBER());
    PRINT CONCAT('Error Severity: ', ERROR_SEVERITY());
    PRINT CONCAT('Error State: ', ERROR_STATE());
    PRINT CONCAT('Error Message: ', ERROR_MESSAGE());
END CATCH;

-- Проверить результат
SELECT AccountID, Balance FROM Accounts WHERE AccountID = 1;
-- Баланс не изменился (откат произошел)
```

### Пример 2: Вложенные TRY-CATCH

```sql
-- Сценарий: Перевод денег с полной проверкой
DECLARE @FromAccountID INT = 1;
DECLARE @ToAccountID INT = 2;
DECLARE @Amount DECIMAL(10,2) = 500;

BEGIN TRY
    BEGIN TRANSACTION
        
        -- Проверка счета-отправителя
        BEGIN TRY
            DECLARE @FromBalance DECIMAL(15,2);
            SELECT @FromBalance = Balance 
            FROM Accounts 
            WHERE AccountID = @FromAccountID;
            
            IF @FromBalance IS NULL
                THROW 52001, 'Source account not found', 1;
                
            IF @FromBalance < @Amount
                THROW 52002, 'Insufficient funds in source account', 1;
        END TRY
        BEGIN CATCH
            THROW;
        END CATCH;
        
        -- Проверка счета-получателя
        BEGIN TRY
            DECLARE @ToBalance DECIMAL(15,2);
            SELECT @ToBalance = Balance 
            FROM Accounts 
            WHERE AccountID = @ToAccountID;
            
            IF @ToBalance IS NULL
                THROW 52003, 'Destination account not found', 1;
        END TRY
        BEGIN CATCH
            THROW;
        END CATCH;
        
        -- Выполнить перевод
        UPDATE Accounts 
        SET Balance = Balance - @Amount,
            LastModified = GETDATE()
        WHERE AccountID = @FromAccountID;
        
        UPDATE Accounts 
        SET Balance = Balance + @Amount,
            LastModified = GETDATE()
        WHERE AccountID = @ToAccountID;
        
        PRINT CONCAT('Successfully transferred ', @Amount, ' from Account ', 
                     @FromAccountID, ' to Account ', @ToAccountID);
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK;
    
    PRINT 'ERROR: Transfer failed';
    PRINT CONCAT('Error: ', ERROR_MESSAGE());
END CATCH;

-- Проверить результаты
SELECT AccountID, Balance FROM Accounts WHERE AccountID IN (@FromAccountID, @ToAccountID);
```

### Пример 3: THROW vs RAISERROR

```sql
-- Сценарий: Различие между THROW и RAISERROR
DECLARE @Amount DECIMAL(10,2) = -100;

BEGIN TRY
    IF @Amount <= 0
        -- THROW (рекомендуется в SQL Server 2012+)
        THROW 50001, 'Amount must be greater than zero', 1;
        
        -- RAISERROR (старый способ)
        -- RAISERROR('Amount must be greater than zero', 16, 1);
END TRY
BEGIN CATCH
    PRINT 'Caught error in CATCH block';
    PRINT ERROR_MESSAGE();
END CATCH;
```

---

## Часть 4: Сложные сценарии с управлением транзакциями

### Сценарий 1: Перевод денег между счетами (производственный код)

```sql
CREATE PROCEDURE sp_TransferFunds
    @FromAccountID INT,
    @ToAccountID INT,
    @Amount DECIMAL(10,2),
    @TransactionID INT OUTPUT,
    @Success BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartingBalance_From DECIMAL(15,2);
    DECLARE @StartingBalance_To DECIMAL(15,2);
    DECLARE @ErrorMessage NVARCHAR(MAX);
    
    SET @Success = 0;
    
    BEGIN TRY
        -- Валидация
        IF @FromAccountID = @ToAccountID
        BEGIN
            SET @ErrorMessage = 'Cannot transfer to the same account';
            THROW 51001, @ErrorMessage, 1;
        END;
        
        IF @Amount <= 0
        BEGIN
            SET @ErrorMessage = 'Amount must be positive';
            THROW 51002, @ErrorMessage, 1;
        END;
        
        BEGIN TRANSACTION TransferTx;
        
            -- Получить начальные балансы
            SELECT @StartingBalance_From = Balance 
            FROM Accounts 
            WHERE AccountID = @FromAccountID;
            
            SELECT @StartingBalance_To = Balance 
            FROM Accounts 
            WHERE AccountID = @ToAccountID;
            
            -- Проверить существование счетов
            IF @StartingBalance_From IS NULL OR @StartingBalance_To IS NULL
            BEGIN
                SET @ErrorMessage = 'One or both accounts do not exist';
                THROW 51003, @ErrorMessage, 1;
            END;
            
            -- Проверить достаточность средств
            IF @StartingBalance_From < @Amount
            BEGIN
                SET @ErrorMessage = 'Insufficient funds';
                THROW 51004, @ErrorMessage, 1;
            END;
            
            -- Выполнить перевод
            UPDATE Accounts 
            SET Balance = Balance - @Amount,
                LastModified = GETDATE()
            WHERE AccountID = @FromAccountID;
            
            UPDATE Accounts 
            SET Balance = Balance + @Amount,
                LastModified = GETDATE()
            WHERE AccountID = @ToAccountID;
            
            -- Записать в лог (если есть таблица логов)
            PRINT CONCAT('Transfer executed: ', @Amount, ' from Account ', 
                        @FromAccountID, ' to Account ', @ToAccountID);
            
            SET @Success = 1;
        
        COMMIT TRANSACTION TransferTx;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION TransferTx;
        
        SET @Success = 0;
        SET @ErrorMessage = CONCAT('Error: ', ERROR_MESSAGE());
        PRINT @ErrorMessage;
        
        -- Можно использовать RAISERROR, чтобы отправить ошибку приложению
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH;
END;

-- Использование процедуры
DECLARE @TxID INT, @IsSuccess BIT;

EXEC sp_TransferFunds 
    @FromAccountID = 1,
    @ToAccountID = 2,
    @Amount = 500,
    @TransactionID = @TxID OUTPUT,
    @Success = @IsSuccess OUTPUT;

IF @IsSuccess = 1
    PRINT 'Transfer successful'
ELSE
    PRINT 'Transfer failed';

-- Проверить результаты
SELECT AccountID, Balance FROM Accounts WHERE AccountID IN (1, 2);
```

### Сценарий 2: Батч-обновление с контролем ошибок

```sql
-- Сценарий: Одновременное увеличение баланса для всех активных счетов
DECLARE @InterestRate DECIMAL(5,4) = 0.02;
DECLARE @UpdatedCount INT = 0;
DECLARE @ErrorCount INT = 0;

BEGIN TRY
    BEGIN TRANSACTION BulkUpdateTx;
        
        UPDATE Accounts 
        SET Balance = Balance * (1 + @InterestRate),
            LastModified = GETDATE()
        WHERE Status = 'Active';
        
        SET @UpdatedCount = @@ROWCOUNT;
        
        PRINT CONCAT('Applied interest to ', @UpdatedCount, ' accounts');
    
    COMMIT TRANSACTION BulkUpdateTx;
END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION BulkUpdateTx;
    
    PRINT CONCAT('Error updating accounts: ', ERROR_MESSAGE());
END CATCH;

-- Проверить результаты
SELECT AccountID, Balance, Status FROM Accounts;
```

### Сценарий 3: Транзакция с точками сохранения (SAVE TRANSACTION)

```sql
-- Сценарий: Частичный откат (Save Points)
BEGIN TRANSACTION MainTx;

    -- Операция 1
    UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 1;
    PRINT 'Operation 1 complete';
    
    -- Сохранить точку
    SAVE TRANSACTION Savepoint1;
    PRINT 'Savepoint 1 created';
    
    -- Операция 2
    UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 2;
    PRINT 'Operation 2 complete';
    
    -- Сохранить точку
    SAVE TRANSACTION Savepoint2;
    PRINT 'Savepoint 2 created';
    
    -- Операция 3 (может быть ошибка)
    BEGIN TRY
        UPDATE Accounts SET Balance = Balance - 50000 WHERE AccountID = 3;
    END TRY
    BEGIN CATCH
        -- Откатиться только до Savepoint2
        ROLLBACK TRANSACTION Savepoint2;
        PRINT 'Rolled back to Savepoint 2';
    END CATCH;

-- Проверить состояние
-- Операции 1 и 2 выполнены
-- Операция 3 откачена
COMMIT TRANSACTION MainTx;

SELECT AccountID, Balance FROM Accounts WHERE AccountID IN (1, 2, 3);
```

---

## Часть 5: Продвинутые техники

### Техника 1: Обработка XACT_STATE()

```sql
-- Сценарий: Проверка состояния транзакции
BEGIN TRY
    BEGIN TRANSACTION;
        UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 1;
        UPDATE Accounts SET Balance = Balance - 100000 WHERE AccountID = 3;
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() = -1
    BEGIN
        -- Транзакция неработоспособна, необходимо откатить
        PRINT 'Transaction is in an uncommittable state, rolling back...';
        ROLLBACK;
    END
    ELSE IF XACT_STATE() = 1
    BEGIN
        -- Транзакция активна, можно откатить
        PRINT 'Transaction is still active, rolling back...';
        ROLLBACK;
    END
    
    PRINT ERROR_MESSAGE();
END CATCH;
```

### Техника 2: Повторная попытка при deadlock

```sql
-- Сценарий: Обработка deadlock с повторными попытками
DECLARE @MaxRetries INT = 3;
DECLARE @RetryCount INT = 0;
DECLARE @Success BIT = 0;

WHILE @RetryCount < @MaxRetries AND @Success = 0
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
            UPDATE Accounts SET Balance = Balance - 100 WHERE AccountID = 1;
            WAITFOR DELAY '00:00:00.100';  -- Имитация работы
            UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 2;
        COMMIT;
        
        SET @Success = 1;
        PRINT 'Transaction successful';
    END TRY
    BEGIN CATCH
        ROLLBACK;
        
        IF ERROR_NUMBER() = 1205  -- Deadlock victim error
        BEGIN
            SET @RetryCount = @RetryCount + 1;
            
            IF @RetryCount < @MaxRetries
            BEGIN
                PRINT CONCAT('Deadlock detected. Retry attempt ', @RetryCount, ' of ', @MaxRetries);
                WAITFOR DELAY '00:00:00.500';  -- Подождать перед повтором
            END
            ELSE
            BEGIN
                PRINT 'Max retries exceeded';
                THROW;
            END
        END
        ELSE
        BEGIN
            THROW;
        END
    END CATCH;
END;
```

### Техника 3: Асинхронное логирование ошибок

```sql
-- Создать таблицу для логирования ошибок
IF OBJECT_ID('ErrorLog', 'U') IS NOT NULL
    DROP TABLE ErrorLog;

CREATE TABLE ErrorLog (
    ErrorLogID INT PRIMARY KEY IDENTITY(1,1),
    ErrorNumber INT,
    ErrorSeverity INT,
    ErrorState INT,
    ErrorMessage NVARCHAR(MAX),
    SourceProcedure NVARCHAR(255),
    ErrorDate DATETIME,
    UserName NVARCHAR(100),
    SQLCommand NVARCHAR(MAX)
);

-- Использование
BEGIN TRY
    BEGIN TRANSACTION;
        UPDATE Accounts SET Balance = 'InvalidValue' WHERE AccountID = 1;
    COMMIT;
END TRY
BEGIN CATCH
    -- Откатить основную транзакцию
    IF @@TRANCOUNT > 0
        ROLLBACK;
    
    -- Залогировать ошибку (начать новую независимую транзакцию)
    BEGIN TRY
        BEGIN TRANSACTION;
            INSERT INTO ErrorLog (
                ErrorNumber,
                ErrorSeverity,
                ErrorState,
                ErrorMessage,
                SourceProcedure,
                ErrorDate,
                UserName,
                SQLCommand
            )
            VALUES (
                ERROR_NUMBER(),
                ERROR_SEVERITY(),
                ERROR_STATE(),
                ERROR_MESSAGE(),
                ERROR_PROCEDURE(),
                GETDATE(),
                USER_NAME(),
                NULL
            );
        COMMIT;
    END TRY
    BEGIN CATCH
        -- Игнорировать ошибки логирования
        PRINT 'Could not log error';
    END CATCH;
END CATCH;

-- Проверить логи
SELECT * FROM ErrorLog;
```

---

## Часть 6: Тестирование и проверка

```sql
-- Вывести все счета с их состоянием
SELECT 
    AccountID,
    AccountNumber,
    AccountHolder,
    Balance,
    Status,
    LastModified
FROM Accounts
ORDER BY AccountID;

-- Очистить всё и вернуться к начальному состоянию
BEGIN TRANSACTION
    DELETE FROM Accounts;
    
    INSERT INTO Accounts (AccountNumber, AccountHolder, Balance, Currency, Status, CreatedDate, LastModified)
    VALUES 
        ('ACC001', 'Alice Johnson', 5000.00, 'USD', 'Active', GETDATE(), GETDATE()),
        ('ACC002', 'Bob Smith', 3000.00, 'USD', 'Active', GETDATE(), GETDATE()),
        ('ACC003', 'Charlie Brown', 1000.00, 'USD', 'Inactive', GETDATE(), GETDATE()),
        ('ACC004', 'Diana Prince', 10000.00, 'USD', 'Active', GETDATE(), GETDATE());
COMMIT;
```

---

## Ключевые выводы

1. **BEGIN TRANSACTION** - запустить транзакцию
2. **COMMIT** - сохранить все изменения
3. **ROLLBACK** - отменить все изменения
4. **TRY-CATCH** - обработка ошибок
5. **THROW** - выбросить исключение (SQL Server 2012+)
6. **SAVE TRANSACTION** - частичный откат
7. **XACT_STATE()** - проверка состояния транзакции
8. **Обработка DEADLOCK** - повторные попытки

---

## Домашнее задание

1. Создайте процедуру для перевода денег между счетами с полной обработкой ошибок
2. Реализуйте батч-обновление с логированием прогресса
3. Напишите функцию для проверки баланса с контролем ошибок
4. Реализуйте систему логирования ошибок в отдельную таблицу
5. Протестируйте все сценарии на корректность
