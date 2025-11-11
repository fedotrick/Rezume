# Лекция 3. Основы C# и .NET для работы с SQL Server

## Цели занятия

- Понять, как .NET-приложение взаимодействует с SQL Server через ADO.NET и Entity Framework Core.
- Научиться вызывать хранимые процедуры, параметры и обрабатывать результаты.
- Управлять жизненным циклом соединений, пулом подключений и диагностикой производительности.
- Организовать надёжную обработку ошибок, логирование и повторные попытки.

## 1. Базовая архитектура интеграции

1. **Слой доступа к данным (DAL)** — изолирует SQL-запросы и хранимые процедуры.
2. **Unit of Work / Repository** — инкапсулирует транзакции и операции над сущностями.
3. **Конфигурация** — строки подключения (Connection String) хранятся в секретах/конфигурации (appsettings.json, Azure Key Vault).

## 2. ADO.NET: быстрый старт

```csharp
using Microsoft.Data.SqlClient;

var connectionString = builder.Configuration.GetConnectionString("TradingDb");
await using var connection = new SqlConnection(connectionString);
await connection.OpenAsync();

await using var command = new SqlCommand("dbo.usp_CreateTrade", connection)
{
    CommandType = CommandType.StoredProcedure,
    CommandTimeout = 60
};

command.Parameters.AddRange(new[]
{
    new SqlParameter("@PortfolioId", SqlDbType.Int) { Value = portfolioId },
    new SqlParameter("@Symbol", SqlDbType.VarChar, 12) { Value = symbol },
    new SqlParameter("@Quantity", SqlDbType.Int) { Value = quantity },
    new SqlParameter("@Price", SqlDbType.Decimal) { Precision = 18, Scale = 4, Value = price }
});

var rowsAffected = await command.ExecuteNonQueryAsync();
```

- `await using` гарантирует возврат соединения в пул.
- Все параметры добавляются явно: защита от SQL-инъекций и стабильность планов.

### 2.1. Чтение данных

```csharp
await using var queryCommand = new SqlCommand("SELECT TOP (10) * FROM dbo.Trades WHERE PortfolioId = @pid", connection);
queryCommand.Parameters.AddWithValue("@pid", portfolioId);

await using var reader = await queryCommand.ExecuteReaderAsync();
while (await reader.ReadAsync())
{
    var trade = new Trade
    {
        TradeId = reader.GetInt64(reader.GetOrdinal("TradeId")),
        Symbol = reader.GetString(reader.GetOrdinal("Symbol")),
        Quantity = reader.GetInt32(reader.GetOrdinal("Quantity")),
        Price = reader.GetDecimal(reader.GetOrdinal("Price"))
    };
    trades.Add(trade);
}
```

Используйте `GetOrdinal` для устойчивости к изменению порядка колонок и минимизации накладных расходов.

## 3. Entity Framework Core

### 3.1. Настройка DbContext

```csharp
services.AddDbContext<TradingContext>(options =>
    options.UseSqlServer(
        configuration.GetConnectionString("TradingDb"),
        sql => sql.CommandTimeout(60)
    ).EnableSensitiveDataLogging(false)
     .EnableDetailedErrors());
```

### 3.2. Маппинг сущностей

```csharp
public class TradingContext : DbContext
{
    public DbSet<Trade> Trades => Set<Trade>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Trade>(entity =>
        {
            entity.ToTable("Trades", "dbo");
            entity.HasKey(e => e.TradeId);
            entity.HasIndex(e => new { e.PortfolioId, e.TradeDate });
            entity.Property(e => e.Price).HasColumnType("decimal(18,4)");
        });
    }
}
```

### 3.3. Выполнение хранимых процедур в EF Core

```csharp
var portfolioIdParam = new SqlParameter("@PortfolioId", SqlDbType.Int) { Value = portfolioId };
var result = await context.TradeSummaries
    .FromSqlRaw("EXEC dbo.usp_GetPortfolioSummary @PortfolioId", portfolioIdParam)
    .AsNoTracking()
    .ToListAsync();
```

- `AsNoTracking()` ускоряет запрос для read-only сценарии.
- Для сложных процедур рассматривайте `DbContext.Database.ExecuteSqlRawAsync`.

## 4. Connection pooling и управление ресурсами

1. **Пул активен по умолчанию** (для `SqlConnection`).
2. **`Max Pool Size`**. Значение по умолчанию 100. При высоконагруженных сервисах увеличивайте до 200–300, но следите за нагрузкой на SQL Server.
3. **Диагностика пула**. Включайте счётчик `NumberOfPooledConnections`, логируйте события `EventId: ConnectionPoolOpening/Closing`.
4. **Проблемы**: `Timeout expired. The timeout period elapsed prior to obtaining a connection from the pool.` — признак утечки соединений, долгих транзакций или недостатка пула.

## 5. Обработка ошибок и повторные попытки

### 5.1. Polly + SqlException

```csharp
var retryPolicy = Policy
    .Handle<SqlException>(ex => TransientErrorNumbers.Contains(ex.Number))
    .WaitAndRetryAsync(3, attempt => TimeSpan.FromSeconds(Math.Pow(2, attempt)));

await retryPolicy.ExecuteAsync(() => command.ExecuteNonQueryAsync());
```

- Transient-ошибки: `4060`, `10928`, `10929`, `40197`, `40501`, `40613`.
- Журналируйте все попытки, чтобы видеть деградацию.

### 5.2. Транзакции

```csharp
await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted);
command.Transaction = transaction;

try
{
    await command.ExecuteNonQueryAsync();
    await transaction.CommitAsync();
}
catch
{
    await transaction.RollbackAsync();
    throw;
}
```

В EF Core используйте `await context.Database.BeginTransactionAsync()` или `IDbContextTransaction`.

## 6. Мониторинг и телеметрия

1. **Logging**: Microsoft.Extensions.Logging с категорией `Microsoft.EntityFrameworkCore.Database.Command`.
2. **DiagnosticListener**: подписывайтесь на события `System.Data.SqlClient.WriteCommandBefore/After`.
3. **Application Insights / OpenTelemetry**: трассируйте `dependency calls` с метриками `duration`, `success`, `resultCode`.
4. **Performance counters**: `SQLClient: Current # pooled connections`, `HardConnectsPerSecond`.

## 7. Best practices для production .NET приложений

- Используйте **минимально необходимые привилегии** для логинов.
- Включайте `Encrypt=true` и `TrustServerCertificate=false` (при наличии корректных сертификатов).
- Храните **миграции** (EF Core Migrations, SSDT, Flyway) вместе с кодом.
- Выполняйте **обязательное тестирование** запросов через интеграционные тесты (docker-compose с SQL Server).
- Планируйте **обновление пакетов** (`Microsoft.Data.SqlClient`, EF Core) и отслеживайте breaking changes.

## 8. Контрольный список

- [ ] Реализован слой доступа к данным с явной параметризацией.
- [ ] Соединения корректно освобождаются и не приводят к истощению пула.
- [ ] Настроены тайм-ауты и политика повторов для временных ошибок.
- [ ] Включено логирование SQL-команд и корреляция с телеметрией.
- [ ] Проведён аудит безопасности (шифрование, секреты, роли).

Интеграция .NET и SQL Server требует дисциплины в работе с соединениями, устойчивости к ошибкам и глубокой наблюдаемости. Эти практики обеспечивают предсказуемую производительность приложений и стабильность финансовых процессов.
