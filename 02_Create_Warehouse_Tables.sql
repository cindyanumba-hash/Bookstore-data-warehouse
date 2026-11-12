/*
This code creates five dimensions and one fact.
It does not load data, seed unknown members, or modify source/staging data.

Validated exceptions to preserve during later ETL:
  - one customer without a survey response;
  - three orders without history (use unknown status);
  - three zero-price lines, matching source: 2641, 3406, 15233.
Zero is a recorded value, not NULL. No evidence establishes why it is zero.
Middle English and Multilingual remain separate from main Non-English totals.

Physical columns follow Gravity_Warehouse_Design_and_Mapping.md.
LoadBatchID remains the existing manually supplied extraction-batch identifier.
No audit-control table or automatic batch-number generator is created here.
*/

USE [GravityDW];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;

IF DB_NAME() <> N'GravityDW'
BEGIN
    THROW 51000, 'Stop: this script must run in GravityDW.', 1;
END;

IF EXISTS (
    SELECT 1
    FROM sys.objects o
    JOIN sys.schemas s ON s.schema_id = o.schema_id
    WHERE s.name = N'dw'
      AND o.name IN (
          N'DimDate', N'DimBook', N'DimCustomer',
          N'DimDeliveryCountry', N'DimOrderStatus', N'FactOrderLine'
      )
)
BEGIN
    THROW 51001, 'Stop: a planned dw object already exists. Inspect it; do not drop it.', 1;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    IF SCHEMA_ID(N'dw') IS NULL
        EXEC(N'CREATE SCHEMA [dw] AUTHORIZATION [dbo];');

    -- DateKey is deterministic YYYYMMDD, rather than an identity.
    -- NULL calendar attributes are allowed for technical unknown key 0.
    CREATE TABLE [dw].[DimDate] (
        DateKey INT NOT NULL CONSTRAINT PK_dw_DimDate PRIMARY KEY,
        FullDate DATE NULL,
        CalendarYear SMALLINT NULL,
        QuarterNumber TINYINT NULL,
        MonthNumber TINYINT NULL,
        MonthName NVARCHAR(10) NOT NULL,
        YearMonth NVARCHAR(7) NOT NULL,
        CONSTRAINT CK_dw_DimDate_DateKey CHECK (
            (DateKey = 0 AND FullDate IS NULL)
            OR (DateKey > 0 AND FullDate IS NOT NULL
                AND DateKey = CONVERT(INT, CONVERT(CHAR(8), FullDate, 112)))
        ),
        CONSTRAINT CK_dw_DimDate_Quarter CHECK (QuarterNumber BETWEEN 1 AND 4),
        CONSTRAINT CK_dw_DimDate_Month CHECK (MonthNumber BETWEEN 1 AND 12)
    );

    CREATE UNIQUE INDEX UX_dw_DimDate_FullDate
        ON [dw].[DimDate] (FullDate) WHERE FullDate IS NOT NULL;

    CREATE TABLE [dw].[DimBook] (
        BookKey INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dw_DimBook PRIMARY KEY,
        SourceBookID INT NULL,
        Title NVARCHAR(400) NOT NULL,
        ISBN13 NVARCHAR(13) NULL,
        LanguageCode NVARCHAR(8) NULL,
        LanguageName NVARCHAR(50) NOT NULL,
        LanguageGroup NVARCHAR(30) NOT NULL,
        CONSTRAINT CK_dw_DimBook_SourceKey CHECK (
            (BookKey = 0 AND SourceBookID IS NULL)
            OR (BookKey > 0 AND SourceBookID IS NOT NULL AND SourceBookID > 0)
        ),
        CONSTRAINT CK_dw_DimBook_LanguageGroup CHECK (
            LanguageGroup IN (
                N'English', N'Historical English', N'Multilingual',
                N'Non-English', N'Unknown / needs review'
            )
        )
    );

    CREATE UNIQUE INDEX UX_dw_DimBook_SourceBookID
        ON [dw].[DimBook] (SourceBookID) WHERE SourceBookID IS NOT NULL;

    CREATE TABLE [dw].[DimCustomer] (
        CustomerKey INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dw_DimCustomer PRIMARY KEY,
        SourceCustomerID INT NULL,
        SurveyResponseAvailable BIT NULL,
        PurchasePreference NVARCHAR(255) NOT NULL,
        DiscoverySource NVARCHAR(255) NOT NULL,
        ActiveCountryCount INT NULL,
        AddressCountryCategory NVARCHAR(40) NOT NULL,
        SingleActiveCountryID INT NULL,
        SingleActiveCountryName NVARCHAR(200) NULL,
        CONSTRAINT CK_dw_DimCustomer_SourceKey CHECK (
            (CustomerKey = 0 AND SourceCustomerID IS NULL)
            OR (CustomerKey > 0 AND SourceCustomerID IS NOT NULL
                AND SourceCustomerID > 0)
        ),
        CONSTRAINT CK_dw_DimCustomer_ActiveCount CHECK (ActiveCountryCount >= 0)
    );

    CREATE UNIQUE INDEX UX_dw_DimCustomer_SourceCustomerID
        ON [dw].[DimCustomer] (SourceCustomerID)
        WHERE SourceCustomerID IS NOT NULL;

    -- SingleActiveCountryID above is a SOURCE identifier, not a warehouse FK

    CREATE TABLE [dw].[DimDeliveryCountry] (
        DeliveryCountryKey INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dw_DimDeliveryCountry PRIMARY KEY,
        SourceCountryID INT NULL,
        CountryName NVARCHAR(200) NOT NULL,
        CONSTRAINT CK_dw_DimDeliveryCountry_SourceKey CHECK (
            (DeliveryCountryKey = 0 AND SourceCountryID IS NULL)
            OR (DeliveryCountryKey > 0 AND SourceCountryID IS NOT NULL
                AND SourceCountryID > 0)
        )
    );

    CREATE UNIQUE INDEX UX_dw_DimDeliveryCountry_SourceCountryID
        ON [dw].[DimDeliveryCountry] (SourceCountryID)
        WHERE SourceCountryID IS NOT NULL;

    CREATE TABLE [dw].[DimOrderStatus] (
        OrderStatusKey INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dw_DimOrderStatus PRIMARY KEY,
        SourceStatusID INT NULL,
        StatusName NVARCHAR(50) NOT NULL,
        CONSTRAINT CK_dw_DimOrderStatus_SourceKey CHECK (
            (OrderStatusKey = 0 AND SourceStatusID IS NULL)
            OR (OrderStatusKey > 0 AND SourceStatusID IS NOT NULL
                AND SourceStatusID > 0)
        )
    );

    CREATE UNIQUE INDEX UX_dw_DimOrderStatus_SourceStatusID
        ON [dw].[DimOrderStatus] (SourceStatusID)
        WHERE SourceStatusID IS NOT NULL;

    CREATE TABLE [dw].[FactOrderLine] (
        OrderLineKey INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dw_FactOrderLine PRIMARY KEY,
        SourceOrderLineID INT NOT NULL,
        SourceOrderID INT NOT NULL,
        OrderDateKey INT NOT NULL,
        BookKey INT NOT NULL,
        CustomerKey INT NOT NULL,
        DeliveryCountryKey INT NOT NULL,
        OrderStatusKey INT NOT NULL,
        OrderLineCount INT NOT NULL
            CONSTRAINT DF_dw_FactOrderLine_LineCount DEFAULT (1),
        RecordedLinePrice DECIMAL(5,2) NULL,
        LoadBatchID INT NOT NULL,
        CONSTRAINT UQ_dw_FactOrderLine_SourceOrderLineID UNIQUE (SourceOrderLineID),
        CONSTRAINT CK_dw_FactOrderLine_SourceLine CHECK (SourceOrderLineID > 0),
        CONSTRAINT CK_dw_FactOrderLine_SourceOrder CHECK (SourceOrderID > 0),
        CONSTRAINT CK_dw_FactOrderLine_LineCount CHECK (OrderLineCount = 1),
        CONSTRAINT CK_dw_FactOrderLine_Batch CHECK (LoadBatchID > 0),
        CONSTRAINT FK_dw_FactOrderLine_Date FOREIGN KEY (OrderDateKey)
            REFERENCES [dw].[DimDate] (DateKey),
        CONSTRAINT FK_dw_FactOrderLine_Book FOREIGN KEY (BookKey)
            REFERENCES [dw].[DimBook] (BookKey),
        CONSTRAINT FK_dw_FactOrderLine_Customer FOREIGN KEY (CustomerKey)
            REFERENCES [dw].[DimCustomer] (CustomerKey),
        CONSTRAINT FK_dw_FactOrderLine_DeliveryCountry FOREIGN KEY (DeliveryCountryKey)
            REFERENCES [dw].[DimDeliveryCountry] (DeliveryCountryKey),
        CONSTRAINT FK_dw_FactOrderLine_OrderStatus FOREIGN KEY (OrderStatusKey)
            REFERENCES [dw].[DimOrderStatus] (OrderStatusKey)
    );

    -- Supports tracing/counting orders and updating every line's latest status.
    CREATE INDEX IX_dw_FactOrderLine_SourceOrderID
        ON [dw].[FactOrderLine] (SourceOrderID);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

PRINT 'Created five empty dimensions and one empty fact table in GravityDW.dw.';

-- Expected: exactly six result rows, each TotalRows = 0.
SELECT N'dw.DimDate' AS WarehouseTable, COUNT(*) AS TotalRows FROM dw.DimDate
UNION ALL SELECT N'dw.DimBook', COUNT(*) FROM dw.DimBook
UNION ALL SELECT N'dw.DimCustomer', COUNT(*) FROM dw.DimCustomer
UNION ALL SELECT N'dw.DimDeliveryCountry', COUNT(*) FROM dw.DimDeliveryCountry
UNION ALL SELECT N'dw.DimOrderStatus', COUNT(*) FROM dw.DimOrderStatus
UNION ALL SELECT N'dw.FactOrderLine', COUNT(*) FROM dw.FactOrderLine;
