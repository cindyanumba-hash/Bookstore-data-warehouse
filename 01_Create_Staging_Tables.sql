USE [GravityDW];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Protect against accidental execution in a different database.
IF DB_NAME() <> N'GravityDW'
BEGIN
    THROW 50001, 'Select GravityDW before running this script.', 1;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    -- A repeated or partial prior setup requires inspection, not deletion.
    IF EXISTS (
        SELECT 1
        FROM sys.tables AS t
        JOIN sys.schemas AS s ON s.schema_id = t.schema_id
        WHERE s.name = N'stg'
          AND t.name IN (N'Customer', N'CustomerSurvey', N'CustomerAddress', N'AddressStatus', N'Address', N'Country', N'Book', N'BookLanguage', N'CustOrder', N'OrderLine', N'OrderHistory', N'OrderStatus')
    )
    BEGIN
        THROW 50002, 'One or more planned staging tables already exist. Nothing was replaced. Inspect the existing setup before continuing.', 1;
    END;

    IF SCHEMA_ID(N'stg') IS NULL
        EXEC(N'CREATE SCHEMA [stg] AUTHORIZATION [dbo];');

    CREATE TABLE [stg].[Customer] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_Customer] PRIMARY KEY,
        customer_id INT NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_Customer_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE [stg].[CustomerSurvey] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_CustomerSurvey] PRIMARY KEY,
        CustomerIDRaw NVARCHAR(100) NULL,
        DiscoverySourceRaw NVARCHAR(255) NULL,
        PurchasePreferenceRaw NVARCHAR(255) NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_CustomerSurvey_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE [stg].[CustomerAddress] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_CustomerAddress] PRIMARY KEY,
        customer_id INT NULL,
        address_id INT NULL,
        status_id INT NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_CustomerAddress_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE [stg].[AddressStatus] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_AddressStatus] PRIMARY KEY,
        status_id INT NULL,
        address_status VARCHAR(30) NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_AddressStatus_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE [stg].[Address] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_Address] PRIMARY KEY,
        address_id INT NULL,
        country_id INT NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_Address_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE [stg].[Country] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_Country] PRIMARY KEY,
        country_id INT NULL,
        country_name VARCHAR(200) NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_Country_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE [stg].[Book] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_Book] PRIMARY KEY,
        book_id INT NULL,
        title VARCHAR(400) NULL,
        isbn13 VARCHAR(13) NULL,
        language_id INT NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_Book_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE [stg].[BookLanguage] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_BookLanguage] PRIMARY KEY,
        language_id INT NULL,
        language_code VARCHAR(8) NULL,
        language_name VARCHAR(50) NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_BookLanguage_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE [stg].[CustOrder] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_CustOrder] PRIMARY KEY,
        order_id INT NULL,
        order_date DATETIME NULL,
        customer_id INT NULL,
        dest_address_id INT NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_CustOrder_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE [stg].[OrderLine] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_OrderLine] PRIMARY KEY,
        line_id INT NULL,
        order_id INT NULL,
        book_id INT NULL,
        price DECIMAL(5,2) NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_OrderLine_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE [stg].[OrderHistory] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_OrderHistory] PRIMARY KEY,
        history_id INT NULL,
        order_id INT NULL,
        status_id INT NULL,
        status_date DATETIME NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_OrderHistory_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE [stg].[OrderStatus] (
        [StagingRowID] BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_stg_OrderStatus] PRIMARY KEY,
        status_id INT NULL,
        status_value VARCHAR(20) NULL,
        [LoadBatchID] INT NOT NULL,
        [ExtractedAt] DATETIME2(3) NOT NULL
            CONSTRAINT [DF_stg_OrderStatus_ExtractedAt] DEFAULT (SYSUTCDATETIME())
    );

    COMMIT TRANSACTION;
    PRINT 'Success: all 12 staging tables have been created. No data was loaded.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- Verification: expect 12 rows, each with row_count = 0.
SELECT
    s.name AS schema_name,
    t.name AS table_name,
    SUM(p.rows) AS row_count
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.partitions AS p ON p.object_id = t.object_id
WHERE s.name = N'stg'
  AND p.index_id IN (0, 1)
  AND t.name IN (N'Customer', N'CustomerSurvey', N'CustomerAddress', N'AddressStatus', N'Address', N'Country', N'Book', N'BookLanguage', N'CustOrder', N'OrderLine', N'OrderHistory', N'OrderStatus')
GROUP BY s.name, t.name
ORDER BY t.name;

