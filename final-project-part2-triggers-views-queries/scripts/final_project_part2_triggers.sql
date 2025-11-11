/*
    Final Project Part 2: Portfolio Management System
    Triggers Script
    ------------------------------------------------
    This script creates three triggers for the portfolio management system:
    1. trg_Transactions_Audit - Logs all changes to the Transactions table
    2. trg_UpdatePortfolioValue_OnQuoteChange - Updates portfolio values when quote prices change
    3. trg_ValidateTransaction - Validates transaction data before insertion
*/

SET XACT_ABORT ON;
GO

/* ============================================================================
   Trigger 1: trg_Transactions_Audit
   ============================================================================
   Type: AFTER INSERT, UPDATE, DELETE on Transactions
   Purpose: Log all changes to the Transactions table into Audit_Log
   Captures: Old/new values, operation type, timestamp, user
*/

CREATE OR ALTER TRIGGER dbo.trg_Transactions_Audit
ON dbo.Transactions
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Action NVARCHAR(50);
    DECLARE @OldValue NVARCHAR(MAX);
    DECLARE @NewValue NVARCHAR(MAX);
    DECLARE @ExecutedBy NVARCHAR(128) = SYSTEM_USER;

    -- Determine the action type
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT 1 FROM deleted)
        SET @Action = 'DELETE';

    -- For UPDATE operations, log both old and new values
    IF @Action = 'UPDATE'
    BEGIN
        INSERT INTO dbo.Audit_Log (TableName, Action, OldValue, NewValue, ChangeDate, ExecutedBy)
        SELECT
            'Transactions',
            @Action,
            (SELECT * FROM deleted d FOR XML AUTO, TYPE),
            (SELECT * FROM inserted i FOR XML AUTO, TYPE),
            SYSUTCDATETIME(),
            @ExecutedBy
        FROM deleted d
        FULL OUTER JOIN inserted i ON d.TransactionID = i.TransactionID;
    END
    -- For INSERT operations, log new values
    ELSE IF @Action = 'INSERT'
    BEGIN
        INSERT INTO dbo.Audit_Log (TableName, Action, NewValue, ChangeDate, ExecutedBy)
        SELECT
            'Transactions',
            @Action,
            (SELECT * FROM inserted FOR XML AUTO, TYPE),
            SYSUTCDATETIME(),
            @ExecutedBy;
    END
    -- For DELETE operations, log old values
    ELSE IF @Action = 'DELETE'
    BEGIN
        INSERT INTO dbo.Audit_Log (TableName, Action, OldValue, ChangeDate, ExecutedBy)
        SELECT
            'Transactions',
            @Action,
            (SELECT * FROM deleted FOR XML AUTO, TYPE),
            SYSUTCDATETIME(),
            @ExecutedBy;
    END
END;
GO

PRINT 'Trigger [trg_Transactions_Audit] created successfully.';
GO

/* ============================================================================
   Trigger 2: trg_UpdatePortfolioValue_OnQuoteChange
   ============================================================================
   Type: AFTER INSERT, UPDATE on Quotes
   Purpose: Update portfolio values when security quotes change
   Optimization: Uses INSERTED table for changed quotes only
*/

CREATE OR ALTER TRIGGER dbo.trg_UpdatePortfolioValue_OnQuoteChange
ON dbo.Quotes
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Get all affected security IDs from the INSERTED table
    DECLARE @AffectedSecurities TABLE (SecurityID INT PRIMARY KEY);
    
    INSERT INTO @AffectedSecurities (SecurityID)
    SELECT DISTINCT SecurityID FROM inserted;

    -- Find all portfolios that contain affected securities
    DECLARE @AffectedPortfolios TABLE (PortfolioID INT PRIMARY KEY);
    
    INSERT INTO @AffectedPortfolios (PortfolioID)
    SELECT DISTINCT t.PortfolioID
    FROM dbo.Transactions t
    WHERE t.SecurityID IN (SELECT SecurityID FROM @AffectedSecurities)
      AND t.PortfolioID IS NOT NULL;

    -- Log this update event in Audit_Log
    INSERT INTO dbo.Audit_Log (TableName, Action, NewValue, ChangeDate, ExecutedBy)
    SELECT
        'Quotes',
        'PRICE_UPDATE',
        (SELECT COUNT(*) AS AffectedPortfolios FROM @AffectedPortfolios FOR XML AUTO, TYPE),
        SYSUTCDATETIME(),
        SYSTEM_USER;
        
    -- Note: In a production environment, you might trigger a stored procedure here
    -- to recalculate portfolio values, or set a flag to schedule updates
    -- EXEC dbo.sp_UpdatePortfolioValue @PortfolioID would be called for each affected portfolio

END;
GO

PRINT 'Trigger [trg_UpdatePortfolioValue_OnQuoteChange] created successfully.';
GO

/* ============================================================================
   Trigger 3: trg_ValidateTransaction
   ============================================================================
   Type: INSTEAD OF INSERT on Transactions
   Purpose: Validate transaction data before insertion
   Validations:
     - Portfolio exists
     - Security exists
     - Quantity > 0
     - Price > 0
     - Sufficient holdings for SELL transactions (optional)
*/

CREATE OR ALTER TRIGGER dbo.trg_ValidateTransaction
ON dbo.Transactions
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PortfolioID INT;
    DECLARE @SecurityID INT;
    DECLARE @Quantity DECIMAL(18,4);
    DECLARE @Price DECIMAL(18,4);
    DECLARE @Type NVARCHAR(4);
    DECLARE @IsValid BIT = 1;
    DECLARE @ErrorMessage NVARCHAR(MAX) = '';

    -- Get the values from inserted
    SELECT TOP 1
        @PortfolioID = PortfolioID,
        @SecurityID = SecurityID,
        @Quantity = Quantity,
        @Price = Price,
        @Type = Type
    FROM inserted;

    -- Validation 1: Portfolio exists
    IF NOT EXISTS (SELECT 1 FROM dbo.Portfolios WHERE PortfolioID = @PortfolioID)
    BEGIN
        SET @IsValid = 0;
        SET @ErrorMessage = @ErrorMessage + 'Portfolio does not exist. ';
    END

    -- Validation 2: Security exists
    IF NOT EXISTS (SELECT 1 FROM dbo.Securities WHERE SecurityID = @SecurityID)
    BEGIN
        SET @IsValid = 0;
        SET @ErrorMessage = @ErrorMessage + 'Security does not exist. ';
    END

    -- Validation 3: Quantity > 0
    IF @Quantity <= 0
    BEGIN
        SET @IsValid = 0;
        SET @ErrorMessage = @ErrorMessage + 'Quantity must be positive. ';
    END

    -- Validation 4: Price > 0
    IF @Price <= 0
    BEGIN
        SET @IsValid = 0;
        SET @ErrorMessage = @ErrorMessage + 'Price must be positive. ';
    END

    -- Validation 5: For SELL transactions, check sufficient holdings
    IF @Type = N'SELL' AND @IsValid = 1
    BEGIN
        DECLARE @AvailableQuantity DECIMAL(18,4);
        
        SELECT @AvailableQuantity = ISNULL(SUM(
            CASE 
                WHEN Type = N'BUY' THEN Quantity
                WHEN Type = N'SELL' THEN -Quantity
                ELSE 0
            END
        ), 0)
        FROM dbo.Transactions
        WHERE PortfolioID = @PortfolioID
          AND SecurityID = @SecurityID;

        IF @AvailableQuantity < @Quantity
        BEGIN
            SET @IsValid = 0;
            SET @ErrorMessage = @ErrorMessage + 'Insufficient holdings for SELL transaction. ';
        END
    END

    -- If validation passed, insert the transaction
    IF @IsValid = 1
    BEGIN
        INSERT INTO dbo.Transactions (PortfolioID, SecurityID, Quantity, Price, TransactionDate, Type, Notes)
        SELECT PortfolioID, SecurityID, Quantity, Price, TransactionDate, Type, Notes
        FROM inserted;

        -- Log successful insertion
        INSERT INTO dbo.Audit_Log (TableName, Action, NewValue, ChangeDate, ExecutedBy)
        VALUES ('Transactions', 'INSERT_VALIDATED', NULL, SYSUTCDATETIME(), SYSTEM_USER);
    END
    ELSE
    BEGIN
        -- Log validation failure
        INSERT INTO dbo.Audit_Log (TableName, Action, OldValue, ChangeDate, ExecutedBy)
        VALUES ('Transactions', 'INSERT_REJECTED', @ErrorMessage, SYSUTCDATETIME(), SYSTEM_USER);

        -- Raise an error to notify the caller
        RAISERROR (N'Transaction validation failed: %s', 16, 1, @ErrorMessage);
    END
END;
GO

PRINT 'Trigger [trg_ValidateTransaction] created successfully.';
GO

PRINT 'All triggers have been created successfully!';
GO
