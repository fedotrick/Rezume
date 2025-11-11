# Лекция 1: Оконные функции (Window Functions)

## 1. Основные концепции

### 1.1 Что такое оконные функции?

Оконные функции (Window Functions) - это специальные функции SQL Server, которые выполняют вычисления над набором строк (окном/window), связанных с текущей строкой. 

**Основное отличие от агрегирующих функций:**
- Агрегирующие функции (SUM, COUNT, AVG) обычно используются с GROUP BY и возвращают одну строку для каждой группы
- Оконные функции возвращают результат для каждой строки, сохраняя исходное количество строк в результате

### 1.2 Синтаксис оконных функций

```sql
SELECT 
    column1,
    column2,
    WINDOW_FUNCTION() OVER ([PARTITION BY columns] [ORDER BY columns] [ROWS/RANGE BETWEEN ...]) AS result
FROM table_name;
```

**Компоненты:**

1. **WINDOW_FUNCTION()** - одна из специальных функций (ROW_NUMBER, RANK, SUM и т.д.)
2. **OVER()** - обязательный клауз, определяющий окно
3. **PARTITION BY** - разделение данных на группы (опционально)
4. **ORDER BY** - сортировка внутри окна (требуется для некоторых функций)
5. **ROWS/RANGE BETWEEN** - определение границ окна (опционально)

### 1.3 Типы оконных функций

| Категория | Функции | Описание |
|-----------|---------|---------|
| **Ранжирование** | ROW_NUMBER, RANK, DENSE_RANK, NTILE | Присваивают номера/ранги строкам |
| **Смещение** | LAG, LEAD, FIRST_VALUE, LAST_VALUE | Получают данные из других строк в окне |
| **Агрегирующие** | SUM, AVG, COUNT, MIN, MAX | Вычисляют агреегаты по окну |
| **Распределение** | PERCENT_RANK, CUME_DIST, PERCENTILE_CONT, PERCENTILE_DISC | Статистические распределения |

## 2. Функции ранжирования

### 2.1 ROW_NUMBER() - Порядковый номер

Присваивает уникальный номер каждой строке в окне, начиная с 1.

```sql
SELECT 
    ClientName,
    TransactionAmount,
    TransactionDate,
    ROW_NUMBER() OVER (ORDER BY TransactionAmount DESC) AS row_num
FROM Transactions
ORDER BY TransactionAmount DESC;
```

**Результат:**
```
ClientName    | TransactionAmount | TransactionDate | row_num
Tony Stark    | 15000.00         | 2024-01-15     | 1
Bruce Wayne   | 12000.00         | 2024-01-14     | 2
Peter Parker  | 10000.00         | 2024-01-13     | 3
```

**С PARTITION BY:**

```sql
SELECT 
    Department,
    EmployeeName,
    Salary,
    ROW_NUMBER() OVER (PARTITION BY Department ORDER BY Salary DESC) AS dept_rank
FROM Employees;
```

Это присваивает номер 1 самому оплачиваемому сотруднику в каждом отделе.

### 2.2 RANK() и DENSE_RANK() - Ранжирование

**RANK()** - присваивает ранг, при одинаковых значениях дает одинаковые ранги и пропускает номера:

```sql
SELECT 
    PortfolioName,
    ReturnPercent,
    RANK() OVER (ORDER BY ReturnPercent DESC) AS rank
FROM Portfolios;
```

**Результат:**
```
PortfolioName | ReturnPercent | rank
Portfolio A   | 25.5         | 1
Portfolio B   | 25.5         | 1      -- Одинаковое значение
Portfolio C   | 23.2         | 3      -- Ранг пропущен
Portfolio D   | 20.1         | 4
```

**DENSE_RANK()** - похож на RANK, но не пропускает номера:

```sql
SELECT 
    PortfolioName,
    ReturnPercent,
    DENSE_RANK() OVER (ORDER BY ReturnPercent DESC) AS rank
FROM Portfolios;
```

**Результат:**
```
PortfolioName | ReturnPercent | rank
Portfolio A   | 25.5         | 1
Portfolio B   | 25.5         | 1      -- Одинаковое значение
Portfolio C   | 23.2         | 2      -- Ранг непропущен
Portfolio D   | 20.1         | 3
```

**Разница:**
- RANK() при 2 одинаковых строках: 1, 1, 3, 4, 5
- DENSE_RANK() при 2 одинаковых строках: 1, 1, 2, 3, 4

### 2.3 NTILE() - Распределение на квартили

Распределяет строки на N равных групп:

```sql
SELECT 
    ClientName,
    AnnualIncome,
    NTILE(4) OVER (ORDER BY AnnualIncome DESC) AS quartile
FROM Clients;
```

**Результат:**
```
ClientName    | AnnualIncome | quartile
Tony Stark    | 500000      | 1  (Верхние 25%)
Bruce Wayne   | 450000      | 1
Peter Parker  | 380000      | 2  (25-50%)
Steve Rogers  | 320000      | 2
...
```

## 3. Функции смещения

### 3.1 LAG() - Получение предыдущего значения

```sql
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    LAG(ClosePrice) OVER (PARTITION BY StockSymbol ORDER BY TradeDate) AS previous_price,
    ClosePrice - LAG(ClosePrice) OVER (PARTITION BY StockSymbol ORDER BY TradeDate) AS price_change
FROM StockPrices
ORDER BY StockSymbol, TradeDate;
```

**Результат:**
```
StockSymbol | TradeDate  | ClosePrice | previous_price | price_change
AAPL        | 2024-01-01 | 150.00    | NULL          | NULL
AAPL        | 2024-01-02 | 152.50    | 150.00        | 2.50
AAPL        | 2024-01-03 | 151.75    | 152.50        | -0.75
AAPL        | 2024-01-04 | 153.00    | 151.75        | 1.25
```

### 3.2 LEAD() - Получение следующего значения

```sql
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    LEAD(ClosePrice) OVER (PARTITION BY StockSymbol ORDER BY TradeDate) AS next_price
FROM StockPrices
WHERE YEAR(TradeDate) = 2024
ORDER BY StockSymbol, TradeDate;
```

### 3.3 FIRST_VALUE() и LAST_VALUE() - Границы окна

```sql
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    FIRST_VALUE(ClosePrice) OVER (
        PARTITION BY StockSymbol 
        ORDER BY TradeDate
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS year_first_price,
    LAST_VALUE(ClosePrice) OVER (
        PARTITION BY StockSymbol 
        ORDER BY TradeDate
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS year_last_price
FROM StockPrices
WHERE YEAR(TradeDate) = 2024;
```

## 4. Агрегирующие функции с OVER

### 4.1 Скользящее среднее (Moving Average)

```sql
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    AVG(ClosePrice) OVER (
        PARTITION BY StockSymbol 
        ORDER BY TradeDate
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    ) AS moving_avg_5days
FROM StockPrices
ORDER BY StockSymbol, TradeDate;
```

**Пояснение:**
- `ROWS BETWEEN 4 PRECEDING AND CURRENT ROW` - окно из 5 строк (текущая + 4 предыдущих)
- Для каждой строки вычисляется среднее за последние 5 дней

### 4.2 Сумма с нарастающим итогом (Running Sum / Cumulative Sum)

```sql
SELECT 
    ClientID,
    ClientName,
    TransactionDate,
    TransactionAmount,
    SUM(TransactionAmount) OVER (
        PARTITION BY ClientID 
        ORDER BY TransactionDate
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_amount
FROM Transactions
ORDER BY ClientID, TransactionDate;
```

**Результат:**
```
ClientID | ClientName   | TransactionDate | TransactionAmount | cumulative_amount
1        | Tony Stark   | 2024-01-01     | 1000.00          | 1000.00
1        | Tony Stark   | 2024-01-05     | 2500.00          | 3500.00
1        | Tony Stark   | 2024-01-10     | 1500.00          | 5000.00
2        | Bruce Wayne  | 2024-01-02     | 5000.00          | 5000.00
```

### 4.3 Количество строк в окне

```sql
SELECT 
    Department,
    EmployeeName,
    Salary,
    COUNT(*) OVER (PARTITION BY Department) AS dept_count,
    SUM(Salary) OVER (PARTITION BY Department) AS dept_total_salary
FROM Employees;
```

## 5. Определение границ окна (ROWS и RANGE)

### 5.1 Варианты ROWS и RANGE

```sql
-- UNBOUNDED PRECEDING - все строки с начала окна
-- UNBOUNDED FOLLOWING - все строки до конца окна
-- CURRENT ROW - текущая строка
-- N PRECEDING - N строк перед текущей
-- N FOLLOWING - N строк после текущей

-- Примеры:
ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW       -- От начала до текущей
ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING               -- ±2 строки от текущей
ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING -- Все строки в окне
```

### 5.2 RANGE vs ROWS

```sql
-- ROWS - физические строки
SELECT 
    TradeDate,
    ClosePrice,
    AVG(ClosePrice) OVER (
        ORDER BY TradeDate
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS moving_avg
FROM StockPrices;

-- RANGE - логические значения (полезно при одинаковых значениях в ORDER BY)
SELECT 
    Quarter,
    Revenue,
    SUM(Revenue) OVER (
        ORDER BY Quarter
        RANGE BETWEEN 1 PRECEDING AND CURRENT ROW
    ) AS quarter_range_sum
FROM QuarterlyRevenue;
```

## 6. Практические примеры с финансовыми данными

### 6.1 Анализ портфелей инвестиций

```sql
SELECT 
    PortfolioID,
    PortfolioName,
    StockSymbol,
    Quantity,
    CurrentPrice,
    Quantity * CurrentPrice AS position_value,
    -- Процент портфеля
    (Quantity * CurrentPrice) * 100.0 / 
        SUM(Quantity * CurrentPrice) OVER (PARTITION BY PortfolioID) AS pct_of_portfolio,
    -- Ранг активов по стоимости в портфеле
    RANK() OVER (PARTITION BY PortfolioID ORDER BY Quantity * CurrentPrice DESC) AS asset_rank
FROM PortfolioHoldings
WHERE PortfolioID = 1;
```

### 6.2 Определение тренда цен акций

```sql
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    -- 20-дневное скользящее среднее
    AVG(ClosePrice) OVER (
        PARTITION BY StockSymbol 
        ORDER BY TradeDate
        ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) AS sma_20,
    -- Процентное изменение от предыдущего дня
    (ClosePrice - LAG(ClosePrice) OVER (PARTITION BY StockSymbol ORDER BY TradeDate)) / 
        LAG(ClosePrice) OVER (PARTITION BY StockSymbol ORDER BY TradeDate) * 100 AS pct_change
FROM StockPrices
ORDER BY StockSymbol, TradeDate;
```

### 6.3 Статистика доходности портфелей

```sql
SELECT 
    PortfolioName,
    MonthYear,
    MonthlyReturn,
    -- Ранжирование портфелей по доходности в месяц
    RANK() OVER (PARTITION BY MonthYear ORDER BY MonthlyReturn DESC) AS monthly_rank,
    -- Процентиль портфеля
    PERCENT_RANK() OVER (PARTITION BY MonthYear ORDER BY MonthlyReturn) * 100 AS percentile,
    -- Квартиль (1-4)
    NTILE(4) OVER (PARTITION BY MonthYear ORDER BY MonthlyReturn) AS return_quartile,
    -- Средняя доходность в месяц
    AVG(MonthlyReturn) OVER (PARTITION BY MonthYear) AS monthly_avg
FROM PortfolioPerformance
ORDER BY MonthYear DESC, monthly_rank;
```

### 6.4 Обнаружение аномалий в торговле

```sql
SELECT 
    ClientID,
    ClientName,
    TransactionDate,
    TransactionAmount,
    -- Среднее значение за последние 30 дней
    AVG(TransactionAmount) OVER (
        PARTITION BY ClientID 
        ORDER BY TransactionDate
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS avg_30days,
    -- Стандартное отклонение (приблизительное)
    STDEV(TransactionAmount) OVER (
        PARTITION BY ClientID 
        ORDER BY TransactionDate
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS stdev_30days,
    CASE 
        WHEN TransactionAmount > 
            AVG(TransactionAmount) OVER (
                PARTITION BY ClientID 
                ORDER BY TransactionDate
                ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
            ) * 1.5
        THEN 'Anomaly - High'
        ELSE 'Normal'
    END AS anomaly_flag
FROM Transactions
ORDER BY ClientID, TransactionDate;
```

## 7. Оптимизация оконных функций

### 7.1 Рекомендации по производительности

1. **Используйте PARTITION BY** - уменьшает размер окна
2. **Минимизируйте ORDER BY** - сортировка дорогая операция
3. **Избегайте вложенных оконных функций** - используйте CTE вместо этого
4. **Индексируйте колонки в PARTITION BY и ORDER BY**
5. **Старайтесь избежать ROWS BETWEEN UNBOUNDED** с большими наборами данных

### 7.2 Примеры оптимизации

```sql
-- ❌ Неоптимально: вложенные оконные функции
SELECT 
    TOP 10
    ClientID,
    (LAG(SUM(Amount)) OVER (ORDER BY Date)) AS prev_sum
FROM Transactions
GROUP BY ClientID;

-- ✅ Оптимально: используйте CTE
WITH DailySums AS (
    SELECT 
        Date,
        ClientID,
        SUM(Amount) AS daily_sum
    FROM Transactions
    GROUP BY Date, ClientID
)
SELECT 
    TOP 10
    ClientID,
    LAG(daily_sum) OVER (ORDER BY Date) AS prev_sum
FROM DailySums;
```

## 8. Важные замечания

1. **Все функции, использующие ORDER BY, требуют окна** - не используйте без OVER()
2. **PARTITION BY означает отдельное окно для каждого значения**
3. **NULL значения в PARTITION BY создают отдельное окно для NULL**
4. **Оконные функции выполняются в конце SELECT, после WHERE и GROUP BY**
5. **Нельзя использовать оконные функции в WHERE, но можно в HAVING**

---

**Резюме:** Оконные функции - мощный инструмент для анализа данных, позволяющий вычислять агреегаты без физического группирования строк. Они незаменимы для финансового анализа, расчета трендов и обнаружения аномалий.
