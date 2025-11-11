# Практическая задача 1: Оконные функции для анализа данных

## Описание

Эта задача ориентирована на использование оконных функций для анализа финансовых данных портфелей и цен акций.

## Требуемые таблицы

```sql
-- StockPrices - историческая информация о ценах акций
-- Columns: StockID, StockSymbol, TradeDate, OpenPrice, ClosePrice, HighPrice, LowPrice, Volume

-- PortfolioHoldings - акции в портфелях
-- Columns: HoldingID, PortfolioID, StockSymbol, Quantity, AcquisitionPrice, CurrentPrice

-- Portfolios - портфели инвестиций
-- Columns: PortfolioID, PortfolioName, ClientID, CreationDate, TotalValue

-- Clients - информация о клиентах
-- Columns: ClientID, ClientName, InvestmentAmount
```

## Задача 1.1: Расчет скользящего среднего цены акций

**Цель:** Рассчитать 20-дневное скользящее среднее (SMA) для каждой акции.

**Требования:**
- Для каждой акции вычислить скользящее среднее за последние 20 дней
- Показать текущую цену, SMA и отклонение от среднего
- Отсортировать по дате торговли в порядке возрастания
- Отфильтровать акции, которые торгуются выше SMA

**Ожидаемый результат:**

| StockSymbol | TradeDate | ClosePrice | SMA_20 | DaysCount | Deviation | Status |
|-------------|-----------|-----------|--------|-----------|-----------|--------|
| AAPL | 2024-01-20 | 150.50 | 148.32 | 20 | 2.18 | Above |
| AAPL | 2024-01-21 | 149.75 | 148.45 | 20 | 1.30 | Above |
| MSFT | 2024-01-20 | 320.00 | 315.20 | 20 | 4.80 | Above |

**Заготовка запроса:**

```sql
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    -- Добавить SMA вычисление
    COUNT(*) OVER (PARTITION BY StockSymbol ORDER BY TradeDate ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS DaysCount,
    -- Добавить отклонение
    -- Добавить статус
FROM StockPrices
-- Условие для фильтрации
ORDER BY StockSymbol, TradeDate DESC;
```

## Задача 1.2: Определение ранжирования портфелей по доходности

**Цель:** Ранжировать портфели по месячной доходности.

**Требования:**
- Рассчитать доходность портфеля за текущий месяц
- Ранжировать портфели по доходности в процентах (RANK и DENSE_RANK)
- Рассчитать процентиль каждого портфеля
- Определить квартиль (NTILE на 4)
- Показать топ 10 портфелей

**Ожидаемый результат:**

| PortfolioName | MonthlyReturn | Rank | DenseRank | Percentile | Quartile |
|---------------|---------------|------|-----------|-----------|----------|
| Portfolio A | 12.50 | 1 | 1 | 95 | 4 |
| Portfolio B | 12.50 | 1 | 1 | 95 | 4 |
| Portfolio C | 11.30 | 3 | 2 | 85 | 4 |

**Заготовка запроса:**

```sql
WITH MonthlyReturnCalc AS (
    SELECT 
        PortfolioID,
        PortfolioName,
        -- Рассчитать месячную доходность
        MONTH(GETDATE()) AS CurrentMonth
    FROM Portfolios
    WHERE YEAR(CreationDate) = YEAR(GETDATE())
)
SELECT 
    TOP 10
    PortfolioName,
    MonthlyReturn,
    RANK() OVER (ORDER BY MonthlyReturn DESC) AS Rank,
    -- Добавить DENSE_RANK
    -- Добавить PERCENT_RANK
    -- Добавить NTILE
FROM MonthlyReturnCalc
ORDER BY Rank;
```

## Задача 1.3: Расчет нарастающего итога (Cumulative Sum)

**Цель:** Рассчитать сумму с нарастающим итогом для портфеля.

**Требования:**
- Для каждого портфеля рассчитать кумулятивную сумму действий (покупок/продаж)
- Показать дату действия, сумму, нарастающий итог и процент от финального итога
- Определить, на какой день было достигнуто 50% от итогового значения
- Отсортировать по портфелю и дате

**Ожидаемый результат:**

| PortfolioName | ActionDate | TransactionAmount | CumulativeAmount | PercentOfTotal | HalfwayReached |
|---------------|-----------|-----------------|-----------------|----------------|----------------|
| Portfolio A | 2024-01-01 | 10000.00 | 10000.00 | 5.00 | No |
| Portfolio A | 2024-01-05 | 15000.00 | 25000.00 | 12.50 | No |
| Portfolio A | 2024-01-10 | 20000.00 | 45000.00 | 22.50 | No |
| Portfolio A | 2024-02-01 | 135000.00 | 180000.00 | 90.00 | Yes |

**Заготовка запроса:**

```sql
WITH ActionData AS (
    SELECT 
        p.PortfolioID,
        p.PortfolioName,
        pa.ActionDate,
        pa.TransactionAmount
        -- Получить финальный итог для расчета процента
    FROM Portfolios p
    INNER JOIN PortfolioActions pa ON p.PortfolioID = pa.PortfolioID
    WHERE p.PortfolioID IN (SELECT TOP 5 PortfolioID FROM Portfolios ORDER BY TotalValue DESC)
)
SELECT 
    PortfolioName,
    ActionDate,
    TransactionAmount,
    -- Добавить нарастающий итог
    -- Добавить процент от итога
    CASE 
        WHEN cumulative >= total * 0.5 THEN 'Yes'
        ELSE 'No'
    END AS HalfwayReached
FROM ActionData
ORDER BY PortfolioName, ActionDate;
```

## Задача 1.4: Обнаружение экстремальных значений

**Цель:** Определить дни с необычными ценовыми движениями.

**Требования:**
- Для каждой акции определить стандартное отклонение цены за последние 30 дней
- Выявить дни, когда цена отклоняется на 2+ стандартных отклонения
- Показать текущую цену, среднюю цену, стандартное отклонение и флаг аномалии
- Отсортировать по величине отклонения в порядке убывания

**Ожидаемый результат:**

| StockSymbol | TradeDate | ClosePrice | AvgPrice | StdDev | Deviation | AnomalyType |
|-------------|-----------|-----------|----------|--------|-----------|-------------|
| AAPL | 2024-01-15 | 165.00 | 150.00 | 5.50 | 2.73 | Strong Spike Up |
| MSFT | 2024-01-16 | 295.00 | 320.00 | 8.00 | 3.13 | Strong Spike Down |

**Заготовка запроса:**

```sql
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    AVG(ClosePrice) OVER (
        PARTITION BY StockSymbol 
        ORDER BY TradeDate 
        -- Определить окно для последних 30 дней
    ) AS AvgPrice,
    STDEV(ClosePrice) OVER (
        -- Аналогичное окно
    ) AS StdDev,
    -- Рассчитать количество стандартных отклонений
    -- Определить тип аномалии
FROM StockPrices
-- WHERE для фильтрации только аномалий (deviation > 2)
ORDER BY -- сортировка по величине отклонения
;
```

## Задача 1.5: Анализ лидеров и аутсайдеров

**Цель:** Определить активы-лидеры и активы-аутсайдеры по производительности.

**Требования:**
- Рассчитать прибыль/убытки по каждому активу в портфеле
- Ранжировать активы по прибыльности (RANK, DENSE_RANK, ROW_NUMBER)
- Определить НА сколько лучше/хуже каждый актив по сравнению с соседним
- Показать топ 3 лидера и топ 3 аутсайдера по портфелю

**Ожидаемый результат:**

| PortfolioName | StockSymbol | ProfitLoss | PnLPercent | Rank | NextAssetProfit | Difference |
|---------------|-------------|-----------|-----------|------|-----------------|-----------|
| Portfolio A | AAPL | 5000.00 | 15.50 | 1 | 3000.00 | 2000.00 |
| Portfolio A | MSFT | 3000.00 | 12.30 | 2 | 1000.00 | 2000.00 |
| Portfolio A | GOOG | 1000.00 | 8.90 | 3 | NULL | NULL |

**Заготовка запроса:**

```sql
WITH PortfolioAssetPerformance AS (
    SELECT 
        p.PortfolioID,
        p.PortfolioName,
        ph.StockSymbol,
        -- Рассчитать прибыль/убытки
        -- Рассчитать процент прибыли
    FROM Portfolios p
    INNER JOIN PortfolioHoldings ph ON p.PortfolioID = ph.PortfolioID
),
RankedAssets AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY PortfolioID ORDER BY ProfitLoss DESC) AS RowNum,
        RANK() OVER (PARTITION BY PortfolioID ORDER BY ProfitLoss DESC) AS Rank,
        LEAD(ProfitLoss) OVER (PARTITION BY PortfolioID ORDER BY ProfitLoss DESC) AS NextAssetProfit
    FROM PortfolioAssetPerformance
)
SELECT * FROM RankedAssets
WHERE RowNum <= 3 OR RowNum >= (SELECT MAX(RowNum) - 2 FROM RankedAssets)
ORDER BY PortfolioID, Rank;
```

## Тестирование

```sql
-- 1. Убедитесь, что все оконные функции работают
-- 2. Проверьте, что данные правильно партиционированы
-- 3. Проверьте граничные случаи (первые и последние дни)
-- 4. Сравните результаты с альтернативными вычислениями
-- 5. Проверьте производительность на больших наборах данных

-- Пример: проверка скользящего среднего
SELECT 
    StockSymbol,
    TradeDate,
    ClosePrice,
    AVG(ClosePrice) OVER (
        PARTITION BY StockSymbol 
        ORDER BY TradeDate 
        ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) AS SMA_20,
    COUNT(*) OVER (
        PARTITION BY StockSymbol 
        ORDER BY TradeDate 
        ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) AS DaysInWindow
FROM StockPrices
WHERE StockSymbol = 'AAPL'
ORDER BY TradeDate DESC
LIMIT 30;
```

## Дополнительные вызовы

1. **Экспоненциальное скользящее среднее (EMA)** - реализовать расчет EMA вместо SMA
2. **Bollinger Bands** - добавить расчет верхней и нижней полосы (SMA ± 2*STDEV)
3. **Относительный индекс силы (RSI)** - рассчитать RSI на основе доходностей
4. **MACD** - реализовать расчет MACD (Moving Average Convergence Divergence)

## Оптимизация

```sql
-- Рекомендация: используйте индексы для лучшей производительности
CREATE INDEX idx_stock_date ON StockPrices(StockSymbol, TradeDate);
CREATE INDEX idx_portfolio_asset ON PortfolioHoldings(PortfolioID, StockSymbol);
```

---

**Мудрость:** Оконные функции - это мощный инструмент финансового анализа, позволяющий выявлять тренды и аномалии в больших наборах данных.
