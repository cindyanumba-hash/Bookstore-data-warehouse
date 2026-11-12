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
    THROW 51010, 'The connection must use the GravityDW database.', 1;
END;

IF OBJECT_ID(N'dw.DimDate', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimBook', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimCustomer', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimDeliveryCountry', N'U') IS NULL
   OR OBJECT_ID(N'dw.DimOrderStatus', N'U') IS NULL
BEGIN
    THROW 51011, 'Warehouse dimensions are missing. Run the warehouse DDL first.', 1;
END;

DECLARE @CalendarStart DATE, @CalendarEnd DATE;

SELECT
    @CalendarStart = DATEFROMPARTS(YEAR(MIN(order_date)), 1, 1),
    @CalendarEnd = DATEFROMPARTS(YEAR(MAX(order_date)), 12, 31)
FROM stg.CustOrder;

IF @CalendarStart IS NULL OR @CalendarEnd IS NULL
BEGIN
    THROW 51012, 'No valid staged order dates were found; check staging extraction.', 1;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dw.DimDate WHERE DateKey = 0)
    BEGIN
        INSERT INTO dw.DimDate
            (DateKey, FullDate, CalendarYear, QuarterNumber,
             MonthNumber, MonthName, YearMonth)
        VALUES (0, NULL, NULL, NULL, NULL, N'Unknown', N'Unknown');
    END;

    -- Explicit key 0 requires IDENTITY_INSERT, one dimension at a time.
    IF NOT EXISTS (SELECT 1 FROM dw.DimBook WHERE BookKey = 0)
    BEGIN
        SET IDENTITY_INSERT dw.DimBook ON;
        INSERT INTO dw.DimBook
            (BookKey, SourceBookID, Title, ISBN13,
             LanguageCode, LanguageName, LanguageGroup)
        VALUES
            (0, NULL, N'Unknown book', NULL,
             NULL, N'Unknown language', N'Unknown / needs review');
        SET IDENTITY_INSERT dw.DimBook OFF;
    END;

    IF NOT EXISTS (SELECT 1 FROM dw.DimCustomer WHERE CustomerKey = 0)
    BEGIN
        SET IDENTITY_INSERT dw.DimCustomer ON;
        INSERT INTO dw.DimCustomer
            (CustomerKey, SourceCustomerID, SurveyResponseAvailable,
             PurchasePreference, DiscoverySource, ActiveCountryCount,
             AddressCountryCategory, SingleActiveCountryID,
             SingleActiveCountryName)
        VALUES
            (0, NULL, NULL, N'Unknown customer', N'Unknown customer',
             NULL, N'Unknown customer', NULL, NULL);
        SET IDENTITY_INSERT dw.DimCustomer OFF;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM dw.DimDeliveryCountry WHERE DeliveryCountryKey = 0
    )
    BEGIN
        SET IDENTITY_INSERT dw.DimDeliveryCountry ON;
        INSERT INTO dw.DimDeliveryCountry
            (DeliveryCountryKey, SourceCountryID, CountryName)
        VALUES (0, NULL, N'Unknown delivery country');
        SET IDENTITY_INSERT dw.DimDeliveryCountry OFF;
    END;

    IF NOT EXISTS (SELECT 1 FROM dw.DimOrderStatus WHERE OrderStatusKey = 0)
    BEGIN
        SET IDENTITY_INSERT dw.DimOrderStatus ON;
        INSERT INTO dw.DimOrderStatus
            (OrderStatusKey, SourceStatusID, StatusName)
        VALUES (0, NULL, N'Unknown / no recorded status');
        SET IDENTITY_INSERT dw.DimOrderStatus OFF;
    END;

    -- Build a continuous calendar, adding only dates not already present.
    ;WITH CalendarDates AS (
        SELECT @CalendarStart AS CalendarDate
        UNION ALL
        SELECT DATEADD(DAY, 1, CalendarDate)
        FROM CalendarDates
        WHERE CalendarDate < @CalendarEnd
    )
    INSERT INTO dw.DimDate
        (DateKey, FullDate, CalendarYear, QuarterNumber,
         MonthNumber, MonthName, YearMonth)
    SELECT
        CONVERT(INT, CONVERT(CHAR(8), d.CalendarDate, 112)),
        d.CalendarDate,
        YEAR(d.CalendarDate),
        DATEPART(QUARTER, d.CalendarDate),
        MONTH(d.CalendarDate),
        CASE MONTH(d.CalendarDate)
            WHEN 1 THEN N'January' WHEN 2 THEN N'February'
            WHEN 3 THEN N'March' WHEN 4 THEN N'April'
            WHEN 5 THEN N'May' WHEN 6 THEN N'June'
            WHEN 7 THEN N'July' WHEN 8 THEN N'August'
            WHEN 9 THEN N'September' WHEN 10 THEN N'October'
            WHEN 11 THEN N'November' WHEN 12 THEN N'December'
        END,
        CONVERT(CHAR(7), d.CalendarDate, 126)
    FROM CalendarDates d
    WHERE NOT EXISTS (
        SELECT 1 FROM dw.DimDate existing
        WHERE existing.FullDate = d.CalendarDate
    )
    OPTION (MAXRECURSION 0);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    -- Reset session settings even if an insertion failed while identity was ON.
    SET IDENTITY_INSERT dw.DimBook OFF;
    SET IDENTITY_INSERT dw.DimCustomer OFF;
    SET IDENTITY_INSERT dw.DimDeliveryCountry OFF;
    SET IDENTITY_INSERT dw.DimOrderStatus OFF;
    THROW;
END CATCH;
