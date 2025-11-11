# Лекция 2: Триггеры (Triggers)

## 1. Назначение триггеров

Триггеры — это специальные объекты, автоматически выполняющиеся при событиях `INSERT`, `UPDATE`, `DELETE` или DDL-операциях. Они используются для аудита, контроля целостности и автоматизации.

### 1.1 Почему (и когда) нужны триггеры

- Автоматизация аудита изменений
- Поддержка сложных бизнес-правил, которые трудно выразить ограничениями
- Синхронизация данных между таблицами
- Реакция на события (например, уведомления)

**Важно:** триггеры не предназначены для массовых вычислений или синхронной интеграции с внешними системами. Повышенная нагрузка на сервер и возможная рекурсия делают их подходящими только для критичных сценариев.

## 2. Типы триггеров

| Тип | Описание | События |
|-----|----------|---------|
| **AFTER/FOR** | Выполняются после завершения операции и фиксации данных во временных таблицах `inserted`/`deleted` | `INSERT`, `UPDATE`, `DELETE` |
| **INSTEAD OF** | Замещают стандартное поведение. Используются в основном для представлений или сложных проверок | `INSERT`, `UPDATE`, `DELETE` |
| **DDL-триггеры** | Реагируют на изменения схемы | `CREATE`, `ALTER`, `DROP`, `GRANT` |

## 3. Синтаксис триггеров

### 3.1 AFTER-триггер

```sql
CREATE OR ALTER TRIGGER dbo.tr_Portfolios_Audit
ON dbo.Portfolios
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.PortfolioAudit
    (
        PortfolioID,
        OperationType,
        OldValue,
        NewValue,
        ChangedBy,
        ChangedAt
    )
    SELECT
        COALESCE(i.PortfolioID, d.PortfolioID) AS PortfolioID,
        CASE 
            WHEN i.PortfolioID IS NOT NULL AND d.PortfolioID IS NULL THEN 'INSERT'
            WHEN i.PortfolioID IS NOT NULL AND d.PortfolioID IS NOT NULL THEN 'UPDATE'
            WHEN i.PortfolioID IS NULL AND d.PortfolioID IS NOT NULL THEN 'DELETE'
        END AS OperationType,
        d.TotalValue AS OldValue,
        i.TotalValue AS NewValue,
        SUSER_SNAME() AS ChangedBy,
        SYSUTCDATETIME() AS ChangedAt
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.PortfolioID = d.PortfolioID;
END;
GO
```

### 3.2 INSTEAD OF-триггер для представления

```sql
CREATE VIEW dbo.vw_ActiveTransactions
AS
SELECT
    t.TransactionID,
    t.ClientID,
    t.PortfolioID,
    t.Amount,
    t.TradeDate
FROM dbo.Transactions t
WHERE t.IsCancelled = 0;
GO

CREATE OR ALTER TRIGGER dbo.tr_vw_ActiveTransactions_Delete
ON dbo.vw_ActiveTransactions
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE t
    SET    t.IsCancelled = 1,
           t.CancelledAt = SYSUTCDATETIME(),
           t.CancelledBy = SUSER_SNAME()
    FROM dbo.Transactions t
    INNER JOIN deleted d ON t.TransactionID = d.TransactionID;
END;
GO
```

### 3.3 DDL-триггер

```sql
CREATE OR ALTER TRIGGER dbo.tr_BlockTableDrop
ON DATABASE
FOR DROP_TABLE
AS
BEGIN
    RAISERROR('Удаление таблиц запрещено в этой базе.', 16, 1);
    ROLLBACK;
END;
GO
```

## 4. Доступ к `inserted` и `deleted`

- `INSERT`: `inserted` содержит новые строки, `deleted` пуст
- `DELETE`: `deleted` содержит удалённые строки, `inserted` пуст
- `UPDATE`: обе таблицы заполнены (доступны старые и новые значения)

```sql
SELECT * FROM inserted;
SELECT * FROM deleted;
```

Работайте со множеством строк! Нельзя предполагать, что триггер вызван для одной записи.

### 4.1 Пример проверки бизнес-правила

```sql
CREATE OR ALTER TRIGGER dbo.tr_Portfolio_TotalValue
ON dbo.Portfolios
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.TotalValue < 0
    )
    BEGIN
        RAISERROR('Стоимость портфеля не может быть отрицательной.', 16, 1);
        ROLLBACK;
    END
END;
GO
```

## 5. Логирование изменений

### 5.1 Структура таблицы аудита

```sql
CREATE TABLE dbo.PortfolioChangeLog
(
    ChangeLogID     BIGINT IDENTITY(1,1) PRIMARY KEY,
    PortfolioID     INT NOT NULL,
    OperationType   NVARCHAR(10) NOT NULL,
    ChangedColumns  NVARCHAR(4000) NULL,
    OldValues       NVARCHAR(MAX) NULL,
    NewValues       NVARCHAR(MAX) NULL,
    ChangedBy       NVARCHAR(128) NOT NULL,
    ChangedAt       DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
```

### 5.2 Триггер со сбором старых/новых значений

```sql
CREATE OR ALTER TRIGGER dbo.tr_Portfolios_LogChanges
ON dbo.Portfolios
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.PortfolioChangeLog
    (
        PortfolioID,
        OperationType,
        ChangedColumns,
        OldValues,
        NewValues,
        ChangedBy
    )
    SELECT
        COALESCE(i.PortfolioID, d.PortfolioID) AS PortfolioID,
        CASE 
            WHEN i.PortfolioID IS NOT NULL AND d.PortfolioID IS NULL THEN 'INSERT'
            WHEN i.PortfolioID IS NOT NULL AND d.PortfolioID IS NOT NULL THEN 'UPDATE'
            ELSE 'DELETE'
        END AS OperationType,
        STRING_AGG(changed.ColumnName, ',') WITHIN GROUP (ORDER BY changed.ColumnName) AS ChangedColumns,
        STRING_AGG(changed.OldValue, '; ') WITHIN GROUP (ORDER BY changed.ColumnName) AS OldValues,
        STRING_AGG(changed.NewValue, '; ') WITHIN GROUP (ORDER BY changed.ColumnName) AS NewValues,
        SUSER_SNAME() AS ChangedBy
    FROM
    (
        SELECT
            COALESCE(i.PortfolioID, d.PortfolioID) AS PortfolioID,
            col.ColumnName,
            col.OldValue,
            col.NewValue
        FROM inserted i
        FULL OUTER JOIN deleted d ON i.PortfolioID = d.PortfolioID
        CROSS APPLY (
            VALUES
                ('PortfolioName', d.PortfolioName, i.PortfolioName),
                ('TotalValue', CAST(d.TotalValue AS NVARCHAR(50)), CAST(i.TotalValue AS NVARCHAR(50))),
                ('ClientID', CAST(d.ClientID AS NVARCHAR(50)), CAST(i.ClientID AS NVARCHAR(50)))
        ) AS col (ColumnName, OldValue, NewValue)
        WHERE ISNULL(col.OldValue, '') <> ISNULL(col.NewValue, '')
    ) AS changed
    GROUP BY changed.PortfolioID,
             CASE 
                 WHEN EXISTS (SELECT 1 FROM inserted i2 WHERE i2.PortfolioID = changed.PortfolioID)
                      AND EXISTS (SELECT 1 FROM deleted d2 WHERE d2.PortfolioID = changed.PortfolioID)
                 THEN 'UPDATE'
                 WHEN EXISTS (SELECT 1 FROM inserted i3 WHERE i3.PortfolioID = changed.PortfolioID)
                 THEN 'INSERT'
                 ELSE 'DELETE'
             END;
END;
GO
```

## 6. Производительность и риски

### 6.1 Распространённые проблемы

1. **Триггеры вызываются синхронно**. Они увеличивают время выполнения исходного DML.
2. **Плохие планы**. Сложные запросы внутри триггера используют те же индексы, что и основная операция.
3. **Рекурсия и циклы**. Триггер может косвенно обновить таблицу, на которую установлен, запуская себя.
4. **Промежуточные ошибки**. Ошибка в триггере откатывает всю исходную операцию.

### 6.2 Практики оптимизации

- Выносите тяжёлые операции в Service Broker или CDC.
- Добавляйте предикаты (`IF NOT EXISTS (...) RETURN;`), если триггер должен отрабатывать только для определённых условий.
- Используйте временные таблицы для агрегации, но очищайте их.
- Мониторьте длительность триггеров через Extended Events (`sqlserver.sql_statement_completed`).

## 7. Альтернативы триггерам

| Сценарий | Альтернатива |
|----------|--------------|
| Аудит DML | Temporal Tables, Change Data Capture (CDC), Change Tracking |
| Проверка данных | CHECK constraints, FOREIGN KEY, вычисляемые столбцы |
| Производственный интеграционный поток | SQL Server Agent jobs, Service Broker |
| Уведомления | Event Grid, Service Broker, приложения-подписчики |

Выбирайте триггеры только тогда, когда альтернативы не дают нужного контроля или когда требуется мгновенная реакция.

## 8. Практические примеры

### 8.1 Триггер для ограничения торгового окна

```sql
CREATE OR ALTER TRIGGER dbo.tr_Transactions_TimeWindow
ON dbo.Transactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE CONVERT(TIME(0), i.TradeDate) NOT BETWEEN '09:00' AND '18:45'
    )
    BEGIN
        RAISERROR('Транзакции допустимы только в рабочем окне 09:00-18:45.', 16, 1);
        ROLLBACK;
    END
END;
GO
```

### 8.2 Триггер для контроля лимитов

```sql
CREATE OR ALTER TRIGGER dbo.tr_PortfolioHoldings_Limit
ON dbo.PortfolioHoldings
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.PortfolioLimits l ON l.PortfolioID = i.PortfolioID AND l.StockSymbol = i.StockSymbol
        WHERE i.Quantity * i.CurrentPrice > l.MaxPositionValue
    )
    BEGIN
        RAISERROR('Превышен лимит позиции по инструменту.', 16, 1);
        ROLLBACK;
    END
END;
GO
```

### 8.3 INSTEAD OF для представления агрегатов

```sql
CREATE VIEW dbo.vw_PortfolioSnapshots
AS
SELECT
    p.PortfolioID,
    p.PortfolioName,
    SUM(ph.Quantity * ph.CurrentPrice) AS MarketValue
FROM dbo.Portfolios p
LEFT JOIN dbo.PortfolioHoldings ph ON ph.PortfolioID = p.PortfolioID
GROUP BY p.PortfolioID, p.PortfolioName;
GO

CREATE OR ALTER TRIGGER dbo.tr_vw_PortfolioSnapshots_Update
ON dbo.vw_PortfolioSnapshots
INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE p
    SET p.TargetValue = i.MarketValue
    FROM dbo.Portfolios p
    INNER JOIN inserted i ON p.PortfolioID = i.PortfolioID;
END;
GO
```

## 9. Чек-лист по триггерам

1. Обрабатывает ли код множества строк?
2. Есть ли защита от рекурсии?
3. Оптимальны ли фильтры и индексы?
4. Логируются ли ошибки и результаты?
5. Есть ли тесты для вставки, обновления и удаления?

### 9.1 Минимальный каркас AFTER-триггера

```sql
CREATE OR ALTER TRIGGER dbo.tr_Template
ON dbo.TableName
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM inserted)
    BEGIN
        -- логика для INSERT/UPDATE
    END

    IF EXISTS (SELECT 1 FROM deleted)
    BEGIN
        -- логика для UPDATE/DELETE
    END
END;
GO
```

Триггеры — мощный инструмент, но использовать их нужно осознанно. В следующих лекциях мы дополним картину расширенными конструкциями T-SQL и обработкой XML, сочетая их с процедурами и триггерами.
