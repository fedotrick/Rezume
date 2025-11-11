# Практическая задача 1: Разработка хранимой процедуры добавления транзакции

## Описание

Создайте надёжную хранимую процедуру, которая добавляет новую финансовую транзакцию в систему с проверкой бизнес-правил, логированием и возвратом статуса операции.

## Требуемые таблицы

```sql
-- Portfolios (существующая таблица)
-- Columns: PortfolioID, PortfolioName, ClientID, TotalValue, IsActive

-- Transactions (целевой объект)
-- Columns: TransactionID, PortfolioID, ClientID, InstrumentCode, TradeDate,
--          Quantity, Price, Amount, TraderLogin, CorrelationID, CreatedAt

-- ProcedureErrorLog (таблица логирования ошибок)
-- Columns: ErrorLogID, ErrorDate, ProcedureName, ErrorNumber, ErrorMessage,
--          ErrorSeverity, ErrorState, ErrorLine, CorrelationID
```

## Требования

1. Процедура должна называться `dbo.usp_AddPortfolioTransaction` и поддерживать параметры:
   - `@PortfolioID INT`
   - `@ClientID INT`
   - `@InstrumentCode NVARCHAR(50)`
   - `@TradeDate DATETIME2`
   - `@Quantity DECIMAL(18,4)`
   - `@Price DECIMAL(18,4)`
   - `@TraderLogin NVARCHAR(100)`
   - `@CorrelationID UNIQUEIDENTIFIER = NULL`
   - `@StatusCode INT OUTPUT`
   - `@StatusMessage NVARCHAR(4000) OUTPUT`
2. Добавить валидации:
   - портфель должен существовать и быть активным
   - клиент должен соответствовать портфелю
   - `@Quantity` и `@Price` > 0
   - дата сделки не должна быть в будущем
3. Выполнять расчёт суммы: `@Quantity * @Price` и записывать в столбец `Amount`.
4. Использовать блок `TRY/CATCH` с логированием через `dbo.usp_LogError`.
5. Возвращать:
   - `@StatusCode = 0` и `@StatusMessage = 'OK'` при успехе
   - осмысленные коды (например, 10, 20, 30) при разных типах ошибок валидации
6. Логировать вызов в таблицу аудита `dbo.TransactionAudit` (создайте таблицу при необходимости) со статусом операции.
7. Возвращать идентификатор созданной транзакции через `SCOPE_IDENTITY()` (можно как OUTPUT или отдельный SELECT).

## Ожидаемый результат

| Шаг | Описание |
|-----|----------|
| 1 | Процедура выполняет все проверки и откатывает транзакцию при ошибках |
| 2 | Таблица `Transactions` пополняется корректными записями |
| 3 | Таблица аудита содержит историю запусков с датой, пользователем, статусом |
| 4 | Ошибки фиксируются в `ProcedureErrorLog` |

## Заготовка кода

```sql
CREATE OR ALTER PROCEDURE dbo.usp_AddPortfolioTransaction
    @PortfolioID INT,
    @ClientID INT,
    @InstrumentCode NVARCHAR(50),
    @TradeDate DATETIME2,
    @Quantity DECIMAL(18,4),
    @Price DECIMAL(18,4),
    @TraderLogin NVARCHAR(100),
    @CorrelationID UNIQUEIDENTIFIER = NULL,
    @StatusCode INT OUTPUT,
    @StatusMessage NVARCHAR(4000) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TranStarted BIT = 0;
    DECLARE @NewTransactionID INT;

    BEGIN TRY
        -- TODO: начать транзакцию при необходимости
        -- TODO: валидации (портфель, клиент, диапазоны)
        -- TODO: вставка в Transactions с расчётом суммы
        -- TODO: логирование в таблицу аудита
        -- TODO: установка статус-кодов
    END TRY
    BEGIN CATCH
        -- TODO: откат и логирование ошибки
        -- TODO: установка статуса ошибки и сообщения
        -- TODO: повторно бросить ошибку или вернуть код
    END CATCH
END;
GO
```

## Подсказки

- Используйте `SET XACT_ABORT ON` при работе с транзакциями.
- Для получения пользователя примените `SUSER_SNAME()` или `ORIGINAL_LOGIN()`.
- Старайтесь использовать `RETURN` только для неудач в валидации, а не для исключений.

## Критерии оценки

1. Процедура обрабатывает и валидирует все входные данные.
2. Реализована логика логирования и возврата статуса.
3. Код читаем, использует схемы (`dbo.`) и форматирование из лекций.
