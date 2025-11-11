# Руководство по Выполнению Скриптов Part 2

Это руководство содержит пошаговые инструкции для развертывания всех компонентов Части 2 Final Project.

## 📋 Предварительные Требования

- ✓ SQL Server 2017 или выше
- ✓ SQL Server Management Studio (SSMS) или Azure Data Studio
- ✓ Права администратора БД
- ✓ Развернутая **Часть 1** Final Project (база данных, таблицы, процедуры)
- ✓ Примерные данные (загружены через Part 1 скрипты)

## 🚀 Пошаговое Выполнение

### Этап 1: Подготовка к выполнению

#### 1.1 Проверка наличия базы данных

```sql
-- Откройте новое окно запроса в SSMS
-- Выполните команду:
SELECT @@VERSION AS 'SQL Server Version';
```

**Ожидаемый результат:** Информация о версии SQL Server 2017 или выше

#### 1.2 Выбор целевой базы данных

```sql
-- Если база данных называется "PortfolioManagement"
USE PortfolioManagement;
GO

-- Проверка наличия таблиц Part 1
SELECT * FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_NAME IN ('Portfolios', 'Securities', 'Transactions', 'Quotes', 'Audit_Log');
```

**Ожидаемый результат:** Все 5 таблиц должны быть перечислены

---

### Этап 2: Выполнение скрипта с триггерами

#### 2.1 Открыть файл триггеров

1. В SSMS откройте: `File` → `Open` → `File`
2. Выберите файл: `final_project_part2_triggers.sql`

#### 2.2 Убедитесь, что выбрана правильная база данных

```sql
-- В верхнем левом углу SSMS убедитесь, что выбрана правильная БД
-- Или выполните в начале скрипта:
USE PortfolioManagement;
GO
```

#### 2.3 Выполнить скрипт

**Способ 1: Через SSMS**
- Нажмите `F5` или `Execute` (или кнопку ▶ на панели инструментов)

**Способ 2: Через PowerShell**
```powershell
sqlcmd -S YourServerName -d PortfolioManagement -i "final_project_part2_triggers.sql"
```

**Способ 3: Через командную строку**
```cmd
sqlcmd -S YourServerName -d PortfolioManagement -i "path\to\final_project_part2_triggers.sql"
```

#### 2.4 Проверка успешного выполнения

```sql
-- Выполните после завершения скрипта триггеров
-- Проверьте наличие триггеров
SELECT 
    OBJECT_NAME(parent_id) AS TableName,
    name AS TriggerName,
    type_desc AS TriggerType,
    is_disabled
FROM sys.triggers
WHERE name LIKE 'trg_%';

-- Ожидаемый результат:
-- TableName  | TriggerName                        | TriggerType   | is_disabled
-- -----------|------------------------------------|---------------|------------
-- Quotes     | trg_UpdatePortfolioValue_OnQuote.. | AFTER         | 0
-- Transactions| trg_Transactions_Audit             | AFTER         | 0
-- Transactions| trg_ValidateTransaction            | INSTEAD OF    | 0
```

#### 2.5 Проверка Audit_Log

```sql
-- Убедитесь, что таблица Audit_Log существует и пуста
SELECT COUNT(*) AS AuditLogCount
FROM dbo.Audit_Log;

-- Результат: 0 (таблица пуста перед началом)
```

---

### Этап 3: Выполнение скрипта с представлениями

#### 3.1 Открыть файл представлений

1. В SSMS откройте: `final_project_part2_views.sql`

#### 3.2 Выполнить скрипт

**Нажмите `F5` для выполнения**

#### 3.3 Проверка успешного выполнения

```sql
-- Проверка наличия представлений
SELECT 
    name AS ViewName,
    type_desc AS ObjectType
FROM sys.objects
WHERE type = 'V'
  AND name LIKE 'vw_%'
ORDER BY name;

-- Ожидаемый результат (4 представления):
-- ViewName                          | ObjectType
-- ----------------------------------|-------------
-- vw_CompletePortfolioInfo         | VIEW
-- vw_PortfolioComposition          | VIEW
-- vw_PortfolioPerformance          | VIEW
-- vw_PortfolioSummary              | VIEW
-- vw_SecurityMovingAverage         | VIEW
-- vw_SecurityRanking               | VIEW
-- vw_TopPortfoliosByROI            | VIEW
```

#### 3.4 Быстрый тест представлений

```sql
-- Тест 1: Portfolio Summary (должна вернуть портфели или пустой результат если нет данных)
SELECT TOP 5 * FROM dbo.vw_PortfolioSummary;

-- Тест 2: Portfolio Composition (если нет портфелей, результат будет пуст)
SELECT TOP 5 * FROM dbo.vw_PortfolioComposition;

-- Тест 3: Portfolio Performance
SELECT TOP 5 * FROM dbo.vw_PortfolioPerformance;

-- Тест 4: Security Ranking
SELECT TOP 5 * FROM dbo.vw_SecurityRanking;
```

---

### Этап 4: Выполнение скрипта с оптимизированными запросами

#### 4.1 Открыть файл оптимизированных запросов

1. В SSMS откройте: `final_project_part2_optimized_queries.sql`

#### 4.2 Выполнить скрипт

**Нажмите `F5` для выполнения**

#### 4.3 Проверка успешного выполнения

```sql
-- Проверка наличия всех объектов
-- Представления (views)
SELECT name FROM sys.objects 
WHERE type = 'V' 
  AND (name LIKE 'vw_Security%' OR name LIKE 'vw_Portfolio%')
ORDER BY name;

-- Процедуры (procedures)
SELECT name FROM sys.objects 
WHERE type = 'P' 
  AND name LIKE 'sp_%'
ORDER BY name;

-- Ожидаемый результат:
-- - vw_SecurityMovingAverage
-- - vw_PortfolioTransactionHierarchy
-- - vw_CompletePortfolioInfo
-- - vw_TopPortfoliosByROI
-- - sp_BatchProcessTransactions
```

#### 4.4 Быстрый тест оптимизированных запросов

```sql
-- Тест 1: Moving Average (если есть котировки)
SELECT TOP 3 * FROM dbo.vw_SecurityMovingAverage;

-- Тест 2: Portfolio Hierarchy
SELECT TOP 3 * FROM dbo.vw_PortfolioTransactionHierarchy;

-- Тест 3: Complete Portfolio Info
SELECT TOP 3 * FROM dbo.vw_CompletePortfolioInfo;

-- Тест 4: Top Portfolios by ROI
SELECT TOP 3 * FROM dbo.vw_TopPortfoliosByROI;

-- Тест 5: Batch Processing (только если много данных)
-- EXEC dbo.sp_BatchProcessTransactions @BatchSize = 1000, @MaxBatches = 5;
```

---

### Этап 5: Выполнение примеров

#### 5.1 Открыть файл примеров

1. В SSMS откройте: `final_project_part2_examples.sql`

#### 5.2 Выполнить примеры

**Вариант 1: Выполнить весь файл**
- Нажмите `F5`

**Вариант 2: Выполнить отдельные примеры**
- Выделите нужный раздел (например, раздел 1 триггеры)
- Нажмите `F5`

#### 5.3 Просмотр результатов

После выполнения примеров в вкладке "Messages" и "Results" будут выведены:
- ✓ Сообщения о успешном выполнении
- ✓ Результаты запросов
- ✓ Данные из таблиц и представлений

---

## ⚠️ Часто Встречающиеся Ошибки и Решения

### Ошибка 1: "Invalid object name 'dbo.Transactions'"

**Причина:** Part 1 не развернут или неправильная база данных

**Решение:**
```sql
-- Проверьте текущую БД
SELECT DB_NAME();

-- Убедитесь, что Part 1 таблицы существуют
SELECT * FROM INFORMATION_SCHEMA.TABLES;
```

### Ошибка 2: "Trigger 'trg_Transactions_Audit' already exists"

**Причина:** Триггер уже создан

**Решение:**
```sql
-- Удалите старый триггер и создайте новый
DROP TRIGGER IF EXISTS dbo.trg_Transactions_Audit;
GO

-- Затем выполните скрипт с триггерами снова
```

### Ошибка 3: "The multi-part identifier ... could not be bound"

**Причина:** Ошибка в синтаксисе или неправильный столбец

**Решение:**
- Проверьте названия столбцов в таблицах Part 1
- Убедитесь, что все таблицы существуют
- Проверьте синтаксис SQL

### Ошибка 4: "The index entry of length ... is greater than the maximum length of 900"

**Причина:** Индекс создается на очень длинное поле

**Решение:**
- Используйте фильтрованный индекс с WHERE условием
- Уменьшите количество полей в индексе

### Ошибка 5: "Insufficient memory to run this query"

**Причина:** Недостаточно памяти tempdb

**Решение:**
- Выполните batch-обработку с меньшим размером батча
- Увеличьте размер tempdb или запустите обработку в несколько этапов

---

## 📊 Процесс Валидации

После выполнения всех скриптов выполните эту проверку:

```sql
-- 1. Проверка триггеров
PRINT '--- ТРИГГЕРЫ ---';
SELECT name, type_desc FROM sys.triggers WHERE name LIKE 'trg_%';

-- 2. Проверка представлений
PRINT '--- ПРЕДСТАВЛЕНИЯ ---';
SELECT name FROM sys.views WHERE name LIKE 'vw_%';

-- 3. Проверка процедур
PRINT '--- ПРОЦЕДУРЫ ---';
SELECT name FROM sys.procedures WHERE name LIKE 'sp_%' 
  AND SCHEMA_NAME(schema_id) = 'dbo';

-- 4. Проверка функций системы
PRINT '--- ФУНКЦИИ ---';
SELECT name FROM sys.objects WHERE type = 'FN' AND name LIKE 'udf_%';

-- 5. Проверка Audit_Log
PRINT '--- AUDIT LOG ---';
SELECT COUNT(*) AS TotalLogs FROM dbo.Audit_Log;
```

**Ожидаемые результаты:**
- 3 триггера
- 7 представлений
- 1 процедура (sp_BatchProcessTransactions)
- 0 или более логов (зависит от активности)

---

## 🔍 Мониторинг Производительности

### Включение статистики выполнения

```sql
-- Перед выполнением запроса
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Ваш запрос
SELECT * FROM dbo.vw_PortfolioSummary;

-- Результат включит:
-- Table 'Portfolios'. Scan count 1, logical reads 10
-- SQL Server parse and compile time: CPU time = 0 ms, elapsed time = 0 ms
-- SQL Server Execution Times: CPU time = 5 ms, elapsed time = 8 ms
```

### Просмотр плана выполнения

1. В SSMS нажмите `Ctrl+L` перед выполнением запроса
2. Выполните запрос (F5)
3. Просмотрите визуальный план выполнения

---

## ✅ Окончательная Проверка

Когда все скрипты выполнены успешно, проведите эту проверку:

```sql
-- Тест 1: Валидация триггера (должна успешно вставиться)
BEGIN TRY
    INSERT INTO dbo.Transactions (PortfolioID, SecurityID, Quantity, Price, Type, Notes)
    VALUES (1, 1, 100, 150.50, N'BUY', N'Test from execution guide');
    PRINT '✓ Trigger validation successful';
END TRY
BEGIN CATCH
    PRINT '✗ Error: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Тест 2: Проверка логирования
SELECT TOP 1 * FROM dbo.Audit_Log ORDER BY LogID DESC;

-- Тест 3: Проверка представлений
SELECT COUNT(*) AS PortfolioCount FROM dbo.vw_PortfolioSummary;
SELECT COUNT(*) AS CompositionCount FROM dbo.vw_PortfolioComposition;
SELECT COUNT(*) AS PerformanceCount FROM dbo.vw_PortfolioPerformance;
SELECT COUNT(*) AS RankingCount FROM dbo.vw_SecurityRanking;

-- Тест 4: Проверка оптимизированных запросов
SELECT COUNT(*) AS MovingAverageCount FROM dbo.vw_SecurityMovingAverage;
SELECT COUNT(*) AS HierarchyCount FROM dbo.vw_PortfolioTransactionHierarchy;
SELECT COUNT(*) AS CompleteCount FROM dbo.vw_CompletePortfolioInfo;
SELECT COUNT(*) AS TopCount FROM dbo.vw_TopPortfoliosByROI;
```

---

## 📝 Логирование Выполнения

### Сохранение результатов выполнения

```sql
-- 1. Откройте новое окно запроса
-- 2. Выполните все скрипты
-- 3. В SSMS перейдите в Query → Query Options → Results → Text
-- 4. После выполнения перейдите в Messages и скопируйте результаты
-- 5. Сохраните в файл: execution_log_[date].txt
```

### Пример логирования

```
--- EXECUTION LOG ---
Date: 2024-05-15 14:30:00
User: DOMAIN\UserName
Database: PortfolioManagement
SQL Server Version: SQL Server 2019

Stage 1: Triggers
✓ Trigger [trg_Transactions_Audit] created successfully.
✓ Trigger [trg_UpdatePortfolioValue_OnQuoteChange] created successfully.
✓ Trigger [trg_ValidateTransaction] created successfully.
All triggers have been created successfully!

Stage 2: Views
✓ View [vw_PortfolioSummary] created successfully.
✓ View [vw_PortfolioComposition] created successfully.
✓ View [vw_PortfolioPerformance] created successfully.
✓ View [vw_SecurityRanking] created successfully.
All views have been created successfully!

...
```

---

## 🎓 Рекомендации

1. **Сохраняйте логи выполнения** для справки и отладки
2. **Добавьте рекомендуемые индексы** для улучшения производительности
3. **Тестируйте в тестовой среде** перед использованием в production
4. **Регулярно просматривайте Audit_Log** для мониторинга активности
5. **Планируйте архивирование логов** по мере их накопления

---

## 📞 Когда нужна помощь

Если возникли проблемы:

1. Проверьте версию SQL Server: `SELECT @@VERSION;`
2. Убедитесь в наличии Part 1 таблиц
3. Проверьте права доступа пользователя
4. Просмотрите окно "Messages" в SSMS на предмет ошибок
5. Проверьте документацию FINAL_PROJECT_PART2_TRIGGERS_VIEWS_QUERIES.md

---

**Версия Руководства:** 1.0  
**Дата:** 2024-05-15  
**SQL Server:** 2017+
