-- =====================================================================
-- Week 2: Advanced SQL Queries - Database Setup Script
-- =====================================================================
-- This script creates all necessary tables and sample data for Week 2 tasks
-- =====================================================================

USE SQLTraining;
GO

-- =====================================================================
-- 1. STOCK PRICES TABLE
-- =====================================================================
IF OBJECT_ID('StockPrices', 'U') IS NOT NULL
    DROP TABLE StockPrices;
GO

CREATE TABLE StockPrices (
    StockID INT IDENTITY(1,1) PRIMARY KEY,
    StockSymbol VARCHAR(10) NOT NULL,
    TradeDate DATE NOT NULL,
    OpenPrice DECIMAL(18,4) NOT NULL,
    ClosePrice DECIMAL(18,4) NOT NULL,
    HighPrice DECIMAL(18,4) NOT NULL,
    LowPrice DECIMAL(18,4) NOT NULL,
    Volume BIGINT NOT NULL,
    DailyChange DECIMAL(18,4) NULL,
    UNIQUE (StockSymbol, TradeDate)
);

-- Indexes
CREATE INDEX idx_stock_symbol ON StockPrices(StockSymbol);
CREATE INDEX idx_trade_date ON StockPrices(TradeDate);
CREATE INDEX idx_stock_date ON StockPrices(StockSymbol, TradeDate);
GO

-- =====================================================================
-- 2. PORTFOLIOS TABLE
-- =====================================================================
IF OBJECT_ID('Portfolios', 'U') IS NOT NULL
    DROP TABLE Portfolios;
GO

CREATE TABLE Portfolios (
    PortfolioID INT IDENTITY(1,1) PRIMARY KEY,
    ClientID INT NOT NULL,
    PortfolioName VARCHAR(100) NOT NULL,
    ParentPortfolioID INT NULL,
    CreationDate DATETIME NOT NULL DEFAULT GETDATE(),
    TotalValue DECIMAL(18,2) NOT NULL DEFAULT 0,
    Status VARCHAR(20) NOT NULL DEFAULT 'Active',
    YieldPercent DECIMAL(5,2) NULL,
    FOREIGN KEY (ClientID) REFERENCES Clients(ClientID),
    FOREIGN KEY (ParentPortfolioID) REFERENCES Portfolios(PortfolioID)
);

CREATE INDEX idx_portfolio_client ON Portfolios(ClientID);
CREATE INDEX idx_portfolio_parent ON Portfolios(ParentPortfolioID);
GO

-- =====================================================================
-- 3. PORTFOLIO HOLDINGS TABLE
-- =====================================================================
IF OBJECT_ID('PortfolioHoldings', 'U') IS NOT NULL
    DROP TABLE PortfolioHoldings;
GO

CREATE TABLE PortfolioHoldings (
    HoldingID INT IDENTITY(1,1) PRIMARY KEY,
    PortfolioID INT NOT NULL,
    StockSymbol VARCHAR(10) NOT NULL,
    Quantity INT NOT NULL,
    AcquisitionPrice DECIMAL(18,4) NOT NULL,
    CurrentPrice DECIMAL(18,4) NOT NULL,
    AcquisitionDate DATE NOT NULL,
    FOREIGN KEY (PortfolioID) REFERENCES Portfolios(PortfolioID),
    UNIQUE (PortfolioID, StockSymbol)
);

CREATE INDEX idx_holding_portfolio ON PortfolioHoldings(PortfolioID);
CREATE INDEX idx_holding_symbol ON PortfolioHoldings(StockSymbol);
GO

-- =====================================================================
-- 4. EMPLOYEES TABLE (for hierarchy)
-- =====================================================================
IF OBJECT_ID('Employees', 'U') IS NOT NULL
    DROP TABLE Employees;
GO

CREATE TABLE Employees (
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeName VARCHAR(100) NOT NULL,
    ManagerID INT NULL,
    Department VARCHAR(50) NOT NULL,
    Salary DECIMAL(18,2) NOT NULL,
    HireDate DATE NOT NULL,
    FOREIGN KEY (ManagerID) REFERENCES Employees(EmployeeID)
);

CREATE INDEX idx_employee_manager ON Employees(ManagerID);
CREATE INDEX idx_employee_department ON Employees(Department);
GO

-- =====================================================================
-- 5. SAMPLE DATA INSERTION
-- =====================================================================

-- Insert Stock Symbols (Sample Data)
INSERT INTO StockPrices (StockSymbol, TradeDate, OpenPrice, ClosePrice, HighPrice, LowPrice, Volume)
VALUES
('AAPL', '2024-01-15', 150.00, 150.50, 151.00, 149.50, 2500000),
('AAPL', '2024-01-16', 150.50, 152.00, 152.50, 150.00, 2300000),
('AAPL', '2024-01-17', 152.00, 151.50, 152.80, 150.80, 2200000),
('AAPL', '2024-01-18', 151.50, 153.00, 153.50, 151.00, 2400000),
('AAPL', '2024-01-19', 153.00, 152.50, 154.00, 152.00, 2600000),
('MSFT', '2024-01-15', 320.00, 321.50, 322.00, 319.50, 1800000),
('MSFT', '2024-01-16', 321.50, 323.00, 324.00, 320.50, 1900000),
('MSFT', '2024-01-17', 323.00, 322.00, 325.00, 321.50, 2000000),
('MSFT', '2024-01-18', 322.00, 324.50, 325.00, 322.00, 1850000),
('MSFT', '2024-01-19', 324.50, 323.00, 325.00, 322.50, 1950000),
('GOOG', '2024-01-15', 140.00, 141.00, 142.00, 139.50, 1500000),
('GOOG', '2024-01-16', 141.00, 142.50, 143.00, 140.50, 1600000),
('GOOG', '2024-01-17', 142.50, 141.50, 143.50, 140.50, 1550000),
('GOOG', '2024-01-18', 141.50, 143.00, 143.50, 141.00, 1700000),
('GOOG', '2024-01-19', 143.00, 142.00, 144.00, 141.50, 1650000);

-- Calculate DailyChange
UPDATE StockPrices
SET DailyChange = ClosePrice - OpenPrice;

-- Insert Portfolio Data
INSERT INTO Portfolios (ClientID, PortfolioName, CreationDate, TotalValue, Status, YieldPercent)
SELECT TOP 5 
    ClientID, 
    'Portfolio_' + CAST(ClientID AS VARCHAR(10)), 
    DATEADD(MONTH, -6, GETDATE()),
    50000 + (ClientID * 10000),
    'Active',
    15.5 + (ClientID * 2)
FROM Clients;

-- Insert Portfolio Holdings
DECLARE @PortfolioID INT = 1;
INSERT INTO PortfolioHoldings (PortfolioID, StockSymbol, Quantity, AcquisitionPrice, CurrentPrice, AcquisitionDate)
VALUES
(@PortfolioID, 'AAPL', 100, 145.00, 150.50, '2024-01-01'),
(@PortfolioID, 'MSFT', 50, 315.00, 323.00, '2024-01-01'),
(@PortfolioID, 'GOOG', 75, 138.00, 142.00, '2024-01-05');

-- Insert Employee Hierarchy
INSERT INTO Employees (EmployeeName, ManagerID, Department, Salary, HireDate)
VALUES
('Alice Johnson', NULL, 'Executive', 500000.00, '2020-01-15'),
('Bob Smith', 1, 'Sales', 400000.00, '2021-03-10'),
('Charlie Brown', 1, 'IT', 380000.00, '2021-05-20'),
('David Wilson', 2, 'Sales', 300000.00, '2022-01-15'),
('Eve Davis', 2, 'Sales', 280000.00, '2022-06-10'),
('Frank Miller', 3, 'IT', 250000.00, '2022-09-15'),
('Grace Lee', 3, 'IT', 240000.00, '2023-01-10');

-- =====================================================================
-- 6. CREATE SAMPLE VIEWS
-- =====================================================================

-- Simple View
CREATE VIEW vw_RecentStockPrices AS
SELECT 
    StockSymbol,
    TradeDate,
    OpenPrice,
    ClosePrice,
    HighPrice,
    LowPrice,
    Volume,
    (ClosePrice - OpenPrice) AS DailyChange,
    ((ClosePrice - OpenPrice) / OpenPrice * 100) AS DailyChangePercent
FROM StockPrices
WHERE TradeDate >= DATEADD(DAY, -30, GETDATE());

-- Complex View with JOIN
CREATE VIEW vw_PortfolioSummary AS
SELECT 
    p.PortfolioID,
    p.PortfolioName,
    c.ClientName,
    COUNT(ph.HoldingID) AS HoldingCount,
    SUM(ph.Quantity * ph.CurrentPrice) AS CurrentValue,
    SUM(ph.Quantity * ph.AcquisitionPrice) AS AcquisitionValue,
    SUM(ph.Quantity * (ph.CurrentPrice - ph.AcquisitionPrice)) AS GainLoss,
    CAST(SUM(ph.Quantity * (ph.CurrentPrice - ph.AcquisitionPrice)) * 100.0 / 
        SUM(ph.Quantity * ph.AcquisitionPrice) AS DECIMAL(5,2)) AS ReturnPercent
FROM Portfolios p
INNER JOIN Clients c ON p.ClientID = c.ClientID
LEFT JOIN PortfolioHoldings ph ON p.PortfolioID = ph.PortfolioID
GROUP BY p.PortfolioID, p.PortfolioName, c.ClientName;

-- =====================================================================
-- 7. PRINT COMPLETION MESSAGE
-- =====================================================================
PRINT 'Week 2 Database Setup Completed Successfully!';
PRINT 'Created tables: StockPrices, Portfolios, PortfolioHoldings, Employees';
PRINT 'Created views: vw_RecentStockPrices, vw_PortfolioSummary';
PRINT 'Sample data inserted for testing.';
GO
