-- ============================================
-- SQL Server Optimization Examples
-- Week 1: Performance Tuning
-- ============================================

USE SQLTraining;

-- ============================================
-- 1. БЛОКИРОВКИ - Примеры и оптимизация
-- ============================================

PRINT '=== LOCKS OPTIMIZATION EXAMPLES ==='
PRINT '';

-- Пример 1: Как избежать deadlock при переводе денег
GO
CREATE PROCEDURE sp_SafeMoneyTransfer
    @FromAccountID INT,
    @ToAccountID INT,
    @Amount DECIMAL(15,2)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RetryCount INT = 0;
    DECLARE @MaxRetries INT = 3;
    
    WHILE @RetryCount < @MaxRetries
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION SafeTransfer
            
                -- Упорядочить доступ (всегда меньший ID первым)
                DECLARE @FirstID INT = CASE WHEN @FromAccountID < @ToAccountID 
                                            THEN @FromAccountID ELSE @ToAccountID END;
                DECLARE @SecondID INT = CASE WHEN @FromAccountID < @ToAccountID 
                                             THEN @ToAccountID ELSE @FromAccountID END;
                
                IF @FromAccountID = @FirstID
                BEGIN
                    -- Списать
                    UPDATE Accounts 
                    SET Balance = Balance - @Amount, LastModified = GETDATE()
                    WHERE AccountID = @FirstID;
                    
                    -- Пополнить
                    UPDATE Accounts 
                    SET Balance = Balance + @Amount, LastModified = GETDATE()
                    WHERE AccountID = @SecondID;
                END
                ELSE
                BEGIN
                    -- Пополнить
                    UPDATE Accounts 
                    SET Balance = Balance + @Amount, LastModified = GETDATE()
                    WHERE AccountID = @FirstID;
                    
                    -- Списать
                    UPDATE Accounts 
                    SET Balance = Balance - @Amount, LastModified = GETDATE()
                    WHERE AccountID = @SecondID;
                END
                
                INSERT INTO TransactionLog VALUES 
                    (@FromAccountID, @ToAccountID, @Amount, GETDATE(), 'Completed', 
                     CONCAT('Transfer successful on attempt ', @RetryCount + 1));
            
            COMMIT TRANSACTION SafeTransfer;
            SET @RetryCount = @MaxRetries;  -- Выход
            
            PRINT CONCAT('SUCCESS: Transferred ', @Amount, ' from Account ', 
                        @FromAccountID, ' to Account ', @ToAccountID);
        END TRY
        BEGIN CATCH
            ROLLBACK TRANSACTION SafeTransfer;
            
            IF ERROR_NUMBER() = 1205  -- Deadlock
            BEGIN
                SET @RetryCount = @RetryCount + 1;
                
                IF @RetryCount < @MaxRetries
                BEGIN
                    PRINT CONCAT('Deadlock detected. Retry ', @RetryCount, ' of ', @MaxRetries);
                    WAITFOR DELAY '00:00:00.100';
                END
                ELSE
                BEGIN
                    PRINT 'FAILED: Max retries exceeded';
                    THROW;
                END
            END
            ELSE
            BEGIN
                PRINT CONCAT('ERROR: ', ERROR_MESSAGE());
                THROW;
            END
        END CATCH;
    END;
END;

-- Использование
EXEC sp_SafeMoneyTransfer @FromAccountID = 1, @ToAccountID = 2, @Amount = 500;
GO

-- ============================================
-- 2. ТРАНЗАКЦИИ - Примеры и оптимизация
-- ============================================

PRINT '';
PRINT '=== TRANSACTION OPTIMIZATION EXAMPLES ==='
PRINT '';

-- Пример 2: Батч-обновление для больших таблиц
GO
CREATE PROCEDURE sp_BatchUpdateStatus
    @OldStatus NVARCHAR(20),
    @NewStatus NVARCHAR(20),
    @BatchSize INT = 1000
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TotalUpdated INT = 0;
    DECLARE @BatchCount INT = 0;
    
    PRINT CONCAT('Starting batch update from ', @OldStatus, ' to ', @NewStatus);
    
    WHILE 1 = 1
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION BatchUpdate
            
                UPDATE TOP (@BatchSize) Orders
                SET Status = @NewStatus, 
                    LastModified = GETDATE()
                WHERE Status = @OldStatus;
                
                SET @BatchCount = @@ROWCOUNT;
                SET @TotalUpdated = @TotalUpdated + @BatchCount;
            
            COMMIT TRANSACTION BatchUpdate;
            
            IF @BatchCount = 0
            BEGIN
                PRINT CONCAT('Batch update completed. Total updated: ', @TotalUpdated);
                BREAK;
            END
            
            PRINT CONCAT('Batch ', @TotalUpdated / @BatchSize + 1, ': Updated ', 
                        @BatchCount, ' rows (Total: ', @TotalUpdated, ')');
            
            -- Небольшая задержка между батчами
            WAITFOR DELAY '00:00:00.500';
        END TRY
        BEGIN CATCH
            ROLLBACK TRANSACTION BatchUpdate;
            PRINT CONCAT('ERROR in batch: ', ERROR_MESSAGE());
            THROW;
        END CATCH;
    END;
END;

-- Использование
EXEC sp_BatchUpdateStatus @OldStatus = 'Pending', @NewStatus = 'Processing', @BatchSize = 100;
GO

-- Пример 3: Обработка ошибок с логированием
GO
CREATE PROCEDURE sp_OrderWithErrorLog
    @CustomerID INT,
    @ProductID INT,
    @Amount DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        BEGIN TRANSACTION OrderTx
        
            -- Проверка
            DECLARE @ProductExists INT;
            SELECT @ProductExists = COUNT(*) FROM Products WHERE ProductID = @ProductID;
            
            IF @ProductExists = 0
                THROW 51001, 'Product not found', 1;
            
            -- Вставить заказ
            INSERT INTO Orders (CustomerID, ProductID, Amount, Status)
            VALUES (@CustomerID, @ProductID, @Amount, 'Pending');
            
            PRINT CONCAT('Order created successfully. Amount: ', @Amount);
        
        COMMIT TRANSACTION OrderTx;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION OrderTx;
        
        -- Логировать ошибку
        BEGIN TRY
            INSERT INTO ErrorLog 
            (ErrorNumber, ErrorSeverity, ErrorState, ErrorMessage, ErrorDate, UserName)
            VALUES 
            (ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), 
             ERROR_MESSAGE(), GETDATE(), USER_NAME());
        END TRY
        BEGIN CATCH
            -- Игнорировать ошибки логирования
        END CATCH;
        
        PRINT CONCAT('ERROR: ', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;

-- Использование
EXEC sp_OrderWithErrorLog @CustomerID = 1, @ProductID = 1, @Amount = 100;
GO

-- ============================================
-- 3. ИНДЕКСЫ - Примеры и оптимизация
-- ============================================

PRINT '';
PRINT '=== INDEXES OPTIMIZATION EXAMPLES ==='
PRINT '';

-- Пример 4: Создание оптимальных индексов для поиска
GO
CREATE PROCEDURE sp_FindOrdersByCustomer
    @CustomerID INT,
    @FromDate DATETIME = NULL,
    @ToDate DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Если индекс IX_Orders_CustomerID существует, он будет использован
    SELECT 
        OrderID,
        CustomerID,
        OrderDate,
        Amount,
        Status
    FROM Orders
    WHERE CustomerID = @CustomerID
        AND (
            (@FromDate IS NULL OR OrderDate >= @FromDate)
            AND (@ToDate IS NULL OR OrderDate <= @ToDate)
        )
    ORDER BY OrderDate DESC;
END;

-- Использование
EXEC sp_FindOrdersByCustomer @CustomerID = 1;
EXEC sp_FindOrdersByCustomer @CustomerID = 1, @FromDate = '2024-01-01', @ToDate = '2024-12-31';
GO

-- Пример 5: Использование покрывающего индекса
GO
CREATE PROCEDURE sp_GetActiveOrdersSummary
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Этот запрос использует IX_Orders_Status (покрывающий индекс)
    SELECT 
        OrderID,
        CustomerID,
        Amount,
        Status
    FROM Orders
    WHERE Status = 'Pending';
    -- Все данные в индексе = очень быстро!
END;

-- Использование
EXEC sp_GetActiveOrdersSummary;
GO

-- ============================================
-- 4. УРОВНИ ИЗОЛЯЦИИ - Примеры
-- ============================================

PRINT '';
PRINT '=== ISOLATION LEVELS EXAMPLES ==='
PRINT '';

-- Пример 6: READ UNCOMMITTED для отчетов (быстро, не точно)
GO
CREATE PROCEDURE sp_QuickOrderCount
AS
BEGIN
    SET NOCOUNT ON;
    
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    BEGIN TRANSACTION
        SELECT 
            Status,
            COUNT(*) as OrderCount,
            SUM(Amount) as TotalAmount
        FROM Orders
        GROUP BY Status;
    COMMIT;
END;

-- Использование
EXEC sp_QuickOrderCount;
GO

-- Пример 7: READ COMMITTED для критичных операций (рекомендуется)
GO
CREATE PROCEDURE sp_ProcessOrder
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    
    BEGIN TRANSACTION
        UPDATE Orders 
        SET Status = 'Processing'
        WHERE OrderID = @OrderID;
    COMMIT;
END;

-- Использование
EXEC sp_ProcessOrder @OrderID = 1;
GO

-- ============================================
-- 5. СТАТИСТИКА И МОНИТОРИНГ
-- ============================================

PRINT '';
PRINT '=== STATISTICS AND MONITORING ==='
PRINT '';

-- Пример 8: Просмотр планов выполнения
GO
CREATE PROCEDURE sp_ShowExecutionPlan
AS
BEGIN
    SET NOCOUNT ON;
    
    SET STATISTICS IO ON;
    SET STATISTICS TIME ON;
    
    SELECT 
        o.OrderID,
        o.CustomerID,
        o.Amount,
        o.Status,
        p.ProductName,
        p.Price
    FROM Orders o
    LEFT JOIN Products p ON o.ProductID = p.ProductID
    WHERE o.Status = 'Pending'
    ORDER BY o.OrderDate DESC;
    
    SET STATISTICS IO OFF;
    SET STATISTICS TIME OFF;
END;

-- Использование
EXEC sp_ShowExecutionPlan;
GO

-- Пример 9: Информация об индексах
GO
CREATE PROCEDURE sp_IndexStatistics
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        OBJECT_NAME(i.object_id) as TableName,
        i.name as IndexName,
        ISNULL(s.user_seeks, 0) as UserSeeks,
        ISNULL(s.user_scans, 0) as UserScans,
        ISNULL(s.user_lookups, 0) as UserLookups,
        ISNULL(s.user_updates, 0) as UserUpdates
    FROM sys.indexes i
    LEFT JOIN sys.dm_db_index_usage_stats s 
        ON i.object_id = s.object_id 
        AND i.index_id = s.index_id
    WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    ORDER BY ISNULL(s.user_seeks, 0) + ISNULL(s.user_scans, 0) + ISNULL(s.user_lookups, 0) DESC;
END;

-- Использование
EXEC sp_IndexStatistics;
GO

-- Пример 10: Информация о фрагментации индексов
GO
CREATE PROCEDURE sp_IndexFragmentation
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        OBJECT_NAME(ips.object_id) as TableName,
        i.name as IndexName,
        ips.avg_fragmentation_in_percent as Fragmentation,
        ips.page_count as PageCount
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
    INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
    WHERE ips.avg_fragmentation_in_percent > 10
        AND ips.page_count > 1000
    ORDER BY ips.avg_fragmentation_in_percent DESC;
END;

-- Использование
EXEC sp_IndexFragmentation;
GO

PRINT '';
PRINT '=== All optimization examples created successfully! ==='
