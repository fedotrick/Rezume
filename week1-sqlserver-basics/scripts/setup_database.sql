-- ============================================
-- SQL Server Training Database Setup
-- Week 1: Basics and Transactions
-- ============================================

-- 1. Создать базу данных
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SQLTraining')
BEGIN
    CREATE DATABASE SQLTraining;
    PRINT 'Database SQLTraining created successfully';
END
ELSE
BEGIN
    PRINT 'Database SQLTraining already exists';
END

-- 2. Использовать базу данных
USE SQLTraining;

-- 3. Удалить старые таблицы (если существуют)
IF OBJECT_ID('ErrorLog', 'U') IS NOT NULL DROP TABLE ErrorLog;
IF OBJECT_ID('TransactionLog', 'U') IS NOT NULL DROP TABLE TransactionLog;
IF OBJECT_ID('Accounts', 'U') IS NOT NULL DROP TABLE Accounts;
IF OBJECT_ID('Orders', 'U') IS NOT NULL DROP TABLE Orders;
IF OBJECT_ID('Products', 'U') IS NOT NULL DROP TABLE Products;

-- 4. Создать таблицу Accounts
CREATE TABLE Accounts (
    AccountID INT PRIMARY KEY IDENTITY(1,1),
    AccountNumber NVARCHAR(20) UNIQUE NOT NULL,
    AccountHolder NVARCHAR(100) NOT NULL,
    Balance DECIMAL(15,2) NOT NULL,
    Currency NVARCHAR(3) DEFAULT 'USD',
    Status NVARCHAR(20) DEFAULT 'Active',
    CreatedDate DATETIME DEFAULT GETDATE(),
    LastModified DATETIME DEFAULT GETDATE()
);

-- 5. Создать таблицу Orders
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT NOT NULL,
    OrderDate DATETIME DEFAULT GETDATE(),
    Amount DECIMAL(10,2) NOT NULL,
    Status NVARCHAR(20) DEFAULT 'Pending',
    ProductID INT,
    ShippingAddress NVARCHAR(255),
    Notes NVARCHAR(MAX)
);

-- 6. Создать таблицу Products
CREATE TABLE Products (
    ProductID INT PRIMARY KEY IDENTITY(1,1),
    ProductName NVARCHAR(100) NOT NULL,
    Category NVARCHAR(50),
    Price DECIMAL(10,2),
    Stock INT,
    CreatedDate DATETIME DEFAULT GETDATE()
);

-- 7. Создать таблицу ErrorLog
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

-- 8. Создать таблицу TransactionLog
CREATE TABLE TransactionLog (
    TransactionID INT PRIMARY KEY IDENTITY(1,1),
    FromAccountID INT,
    ToAccountID INT,
    Amount DECIMAL(15,2),
    TransactionDate DATETIME DEFAULT GETDATE(),
    Status NVARCHAR(20),
    Notes NVARCHAR(MAX)
);

-- 9. Вставить тестовые данные в Accounts
INSERT INTO Accounts (AccountNumber, AccountHolder, Balance, Currency, Status)
VALUES 
    ('ACC001', 'Alice Johnson', 5000.00, 'USD', 'Active'),
    ('ACC002', 'Bob Smith', 3000.00, 'USD', 'Active'),
    ('ACC003', 'Charlie Brown', 1000.00, 'USD', 'Inactive'),
    ('ACC004', 'Diana Prince', 10000.00, 'USD', 'Active'),
    ('ACC005', 'Edward Norton', 2500.00, 'USD', 'Active');

-- 10. Вставить тестовые данные в Products
INSERT INTO Products (ProductName, Category, Price, Stock)
VALUES 
    ('Laptop', 'Electronics', 1000.00, 50),
    ('Mouse', 'Accessories', 25.00, 200),
    ('Keyboard', 'Accessories', 75.00, 150),
    ('Monitor', 'Electronics', 300.00, 30),
    ('Desk', 'Furniture', 200.00, 20);

-- 11. Вставить начальные данные в Orders
INSERT INTO Orders (CustomerID, OrderDate, Amount, Status, ProductID)
VALUES 
    (1, GETDATE(), 100.00, 'Pending', 1),
    (2, GETDATE(), 50.00, 'Completed', 2),
    (3, GETDATE(), 75.00, 'Shipped', 3),
    (4, GETDATE(), 300.00, 'Processing', 4);

-- 12. Создать индексы для Orders
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID 
ON Orders(CustomerID);

CREATE NONCLUSTERED INDEX IX_Orders_OrderDate 
ON Orders(OrderDate DESC)
INCLUDE (CustomerID, Amount);

CREATE NONCLUSTERED INDEX IX_Orders_Status 
ON Orders(Status)
WHERE Status IN ('Pending', 'Processing');

-- 13. Создать индексы для Products
CREATE NONCLUSTERED INDEX IX_Products_Category 
ON Products(Category);

-- 14. Вывести статистику
PRINT '================================================';
PRINT 'Database Setup Complete!';
PRINT '================================================';
PRINT '';
PRINT 'Tables created:';
PRINT '  - Accounts';
PRINT '  - Orders';
PRINT '  - Products';
PRINT '  - ErrorLog';
PRINT '  - TransactionLog';
PRINT '';
PRINT 'Test data inserted:';
SELECT 'Accounts' as TableName, COUNT(*) as RecordCount FROM Accounts
UNION ALL
SELECT 'Orders', COUNT(*) FROM Orders
UNION ALL
SELECT 'Products', COUNT(*) FROM Products;
PRINT '';
PRINT '================================================';
