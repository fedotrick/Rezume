# Практическая задача 5: Динамический SQL для универсального поиска

## Описание

Разработайте универсальную процедуру, которая выполняет поиск транзакций по произвольному набору фильтров. Используйте динамический SQL с `sp_executesql`, обеспечив защиту от SQL-инъекций.

## Исходные данные

```sql
-- Transactions
-- Columns: TransactionID, ClientID, PortfolioID, InstrumentCode,
--          TradeDate, Quantity, Price, Amount, TraderLogin, SourceSystem

-- Clients
-- Columns: ClientID, ClientName, Segment

-- Portfolios
-- Columns: PortfolioID, PortfolioName, RiskProfile, AdvisorLogin
```

## Требования

1. Процедура `dbo.usp_SearchTransactionsDynamic` должна поддерживать параметры (все необязательные):
   - `@ClientName NVARCHAR(200) = NULL`
   - `@PortfolioName NVARCHAR(200) = NULL`
  - `@InstrumentCode NVARCHAR(50) = NULL`
   - `@DateFrom DATE = NULL`
   - `@DateTo DATE = NULL`
   - `@MinAmount DECIMAL(18,2) = NULL`
   - `@MaxAmount DECIMAL(18,2) = NULL`
   - `@TraderLogin NVARCHAR(100) = NULL`
   - `@SourceSystem NVARCHAR(50) = NULL`
   - `@SortColumn NVARCHAR(30) = 'TradeDate'`
   - `@SortDirection NVARCHAR(4) = 'DESC'`
   - `@PageNumber INT = 1`
   - `@PageSize INT = 50`
2. Построить SELECT с JOIN таблиц `Transactions`, `Clients`, `Portfolios`.
3. Добавить условия фильтрации только для переданных параметров.
4. Реализовать пагинацию через `OFFSET ... FETCH NEXT`.
5. Защитить сортировку: разрешить только набор столбцов (`TradeDate`, `Amount`, `ClientName`, `PortfolioName`).
6. Использовать `sp_executesql` и параметризацию всех значений.
7. Возвращать общее количество записей (`COUNT(*) OVER () AS TotalCount`) для пагинации.
8. Логировать фактическую SQL-строку и параметры в таблицу `dbo.DynamicQueryLog` с полями:
   - `ExecID BIGINT IDENTITY`
   - `ExecutedAt DATETIME2`
   - `ExecutedBy NVARCHAR(128)`
   - `QueryText NVARCHAR(MAX)`
   - `Parameters NVARCHAR(MAX)`

## Ожидаемый результат

| Поле | Описание |
|------|----------|
| `TransactionID` | Идентификатор сделки |
| `ClientName` | Имя клиента |
| `PortfolioName` | Наименование портфеля |
| `InstrumentCode` | Инструмент |
| `TradeDate` | Дата сделки |
| `Amount` | Сумма |
| `TraderLogin` | Трейдер |
| `SourceSystem` | Источник |
| `TotalCount` | Общее количество записей по запросу |

## Заготовка

```sql
CREATE OR ALTER PROCEDURE dbo.usp_SearchTransactionsDynamic
    @ClientName NVARCHAR(200) = NULL,
    @PortfolioName NVARCHAR(200) = NULL,
    @InstrumentCode NVARCHAR(50) = NULL,
    @DateFrom DATE = NULL,
    @DateTo DATE = NULL,
    @MinAmount DECIMAL(18,2) = NULL,
    @MaxAmount DECIMAL(18,2) = NULL,
    @TraderLogin NVARCHAR(100) = NULL,
    @SourceSystem NVARCHAR(50) = NULL,
    @SortColumn NVARCHAR(30) = 'TradeDate',
    @SortDirection NVARCHAR(4) = 'DESC',
    @PageNumber INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SQL NVARCHAR(MAX) = N'';
    DECLARE @ParamDef NVARCHAR(MAX) = N'';

    -- TODO: валидация SortColumn и SortDirection
    -- TODO: построение SELECT + JOIN
    -- TODO: добавление условий WHERE при наличии параметров
    -- TODO: добавление ORDER BY и OFFSET/FETCH
    -- TODO: параметризация значений и вызов sp_executesql
    -- TODO: логирование запроса в DynamicQueryLog
END;
GO
```

## Подсказки

- Для whitelist сортировки используйте `CASE` и `QUOTENAME`:

```sql
DECLARE @OrderColumn NVARCHAR(128) = CASE @SortColumn
    WHEN 'TradeDate' THEN QUOTENAME('TradeDate')
    WHEN 'Amount' THEN QUOTENAME('Amount')
    WHEN 'ClientName' THEN QUOTENAME('ClientName')
    WHEN 'PortfolioName' THEN QUOTENAME('PortfolioName')
    ELSE QUOTENAME('TradeDate')
END;
```

- Контролируйте `@SortDirection`: только `ASC` или `DESC`.
- Используйте `STRING_ESCAPE` или `JSON` для хранения параметров в логе.
- Для пагинации рассчитайте `@Offset = (@PageNumber - 1) * @PageSize`.

## Критерии оценки

1. Процедура безопасна к SQL-инъекциям и поддерживает гибкое фильтрование.
2. Код чистый, читаемый, следует рекомендациям лекции 3.
3. Лог запросов содержит полную информацию для аудита.
