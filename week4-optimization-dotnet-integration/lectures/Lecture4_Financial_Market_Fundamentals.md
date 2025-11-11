# Лекция 4. Основы финансовых рынков и аналитика в SQL

## Цели занятия

- Познакомиться с основными инструментами финансовых рынков: акциями, облигациями, деривативами.
- Понять принцип формирования портфелей и диверсификации.
- Рассчитать ключевые метрики: доходность, риск, волатильность, Value at Risk.
- Научиться выполнять финансовые расчёты в SQL Server для отчётности и аналитики.

## 1. Инструменты финансового рынка

| Тип инструмента | Описание | Особенности обработки данных |
|-----------------|----------|-------------------------------|
| **Акции** | Доля в капитале компании, торгуется на бирже | Высокая волатильность, анализируется по тиковым/дневным котировкам |
| **Облигации** | Долговой инструмент, фиксированный или плавающий купон | Важны даты погашения, купонный доход, рейтинг |
| **ETF / Индексные фонды** | Набор активов, следит за индексом | Распределение рисков, анализируется по структуре пайпа |
| **Деривативы (фьючерсы, опционы)** | Контракты на будущие поставки/цены | Хеджирование, расчёт маржинальных требований |
| **Депозиты, денежный рынок** | Низкорискованные инструменты | Используются как «cash» для балансировки портфеля |

## 2. Понимание портфеля и диверсификации

- **Портфель** — набор активов с целевыми весами и стратегией (growth, value, income).
- **Диверсификация** снижает несистематический риск: распределение по классам активов, секторам, географии.
- **Asset Allocation** — ключевое решение: 80% успеха зависит от правильного распределения активов.

### 2.1. Структура таблиц

```sql
CREATE TABLE dbo.Portfolios (
    PortfolioId   INT PRIMARY KEY,
    PortfolioName NVARCHAR(100),
    Strategy      NVARCHAR(50),
    BaseCurrency  CHAR(3)
);

CREATE TABLE dbo.PortfolioHoldings (
    PortfolioId   INT,
    Symbol        NVARCHAR(12),
    AssetClass    NVARCHAR(20),
    Weight        DECIMAL(9,6),
    Constraint PK_PortfolioHoldings PRIMARY KEY (PortfolioId, Symbol)
);
```

## 3. Метрики портфеля

### 3.1. Доходность (Return)

- **Простая доходность**: `(Price_t - Price_{t-1}) / Price_{t-1}`.
- **Геометрическая (кумулятивная)**: `Π(1 + r_i) - 1`.

```sql
WITH Prices AS (
    SELECT
        Symbol,
        TradeDate,
        ClosingPrice,
        LAG(ClosingPrice) OVER (PARTITION BY Symbol ORDER BY TradeDate) AS PrevPrice
    FROM dbo.DailyPrices
)
SELECT
    Symbol,
    TradeDate,
    (ClosingPrice - PrevPrice) / PrevPrice AS DailyReturn
FROM Prices
WHERE PrevPrice IS NOT NULL;
```

### 3.2. Риск (Standard Deviation)

```sql
SELECT
    Symbol,
    SQRT(VARP(DailyReturn)) AS DailyVolatility,
    SQRT(VARP(DailyReturn) * 252) AS AnnualizedVolatility
FROM dbo.DailyReturns
GROUP BY Symbol;
```

### 3.3. Корреляция

```sql
SELECT
    a.Symbol AS SymbolA,
    b.Symbol AS SymbolB,
    SUM((a.DailyReturn - avgA.AvgReturn) * (b.DailyReturn - avgB.AvgReturn)) /
    (SQRT(SUM(POWER(a.DailyReturn - avgA.AvgReturn, 2))) *
     SQRT(SUM(POWER(b.DailyReturn - avgB.AvgReturn, 2)))) AS Correlation
FROM dbo.DailyReturns a
JOIN dbo.DailyReturns b
    ON a.TradeDate = b.TradeDate AND a.Symbol < b.Symbol
JOIN (
    SELECT Symbol, AVG(DailyReturn) AS AvgReturn FROM dbo.DailyReturns GROUP BY Symbol
) avgA ON avgA.Symbol = a.Symbol
JOIN (
    SELECT Symbol, AVG(DailyReturn) AS AvgReturn FROM dbo.DailyReturns GROUP BY Symbol
) avgB ON avgB.Symbol = b.Symbol
GROUP BY a.Symbol, b.Symbol, avgA.AvgReturn, avgB.AvgReturn;
```

### 3.4. Value at Risk (VaR)

- **Historical VaR**: сортируем доходности, берём процентиль (например, 5%).
- **Parametric VaR**: `z * σ * √t`, где `z` — квантиль нормального распределения.

```sql
SELECT TOP (1) WITH TIES
    PortfolioId,
    DailyReturn
FROM dbo.PortfolioReturns
WHERE TradeDate BETWEEN '2024-01-01' AND '2024-03-31'
ORDER BY DailyReturn ASC
OFFSET (SELECT COUNT(*) * 0.05 FROM dbo.PortfolioReturns WHERE TradeDate BETWEEN '2024-01-01' AND '2024-03-31') ROWS;
```

## 4. Примеры финансовых расчётов в SQL

### 4.1. Расчёт NAV (Net Asset Value)

```sql
SELECT
    p.PortfolioId,
    pr.TradeDate,
    SUM(pr.MarketValue) AS NetAssetValue
FROM dbo.PortfolioPositions pr
JOIN dbo.Portfolios p ON p.PortfolioId = pr.PortfolioId
GROUP BY p.PortfolioId, pr.TradeDate;
```

### 4.2. Пересчёт в базовую валюту

```sql
SELECT
    nav.PortfolioId,
    nav.TradeDate,
    SUM(nav.MarketValue * fx.RateToBase) AS NetAssetValueBase
FROM dbo.PortfolioNav nav
JOIN dbo.FxRates fx
    ON fx.Currency = nav.Currency AND fx.RateDate = nav.TradeDate
GROUP BY nav.PortfolioId, nav.TradeDate;
```

### 4.3. Сравнение портфелей

```sql
WITH PortfolioPerformance AS (
    SELECT
        PortfolioId,
        TradeDate,
        SUM(MarketValue) AS NAV,
        LAG(SUM(MarketValue)) OVER (PARTITION BY PortfolioId ORDER BY TradeDate) AS PrevNAV
    FROM dbo.PortfolioPositions
    GROUP BY PortfolioId, TradeDate
)
SELECT
    PortfolioId,
    TradeDate,
    (NAV - PrevNAV) / PrevNAV AS DailyReturn
FROM PortfolioPerformance
WHERE PrevNAV IS NOT NULL;
```

## 5. Использование данных в отчётности

1. **ETL**: выгрузка биржевых данных, очистка, агрегация (см. Практическое задание 4).
2. **Отчётность**: ежедневные/недельные отчёты по доходности, удержаниям, рискам.
3. **Dashboards**: Power BI, Tableau, Excel — подключаются к представлениям или API.
4. **Alerts**: оповещения о просадках, превышении VaR, отклонении от таргетовых весов.

## 6. Контрольный список

- [ ] Разобрались с типами активов и их особенностями.
- [ ] Понимаете структуру портфелей и значение диверсификации.
- [ ] Рассчитали доходность, волатильность, корреляцию и VaR в SQL.
- [ ] Сформировали отчёт по NAV и сравнили портфели между собой.
- [ ] Подготовили данные для дашбордов и оповещений.

Финансовая аналитика требует точности, консистентности и прозрачной методологии расчётов. SQL Server предоставляет инструменты для воспроизводимых расчётов и аудита, что критично для соблюдения регуляторных требований и доверия инвесторов.
