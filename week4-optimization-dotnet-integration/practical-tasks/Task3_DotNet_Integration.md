# Задача 3. Интеграция с C# приложением

## Цель

Реализовать .NET-сервис, который вызывает хранимые процедуры SQL Server, обрабатывает результаты, использует connection pooling и собирает метрики производительности.

## Исходные данные

- Файл `scripts/Week4_DotNet_Integration_Samples.cs` — шаблон реализации репозитория и сервисов.
- Хранимые процедуры: `dbo.usp_GetPortfolioSummary`, `dbo.usp_UpsertTrade`, `dbo.usp_GetPerformanceHistory` (создаются скриптом `week4_optimization_examples.sql`).
- .NET 7+ SDK, Microsoft.Data.SqlClient 5.x, Polly 7.x.

## Этапы выполнения

1. **Настройте проект**.
   - Создайте solution и слой `Trading.Infrastructure` (class library) + консольное/веб-приложение.
   - Подключите пакеты `Microsoft.Data.SqlClient`, `Microsoft.Extensions.Logging.Console`, `Polly`, `EFCore` (опционально).

2. **Реализуйте слой доступа к данным**.
   - Используйте паттерн repository из примера `PortfolioRepository`.
   - Все команды должны использовать `await using` и параметризацию (`SqlParameter`).
   - Настройте `CommandTimeout = 60` и логирование через `ILogger`.

3. **Выполнение хранимых процедур**.
   - Реализуйте методы `GetPortfolioSummaryAsync`, `UpsertTradeAsync`, `GetPerformanceHistoryAsync`.
   - Обрабатывайте ошибки через Polly (`WaitAndRetryAsync` для transient-ошибок).
   - Сохраняйте результаты в доменные модели (`PortfolioSummary`, `Trade`, `PerformancePoint`).

4. **Connection pooling и ресурсный менеджмент**.
   - Проверьте, что каждая операция освобождает соединение (см. `await using var connection`).
   - Настройте строку подключения с `Max Pool Size`, `Min Pool Size`, `MultipleActiveResultSets=false` (при необходимости).

5. **Метрики и телеметрия**.
   - Добавьте измерение длительности (Stopwatch или `ActivitySource`).
   - Логируйте `CommandText`, `Duration`, `RowsAffected`, `CorrelationId`.
   - Протестируйте нагрузку (10 одновременных запросов) и оцените латентность.

6. **Тестирование**.
   - Напишите интеграционные тесты (xUnit/NUnit) с использованием `Sqlite` или тестовой базы SQL Server.
   - Проверьте корректность обработки ошибок и повторов.

## Ожидаемый результат

- .NET-приложение или сервис, выполняющий указанные хранимые процедуры.
- Корректное управление соединениями, отсутствие тайм-аутов пула.
- Логи и метрики, демонстрирующие стабильную работу при одновременных запросах.
- Документация (README или Wiki) о настройках строки подключения, логике ретраев и мониторинге.

## Дополнительные материалы

- Лекция 3 (ADO.NET, EF Core, retry-политики).
- `BEST_PRACTICES_AND_RECOMMENDATIONS.md`, разделы «ADO.NET и EF Core» и «Мониторинг».
- Документация: [Microsoft.Data.SqlClient](https://learn.microsoft.com/dotnet/framework/data/adonet/), [EF Core Stored Procedures](https://learn.microsoft.com/ef/core/querying/raw-sql).
