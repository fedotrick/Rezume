# Практическая задача 3: Использование CTE (Common Table Expressions)

## Описание

Эта задача ориентирована на использование простых и рекурсивных CTE для решения сложных проблем анализа иерархических данных и пошаговых вычислений.

## Требуемые таблицы

```sql
-- Employees - сотрудники с иерархией
-- Columns: EmployeeID, EmployeeName, ManagerID (NULL для CEO), Department, Salary, HireDate

-- Departments - отделы
-- Columns: DepartmentID, DepartmentName, ParentDepartmentID (NULL для главных)

-- SalesData - данные о продажах
-- Columns: SaleID, SalesPersonID, SaleDate, SaleAmount, Commission

-- Projects - проекты с иерархией
-- Columns: ProjectID, ProjectName, ParentProjectID, Status, StartDate, EndDate, Budget

-- Clients - клиенты
-- Columns: ClientID, ClientName, ManagingEmployeeID
```

## Задача 3.1: Рекурсивный CTE для иерархии сотрудников

**Цель:** Построить полную иерархию подчинения сотрудников.

**Требования:**
- Начать с CEO (ManagerID IS NULL)
- Рекурсивно добавить всех подчиненных на каждом уровне
- Показать уровень иерархии и путь от CEO до сотрудника
- Рассчитать количество прямых подчиненных
- Рассчитать зарплату подразделения (сумма всех зарплат в иерархии)

**Ожидаемый результат:**

| Level | HierarchyPath | EmployeeID | EmployeeName | Department | Salary | DirectReports | SubtreeTotal |
|-------|---------------|-----------|--------------|-----------|--------|--------------|-------------|
| 1 | CEO | 1 | Alice | Executive | 500000 | 3 | 1500000 |
| 2 | CEO → Sales | 2 | Bob | Sales | 400000 | 2 | 900000 |
| 3 | CEO → Sales → Team1 | 3 | Charlie | Sales | 300000 | 1 | 300000 |
| 4 | CEO → Sales → Team1 → Junior | 5 | David | Sales | 200000 | 0 | 200000 |

**Заготовка запроса:**

```sql
WITH EmployeeHierarchy AS (
    -- Якорь: CEO и топ-менеджеры
    SELECT 
        EmployeeID,
        EmployeeName,
        ManagerID,
        Department,
        Salary,
        1 AS HierarchyLevel,
        CAST(EmployeeName AS VARCHAR(MAX)) AS HierarchyPath,
        0 AS DirectReports
    FROM Employees
    WHERE ManagerID IS NULL
    
    UNION ALL
    
    -- Рекурсия: все подчиненные
    SELECT 
        e.EmployeeID,
        e.EmployeeName,
        e.ManagerID,
        e.Department,
        e.Salary,
        eh.HierarchyLevel + 1,
        eh.HierarchyPath + ' → ' + e.EmployeeName,
        -- Счет подчиненных
    FROM Employees e
    INNER JOIN EmployeeHierarchy eh ON e.ManagerID = eh.EmployeeID
    WHERE eh.HierarchyLevel < 10  -- Избегаем бесконечной рекурсии
)
SELECT 
    HierarchyLevel AS Level,
    HierarchyPath,
    EmployeeID,
    EmployeeName,
    Department,
    Salary,
    DirectReports,
    -- Добавить рекурсивный расчет суммы
    REPLICATE('  ', HierarchyLevel - 1) + EmployeeName AS IndentedName
FROM EmployeeHierarchy
ORDER BY HierarchyPath;
```

## Задача 3.2: Рекурсивный CTE для иерархии отделов

**Цель:** Визуализировать структуру организации.

**Требования:**
- Построить иерархию отделов с индентацией
- Показать количество сотрудников в каждом отделе
- Рассчитать общий бюджет отдела (если есть информация)
- Определить полный путь от корневого отдела
- Показать глубину иерархии

**Ожидаемый результат:**

| OrganizationTree | DepartmentName | EmployeeCount | TotalSalary | Level | Path |
|-----------------|----------------|---------------|-----------|-------|------|
| Executive | Executive | 1 | 500000 | 1 | / Executive |
|   Sales | Sales | 5 | 1500000 | 2 | / Executive / Sales |
|     North Sales | North Sales | 2 | 600000 | 3 | / Executive / Sales / North Sales |
|     South Sales | South Sales | 3 | 900000 | 3 | / Executive / Sales / South Sales |

**Заготовка запроса:**

```sql
WITH DepartmentHierarchy AS (
    -- Якорь: главные отделы
    SELECT 
        DepartmentID,
        DepartmentName,
        ParentDepartmentID,
        1 AS DeptLevel,
        '/' + DepartmentName AS DeptPath
    FROM Departments
    WHERE ParentDepartmentID IS NULL
    
    UNION ALL
    
    -- Рекурсия: подотделы
    SELECT 
        d.DepartmentID,
        d.DepartmentName,
        d.ParentDepartmentID,
        dh.DeptLevel + 1,
        dh.DeptPath + ' / ' + d.DepartmentName
    FROM Departments d
    INNER JOIN DepartmentHierarchy dh ON d.ParentDepartmentID = dh.DepartmentID
    WHERE dh.DeptLevel < 10
)
SELECT 
    REPLICATE('  ', DeptLevel - 1) + DepartmentName AS OrganizationTree,
    DepartmentName,
    -- Подсчет сотрудников через подзапрос
    -- Расчет зарплаты
    DeptLevel AS Level,
    DeptPath AS Path
FROM DepartmentHierarchy
ORDER BY DeptPath;
```

## Задача 3.3: Использование CTE для пошагового вычисления метрик

**Цель:** Рассчитать комиссии и сумма продаж поэтапно.

**Требования:**
- CTE 1: Получить все продажи в текущем месяце
- CTE 2: Рассчитать комиссию для каждой продажи (разные % в зависимости от суммы)
- CTE 3: Рассчитать итоги по продавцу
- CTE 4: Ранжировать продавцов
- Финальный запрос: показать топ продавцов с их метриками

**Ожидаемый результат:**

| Rank | SalesPersonID | SalesPersonName | TotalSales | TotalCommission | AvgSale | SaleCount | CommissionPercent |
|------|--------------|-----------------|-----------|-----------------|---------|-----------|-------------------|
| 1 | 2 | Bob | 150000 | 15000 | 15000 | 10 | 10.00 |
| 2 | 3 | Charlie | 120000 | 10800 | 12000 | 10 | 9.00 |

**Заготовка запроса:**

```sql
WITH MonthlySales AS (
    -- Шаг 1: Фильтровать продажи текущего месяца
    SELECT 
        SaleID,
        SalesPersonID,
        SaleDate,
        SaleAmount
    FROM SalesData
    WHERE MONTH(SaleDate) = MONTH(GETDATE())
        AND YEAR(SaleDate) = YEAR(GETDATE())
),
SalesWithCommission AS (
    -- Шаг 2: Рассчитать комиссию
    SELECT 
        SaleID,
        SalesPersonID,
        SaleDate,
        SaleAmount,
        CASE 
            WHEN SaleAmount >= 10000 THEN SaleAmount * 0.10  -- 10%
            WHEN SaleAmount >= 5000 THEN SaleAmount * 0.08   -- 8%
            ELSE SaleAmount * 0.05                            -- 5%
        END AS Commission
    FROM MonthlySales
),
PersonTotals AS (
    -- Шаг 3: Итого по продавцу
    SELECT 
        SalesPersonID,
        COUNT(*) AS SaleCount,
        SUM(SaleAmount) AS TotalSales,
        SUM(Commission) AS TotalCommission,
        AVG(SaleAmount) AS AvgSale,
        (SUM(Commission) * 100.0 / SUM(SaleAmount)) AS CommissionPercent
    FROM SalesWithCommission
    GROUP BY SalesPersonID
),
RankedSales AS (
    -- Шаг 4: Ранжировать
    SELECT 
        ROW_NUMBER() OVER (ORDER BY TotalCommission DESC) AS Rank,
        e.EmployeeID,
        e.EmployeeName,
        pt.*
    FROM PersonTotals pt
    INNER JOIN Employees e ON pt.SalesPersonID = e.EmployeeID
)
SELECT 
    Rank,
    EmployeeID,
    EmployeeName,
    TotalSales,
    TotalCommission,
    AvgSale,
    SaleCount,
    CommissionPercent
FROM RankedSales
WHERE Rank <= 10
ORDER BY Rank;
```

## Задача 3.4: Рекурсивный CTE для генерации календаря

**Цель:** Создать календарь на определенный период.

**Требования:**
- Сгенерировать все дни между двумя датами
- Определить день недели и номер недели
- Найти выходные дни (субботы и воскресенья)
- Подсчитать рабочие дни в периоде
- Определить праздничные дни

**Ожидаемый результат:**

| Calendar Date | DayName | Week | DayType | RemainingWorkDays |
|---------------|---------|------|---------|-------------------|
| 2024-01-01 | Monday | 1 | Holiday | 20 |
| 2024-01-02 | Tuesday | 1 | Workday | 19 |
| 2024-01-06 | Saturday | 1 | Weekend | 19 |
| 2024-01-07 | Sunday | 1 | Weekend | 19 |

**Заготовка запроса:**

```sql
DECLARE @StartDate DATE = '2024-01-01';
DECLARE @EndDate DATE = '2024-12-31';

WITH DateSeries AS (
    -- Якорь: начальная дата
    SELECT @StartDate AS CalendarDate
    
    UNION ALL
    
    -- Рекурсия: добавляем по одному дню
    SELECT DATEADD(DAY, 1, CalendarDate)
    FROM DateSeries
    WHERE CalendarDate < @EndDate
),
HolidayList AS (
    -- Список праздников
    VALUES
        ('2024-01-01'),  -- New Year
        ('2024-12-25')   -- Christmas
)
SELECT 
    CalendarDate,
    DATENAME(WEEKDAY, CalendarDate) AS DayName,
    DATEPART(ISO_WEEK, CalendarDate) AS Week,
    CASE 
        WHEN DATENAME(WEEKDAY, CalendarDate) IN ('Saturday', 'Sunday') THEN 'Weekend'
        WHEN CalendarDate IN (SELECT * FROM HolidayList) THEN 'Holiday'
        ELSE 'Workday'
    END AS DayType,
    -- Подсчет оставшихся рабочих дней
    COUNT(CASE WHEN DATENAME(WEEKDAY, CalendarDate) NOT IN ('Saturday', 'Sunday') THEN 1 END) 
        OVER (ORDER BY CalendarDate DESC) AS RemainingWorkDays
FROM DateSeries
WHERE CalendarDate <= @EndDate
ORDER BY CalendarDate;
```

## Задача 3.5: Оптимизация сложного запроса с CTE

**Цель:** Переписать сложный запрос для улучшения читаемости и производительности.

**Требования:**
- Дан сложный вложенный запрос
- Разбить его на несколько CTE
- Каждый CTE должен выполнять одну логическую функцию
- Добавить комментарии объясняющие каждый CTE
- Сравнить производительность

**Исходный запрос (сложный для чтения):**

```sql
SELECT TOP 10
    e.EmployeeID,
    e.EmployeeName,
    (SELECT COUNT(*) FROM Clients c WHERE c.ManagingEmployeeID = e.EmployeeID) AS ClientCount,
    (SELECT SUM(SaleAmount) FROM SalesData sd INNER JOIN Clients c ON sd.SalesPersonID = e.EmployeeID 
     WHERE YEAR(sd.SaleDate) = YEAR(GETDATE())) AS YearSales,
    (SELECT AVG(s.SaleAmount) FROM SalesData s WHERE s.SalesPersonID = e.EmployeeID) AS AvgSaleAmount,
    (SELECT TOP 1 sd.SaleDate FROM SalesData sd WHERE sd.SalesPersonID = e.EmployeeID ORDER BY sd.SaleDate DESC) AS LastSaleDate
FROM Employees e
WHERE e.HireDate > DATEADD(YEAR, -5, GETDATE())
    AND (SELECT COUNT(*) FROM Clients c WHERE c.ManagingEmployeeID = e.EmployeeID) > 0
ORDER BY YearSales DESC;
```

**Оптимизированный запрос с CTE:**

```sql
-- CTE 1: Активные сотрудники за последние 5 лет
WITH RecentEmployees AS (
    SELECT 
        EmployeeID,
        EmployeeName,
        HireDate
    FROM Employees
    WHERE HireDate > DATEADD(YEAR, -5, GETDATE())
),

-- CTE 2: Клиенты по менеджерам
ClientStats AS (
    SELECT 
        ManagingEmployeeID,
        COUNT(*) AS ClientCount
    FROM Clients
    WHERE ManagingEmployeeID IS NOT NULL
    GROUP BY ManagingEmployeeID
),

-- CTE 3: Годовые продажи
YearlySalesStats AS (
    SELECT 
        SalesPersonID,
        SUM(SaleAmount) AS YearSales,
        AVG(SaleAmount) AS AvgSaleAmount,
        COUNT(*) AS SaleCount
    FROM SalesData
    WHERE YEAR(SaleDate) = YEAR(GETDATE())
    GROUP BY SalesPersonID
),

-- CTE 4: Последние дни продаж
LastSaleDate AS (
    SELECT 
        SalesPersonID,
        MAX(SaleDate) AS LastSaleDate
    FROM SalesData
    GROUP BY SalesPersonID
),

-- CTE 5: Объединение всех данных
EmployeeSummary AS (
    SELECT 
        re.EmployeeID,
        re.EmployeeName,
        COALESCE(cs.ClientCount, 0) AS ClientCount,
        COALESCE(yss.YearSales, 0) AS YearSales,
        COALESCE(yss.AvgSaleAmount, 0) AS AvgSaleAmount,
        lsd.LastSaleDate
    FROM RecentEmployees re
    LEFT JOIN ClientStats cs ON re.EmployeeID = cs.ManagingEmployeeID
    LEFT JOIN YearlySalesStats yss ON re.EmployeeID = yss.SalesPersonID
    LEFT JOIN LastSaleDate lsd ON re.EmployeeID = lsd.SalesPersonID
    WHERE COALESCE(cs.ClientCount, 0) > 0
)
SELECT TOP 10 *
FROM EmployeeSummary
ORDER BY YearSales DESC;
```

**Анализ улучшений:**
- Каждый CTE решает одну задачу
- Легче читать и поддерживать
- Более эффективно для оптимизатора
- Легче заменить части запроса

## Тестирование

```sql
-- 1. Проверьте глубину рекурсии
SET STATISTICS IO ON;

-- Запустите рекурсивный запрос
-- Проверьте количество уровней

-- 2. Проверьте граничные случаи
-- NULL значения в иерархии
-- Циклические ссылки (A -> B -> A) - должны быть запрещены

-- 3. Сравните MAXRECURSION настройки
SELECT ... FROM CTE
OPTION (MAXRECURSION 100);   -- По умолчанию

SELECT ... FROM CTE
OPTION (MAXRECURSION 32767); -- Максимум

-- 4. Проверьте производительность
SET STATISTICS IO OFF;
```

## Дополнительные вызовы

1. **Граф зависимостей** - построить все проекты с их зависимостями
2. **Шапка и детали** - объединить иерархию в один уровень
3. **Поиск в ширину** - найти все узлы на определенном уровне
4. **Обнаружение циклов** - выявить циклические ссылки в иерархии

## Best Practices

```sql
-- ✅ Хорошо: явное ограничение рекурсии
WITH cte AS (
    SELECT ... WHERE recursion_level = 1
    UNION ALL
    SELECT ... WHERE recursion_level < 100
)
OPTION (MAXRECURSION 100);

-- ❌ Плохо: неограниченная рекурсия
WITH cte AS (
    SELECT ...
    UNION ALL
    SELECT ...
)
SELECT * FROM cte;
```

---

**Мудрость:** CTE делает код более читаемым и поддерживаемым. Используйте рекурсивные CTE для иерархий, но всегда устанавливайте явное ограничение глубины.
