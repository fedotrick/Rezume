using System;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace PortfolioManagement.Common
{
    /// <summary>
    /// Centralized management for SQL Server database connections with connection pooling.
    /// Connection pooling is enabled by default in SqlClient.
    /// </summary>
    public class ConnectionManager : IDisposable
    {
        private readonly string _connectionString;
        private SqlConnection _connection;
        private bool _disposed = false;

        /// <summary>
        /// Creates a ConnectionManager using a connection string.
        /// </summary>
        /// <param name="connectionString">The SQL Server connection string</param>
        public ConnectionManager(string connectionString)
        {
            if (string.IsNullOrWhiteSpace(connectionString))
                throw new ArgumentNullException(nameof(connectionString));

            _connectionString = connectionString;
        }

        /// <summary>
        /// Creates a ConnectionManager using configuration (recommended approach).
        /// </summary>
        /// <param name="configuration">IConfiguration instance to extract connection string</param>
        /// <param name="connectionName">Connection string key in configuration (default: "PortfolioDb")</param>
        public ConnectionManager(IConfiguration configuration, string connectionName = "PortfolioDb")
        {
            if (configuration == null)
                throw new ArgumentNullException(nameof(configuration));

            _connectionString = configuration.GetConnectionString(connectionName);
            
            if (string.IsNullOrWhiteSpace(_connectionString))
                throw new InvalidOperationException($"Connection string '{connectionName}' not found in configuration.");
        }

        /// <summary>
        /// Gets or creates a SqlConnection. Opens the connection if not already open.
        /// </summary>
        public SqlConnection GetConnection()
        {
            if (_connection == null)
            {
                _connection = new SqlConnection(_connectionString);
            }

            if (_connection.State != System.Data.ConnectionState.Open)
            {
                _connection.Open();
            }

            return _connection;
        }

        /// <summary>
        /// Creates a new SqlConnection instance (does not open it).
        /// Useful for short-lived operations with using statements.
        /// </summary>
        public SqlConnection CreateConnection()
        {
            return new SqlConnection(_connectionString);
        }

        /// <summary>
        /// Closes the managed connection if open.
        /// </summary>
        public void CloseConnection()
        {
            if (_connection != null && _connection.State == System.Data.ConnectionState.Open)
            {
                _connection.Close();
            }
        }

        /// <summary>
        /// Gets the configured connection string (without sensitive data for logging).
        /// </summary>
        public string GetConnectionStringForLogging()
        {
            var builder = new SqlConnectionStringBuilder(_connectionString);
            builder.Password = "***HIDDEN***";
            return builder.ToString();
        }

        /// <summary>
        /// Disposes the managed connection and releases resources.
        /// </summary>
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        protected virtual void Dispose(bool disposing)
        {
            if (!_disposed)
            {
                if (disposing)
                {
                    if (_connection != null)
                    {
                        if (_connection.State == System.Data.ConnectionState.Open)
                        {
                            _connection.Close();
                        }
                        _connection.Dispose();
                        _connection = null;
                    }
                }
                _disposed = true;
            }
        }
    }

    /// <summary>
    /// Builder for creating properly configured connection strings.
    /// </summary>
    public static class ConnectionStringBuilder
    {
        /// <summary>
        /// Creates a connection string with recommended connection pooling parameters.
        /// </summary>
        public static string Build(
            string server,
            string database,
            string userId = null,
            string password = null,
            bool integratedSecurity = false,
            int minPoolSize = 5,
            int maxPoolSize = 100,
            int connectionTimeout = 30,
            bool multipleActiveResultSets = true,
            bool encrypt = true,
            bool trustServerCertificate = false)
        {
            var builder = new SqlConnectionStringBuilder
            {
                DataSource = server,
                InitialCatalog = database,
                IntegratedSecurity = integratedSecurity,
                ConnectTimeout = connectionTimeout,
                Pooling = true,
                MinPoolSize = minPoolSize,
                MaxPoolSize = maxPoolSize,
                MultipleActiveResultSets = multipleActiveResultSets,
                Encrypt = encrypt,
                TrustServerCertificate = trustServerCertificate
            };

            if (!integratedSecurity)
            {
                builder.UserID = userId;
                builder.Password = password;
            }

            return builder.ToString();
        }
    }
}
