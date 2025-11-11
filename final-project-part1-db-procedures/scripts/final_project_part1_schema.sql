/*
    Final Project Part 1: Portfolio Management System
    Database Schema Definition Script
    ------------------------------------------------
    This script creates the database objects required for the portfolio management
    system, including tables, keys, indexes, and constraints.
*/

SET XACT_ABORT ON;
GO

/* Drop existing tables to allow clean recreation */
IF OBJECT_ID('dbo.Transactions', 'U') IS NOT NULL
    DROP TABLE dbo.Transactions;
GO
IF OBJECT_ID('dbo.Quotes', 'U') IS NOT NULL
    DROP TABLE dbo.Quotes;
GO
IF OBJECT_ID('dbo.Operations', 'U') IS NOT NULL
    DROP TABLE dbo.Operations;
GO
IF OBJECT_ID('dbo.Audit_Log', 'U') IS NOT NULL
    DROP TABLE dbo.Audit_Log;
GO
IF OBJECT_ID('dbo.Portfolios', 'U') IS NOT NULL
    DROP TABLE dbo.Portfolios;
GO
IF OBJECT_ID('dbo.Securities', 'U') IS NOT NULL
    DROP TABLE dbo.Securities;
GO

/* Core reference tables */
CREATE TABLE dbo.Securities
(
    SecurityID      INT IDENTITY(1,1) CONSTRAINT PK_Securities PRIMARY KEY,
    Ticker          NVARCHAR(10)  NOT NULL,
    Name            NVARCHAR(150) NOT NULL,
    Type            NVARCHAR(50)  NOT NULL,
    Sector          NVARCHAR(100) NOT NULL,
    CreatedAt       DATETIME2(0)  NOT NULL CONSTRAINT DF_Securities_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_Securities_Ticker UNIQUE (Ticker),
    CONSTRAINT CK_Securities_Type CHECK (Type IN (N'Stock', N'Bond', N'ETF', N'Fund', N'Other'))
);
GO

CREATE TABLE dbo.Portfolios
(
    PortfolioID     INT IDENTITY(1,1) CONSTRAINT PK_Portfolios PRIMARY KEY,
    Name            NVARCHAR(120) NOT NULL,
    Owner           NVARCHAR(120) NOT NULL,
    CreatedDate     DATETIME2(0)  NOT NULL CONSTRAINT DF_Portfolios_CreatedDate DEFAULT (SYSUTCDATETIME()),
    Description     NVARCHAR(250) NULL,
    CONSTRAINT UQ_Portfolios_Owner_Name UNIQUE (Owner, Name)
);
GO

/* Transactional tables */
CREATE TABLE dbo.Transactions
(
    TransactionID   BIGINT IDENTITY(1,1) CONSTRAINT PK_Transactions PRIMARY KEY,
    PortfolioID     INT            NOT NULL,
    SecurityID      INT            NOT NULL,
    Quantity        DECIMAL(18,4)  NOT NULL,
    Price           DECIMAL(18,4)  NOT NULL,
    TransactionDate DATETIME2(0)   NOT NULL CONSTRAINT DF_Transactions_Date DEFAULT (SYSUTCDATETIME()),
    Type            NVARCHAR(4)    NOT NULL,
    Notes           NVARCHAR(250)  NULL,
    CONSTRAINT FK_Transactions_Portfolios FOREIGN KEY (PortfolioID) REFERENCES dbo.Portfolios (PortfolioID) ON DELETE CASCADE,
    CONSTRAINT FK_Transactions_Securities FOREIGN KEY (SecurityID) REFERENCES dbo.Securities (SecurityID),
    CONSTRAINT CK_Transactions_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_Transactions_Price CHECK (Price > 0),
    CONSTRAINT CK_Transactions_Type CHECK (Type IN (N'BUY', N'SELL'))
);
GO

CREATE TABLE dbo.Quotes
(
    QuoteID     BIGINT IDENTITY(1,1) CONSTRAINT PK_Quotes PRIMARY KEY,
    SecurityID  INT            NOT NULL,
    Price       DECIMAL(18,4)  NOT NULL,
    QuoteDate   DATETIME2(0)   NOT NULL,
    Volume      BIGINT         NOT NULL,
    Source      NVARCHAR(100)  NULL,
    CONSTRAINT FK_Quotes_Securities FOREIGN KEY (SecurityID) REFERENCES dbo.Securities (SecurityID) ON DELETE CASCADE,
    CONSTRAINT CK_Quotes_Price CHECK (Price > 0),
    CONSTRAINT CK_Quotes_Volume CHECK (Volume >= 0),
    CONSTRAINT UQ_Quotes_Security_Date UNIQUE (SecurityID, QuoteDate)
);
GO

CREATE TABLE dbo.Operations
(
    OperationID   BIGINT IDENTITY(1,1) CONSTRAINT PK_Operations PRIMARY KEY,
    PortfolioID   INT            NOT NULL,
    Description   NVARCHAR(250)  NOT NULL,
    Amount        DECIMAL(18,2)  NOT NULL,
    OperationDate DATETIME2(0)   NOT NULL CONSTRAINT DF_Operations_Date DEFAULT (SYSUTCDATETIME()),
    Category      NVARCHAR(80)   NULL,
    CONSTRAINT FK_Operations_Portfolios FOREIGN KEY (PortfolioID) REFERENCES dbo.Portfolios (PortfolioID) ON DELETE CASCADE,
    CONSTRAINT CK_Operations_Amount CHECK (Amount <> 0)
);
GO

CREATE TABLE dbo.Audit_Log
(
    LogID      BIGINT IDENTITY(1,1) CONSTRAINT PK_Audit_Log PRIMARY KEY,
    TableName  NVARCHAR(128) NOT NULL,
    Action     NVARCHAR(50)  NOT NULL,
    OldValue   NVARCHAR(MAX) NULL,
    NewValue   NVARCHAR(MAX) NULL,
    ChangeDate DATETIME2(0)  NOT NULL CONSTRAINT DF_AuditLog_ChangeDate DEFAULT (SYSUTCDATETIME()),
    ExecutedBy NVARCHAR(128) NULL,
    CONSTRAINT CK_Audit_Log_Action CHECK (LEN(Action) > 0)
);
GO

/* Supporting indexes */
CREATE NONCLUSTERED INDEX IX_Securities_Sector_Type
    ON dbo.Securities (Sector, Type);
GO

CREATE NONCLUSTERED INDEX IX_Portfolios_Owner
    ON dbo.Portfolios (Owner);
GO

CREATE NONCLUSTERED INDEX IX_Transactions_Portfolio_Date
    ON dbo.Transactions (PortfolioID, TransactionDate DESC);
GO

CREATE NONCLUSTERED INDEX IX_Transactions_Security
    ON dbo.Transactions (SecurityID, TransactionDate DESC);
GO

CREATE NONCLUSTERED INDEX IX_Quotes_Security_Date
    ON dbo.Quotes (SecurityID, QuoteDate DESC);
GO

CREATE NONCLUSTERED INDEX IX_Operations_Portfolio_Date
    ON dbo.Operations (PortfolioID, OperationDate DESC);
GO

CREATE NONCLUSTERED INDEX IX_AuditLog_TableName_Date
    ON dbo.Audit_Log (TableName, ChangeDate DESC);
GO

PRINT 'Database schema for the portfolio management system has been created successfully.';
GO
