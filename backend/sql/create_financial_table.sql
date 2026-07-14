-- =============================================================================
-- FinancialQueryBuilder_MasterTable: Partition + Index Setup
-- Partition boundary: 2026-07-01
--   Partition 1 (LEFT):  TxnDate <= '2026-07-01'  → historical load
--   Partition 2 (RIGHT): TxnDate >  '2026-07-01'  → incremental load
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Partition Function
--    LEFT means the boundary value (2026-07-01) belongs to partition 1.
-- -----------------------------------------------------------------------------
CREATE PARTITION FUNCTION pf_Financial_TxnDate (DATE)
AS RANGE LEFT FOR VALUES ('2026-07-01');
GO

-- -----------------------------------------------------------------------------
-- 2. Partition Scheme
--    Map both partitions to [PRIMARY]. Swap filegroup names if you use
--    separate filegroups per partition (e.g. FG_Historical, FG_Current).
-- -----------------------------------------------------------------------------
CREATE PARTITION SCHEME ps_Financial_TxnDate
AS PARTITION pf_Financial_TxnDate
ALL TO ([PRIMARY]);
GO

-- -----------------------------------------------------------------------------
-- 3. Table with clustered index aligned to the partition scheme
--    The clustered index key must include TxnDate (the partition column).
--    (Sequence, TxnDate) gives uniqueness while keeping rows in date order
--    within each partition.
-- -----------------------------------------------------------------------------
CREATE TABLE dbo.FinancialQueryBuilder_MasterTable (
    Sequence                NVARCHAR(50)        NOT NULL,
    Account                 NVARCHAR(50)            NULL,
    AccountUnit1            NVARCHAR(50)            NULL,
    AccountUnit2            NVARCHAR(50)            NULL,
    AccountUnit3            NVARCHAR(50)            NULL,
    AccountUnit4            NVARCHAR(50)            NULL,
    AccountDescription      NVARCHAR(255)           NULL,
    TxnDate                 DATE                NOT NULL,
    Site                    NVARCHAR(50)            NULL,
    AllocationTransaction   NVARCHAR(50)            NULL,
    Reference               NVARCHAR(100)           NULL,
    DebitDomestic           DECIMAL(18, 4)          NULL,
    CreditDomestic          DECIMAL(18, 4)          NULL,
    ExchangeRate            DECIMAL(10, 6)          NULL,
    DebitForeign            DECIMAL(18, 4)          NULL,
    CreditForeign           DECIMAL(18, 4)          NULL,
    PostedFrom              NVARCHAR(100)           NULL,
    PostedFromSite          NVARCHAR(50)            NULL,
    CustVendor              NVARCHAR(50)            NULL,
    Name                    NVARCHAR(255)           NULL,
    InvoiceVoucher          NVARCHAR(50)            NULL,
    Cancellation            NVARCHAR(10)            NULL,
    InvoiceVchSeq           NVARCHAR(50)            NULL,
    Hierarchy               NVARCHAR(50)            NULL,
    ControlPrefix           NVARCHAR(10)            NULL,
    ControlSite             NVARCHAR(50)            NULL,
    ControlYear             NVARCHAR(10)            NULL,
    ControlPeriod           NVARCHAR(10)            NULL,
    ControlNumber           NVARCHAR(50)            NULL,
    RefControlPrefix        NVARCHAR(10)            NULL,
    RefControlSite          NVARCHAR(50)            NULL,
    RefControlYear          NVARCHAR(10)            NULL,
    RefControlPeriod        NVARCHAR(10)            NULL,
    RefControlNumber        NVARCHAR(50)            NULL,
    CheckNumber             NVARCHAR(50)            NULL,
    CheckDate               DATE                    NULL,
    Currency                NVARCHAR(10)            NULL,
    BankCode                NVARCHAR(50)            NULL,
    Consolidated            NVARCHAR(10)            NULL
)
ON ps_Financial_TxnDate (TxnDate);  -- partition on TxnDate
GO

-- -----------------------------------------------------------------------------
-- 4. Clustered index (partition-aligned)
--    (TxnDate, Sequence) → rows physically ordered by date then transaction,
--    which matches both partition boundaries and the most common sort order.
-- -----------------------------------------------------------------------------
CREATE CLUSTERED INDEX CIX_Financial_TxnDate_Sequence
    ON dbo.FinancialQueryBuilder_MasterTable (TxnDate, Sequence)
    ON ps_Financial_TxnDate (TxnDate);
GO

-- -----------------------------------------------------------------------------
-- 5. Non-clustered indexes for Query Builder filter patterns
-- -----------------------------------------------------------------------------

-- Date range filter (most common — already covered by clustered index,
-- but this NCI adds INCLUDE columns to avoid key lookups on common projections)
CREATE NONCLUSTERED INDEX IX_Financial_TxnDate
    ON dbo.FinancialQueryBuilder_MasterTable (TxnDate)
    INCLUDE (Site, Account, DebitDomestic, CreditDomestic, Currency)
    ON ps_Financial_TxnDate (TxnDate);
GO

-- Account filtering (drill-down by GL account)
CREATE NONCLUSTERED INDEX IX_Financial_Account
    ON dbo.FinancialQueryBuilder_MasterTable (Account, TxnDate)
    INCLUDE (AccountUnit1, AccountUnit2, AccountUnit3, AccountUnit4,
             AccountDescription, DebitDomestic, CreditDomestic)
    ON ps_Financial_TxnDate (TxnDate);
GO

-- Period filtering (ControlYear + ControlPeriod — common for GL reporting)
CREATE NONCLUSTERED INDEX IX_Financial_ControlPeriod
    ON dbo.FinancialQueryBuilder_MasterTable (ControlYear, ControlPeriod, TxnDate)
    INCLUDE (Account, Site, DebitDomestic, CreditDomestic, ControlNumber)
    ON ps_Financial_TxnDate (TxnDate);
GO

-- Site filter
CREATE NONCLUSTERED INDEX IX_Financial_Site
    ON dbo.FinancialQueryBuilder_MasterTable (Site, TxnDate)
    INCLUDE (Account, DebitDomestic, CreditDomestic, CustVendor)
    ON ps_Financial_TxnDate (TxnDate);
GO

-- Vendor / Customer filter
CREATE NONCLUSTERED INDEX IX_Financial_CustVendor
    ON dbo.FinancialQueryBuilder_MasterTable (CustVendor, TxnDate)
    INCLUDE (Name, InvoiceVoucher, DebitDomestic, CreditDomestic)
    ON ps_Financial_TxnDate (TxnDate);
GO

-- Currency filter (for multi-currency reporting)
CREATE NONCLUSTERED INDEX IX_Financial_Currency
    ON dbo.FinancialQueryBuilder_MasterTable (Currency, TxnDate)
    INCLUDE (DebitForeign, CreditForeign, ExchangeRate)
    ON ps_Financial_TxnDate (TxnDate);
GO
