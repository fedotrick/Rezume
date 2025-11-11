# Лекция 2. Оптимизация запросов для больших данных

## Цели занятия

- Познакомиться с архитектурными подходами к работе с наборами данных 10M+ строк.
- Научиться выбирать подходящий тип индекса и стратегию хранения.
- Освоить приёмы batch-обработки, partitioning и архивирования.
- Оптимизировать ETL-процессы и загрузку данных с использованием BULK-операций.

## 1. Диагностика «узких мест» на больших объёмах

1. **IO-bound vs CPU-bound**: измеряем `logical_reads`, `elapsed_time`, `cpu_time`. IO-проблемы требуют индексов, partitioning; CPU — переписывание логики, предагрегирование.
2. **Wait statistics**: `PAGEIOLATCH_*`, `CXPACKET`, `SOS_SCHEDULER_YIELD` указывают на тип нагрузки.
3. **Tempdb contention**: при массовых сортировках и hash join следите за `PFS/SGAM/GAM` ожиданиями.

## 2. Индексирование для больших таблиц

### 2.1. Составные индексы и включённые колонки

```sql
CREATE NONCLUSTERED INDEX IX_Trades_Symbol_Date
ON dbo.Trades (Symbol, TradeDate)
INCLUDE (Quantity, Price, PortfolioId);
```

- **Symbol** обеспечивает селективность, **TradeDate** поддерживает поиск по диапазону.
- Включённые колонки устраняют `Key Lookup` и снижают IO.

### 2.2. Columnstore индексы

- Идеальны для аналитических запросов и агрегаций по миллионам строк.
- Используйте в паре с кластерным b-tree (Hybrid) для OLTP + аналитика.

```sql
CREATE CLUSTERED COLUMNSTORE INDEX CCI_Trades
ON dbo.TradesFact;
```

### 2.3. Filtered индексы

- Подходят для хранения только «активных» данных (последние 6-12 месяцев).
- Снижают размер и стоимость обслуживания.

## 3. Партиционирование и архивирование

### 3.1. Projected architecture

1. **Partition function**: определяет границы (обычно по дате заседания).
2. **Partition scheme**: сопоставляет границы файловым группам.
3. **Sliding window**: добавляет новый раздел, архивирует старый.

```sql
CREATE PARTITION FUNCTION PF_TradesByMonth (DATE)
AS RANGE RIGHT FOR VALUES ('2023-01-01', '2023-02-01', '2023-03-01');

CREATE PARTITION SCHEME PS_TradesByMonth
AS PARTITION PF_TradesByMonth
TO ([FG2022], [FG2023], [FG2024], [FGArchive]);

CREATE TABLE dbo.TradesFact
(
    TradeId       BIGINT IDENTITY PRIMARY KEY,
    TradeDate     DATE,
    Symbol        VARCHAR(12),
    PortfolioId   INT,
    Quantity      INT,
    Price         DECIMAL(18,4)
)
ON PS_TradesByMonth (TradeDate);
```

### 3.2. Архивирование

- Используйте `SWITCH PARTITION` для перемещения старых данных в архивную таблицу без блокировок.
- Автоматизируйте расписание через SQL Agent, Azure Automation или DevOps pipeline.

## 4. Batch-processing вместо row-by-row

- Заменяйте курсоры и циклы операциями set-based (`MERGE`, `SUM`, `CASE`).
- Для обновлений/удалений используйте «порционные» операции:

```sql
DECLARE @BatchSize INT = 5000;
WHILE 1 = 1
BEGIN
    WITH cte AS (
        SELECT TOP (@BatchSize) TradeId
        FROM dbo.TradesFact WITH (READPAST)
        WHERE ProcessedFlag = 0
        ORDER BY TradeId
    )
    UPDATE cte
    SET ProcessedFlag = 1;

    IF @@ROWCOUNT = 0 BREAK;
END;
```

- READPAST снижает блокировки, особенно в очередях.

## 5. BULK-операции и параллелизм

### 5.1. BULK INSERT + форматирование

```sql
BULK INSERT dbo.TradesStage
FROM 'C:\data\trades_2024_01.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK,
    BATCHSIZE = 50000
);
```

- `TABLOCK` + `BATCHSIZE` уменьшают журналирование.
- Очистка и валидация проводятся уже на staging-таблице (`dbo.TradesStage`).

### 5.2. Параллельная обработка

- Контролируйте `MAXDOP`. Аналитические запросы получают выгоду от параллелизма, но OLTP может пострадать.
- Используйте `Resource Governor` для ограничения ресурсов ETL.

## 6. Оптимизация ETL

1. **Stage → Validate → Load**: разделяйте этапы загрузки, валидации, агрегации.
2. **Храните контрольные точки**: таблицы прогресса (номер партии, дата последнего успешного запуска).
3. **Минимизируйте блокировки**: используйте `TABLOCK`, `ROWLOCK`, `READ COMMITTED SNAPSHOT`.
4. **Валидация**: `CHECKSUM`, `COUNT_BIG`, сверка суммы количественных показателей.
5. **Профилирование**: включайте `SET STATISTICS IO`, Extended Events на долгие операции.

## 7. Кейс: ускорение отчёта по портфелю

| Шаг | Описание | Выигрыш |
|-----|----------|---------|
| 1 | Добавление индекса `(PortfolioId, TradeDate) INCLUDE (InstrumentType, Amount)` | ×3 |
| 2 | Перенос исторических данных (> 2 лет) в архивную таблицу | ×1.5 |
| 3 | Использование columnstore на Fact-таблице | ×4 |
| 4 | Подготовка агрегатов (daily NAV) в отдельной таблице | ×6 |

Общий выигрыш по времени выполнения: с 4 минут до 6 секунд.

## 8. Контрольный список

- [ ] Проанализированы метрики IO/CPU и идентифицирован тип нагрузки.
- [ ] Проведён аудит индексов: актуальность, перекрывающие, columnstore.
- [ ] Внедрены partitioning и архивирование для больших таблиц.
- [ ] Переписаны курсоры и циклы на batch/set-based обработку.
- [ ] Настроены BULK-операции и обслуживающие задания (перестроение, статистика).

Минимизируя накладные расходы и правильно распределяя данные по слоям хранения, вы обеспечите масштабируемость и предсказуемое время отклика даже при десятках миллионов записей.
