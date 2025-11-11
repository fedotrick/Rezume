# Практическая задача 2: Триггер для логирования изменений портфелей

## Описание

Создайте триггер, который фиксирует все изменения в таблице портфелей, включая старые и новые значения, метаинформацию о пользователе и времени.

## Требуемые таблицы

```sql
-- Portfolios (целевой объект)
-- Columns: PortfolioID, PortfolioName, ClientID, TotalValue, RiskProfile,
--          IsActive, UpdatedAt, UpdatedBy

-- PortfolioChangeLog (таблица аудита)
-- Columns: ChangeLogID, PortfolioID, OperationType, ChangedColumns,
--          OldValues, NewValues, ChangedBy, ChangedAt, CorrelationID
```

## Требования

1. Создать `AFTER INSERT, UPDATE, DELETE` триггер `dbo.tr_Portfolios_ChangeAudit`.
2. Для каждой операции записывать в `PortfolioChangeLog`:
   - `PortfolioID`
   - `OperationType` (`INSERT`, `UPDATE`, `DELETE`)
   - Список изменённых столбцов в виде CSV (`ChangedColumns`)
   - Старые значения в формате `Column=Value` (через `STRING_AGG`)
   - Новые значения в аналогичном формате
   - Пользователь (`SUSER_SNAME()`)
   - Время (`SYSUTCDATETIME()`)
   - Корреляционный идентификатор (из `inserted.CorrelationID`, если он есть, иначе NULL)
3. Обрабатывать множество строк (не использовать переменные, рассчитанные на одиночную запись).
4. Исключить логирование, если изменения затрагивают только технические столбцы (`UpdatedAt`, `UpdatedBy`).
5. Добавить защиту от рекурсии: если запись ведётся в ту же таблицу (например, при массовом обновлении), триггер не должен запускаться повторно.
6. Обеспечить корректное логирование при частичном обновлении (если обновлён только один столбец, журнал должен отражать только его).

## Ожидаемый результат

| Операция | Пример записи |
|----------|----------------|
| INSERT | `OperationType = INSERT`, `ChangedColumns = PortfolioName,TotalValue`, `OldValues = NULL`, `NewValues = PortfolioName=Global Alpha; TotalValue=1000000` |
| UPDATE | `ChangedColumns = TotalValue`, `OldValues = TotalValue=950000`, `NewValues = TotalValue=1000000` |
| DELETE | `ChangedColumns = *`, `OldValues = PortfolioName=Global Alpha; TotalValue=1000000`, `NewValues = NULL` |

## Заготовка триггера

```sql
CREATE OR ALTER TRIGGER dbo.tr_Portfolios_ChangeAudit
ON dbo.Portfolios
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- TODO: обработка множественных строк
    -- TODO: формирование OperationType
    -- TODO: исключение технических столбцов
    -- TODO: заполнение таблицы аудита
END;
GO
```

## Подсказки

- Используйте `inserted` и `deleted` с `FULL OUTER JOIN` по `PortfolioID`.
- Для определения изменённых столбцов примените `UNION ALL` по каждому полю и фильтр `ISNULL(old, '') <> ISNULL(new, '')`.
- Воспользуйтесь `STRING_AGG` для конкатенации значений.
- Для защиты от рекурсии добавьте условие `IF TRIGGER_NESTLEVEL() > 1 RETURN;`.
- Если в таблице нет поля `CorrelationID`, можно брать новое значение `NEWID()`.

## Критерии оценки

1. Триггер корректно обрабатывает вставку, обновление и удаление множества строк.
2. Журнальные записи содержат точные списки изменённых столбцов и значений.
3. Код защищён от рекурсии и не тормозит массовые операции.
