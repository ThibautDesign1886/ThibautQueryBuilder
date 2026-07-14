-- =============================================================================
-- Indexes for dbo.FinancialQueryBuilder_MasterTable
-- Run after the table is created and loaded.
-- =============================================================================

-- Clustered: physical row order by date then transaction
CREATE CLUSTERED INDEX CIX_Financial_TxnDate_Sequence
    ON dbo.FinancialQueryBuilder_MasterTable (TxnDate, Sequence);
GO

-- Date range filter (most common Query Builder filter)
CREATE NONCLUSTERED INDEX IX_Financial_TxnDate
    ON dbo.FinancialQueryBuilder_MasterTable (TxnDate)
    INCLUDE (Site, Account, DebitDomestic, CreditDomestic, Currency);
GO

-- GL account drill-down
CREATE NONCLUSTERED INDEX IX_Financial_Account
    ON dbo.FinancialQueryBuilder_MasterTable (Account, TxnDate)
    INCLUDE (AccountUnit1, AccountUnit2, AccountUnit3, AccountUnit4,
             AccountDescription, DebitDomestic, CreditDomestic);
GO

-- Period filtering (ControlYear + ControlPeriod)
CREATE NONCLUSTERED INDEX IX_Financial_ControlPeriod
    ON dbo.FinancialQueryBuilder_MasterTable (ControlYear, ControlPeriod, TxnDate)
    INCLUDE (Account, Site, DebitDomestic, CreditDomestic, ControlNumber);
GO

-- Site filter
CREATE NONCLUSTERED INDEX IX_Financial_Site
    ON dbo.FinancialQueryBuilder_MasterTable (Site, TxnDate)
    INCLUDE (Account, DebitDomestic, CreditDomestic, CustVendor);
GO

-- Vendor / Customer filter
CREATE NONCLUSTERED INDEX IX_Financial_CustVendor
    ON dbo.FinancialQueryBuilder_MasterTable (CustVendor, TxnDate)
    INCLUDE (Name, InvoiceVoucher, DebitDomestic, CreditDomestic);
GO

-- Currency filter
CREATE NONCLUSTERED INDEX IX_Financial_Currency
    ON dbo.FinancialQueryBuilder_MasterTable (Currency, TxnDate)
    INCLUDE (DebitForeign, CreditForeign, ExchangeRate);
GO
