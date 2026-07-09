-- ---------------------------------------------------------------------------
-- Example master table + sample data.
-- This matches metadata_config.json (dbo.MasterReportTable). Replace this with
-- your own master table; just keep the metadata config in sync with its
-- columns and data types.
-- ---------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.tables
    WHERE name = 'MasterReportTable' AND schema_id = SCHEMA_ID('dbo')
)
BEGIN
    CREATE TABLE dbo.MasterReportTable (
        id               INT IDENTITY(1,1) PRIMARY KEY,
        customer_name    NVARCHAR(200),
        customer_email   NVARCHAR(200),
        region           NVARCHAR(100),
        product_category NVARCHAR(100),
        invoice_number   NVARCHAR(50),
        invoice_date     DATE,
        sales_amount     DECIMAL(18, 2),
        quantity         INT,
        discount_percent DECIMAL(5, 2),
        is_paid          BIT
    );
END;
GO

-- Seed a few rows for testing (only if the table is empty).
IF NOT EXISTS (SELECT 1 FROM dbo.MasterReportTable)
BEGIN
    INSERT INTO dbo.MasterReportTable
        (customer_name, customer_email, region, product_category,
         invoice_number, invoice_date, sales_amount, quantity,
         discount_percent, is_paid)
    VALUES
        ('Acme Corp',        'ap@acme.com',      'North', 'Hardware',  'INV-1001', '2026-01-15', 12500.00, 10, 5.00,  1),
        ('Globex',           'billing@globex.io','West',  'Software',  'INV-1002', '2026-02-03',  8400.50,  4, 0.00,  1),
        ('Initech',          'accounts@init.com','East',  'Services',  'INV-1003', '2026-02-20',  3200.00,  2, 10.00, 0),
        ('Umbrella Ltd',     'pay@umbrella.com', 'South', 'Hardware',  'INV-1004', '2026-03-11', 21750.75, 18, 7.50,  1),
        ('Stark Industries', 'ar@stark.com',     'North', 'Software',  'INV-1005', '2026-03-29', 56000.00, 25, 12.00, 1),
        ('Wayne Enterprises','finance@wayne.com','West',  'Services',  'INV-1006', '2026-04-08',  9900.00,  6, 0.00,  0),
        ('Soylent Co',       '',                 'East',  'Hardware',  'INV-1007', '2026-04-22',  1499.99,  1, 0.00,  0),
        ('Hooli',            'ap@hooli.com',     'South', 'Software',  'INV-1008', '2026-05-05', 33250.00, 14, 8.00,  1);
END;
GO
