# Практическая задача 4: Обработка XML-документа с данными о сделках

## Описание

Разработайте процесс загрузки XML-документа, содержащего данные о биржевых сделках. Задача включает в себя валидацию XML, разбор элементов, вставку данных в таблицы и обработку ошибок.

## Структура XML

```xml
<Trades batchId="8f01f901-8420-4b3d-8d1e-c7f424adc2b7" source="OMS" generatedAt="2024-01-15T12:45:00Z">
  <Trade id="TRX-1001">
    <ClientID>101</ClientID>
    <PortfolioID>10</PortfolioID>
    <Instrument>AAPL</Instrument>
    <TradeDate>2024-01-15</TradeDate>
    <Quantity>150</Quantity>
    <Price>187.34</Price>
    <Trader>JSTARK</Trader>
  </Trade>
  <Trade id="TRX-1002">
    <ClientID>102</ClientID>
    <PortfolioID>11</PortfolioID>
    <Instrument>MSFT</Instrument>
    <TradeDate>2024-01-15</TradeDate>
    <Quantity>200</Quantity>
    <Price>320.10</Price>
    <Trader>BWYNE</Trader>
  </Trade>
  <!-- ... -->
</Trades>
```

## Требуемые объекты

```sql
-- TradeImportQueue (очередь загрузок)
-- Columns: ImportID, Payload XML, SourceSystem, ReceivedAt, Status, ErrorMessage

-- TradeImportItems (стейджинговая таблица)
-- Columns: ImportID, ExternalTradeID, ClientID, PortfolioID,
--          InstrumentCode, TradeDate, Quantity, Price, Trader, Amount

-- TradeImportErrors (лог ошибок)
-- Columns: ErrorID, ImportID, TradeExternalID, ErrorCode, ErrorMessage, CreatedAt
```

## Требования

1. Написать процедуру `dbo.usp_ProcessTradeImport` с параметром `@ImportID INT`.
2. Процедура должна:
   - Извлечь XML-пакет из `TradeImportQueue` со статусом `NEW`.
   - Проверить, что документ содержит хотя бы один `<Trade>`.
   - Для каждого `<Trade>`:
     - Считать значения полей и конвертировать типы
     - Рассчитать сумму `Amount = Quantity * Price`
     - Валидировать: `Quantity > 0`, `Price > 0`, `TradeDate <= @BusinessDate`
     - При ошибках записать в `TradeImportErrors` и продолжить обработку следующих записей
   - Успешно разобранные данные вставить в `TradeImportItems`
3. По завершении установить статус загрузки:
   - `PROCESSED`, если все сделки успешно обработаны
   - `PROCESSED_WITH_ERRORS`, если были ошибки, но часть данных загружена
   - `FAILED`, если XML недоступен или невалиден
4. Использовать блок `TRY/CATCH` для общего контроля и логирования ошибок.
5. Логировать `CorrelationID` (атрибут `batchId`) для связи записей.
6. Все операции выполнять в транзакции. При критических ошибках — откатить.
7. Подготовить наглядный отчёт (SELECT) по итогам обработки: количество успешных, с ошибками, общая сумма.

## Ожидаемый результат

| Метрика | Значение |
|---------|----------|
| `SuccessCount` | Количество прайсингов, прошедших валидацию |
| `ErrorCount` | Количество сделок с ошибками |
| `TotalAmount` | Сумма по успешным сделкам |
| `Status` | Итоговый статус записи в очереди |

## Заготовка

```sql
CREATE OR ALTER PROCEDURE dbo.usp_ProcessTradeImport
    @ImportID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Payload XML;
    DECLARE @BatchId UNIQUEIDENTIFIER;
    DECLARE @Source NVARCHAR(50);
    DECLARE @SuccessCount INT = 0;
    DECLARE @ErrorCount INT = 0;

    BEGIN TRY
        -- TODO: получить XML и атрибуты (batchId, source)
        -- TODO: проверить наличие элементов Trade
        -- TODO: начать транзакцию
        -- TODO: разобрать XML через .nodes()
        -- TODO: валидировать каждую запись; ошибки -> TradeImportErrors
        -- TODO: успешные записи -> TradeImportItems
        -- TODO: обновить статус очереди

        SELECT @SuccessCount AS SuccessCount,
               @ErrorCount AS ErrorCount,
               SUM(Amount) AS TotalAmount
        FROM TradeImportItems
        WHERE ImportID = @ImportID;
    END TRY
    BEGIN CATCH
        -- TODO: откат, логирование, обновление статуса FAILED
        THROW;
    END CATCH
END;
GO
```

## Подсказки

- Извлеките атрибуты: `@Payload.value('(/Trades/@batchId)[1]', 'uniqueidentifier')`.
- Для валидированных данных используйте `INSERT ... SELECT` из `CROSS APPLY @Payload.nodes('/Trades/Trade')`.
- Обработку ошибок удобно ведти через табличную переменную, а затем bulk insert в `TradeImportErrors`.
- В CATCH-блоке обновите `TradeImportQueue.Status` и вызовите `dbo.usp_LogError`.

## Критерии оценки

1. Процедура корректно парсит XML и обрабатывает частичные ошибки.
2. Итоговый статус загрузки отражает фактический результат.
3. Логируются все ошибки с привязкой к конкретной сделке и batchId.
