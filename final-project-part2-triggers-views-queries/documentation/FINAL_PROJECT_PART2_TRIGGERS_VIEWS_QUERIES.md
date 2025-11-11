# Итоговый проект. Часть 2 — Триггеры, Представления и Оптимизированные Запросы

Часть 2 финального проекта системы управления портфелями ценных бумаг включает полный набор триггеров для аудита и валидации, четыре аналитических представления и пять оптимизированных запросов с использованием продвинутых техник SQL.

## Структура скриптов

| Файл | Назначение |
|------|------------|
| `scripts/final_project_part2_triggers.sql` | Создание трех триггеров для аудита, валидации и обновления значений портфеля. |
| `scripts/final_project_part2_views.sql` | Создание четырех представлений для анализа портфелей и ценных бумаг. |
| `scripts/final_project_part2_optimized_queries.sql` | Создание пяти оптимизированных запросов с использованием окон, CTE и сложных JOINов. |
| `scripts/final_project_part2_examples.sql` | Примеры использования триггеров, представлений и запросов с результатами. |

> Рекомендуемый порядок выполнения: `triggers` → `views` → `optimized_queries` → `examples`.

---

## Раздел 1: Триггеры

Три триггера обеспечивают аудит изменений, валидацию данных и автоматическое обновление значений портфеля.

### 1.1 Триггер: trg_Transactions_Audit

**Тип:** `AFTER INSERT, UPDATE, DELETE` на таблице `Transactions`

**Назначение:** Логирование всех изменений в таблице Transactions в Audit_Log

**Логика:**
- При INSERT: Записывает новые значения транзакции
- При UPDATE: Записывает оба значения (старое и новое)
- При DELETE: Записывает старые значения перед удалением
- Каждое действие помечается типом операции, временем и пользователем

**Пример использования:**

```sql
-- Триггер автоматически срабатывает при вставке
INSERT INTO dbo.Transactions (PortfolioID, SecurityID, Quantity, Price, Type, Notes)
VALUES (1, 1, 100, 150.50, N'BUY', N'Покупка акций');

-- Проверка логирования
SELECT TOP 5 LogID, TableName, Action, ChangeDate, ExecutedBy
FROM dbo.Audit_Log
WHERE TableName = 'Transactions'
ORDER BY LogID DESC;
```

**XML-формат логирования:** Старые и новые значения сохраняются в XML-формате для полной истории изменений.

---

### 1.2 Триггер: trg_UpdatePortfolioValue_OnQuoteChange

**Тип:** `AFTER INSERT, UPDATE` на таблице `Quotes`

**Назначение:** Автоматическое обновление стоимости портфелей при изменении котировок

**Логика:**
1. При изменении котировки определяются все затронутые ценные бумаги
2. Находятся все портфели, содержащие эти ценные бумаги
3. Регистрируется событие в Audit_Log для отслеживания
4. В производственной среде здесь была бы вызвана процедура пересчета портфеля

**Оптимизация:** Использует INSERTED таблицу для получения только измененных котировок

**Пример использования:**

```sql
-- При добавлении новой котировки триггер автоматически срабатывает
INSERT INTO dbo.Quotes (SecurityID, Price, QuoteDate, Volume, Source)
VALUES (1, 155.75, SYSUTCDATETIME(), 1000000, N'Market Data Provider');

-- Проверка логирования обновления
SELECT TOP 3 LogID, TableName, Action, ChangeDate, NewValue
FROM dbo.Audit_Log
WHERE TableName = 'Quotes' AND Action = 'PRICE_UPDATE'
ORDER BY LogID DESC;
```

**Оптимизация производительности:**
- Использование INSERTED таблицы предотвращает сканирование всей таблицы Quotes
- Применение дельта-логики для определения затронутых портфелей
- Возможность асинхронной обработки в фоновом режиме

---

### 1.3 Триггер: trg_ValidateTransaction

**Тип:** `INSTEAD OF INSERT` на таблице `Transactions`

**Назначение:** Валидация данных транзакции перед добавлением в БД

**Проверяемые условия:**
1. **Существование портфеля** — PortfolioID должен существовать в Portfolios
2. **Существование ценной бумаги** — SecurityID должен существовать в Securities
3. **Положительное количество** — Quantity > 0
4. **Положительная цена** — Price > 0
5. **Достаточное количество для SELL** — Для операций SELL проверяется наличие достаточного количества ценных бумаг

**Логика обработки:**
- При успешной валидации — транзакция вставляется
- При ошибке — транзакция отклоняется, ошибка логируется в Audit_Log, вызывается RAISERROR

**Пример использования:**

```sql
-- Успешная вставка (валидна)
BEGIN TRY
    INSERT INTO dbo.Transactions (PortfolioID, SecurityID, Quantity, Price, Type, Notes)
    VALUES (1, 1, 100, 150.50, N'BUY', N'Валидная транзакция');
    PRINT 'Транзакция успешно добавлена';
END TRY
BEGIN CATCH
    PRINT 'ОШИБКА: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Неудачная попытка (неверный PortfolioID)
BEGIN TRY
    INSERT INTO dbo.Transactions (PortfolioID, SecurityID, Quantity, Price, Type, Notes)
    VALUES (9999, 1, 100, 150.50, N'BUY', N'Невалидный портфель');
END TRY
BEGIN CATCH
    PRINT 'Ожидаемая ошибка: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Проверка логирования отклонений
SELECT TOP 5 LogID, TableName, Action, OldValue AS ErrorMessage, ChangeDate
FROM dbo.Audit_Log
WHERE TableName = 'Transactions' AND Action = 'INSERT_REJECTED'
ORDER BY LogID DESC;
```

---

## Раздел 2: Представления (Views)

Четыре представления предоставляют различные углы зрения на данные портфелей и ценных бумаг.

### 2.1 Представление: vw_PortfolioSummary

**Назначение:** Краткий обзор каждого портфеля с ключевыми метриками

**Поля:**
- `PortfolioID` — ID портфеля
- `PortfolioName` — Название портфеля
- `Owner` — Владелец
- `TotalValue` — Текущая стоимость портфеля
- `SecurityCount` — Количество различных ценных бумаг
- `PositionCount` — Всего позиций (транзакций)
- `LastUpdate` — Дата последнего обновления информации
- `CreatedDate` — Дата создания портфеля

**Использование:**

```sql
SELECT
    PortfolioID,
    PortfolioName,
    Owner,
    TotalValue,
    SecurityCount
FROM dbo.vw_PortfolioSummary
ORDER BY TotalValue DESC;
```

**Типичное применение:** Быстрый просмотр портфелей, рейтинг по стоимости, мониторинг активных портфелей.

---

### 2.2 Представление: vw_PortfolioComposition

**Назначение:** Детальный состав портфеля с процентным распределением

**Поля:**
- `PortfolioID` — ID портфеля
- `SecurityID` — ID ценной бумаги
- `Ticker` — Тикер бумаги
- `Name` — Название бумаги
- `Type` — Тип (Stock, Bond, ETF и т.д.)
- `CurrentPrice` — Текущая цена
- `Quantity` — Количество в портфеле
- `TotalValue` — Стоимость позиции
- `Percentage` — Доля в портфеле (%)

**Использование:**

```sql
-- Просмотр состава конкретного портфеля
SELECT
    Ticker,
    Name,
    Quantity,
    CurrentPrice,
    TotalValue,
    CAST(Percentage AS DECIMAL(5,2)) AS Percentage
FROM dbo.vw_PortfolioComposition
WHERE PortfolioID = 1
ORDER BY TotalValue DESC;
```

**Типичное применение:** Анализ структуры портфеля, балансировка, определение основных позиций.

---

### 2.3 Представление: vw_PortfolioPerformance

**Назначение:** Оценка производительности портфеля с расчетом прибыли и ROI

**Поля:**
- `PortfolioID` — ID портфеля
- `PortfolioName` — Название
- `Owner` — Владелец
- `CurrentValue` — Текущая стоимость портфеля
- `TotalInvestment` — Общая сумма инвестиций
- `ProfitLoss` — Абсолютная прибыль/убыток
- `ReturnPercentage` — Процент доходности (ROI)
- `TransactionCount` — Количество сделок
- `LastTransactionDate` — Дата последней сделки

**Использование:**

```sql
-- Топ портфелей по доходности
SELECT TOP 10
    PortfolioID,
    PortfolioName,
    Owner,
    CAST(ProfitLoss AS DECIMAL(12,2)) AS ProfitLoss,
    CAST(ReturnPercentage AS DECIMAL(8,2)) AS ROI_Percentage
FROM dbo.vw_PortfolioPerformance
WHERE TotalInvestment > 0
ORDER BY ReturnPercentage DESC;
```

**Формулы:**
- ROI (%) = ((CurrentValue - TotalInvestment + RealizedGainLoss) / TotalInvestment) × 100
- ProfitLoss = (CurrentValue - TotalInvestment) + RealizedGainLoss

**Типичное применение:** Отчеты о производительности, оценка успеха стратегий инвестирования.

---

### 2.4 Представление: vw_SecurityRanking

**Назначение:** Ранжирование ценных бумаг по активности и популярности

**Поля:**
- `SecurityID` — ID ценной бумаги
- `Ticker` — Тикер
- `Name` — Название
- `Type` — Тип инструмента
- `Sector` — Сектор
- `AvgPrice` — Средняя цена
- `MinPrice` — Минимальная цена
- `MaxPrice` — Максимальная цена
- `TradeCount` — Количество сделок
- `PortfoliosContaining` — Количество портфелей, содержащих бумагу
- `TotalVolume` — Общий объем торговли
- `LastQuoteDate` — Дата последней котировки

**Использование:**

```sql
-- Топ 10 самых активно торгуемых бумаг
SELECT TOP 10
    Ticker,
    Name,
    Type,
    Sector,
    CAST(AvgPrice AS DECIMAL(10,2)) AS AvgPrice,
    TradeCount,
    PortfoliosContaining
FROM dbo.vw_SecurityRanking
WHERE TradeCount > 0
ORDER BY TradeCount DESC;
```

**Типичное применение:** Анализ торговой активности, выявление популярных инструментов, диверсификация портфелей.

---

## Раздел 3: Оптимизированные Запросы

Пять запросов демонстрируют продвинутые техники SQL для анализа больших объемов данных.

### 3.1 Запрос с оконными функциями: Moving Average

**Назначение:** Расчет скользящих средних для анализа тренда цен

**Представление:** `vw_SecurityMovingAverage`

**Используемые техники:**
- `ROW_NUMBER()` — Нумерация строк для сортировки
- `LAG()` — Получение значения из предыдущей строки (предыдущая цена)
- `AVG() OVER()` — Оконная функция для вычисления скользящего среднего

**Расчетные поля:**
- `MA7` — 7-дневное скользящее среднее
- `MA30` — 30-дневное скользящее среднее
- `PreviousPrice` — Цена из предыдущего дня
- `PricePctChange` — Изменение цены в процентах
- `PriceTrendVsMA7` — Соотношение цены к MA7 (ABOVE/BELOW/AT)

**Использование:**

```sql
-- Анализ последних 30 дней котировок
SELECT TOP 30
    Ticker,
    Name,
    QuoteDate,
    Price,
    CAST(MA7 AS DECIMAL(10,2)) AS MA7,
    CAST(MA30 AS DECIMAL(10,2)) AS MA30,
    PriceTrendVsMA7,
    CAST(PricePctChange AS DECIMAL(8,4)) AS PricePctChange
FROM dbo.vw_SecurityMovingAverage
WHERE RowNum <= 30
ORDER BY Ticker, QuoteDate DESC;
```

**Применение:** Теханализ, определение трендов, торговые сигналы.

---

### 3.2 Запрос с CTE: Portfolio & Transaction Hierarchy

**Назначение:** Иерархический анализ портфелей с многоуровневой агрегацией

**Представление:** `vw_PortfolioTransactionHierarchy`

**Структура CTE:**
1. **PortfolioBase** — Базовая информация о портфелях
2. **TransactionDetails** — Детали трансформаций (BUY/SELL подсчет, суммы)
3. **PortfolioWithMetrics** — Объединение данных с расчетом ROI

**Используемые техники:**
- Множественные CTE для пошагового расчета
- Условные агрегации (CASE при SUM)
- Групповые операции для иерархии

**Пример использования:**

```sql
-- Анализ портфелей с метриками
SELECT
    PortfolioID,
    PortfolioName,
    SecurityCount,
    BuyCount,
    SellCount,
    CAST(TotalInvested AS DECIMAL(12,2)) AS TotalInvested,
    CAST(ROI_Percentage AS DECIMAL(8,2)) AS ROI_Percentage
FROM dbo.vw_PortfolioTransactionHierarchy
ORDER BY ROI_Percentage DESC;
```

**Преимущества:**
- Четкая структура для пошагового расчета сложных метрик
- Удобство для разработки и тестирования
- Экономия памяти через использование CTE вместо временных таблиц

---

### 3.3 Запрос с JOINами: Complete Portfolio Information

**Назначение:** Получение полной информации о портфеле со всеми связанными данными

**Представление:** `vw_CompletePortfolioInfo`

**Используемые JOINы:**
- `Portfolios → Transactions` (LEFT JOIN)
- `Transactions → Securities` (LEFT JOIN)
- `Securities → Quotes` (LEFT JOIN для последней котировки)
- `Transactions → Audit_Log` (LEFT JOIN для логирования)

**Поля результата:**
- Информация о портфеле (ID, название, владелец, дата создания)
- Информация о ценной бумаге (тикер, название, тип, сектор)
- Информация о транзакции (дата, тип, количество, цена)
- Информация о котировке (текущая цена, дата котировки)
- Расчетные поля (текущая стоимость позиции, нереализованная прибыль)
- Информация об аудите

**Использование:**

```sql
-- Полная информация о портфеле
SELECT TOP 20
    PortfolioName,
    Ticker,
    SecurityName,
    TransactionType,
    Quantity,
    CAST(TransactionPrice AS DECIMAL(10,2)) AS TransactionPrice,
    CAST(CurrentPrice AS DECIMAL(10,2)) AS CurrentPrice,
    CAST(UnrealizedGainLoss AS DECIMAL(12,2)) AS UnrealizedGainLoss
FROM dbo.vw_CompletePortfolioInfo
WHERE Ticker IS NOT NULL
ORDER BY PortfolioID, TransactionDate DESC;
```

**Применение:** Комплексные отчеты, экспорт данных, детальный аудит портфелей.

---

### 3.4 Запрос для больших данных: Batch Processing

**Назначение:** Эффективная обработка больших объемов данных (100k+ транзакций)

**Процедура:** `sp_BatchProcessTransactions`

**Параметры:**
- `@BatchSize` — Размер батча (по умолчанию 10000 строк)
- `@MaxBatches` — Максимальное количество батчей (по умолчанию 100)

**Логика:**
1. Создание временной таблицы с ROW_NUMBER() для разбиения на батчи
2. Цикл обработки батчей по заданному размеру
3. Для каждого батча выполняется обработка (в примере — расчет стоимостей)
4. Логирование прогресса в Audit_Log
5. Вывод статистики

**Использование:**

```sql
-- Обработка всех транзакций батчами
EXEC dbo.sp_BatchProcessTransactions 
    @BatchSize = 5000,      -- Обрабатывать по 5000 транзакций
    @MaxBatches = 50;       -- Максимум 50 батчей

/* Результат:
   Starting batch processing of 250000 transactions...
   Batch 1 processed: 5000 transactions. Total: 5000
   Batch 2 processed: 5000 transactions. Total: 10000
   ...
   Batch processing completed!
   Total batches: 50
   Total transactions processed: 250000
   Duration (ms): 15432
*/
```

**Оптимизация производительности:**
- Предотвращение блокировок через обработку небольших порций
- Использование ROW_NUMBER() вместо курсоров
- Минимизация требований к памяти
- Логирование для мониторинга прогресса

---

### 3.5 Запрос с подзапросами: TOP Portfolios by ROI

**Назначение:** Выявление лучших портфелей по доходности

**Представление:** `vw_TopPortfoliosByROI`

**Структура CTE:**
1. **PortfolioROI** — Расчет ROI для каждого портфеля
2. **PortfolioRanked** — Ранжирование по ROI и выбор TOP 10

**Используемые техники:**
- Вложенные подзапросы для расчета максимальной котировки
- ROW_NUMBER() для ранжирования
- CASE для условного расчета ROI

**Использование:**

```sql
-- Топ 10 портфелей по доходности
SELECT
    ROI_Rank,
    PortfolioID,
    PortfolioName,
    Owner,
    CAST(TotalInvested AS DECIMAL(12,2)) AS TotalInvested,
    CAST(CurrentValue AS DECIMAL(12,2)) AS CurrentValue,
    CAST(TotalProfitLoss AS DECIMAL(12,2)) AS TotalProfitLoss,
    CAST(ROI_Percentage AS DECIMAL(8,2)) AS ROI_Percentage,
    DaysActive
FROM dbo.vw_TopPortfoliosByROI
ORDER BY ROI_Rank;
```

**Результат:**
```
ROI_Rank | PortfolioID | PortfolioName      | Owner    | ROI_Percentage | DaysActive
---------|-------------|-------------------|----------|----------------|----------
1        | 5           | Tech Growth Fund   | John Doe | 45.67          | 180
2        | 3           | Balanced Portfolio | Jane Sm  | 32.45          | 180
3        | 1           | Value Stocks       | Bob Jone | 28.90          | 90
...
```

**Применение:** Отчеты о производительности, бенчмаркинг, выявление успешных стратегий.

---

## Раздел 4: Анализ Performance

### 4.1 Execution Plans и Оптимизация

**Критические запросы для мониторинга:**

1. **vw_PortfolioComposition** — Использует CTE с множественными GROUP BY
   - Потенциальное узкое место: сканирование большого количества транзакций
   - Рекомендация: Добавить индекс на (PortfolioID, SecurityID)

2. **vw_SecurityMovingAverage** — Оконные функции с LAG/AVG
   - Потенциальное узкое место: сортировка больших наборов по датам
   - Рекомендация: Индекс на (SecurityID, QuoteDate DESC, Price)

3. **vw_CompletePortfolioInfo** — Множественные LEFT JOINы
   - Потенциальное узкое место: поиск максимальной котировки в подзапросе
   - Рекомендация: Использовать ROW_NUMBER() вместо MAX() с GROUP BY

### 4.2 Рекомендуемые Индексы

```sql
-- Индекс для улучшения производительности Moving Average
CREATE NONCLUSTERED INDEX IX_Quotes_SecurityID_QuoteDate_Price
ON dbo.Quotes (SecurityID, QuoteDate DESC, Price)
INCLUDE (Volume)
WHERE Price > 0;  -- Фильтрованный индекс

-- Индекс для улучшения расчетов ROI
CREATE NONCLUSTERED INDEX IX_Transactions_Type_PortfolioID
ON dbo.Transactions (Type, PortfolioID)
INCLUDE (Quantity, Price, SecurityID);

-- Индекс для аудит-логов
CREATE NONCLUSTERED INDEX IX_AuditLog_Action_ChangeDate
ON dbo.Audit_Log (Action, ChangeDate DESC)
WHERE Action IN ('INSERT_VALIDATED', 'INSERT_REJECTED');

-- Индекс для портфелей по дате создания
CREATE NONCLUSTERED INDEX IX_Portfolios_CreatedDate
ON dbo.Portfolios (CreatedDate DESC)
INCLUDE (Owner, Name);
```

### 4.3 Мониторинг Производительности

```sql
-- Запуск с включенной статистикой
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Ваш запрос здесь
SELECT * FROM dbo.vw_PortfolioSummary;

-- Результат включает информацию о:
-- - Table 'Transactions'. Scan count X, logical reads Y
-- - CPU time = Z ms, elapsed time = W ms
```

### 4.4 Потенциальные Узкие Места

| Узкое место | Причина | Решение |
|----------|---------|---------|
| Множественные LEFT JOINы | Декартово произведение | Использовать CTE для пошагового расчета |
| Оконные функции на больших таблицах | Сортировка и буферизация | Добавить индекс на колонки в PARTITION BY |
| Поиск MAX() в подзапросах | Сканирование всей таблицы | Использовать ROW_NUMBER() с последующей фильтрацией |
| Агрегирование по многим группам | Много GROUP BY операций | Разделить на несколько CTE |

---

## Раздел 5: Примеры Выполнения

### 5.1 Пример: Аудит транзакций

```sql
-- Вставка транзакции
INSERT INTO dbo.Transactions (PortfolioID, SecurityID, Quantity, Price, Type, Notes)
VALUES (1, 1, 100, 150.50, N'BUY', N'Test transaction');

-- Проверка логирования
SELECT TOP 1
    LogID,
    TableName,
    Action,
    ExecutedBy,
    ChangeDate
FROM dbo.Audit_Log
WHERE TableName = 'Transactions'
ORDER BY LogID DESC;

/*
Результат:
LogID | TableName    | Action | ExecutedBy       | ChangeDate
------|--------------|--------|------------------|------------------------
1001  | Transactions | INSERT | DOMAIN\UserName  | 2024-05-15 14:30:22.123
*/
```

### 5.2 Пример: Portfolio Composition

```sql
SELECT
    Ticker,
    Name,
    Quantity,
    CurrentPrice,
    TotalValue,
    CAST(Percentage AS DECIMAL(5,2)) AS Percentage
FROM dbo.vw_PortfolioComposition
WHERE PortfolioID = 1
ORDER BY TotalValue DESC;

/*
Результат:
Ticker | Name           | Quantity | CurrentPrice | TotalValue | Percentage
-------|----------------|----------|--------------|------------|----------
AAPL   | Apple Inc.     | 50       | 175.50       | 8775.00    | 35.50
MSFT   | Microsoft Corp | 30       | 310.25       | 9307.50    | 37.65
GOOGL  | Alphabet Inc.  | 15       | 140.80       | 2112.00    | 8.54
AMZN   | Amazon Inc.    | 10       | 175.25       | 1752.50    | 7.09
TSLA   | Tesla Inc.     | 25       | 245.30       | 6132.50    | 11.22
*/
```

### 5.3 Пример: Moving Average

```sql
SELECT TOP 5
    Ticker,
    QuoteDate,
    Price,
    CAST(MA7 AS DECIMAL(10,2)) AS MA7,
    CAST(MA30 AS DECIMAL(10,2)) AS MA30,
    PriceTrendVsMA7,
    CAST(PricePctChange AS DECIMAL(8,4)) AS DailyChange
FROM dbo.vw_SecurityMovingAverage
WHERE Ticker = 'AAPL'
ORDER BY QuoteDate DESC;

/*
Результат:
Ticker | QuoteDate  | Price  | MA7     | MA30    | PriceTrendVsMA7 | DailyChange
-------|------------|--------|---------|---------|-----------------|----------
AAPL   | 2024-05-15 | 175.50 | 172.80  | 170.25  | ABOVE_MA7       | 0.4250
AAPL   | 2024-05-14 | 174.76 | 172.35  | 169.95  | ABOVE_MA7       | -0.1250
AAPL   | 2024-05-13 | 175.18 | 171.95  | 169.75  | ABOVE_MA7       | 0.2100
AAPL   | 2024-05-12 | 174.81 | 171.50  | 169.50  | ABOVE_MA7       | -0.3300
AAPL   | 2024-05-11 | 175.39 | 171.10  | 169.35  | ABOVE_MA7       | 0.5600
*/
```

---

## Раздел 6: Рекомендации по Использованию

### 6.1 Когда использовать каждый триггер

| Триггер | Когда использовать | Когда избегать |
|---------|------------------|----------------|
| trg_Transactions_Audit | Всегда (требуется аудит) | Никогда |
| trg_UpdatePortfolioValue_OnQuoteChange | Для автоматического обновления цен | Если нужна ручная обработка |
| trg_ValidateTransaction | Для строгой валидации данных | Если необходима гибкость |

### 6.2 Когда использовать каждое представление

| Представление | Использование | Частота обновления |
|---------------|---------------|--------------------|
| vw_PortfolioSummary | Dashboard, быстрый просмотр | Реал-тайм |
| vw_PortfolioComposition | Анализ структуры, балансировка | При изменении транзакций |
| vw_PortfolioPerformance | Отчеты ROI, бенчмаркинг | Ежедневно |
| vw_SecurityRanking | Анализ активности, выбор инструментов | Еженедельно |

### 6.3 Производительность представлений

| Представление | Типичное время | Оптимизировано для |
|---------------|---------------|------------------|
| vw_PortfolioSummary | < 100 ms | Скорость |
| vw_PortfolioComposition | 200-500 ms | Точность |
| vw_PortfolioPerformance | 100-300 ms | Точность |
| vw_SecurityRanking | 300-800 ms | Полнота |

---

## Раздел 7: Вопросы и Ответы

**Q: Почему триггер trg_ValidateTransaction использует INSTEAD OF INSERT?**
A: Это позволяет нам полностью контролировать процесс вставки, выполняя валидацию перед добавлением данных. При ошибке валидации мы можем отклонить транзакцию, не нарушая целостность данных.

**Q: Как оптимизировать медленные запросы в представлениях?**
A: Добавьте рекомендуемые индексы (см. раздел 4.2), используйте фильтрацию где возможно (WHERE при выборе из представлений), рассмотрите использованием материализованных представлений для часто используемых агрегаций.

**Q: Что делать при блокировке триггера при высокой нагрузке?**
A: Измените триггер на асинхронную обработку через сервис-брокер или отдельный процесс, используйте батч-обработку для группировки операций.

**Q: Можно ли использовать эти триггеры и представления вместе с Part 1 процедурами?**
A: Да, они полностью совместимы. Триггеры будут срабатывать при вставке транзакций через процедуры, представления будут отражать изменения.

---

## Заключение

Часть 2 Final Project обеспечивает полный набор инструментов для управления аудитом, валидацией и анализом портфелей. Комбинация триггеров, представлений и оптимизированных запросов создает мощную платформу для работы с портфелями ценных бумаг.

### Ключевые достижения:
- ✓ Полный аудит всех изменений в Transactions
- ✓ Автоматическая валидация данных перед вставкой
- ✓ Четыре разнообразных представления для анализа
- ✓ Пять оптимизированных запросов с продвинутыми техниками
- ✓ Batch-обработка для больших объемов данных
- ✓ Рекомендации по оптимизации производительности

---

**Версия документации:** 1.0  
**Дата:** 2024-05-15  
**Совместимость:** SQL Server 2017+
