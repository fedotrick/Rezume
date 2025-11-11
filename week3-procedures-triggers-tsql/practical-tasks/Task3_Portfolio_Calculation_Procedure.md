# Практическая задача 3: Комплексная процедура расчёта стоимости портфеля

## Описание

Реализуйте процедуру, которая рассчитывает стоимость портфеля по всем активам с учётом лимитов, валют и сценариев перерасчёта. Используйте циклы и условные операторы для пошаговой обработки.

## Исходные данные

```sql
-- Portfolios
-- Columns: PortfolioID, PortfolioName, BaseCurrency, TargetValue, LastCalculatedAt

-- PortfolioHoldings
-- Columns: HoldingID, PortfolioID, StockSymbol, Quantity, CurrentPrice, CurrencyCode

-- CurrencyRates
-- Columns: RateDate, FromCurrency, ToCurrency, Rate

-- PortfolioValuationLog (создайте при необходимости)
-- Columns: LogID, PortfolioID, CalculationDate, TotalMarketValue,
--          TotalCost, FXAdjustments, StatusMessage, CalculatedBy
```

## Требования

1. Процедура `dbo.usp_RecalculatePortfolioValue` принимает параметры:
   - `@PortfolioID INT`
   - `@AsOfDate DATE`
   - `@RunMode NVARCHAR(20)` (`'FULL'`, `'DELTA'`, `'INTRADAY'`)
   - `@ForceRecalc BIT = 0`
   - `@StatusMessage NVARCHAR(4000) OUTPUT`
2. Алгоритм:
   1. Проверить, существует ли портфель и активен ли он. Если нет — вернуть статус ошибки.
   2. Определить источник цен:
      - `FULL`: брать `CurrentPrice`
      - `DELTA`: использовать прирост с предыдущей даты (хранить в временной таблице)
      - `INTRADAY`: взять цены из таблицы `IntradayQuotes` (создайте представление или таблицу-заглушку)
   3. Пройтись по активам портфеля циклом `WHILE` или `CURSOR`, рассчитав рыночную стоимость с учётом валютного курса (используйте `CurrencyRates`).
   4. Накопить показатели: `TotalMarketValue`, `FXAdjustments`, `HighRiskExposure` (например, доля активов с `RiskProfile = 'High'`).
   5. Если `@ForceRecalc = 0` и последний расчёт был менее 1 часа назад — завершить работу с предупреждением.
   6. Обновить `Portfolios.TotalValue` и `LastCalculatedAt`.
   7. Записать результат в `PortfolioValuationLog` с подробностями.
3. Добавить обработку ошибок через `TRY/CATCH` и транзакцию.
4. Для производительности используйте временные таблицы и индексы (`CREATE TABLE #Holdings ...; CREATE CLUSTERED INDEX`).
5. Возвращать код статуса через `RETURN` (0 — успех, >0 — ошибки валидации или недоступности данных).

## Ожидаемый результат

| Показатель | Описание |
|------------|----------|
| `TotalMarketValue` | Суммарная стоимость активов портфеля в базовой валюте |
| `FXAdjustments` | Корректировка от валютных пересчётов |
| `HighRiskExposure` | Процент стоимости активов с высоким риском |
| `StatusMessage` | Подробное описание хода расчёта |

После выполнения процедуры:
- Поля в `Portfolios` обновляются
- В `PortfolioValuationLog` создаётся запись
- В случае ошибок логируются события и возвращается код

## Заготовка

```sql
CREATE OR ALTER PROCEDURE dbo.usp_RecalculatePortfolioValue
    @PortfolioID INT,
    @AsOfDate DATE,
    @RunMode NVARCHAR(20),
    @ForceRecalc BIT = 0,
    @StatusMessage NVARCHAR(4000) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TranStarted BIT = 0;
    DECLARE @ReturnCode INT = 0;

    BEGIN TRY
        -- TODO: проверки существования портфеля и времени последнего расчёта
        -- TODO: загрузка активов во временную таблицу
        -- TODO: цикл/курсор для расчётов и накопления метрик
        -- TODO: обновление портфеля и логирование

        SET @StatusMessage = N'Расчёт выполнен успешно.';
    END TRY
    BEGIN CATCH
        -- TODO: обработка ошибок, откат транзакции
        -- TODO: вызов dbo.usp_LogError
        SET @ReturnCode = ERROR_NUMBER();
        SET @StatusMessage = ERROR_MESSAGE();
    END CATCH

    RETURN @ReturnCode;
END;
GO
```

## Подсказки

- Для итераций используйте `DECLARE PortfolioCursor CURSOR FAST_FORWARD FOR ...` или `WHILE` с таблицей и столбцом-счётчиком.
- Храните промежуточные итоговые суммы в табличных переменных или временных таблицах.
- Для режимов расчёта можно использовать конструкцию `CASE @RunMode WHEN 'FULL' THEN ...`.
- Добавьте диагностическое логирование (`RAISERROR` уровня 10 в dev-среде).

## Критерии оценки

1. Процедура корректно обрабатывает разные режимы и форсированный пересчёт.
2. Использование циклов и условий оправдано и безопасно.
3. Реализован учёт валют и логирование результатов.
