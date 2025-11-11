# Лекция 4: XML обработка в SQL Server

## 1. Основы XML в SQL Server

### 1.1 Тип данных XML

- Хранит полуструктурированные данные.
- Поддерживает индексацию и схему.
- Используется для интеграции с внешними системами (финансовые шлюзы, отчёты).

```sql
CREATE TABLE dbo.TradeImportQueue
(
    ImportID       INT IDENTITY(1,1) PRIMARY KEY,
    Payload        XML NOT NULL,
    ReceivedAt     DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    Status         NVARCHAR(20) NOT NULL DEFAULT 'NEW',
    ErrorMessage   NVARCHAR(2000) NULL
);
```

### 1.2 Методы XML-типов

| Метод | Назначение |
|-------|------------|
| `.value('xquery', sql_type)` | Извлекает скалярное значение |
| `.query('xquery')` | Возвращает XML-фрагмент |
| `.nodes('xquery')` | Разбивает XML на строки (табличное выражение) |
| `.exist('xquery')` | Проверяет наличие узлов (0/1) |
| `.modify('xquery')` | Изменяет XML (INSERT/REPLACE/DELETE) |

## 2. Генерация XML с FOR XML

### 2.1 FOR XML RAW

```sql
SELECT
    PortfolioID,
    PortfolioName,
    TotalValue
FROM dbo.Portfolios
FOR XML RAW('Portfolio'), ROOT('Portfolios'), ELEMENTS;
```

### 2.2 FOR XML AUTO

```sql
SELECT
    p.PortfolioID,
    p.PortfolioName,
    ph.StockSymbol,
    ph.Quantity,
    ph.CurrentPrice
FROM dbo.Portfolios p
INNER JOIN dbo.PortfolioHoldings ph ON ph.PortfolioID = p.PortfolioID
FOR XML AUTO, ROOT('Portfolios');
```

### 2.3 FOR XML PATH

`PATH` — наиболее гибкий режим для формирования кастомной структуры.

```sql
SELECT
    p.PortfolioID AS '@id',
    p.PortfolioName AS 'Name',
    (
        SELECT
            ph.StockSymbol AS '@symbol',
            ph.Quantity AS 'Quantity',
            ph.CurrentPrice AS 'Price'
        FROM dbo.PortfolioHoldings ph
        WHERE ph.PortfolioID = p.PortfolioID
        FOR XML PATH('Holding'), TYPE
    )
FROM dbo.Portfolios p
FOR XML PATH('Portfolio'), ROOT('Portfolios');
```

### 2.4 FOR XML EXPLICIT

Используется редко. Требует указания `Tag` и `Parent` колонок, полезен для сложных иерархий. Рекомендуется переходить на `PATH`.

## 3. Парсинг XML

### 3.1 Разбор с `.nodes()`

```sql
DECLARE @Payload XML = N'
<Trades>
  <Trade id="1">
    <ClientID>101</ClientID>
    <PortfolioID>12</PortfolioID>
    <Instrument>AAPL</Instrument>
    <TradeDate>2024-01-15</TradeDate>
    <Quantity>150</Quantity>
    <Price>187.34</Price>
  </Trade>
  <Trade id="2">
    <ClientID>102</ClientID>
    <PortfolioID>18</PortfolioID>
    <Instrument>MSFT</Instrument>
    <TradeDate>2024-01-15</TradeDate>
    <Quantity>75</Quantity>
    <Price>320.10</Price>
  </Trade>
</Trades>';

SELECT
    T.X.value('@id', 'INT') AS TradeExternalID,
    T.X.value('(ClientID/text())[1]', 'INT') AS ClientID,
    T.X.value('(PortfolioID/text())[1]', 'INT') AS PortfolioID,
    T.X.value('(Instrument/text())[1]', 'NVARCHAR(20)') AS InstrumentCode,
    T.X.value('(TradeDate/text())[1]', 'DATE') AS TradeDate,
    T.X.value('(Quantity/text())[1]', 'DECIMAL(18,4)') AS Quantity,
    T.X.value('(Price/text())[1]', 'DECIMAL(18,4)') AS Price
FROM @Payload.nodes('/Trades/Trade') AS T(X);
```

### 3.2 Вставка данных из XML

```sql
INSERT INTO dbo.Transactions
(
    ExternalTradeID,
    ClientID,
    PortfolioID,
    InstrumentCode,
    TradeDate,
    Quantity,
    Price,
    Amount
)
SELECT
    n.X.value('@id', 'INT') AS ExternalTradeID,
    n.X.value('(ClientID/text())[1]', 'INT') AS ClientID,
    n.X.value('(PortfolioID/text())[1]', 'INT') AS PortfolioID,
    n.X.value('(Instrument/text())[1]', 'NVARCHAR(20)') AS Instrument,
    n.X.value('(TradeDate/text())[1]', 'DATE') AS TradeDate,
    n.X.value('(Quantity/text())[1]', 'DECIMAL(18,4)') AS Quantity,
    n.X.value('(Price/text())[1]', 'DECIMAL(18,4)') AS Price,
    n.X.value('(Quantity/text())[1]', 'DECIMAL(18,4)') * n.X.value('(Price/text())[1]', 'DECIMAL(18,4)') AS Amount
FROM @Payload.nodes('/Trades/Trade') AS n(X);
```

## 4. Валидация XML

### 4.1 Проверка структуры

```sql
IF @Payload.exist('/Trades[Trade]') = 0
BEGIN
    THROW 52001, 'XML не содержит элементов Trade.', 1;
END;
```

### 4.2 XML Schema Collection

```sql
CREATE XML SCHEMA COLLECTION dbo.TradeSchema AS N'
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <xs:element name="Trades">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="Trade" maxOccurs="unbounded">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="ClientID" type="xs:int" />
              <xs:element name="PortfolioID" type="xs:int" />
              <xs:element name="Instrument" type="xs:string" />
              <xs:element name="TradeDate" type="xs:date" />
              <xs:element name="Quantity" type="xs:decimal" />
              <xs:element name="Price" type="xs:decimal" />
            </xs:sequence>
            <xs:attribute name="id" type="xs:int" use="required" />
          </xs:complexType>
        </xs:element>
      </xs:sequence>
    </xs:complexType>
  </xs:element>
</xs:schema>';
GO
```

```sql
ALTER TABLE dbo.TradeImportQueue
ADD CONSTRAINT CK_TradeImportQueue_Payload
CHECK (Payload IS NOT NULL AND Payload.exist('/Trades/Trade') = 1);
```

XML, привязанный к схеме, обеспечивает автоматическую проверку типов и структуры.

## 5. Производительность XML-операций

### 5.1 Индексирование

```sql
CREATE PRIMARY XML INDEX PXML_TradeImport_Payload
ON dbo.TradeImportQueue(Payload);

CREATE XML INDEX PXML_TradeImport_Payload_PATH
ON dbo.TradeImportQueue(Payload)
USING XML INDEX PXML_TradeImport_Payload FOR PATH;
```

- Основной индекс (Primary XML Index) обязателен перед созданием вторичных.
- Вторичные индексы (PATH, VALUE, PROPERTY) добавляйте только при необходимости.

### 5.2 Разбиение (shredding) и кеширование

- Извлекайте данные один раз и сохраняйте во временную таблицу.
- Используйте `CROSS APPLY` для чтения XML.

### 5.3 Ограничения

- XML-поля могут занимать много места; следите за размером.
- Для больших сообщений используйте BULK INSERT + `OPENXML` или `OPENROWSET(BULK...)`.

## 6. Практический шаблон обработки

```sql
CREATE OR ALTER PROCEDURE dbo.usp_ProcessTradePayload
    @ImportID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Payload XML;
    DECLARE @CorrelationID UNIQUEIDENTIFIER = NEWID();

    SELECT @Payload = Payload
    FROM dbo.TradeImportQueue
    WHERE ImportID = @ImportID;

    IF @Payload IS NULL
    BEGIN
        THROW 52002, 'Загрузка не найдена или пустой XML.', 1;
    END;

    BEGIN TRY
        -- Валидация
        IF @Payload.exist('/Trades/Trade') = 0
        BEGIN
            THROW 52003, 'Сообщение не содержит элементов Trade.', 1;
        END;

        INSERT INTO dbo.TransactionsStaging
        (
            ImportID,
            ExternalTradeID,
            ClientID,
            PortfolioID,
            InstrumentCode,
            TradeDate,
            Quantity,
            Price,
            Amount,
            CorrelationID
        )
        SELECT
            @ImportID,
            X.value('@id', 'INT'),
            X.value('(ClientID/text())[1]', 'INT'),
            X.value('(PortfolioID/text())[1]', 'INT'),
            X.value('(Instrument/text())[1]', 'NVARCHAR(20)'),
            X.value('(TradeDate/text())[1]', 'DATE'),
            X.value('(Quantity/text())[1]', 'DECIMAL(18,4)'),
            X.value('(Price/text())[1]', 'DECIMAL(18,4)'),
            X.value('(Quantity/text())[1]', 'DECIMAL(18,4)') * X.value('(Price/text())[1]', 'DECIMAL(18,4)'),
            @CorrelationID
        FROM @Payload.nodes('/Trades/Trade') AS Trades(X);

        UPDATE dbo.TradeImportQueue
        SET Status = 'PROCESSED',
            ErrorMessage = NULL
        WHERE ImportID = @ImportID;
    END TRY
    BEGIN CATCH
        UPDATE dbo.TradeImportQueue
        SET Status = 'FAILED',
            ErrorMessage = ERROR_MESSAGE()
        WHERE ImportID = @ImportID;

        EXEC dbo.usp_LogError
            @ProcedureName = OBJECT_NAME(@@PROCID),
            @ErrorNumber = ERROR_NUMBER(),
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE(),
            @ErrorLine = ERROR_LINE(),
            @CorrelationID = @CorrelationID;

        THROW;
    END CATCH
END;
GO
```

## 7. Интеграция XML в отчёты

### 7.1 Создание XML-отчёта

```sql
SELECT
    (
        SELECT
            p.PortfolioName AS '@name',
            p.TotalValue AS '@value',
            (
                SELECT
                    ph.StockSymbol AS '@symbol',
                    ph.Quantity AS '@qty',
                    ph.CurrentPrice AS '@price'
                FROM dbo.PortfolioHoldings ph
                WHERE ph.PortfolioID = p.PortfolioID
                FOR XML PATH('Holding'), TYPE
            )
        FROM dbo.Portfolios p
        FOR XML PATH('Portfolio'), ROOT('PortfolioReport'), TYPE
    ) AS ReportXML;
```

### 7.2 Выгрузка в файл (SQLCMD/PowerShell)

```powershell
Invoke-Sqlcmd -ServerInstance "sql01" -Database "Trading"
    -Query "EXEC dbo.usp_GeneratePortfolioReport"
    -OutputAs Xml | Out-File "C:\Reports\PortfolioReport.xml"
```

## 8. Сравнение XML и JSON

| Критерий | XML | JSON |
|----------|-----|------|
| Схема | Да (`XML Schema`) | Нет (но есть JSON Schema вне SQL Server) |
| Индексирование | XML Index | Индексы JSON (в SQL 2016+) |
| Поддержка в SQL Server | Полная (методы, индексы) | Ограниченная (`ISJSON`, `JSON_VALUE`, `OPENJSON`) |
| verbosity | Высокая | Низкая |

Для обмена с системами, где требуется строгая схема (финансовые стандарты), XML остаётся предпочтительным.

## 9. Рекомендации

1. Очищайте таблицы очередей после обработки.
2. Не храните тяжёлый XML в транзакционных таблицах — переносите в архив.
3. Для массовых загрузок используйте BULK INSERT + OPENROWSET для чтения файлов.
4. Следите за размером: включайте компрессию строк/страниц (`ROW`/`PAGE`).
5. Документируйте структуру XML и поддерживайте версионирование.

## 10. Контрольный список

| Вопрос | Проверка |
|--------|----------|
| XML валиден? | Используются ли `.exist()` или схема? |
| Производительность | Создан ли первичный XML-индекс? |
| Безопасность | Проверены ли максимальные размеры сообщений? |
| Логирование | Фиксируются ли ошибки разбора? |
| Поддержка | Есть ли версия схемы в payload? |

XML-интеграции завершают комплексную картину недели. В сочетании с процедурами и триггерами они позволяют стройно выстраивать ETL-потоки, аудирование и обмен данными.
