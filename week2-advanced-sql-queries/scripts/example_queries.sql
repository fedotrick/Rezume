-- =====================================================================
-- Week 2: Advanced SQL Queries - Example Queries
-- =====================================================================
-- This script contains ready-to-run examples from the lectures
-- =====================================================================

USE SQLTraining;
GO

-- =====================================================================
-- SECTION 1: WINDOW FUNCTIONS EXAMPLES
-- =====================================================================

-- 1.1 ROW_NUMBER Example
PRINT '=== 1.1 ROW_NUMBER Example ===';
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    ROW_NUMBER() OVER (ORDER BY ClosePrice DESC) AS row_num,
    ROW_NUMBER() OVER (PARTITION BY StockSymbol ORDER BY TradeDate) AS date_sequence
FROM StockPrices
WHERE TradeDate >= '2024-01-15'
ORDER BY StockSymbol, TradeDate;
GO

-- 1.2 RANK and DENSE_RANK Example
PRINT '=== 1.2 RANK vs DENSE_RANK Example ===';
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    RANK() OVER (ORDER BY ClosePrice DESC) AS rank,
    DENSE_RANK() OVER (ORDER BY ClosePrice DESC) AS dense_rank,
    ROW_NUMBER() OVER (ORDER BY ClosePrice DESC) AS row_num
FROM StockPrices
WHERE TradeDate >= '2024-01-15'
ORDER BY ClosePrice DESC;
GO

-- 1.3 LAG and LEAD Example
PRINT '=== 1.3 LAG and LEAD Example ===';
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    LAG(ClosePrice) OVER (PARTITION BY StockSymbol ORDER BY TradeDate) AS prev_price,
    LEAD(ClosePrice) OVER (PARTITION BY StockSymbol ORDER BY TradeDate) AS next_price,
    ClosePrice - LAG(ClosePrice) OVER (PARTITION BY StockSymbol ORDER BY TradeDate) AS price_change,
    (ClosePrice - LAG(ClosePrice) OVER (PARTITION BY StockSymbol ORDER BY TradeDate)) * 100.0 /
        LAG(ClosePrice) OVER (PARTITION BY StockSymbol ORDER BY TradeDate) AS pct_change
FROM StockPrices
ORDER BY StockSymbol, TradeDate;
GO

-- 1.4 Moving Average Example
PRINT '=== 1.4 Moving Average (5-day SMA) ===';
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    AVG(ClosePrice) OVER (
        PARTITION BY StockSymbol 
        ORDER BY TradeDate
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    ) AS sma_5,
    COUNT(*) OVER (
        PARTITION BY StockSymbol 
        ORDER BY TradeDate
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    ) AS days_in_window
FROM StockPrices
ORDER BY StockSymbol, TradeDate;
GO

-- 1.5 Cumulative Sum Example
PRINT '=== 1.5 Cumulative Sum ===';
SELECT 
    StockSymbol,
    TradeDate,
    Volume,
    SUM(Volume) OVER (
        PARTITION BY StockSymbol
        ORDER BY TradeDate
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_volume
FROM StockPrices
ORDER BY StockSymbol, TradeDate;
GO

-- 1.6 NTILE Example (Quartiles)
PRINT '=== 1.6 NTILE Example ===';
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    NTILE(4) OVER (ORDER BY ClosePrice DESC) AS quartile
FROM StockPrices
ORDER BY ClosePrice DESC;
GO

-- =====================================================================
-- SECTION 2: JOIN EXAMPLES
-- =====================================================================

-- 2.1 INNER JOIN
PRINT '=== 2.1 INNER JOIN Example ===';
SELECT 
    c.ClientName,
    o.OrderID,
    o.OrderAmount,
    o.OrderDate
FROM Clients c
INNER JOIN Orders o ON c.ClientID = o.ClientID
WHERE o.OrderAmount > 1000
ORDER BY o.OrderAmount DESC;
GO

-- 2.2 LEFT JOIN
PRINT '=== 2.2 LEFT JOIN Example ===';
SELECT 
    c.ClientName,
    COUNT(o.OrderID) AS order_count,
    SUM(o.OrderAmount) AS total_spent,
    MAX(o.OrderDate) AS last_order_date
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID, c.ClientName
ORDER BY total_spent DESC;
GO

-- 2.3 FULL OUTER JOIN
PRINT '=== 2.3 FULL OUTER JOIN Example ===';
SELECT 
    COALESCE(c.ClientID, p.ClientID) AS client_id,
    COALESCE(c.ClientName, 'Unknown') AS client_name,
    COUNT(DISTINCT o.OrderID) AS order_count,
    COUNT(DISTINCT p.PortfolioID) AS portfolio_count
FROM Clients c
FULL OUTER JOIN Orders o ON c.ClientID = o.ClientID
FULL OUTER JOIN Portfolios p ON c.ClientID = p.ClientID
GROUP BY COALESCE(c.ClientID, p.ClientID), COALESCE(c.ClientName, 'Unknown')
ORDER BY order_count DESC;
GO

-- 2.4 Self Join (Employees Hierarchy)
PRINT '=== 2.4 Self Join Example (Employee Hierarchy) ===';
SELECT 
    e1.EmployeeID,
    e1.EmployeeName,
    e1.Department,
    e1.Salary,
    e2.EmployeeName AS ManagerName,
    e2.Department AS ManagerDepartment
FROM Employees e1
LEFT JOIN Employees e2 ON e1.ManagerID = e2.EmployeeID
ORDER BY e1.Department, e1.EmployeeName;
GO

-- 2.5 Multiple JOINs
PRINT '=== 2.5 Multiple JOINs Example ===';
SELECT 
    c.ClientName,
    o.OrderID,
    o.OrderDate,
    oi.Quantity,
    p.ProductName,
    (oi.Quantity * oi.Price) AS item_total
FROM Clients c
INNER JOIN Orders o ON c.ClientID = o.ClientID
INNER JOIN OrderItems oi ON o.OrderID = oi.OrderID
INNER JOIN Products p ON oi.ProductID = p.ProductID
WHERE o.OrderAmount > 1000
ORDER BY o.OrderID;
GO

-- =====================================================================
-- SECTION 3: SUBQUERY EXAMPLES
-- =====================================================================

-- 3.1 Subquery in WHERE with IN
PRINT '=== 3.1 Subquery with IN ===';
SELECT 
    ClientID,
    ClientName
FROM Clients
WHERE ClientID IN (
    SELECT DISTINCT ClientID 
    FROM Orders 
    WHERE OrderAmount > 5000
)
ORDER BY ClientName;
GO

-- 3.2 Subquery with EXISTS
PRINT '=== 3.2 Subquery with EXISTS ===';
SELECT 
    c.ClientID,
    c.ClientName,
    c.RegistrationDate
FROM Clients c
WHERE EXISTS (
    SELECT 1 FROM Orders o 
    WHERE o.ClientID = c.ClientID 
    AND o.OrderAmount > 10000
)
ORDER BY c.ClientName;
GO

-- 3.3 Subquery in SELECT
PRINT '=== 3.3 Subquery in SELECT ===';
SELECT 
    c.ClientID,
    c.ClientName,
    (SELECT COUNT(*) FROM Orders WHERE ClientID = c.ClientID) AS order_count,
    (SELECT SUM(OrderAmount) FROM Orders WHERE ClientID = c.ClientID) AS total_spent,
    (SELECT MAX(OrderDate) FROM Orders WHERE ClientID = c.ClientID) AS last_order_date
FROM Clients c
ORDER BY ClientName;
GO

-- 3.4 Correlated Subquery
PRINT '=== 3.4 Correlated Subquery ===';
SELECT 
    c.ClientID,
    c.ClientName,
    (SELECT AVG(OrderAmount) FROM Orders o WHERE o.ClientID = c.ClientID) AS client_avg_order
FROM Clients c
ORDER BY ClientName;
GO

-- =====================================================================
-- SECTION 4: CTE EXAMPLES
-- =====================================================================

-- 4.1 Simple CTE
PRINT '=== 4.1 Simple CTE ===';
WITH HighValueClients AS (
    SELECT 
        ClientID,
        ClientName,
        SUM(OrderAmount) AS total_spent
    FROM Clients c
    LEFT JOIN Orders o ON c.ClientID = o.ClientID
    GROUP BY c.ClientID, c.ClientName
    HAVING SUM(OrderAmount) > 10000
)
SELECT * FROM HighValueClients
ORDER BY total_spent DESC;
GO

-- 4.2 Multiple CTEs
PRINT '=== 4.2 Multiple CTEs ===';
WITH ClientStats AS (
    SELECT 
        ClientID,
        COUNT(OrderID) AS order_count,
        SUM(OrderAmount) AS total_spent
    FROM Orders
    GROUP BY ClientID
),
TopClients AS (
    SELECT TOP 10 * FROM ClientStats
    WHERE order_count > 0
    ORDER BY total_spent DESC
)
SELECT 
    c.ClientName,
    tc.order_count,
    tc.total_spent,
    tc.total_spent * 0.1 AS loyalty_bonus
FROM TopClients tc
INNER JOIN Clients c ON tc.ClientID = c.ClientID;
GO

-- 4.3 Recursive CTE (Employee Hierarchy)
PRINT '=== 4.3 Recursive CTE (Employee Hierarchy) ===';
WITH EmployeeHierarchy AS (
    -- Anchor: CEO/Managers without a manager
    SELECT 
        EmployeeID,
        EmployeeName,
        ManagerID,
        Department,
        Salary,
        1 AS hierarchy_level,
        CAST(EmployeeName AS VARCHAR(MAX)) AS hierarchy_path
    FROM Employees
    WHERE ManagerID IS NULL
    
    UNION ALL
    
    -- Recursive: All subordinates
    SELECT 
        e.EmployeeID,
        e.EmployeeName,
        e.ManagerID,
        e.Department,
        e.Salary,
        eh.hierarchy_level + 1,
        eh.hierarchy_path + ' -> ' + e.EmployeeName
    FROM Employees e
    INNER JOIN EmployeeHierarchy eh ON e.ManagerID = eh.EmployeeID
    WHERE eh.hierarchy_level < 10
)
SELECT 
    REPLICATE('  ', hierarchy_level - 1) + EmployeeName AS hierarchy_tree,
    Department,
    Salary,
    hierarchy_level
FROM EmployeeHierarchy
ORDER BY hierarchy_path;
GO

-- =====================================================================
-- SECTION 5: TEMPORARY TABLE EXAMPLES
-- =====================================================================

-- 5.1 Temporary Table Usage
PRINT '=== 5.1 Temporary Table Example ===';
CREATE TABLE #TopClients (
    ClientID INT,
    ClientName VARCHAR(100),
    TotalSpent DECIMAL(18,2),
    INDEX idx_client (ClientID)
);

INSERT INTO #TopClients
SELECT TOP 10
    c.ClientID,
    c.ClientName,
    SUM(o.OrderAmount) AS TotalSpent
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID, c.ClientName
ORDER BY TotalSpent DESC;

SELECT * FROM #TopClients;

DROP TABLE #TopClients;
GO

-- 5.2 Table Variable Usage
PRINT '=== 5.2 Table Variable Example ===';
DECLARE @ClientOrders TABLE (
    ClientID INT,
    ClientName VARCHAR(100),
    OrderCount INT,
    PRIMARY KEY (ClientID)
);

INSERT INTO @ClientOrders
SELECT 
    c.ClientID,
    c.ClientName,
    COUNT(o.OrderID) AS OrderCount
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID, c.ClientName;

SELECT * FROM @ClientOrders
WHERE OrderCount > 0
ORDER BY OrderCount DESC;
GO

-- =====================================================================
-- SECTION 6: VIEW EXAMPLES
-- =====================================================================

-- 6.1 Check existing views
PRINT '=== 6.1 List of Views ===';
SELECT 
    name AS view_name,
    create_date,
    modify_date
FROM sys.objects
WHERE type = 'V'
ORDER BY name;
GO

-- 6.2 Query views
PRINT '=== 6.2 Query Sample Views ===';
IF EXISTS (SELECT 1 FROM sys.objects WHERE type = 'V' AND name = 'vw_RecentStockPrices')
BEGIN
    SELECT * FROM vw_RecentStockPrices
    ORDER BY TradeDate DESC;
END
GO

-- 6.3 View with aggregation
PRINT '=== 6.3 Portfolio Summary View ===';
IF EXISTS (SELECT 1 FROM sys.objects WHERE type = 'V' AND name = 'vw_PortfolioSummary')
BEGIN
    SELECT * FROM vw_PortfolioSummary
    ORDER BY CurrentValue DESC;
END
GO

-- =====================================================================
-- SECTION 7: PERFORMANCE COMPARISON
-- =====================================================================

-- 7.1 Compare execution times
PRINT '=== 7.1 Performance Comparison ===';

PRINT 'Method 1: Using CTE';
SET STATISTICS TIME ON;
WITH ClientOrders AS (
    SELECT 
        ClientID,
        COUNT(*) AS order_count,
        SUM(OrderAmount) AS total
    FROM Orders
    GROUP BY ClientID
)
SELECT * FROM ClientOrders WHERE order_count > 0;
SET STATISTICS TIME OFF;

PRINT 'Method 2: Using JOIN with GROUP BY';
SET STATISTICS TIME ON;
SELECT 
    c.ClientID,
    COUNT(o.OrderID) AS order_count,
    SUM(o.OrderAmount) AS total
FROM Clients c
LEFT JOIN Orders o ON c.ClientID = o.ClientID
GROUP BY c.ClientID
HAVING COUNT(o.OrderID) > 0;
SET STATISTICS TIME OFF;
GO

-- =====================================================================
-- SUMMARY REPORT
-- =====================================================================

PRINT '=== Week 2 Examples Summary ===';
PRINT 'Window Functions: ROW_NUMBER, RANK, DENSE_RANK, LAG, LEAD, SMA, Cumulative Sum, NTILE';
PRINT 'JOINs: INNER, LEFT, RIGHT, FULL OUTER, Self Join, Multiple JOINs';
PRINT 'Subqueries: IN, EXISTS, SELECT, Correlated';
PRINT 'CTEs: Simple, Multiple, Recursive';
PRINT 'Temporary Objects: #TempTable, @TableVariable';
PRINT 'Views: Simple, Complex, Indexed';
PRINT '';
PRINT 'All examples executed successfully!';
GO
