using Microsoft.EntityFrameworkCore;
using PortfolioManagement.Models;

namespace PortfolioManagement.Data
{
    /// <summary>
    /// Entity Framework DbContext for the portfolio management system.
    /// </summary>
    public class PortfolioDbContext : DbContext
    {
        public PortfolioDbContext(DbContextOptions<PortfolioDbContext> options) : base(options)
        {
        }

        public DbSet<Portfolio> Portfolios { get; set; }
        public DbSet<Security> Securities { get; set; }
        public DbSet<Transaction> Transactions { get; set; }
        public DbSet<Quote> Quotes { get; set; }
        public DbSet<Operation> Operations { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            modelBuilder.Entity<Portfolio>(entity =>
            {
                entity.ToTable("Portfolios");
                entity.HasKey(e => e.PortfolioID);
                entity.Property(e => e.PortfolioID).ValueGeneratedOnAdd();
                entity.Property(e => e.Name).IsRequired().HasMaxLength(120);
                entity.Property(e => e.Owner).IsRequired().HasMaxLength(120);
                entity.Property(e => e.Description).HasMaxLength(250);
                entity.Property(e => e.CreatedDate).HasDefaultValueSql("SYSUTCDATETIME()");
                entity.HasIndex(e => new { e.Owner, e.Name }).IsUnique();
            });

            modelBuilder.Entity<Security>(entity =>
            {
                entity.ToTable("Securities");
                entity.HasKey(e => e.SecurityID);
                entity.Property(e => e.SecurityID).ValueGeneratedOnAdd();
                entity.Property(e => e.Ticker).IsRequired().HasMaxLength(10);
                entity.Property(e => e.Name).IsRequired().HasMaxLength(150);
                entity.Property(e => e.Type).IsRequired().HasMaxLength(50);
                entity.Property(e => e.Sector).IsRequired().HasMaxLength(100);
                entity.Property(e => e.CreatedAt).HasDefaultValueSql("SYSUTCDATETIME()");
                entity.HasIndex(e => e.Ticker).IsUnique();
            });

            modelBuilder.Entity<Transaction>(entity =>
            {
                entity.ToTable("Transactions");
                entity.HasKey(e => e.TransactionId);
                entity.Property(e => e.TransactionId).HasColumnName("TransactionID").ValueGeneratedOnAdd();
                entity.Property(e => e.PortfolioId).HasColumnName("PortfolioID");
                entity.Property(e => e.SecurityId).HasColumnName("SecurityID");
                entity.Property(e => e.Quantity).HasPrecision(18, 4);
                entity.Property(e => e.Price).HasPrecision(18, 4);
                entity.Property(e => e.TransactionDate).HasDefaultValueSql("SYSUTCDATETIME()");
                entity.Property(e => e.Type).IsRequired().HasMaxLength(4);
                entity.Property(e => e.Notes).HasMaxLength(250);
            });

            modelBuilder.Entity<Quote>(entity =>
            {
                entity.ToTable("Quotes");
                entity.HasKey(e => e.QuoteID);
                entity.Property(e => e.QuoteID).ValueGeneratedOnAdd();
                entity.Property(e => e.SecurityID).IsRequired();
                entity.Property(e => e.Price).HasPrecision(18, 4);
                entity.Property(e => e.QuoteDate).IsRequired();
                entity.Property(e => e.Volume).IsRequired();
                entity.Property(e => e.Source).HasMaxLength(100);
                entity.HasIndex(e => new { e.SecurityID, e.QuoteDate }).IsUnique();

                entity.HasOne(q => q.Security)
                    .WithMany(s => s.Quotes)
                    .HasForeignKey(q => q.SecurityID)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            modelBuilder.Entity<Operation>(entity =>
            {
                entity.ToTable("Operations");
                entity.HasKey(e => e.OperationID);
                entity.Property(e => e.OperationID).ValueGeneratedOnAdd();
                entity.Property(e => e.PortfolioID).IsRequired();
                entity.Property(e => e.Description).IsRequired().HasMaxLength(250);
                entity.Property(e => e.Amount).HasPrecision(18, 2);
                entity.Property(e => e.OperationDate).HasDefaultValueSql("SYSUTCDATETIME()");
                entity.Property(e => e.Category).HasMaxLength(80);

                entity.HasOne(o => o.Portfolio)
                    .WithMany()
                    .HasForeignKey(o => o.PortfolioID)
                    .OnDelete(DeleteBehavior.Cascade);
            });
        }
    }
}
