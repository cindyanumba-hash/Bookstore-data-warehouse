/*
This creates/replaces two views and one stored procedure, validates preparation,
and displays checks. It DOES NOT insert or update warehouse fact rows here.
Keep extraction/staging unchanged while running this warehouse package.

SSIS control flow, after DFT_Load_DimCustomer:
  SQL_Validate_And_Update_FactOrderLine -> DFT_Load_FactOrderLine

Execute SQL Task (CM_GravityDW, Direct input, ResultSet None,
                 BypassPrepare True, no parameters):
  EXEC etl.uspValidateAndUpdateFactOrderLine @ApplyUpdates = 1;

Data Flow OLE DB Source (CM_GravityDW, SQL command):
  SELECT p.SourceOrderLineID, p.SourceOrderID, p.OrderDateKey, p.BookKey,
         p.CustomerKey, p.DeliveryCountryKey, p.OrderStatusKey,
         p.OrderLineCount, p.RecordedLinePrice, p.LoadBatchID
  FROM etl.vwFactOrderLinePrepared AS p
  WHERE NOT EXISTS (
      SELECT 1 FROM dw.FactOrderLine AS f
      WHERE f.SourceOrderLineID = p.SourceOrderLineID
  );

Connects source DIRECTLY to OLE DB Destination (no Derived Column required).
Destination: CM_GravityDW, Table or view - fast load, [dw].[FactOrderLine].
Map the ten selected columns by identical name. Ignore OrderLineKey (identity).
Keep identity unchecked; Keep nulls unchecked; Check constraints checked.
The validation task must succeed BEFORE the fact Data Flow starts.


*/

USE [GravityDW];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF SCHEMA_ID(N'etl') IS NULL
    EXEC(N'CREATE SCHEMA [etl] AUTHORIZATION [dbo];');
GO

CREATE OR ALTER VIEW etl.vwFactOrderLinePrepared
AS
WITH HistorySummary AS (
    SELECT order_id,
           COUNT(*) AS HistoryRows,
           MIN(status_date) AS FirstStatusDate,
           MAX(status_date) AS LatestStatusDate,
           SUM(CASE WHEN status_date IS NULL THEN 1 ELSE 0 END) AS MissingStatusDates
    FROM stg.OrderHistory
    GROUP BY order_id
),
LatestStatus AS (
    -- Collapse identical statuses at the latest timestamp. Conflicting statuses
    -- remain an issue, so MAX(status_id) never silently chooses between them.
    SELECT h.order_id,
           MAX(h.status_id) AS LatestSourceStatusID,
           COUNT(DISTINCT h.status_id) AS DistinctLatestStatuses,
           SUM(CASE WHEN h.status_id IS NULL THEN 1 ELSE 0 END) AS MissingLatestStatusIDs
    FROM stg.OrderHistory AS h
    JOIN HistorySummary AS hs
      ON hs.order_id = h.order_id AND hs.LatestStatusDate = h.status_date
    GROUP BY h.order_id
)
SELECT
    l.line_id AS SourceOrderLineID,
    l.order_id AS SourceOrderID,
    ISNULL(d.DateKey, 0) AS OrderDateKey,
    ISNULL(b.BookKey, 0) AS BookKey,
    ISNULL(c.CustomerKey, 0) AS CustomerKey,
    ISNULL(dc.DeliveryCountryKey, 0) AS DeliveryCountryKey,
    CASE WHEN hs.HistoryRows IS NULL THEN 0
         ELSE ISNULL(os.OrderStatusKey, 0) END AS OrderStatusKey,
    CAST(1 AS INT) AS OrderLineCount,
    l.price AS RecordedLinePrice,
    l.LoadBatchID,
    CAST(CASE WHEN hs.HistoryRows IS NULL THEN 1 ELSE 0 END AS BIT) AS NoRecordedHistory,
    CAST(CASE WHEN hs.HistoryRows IS NOT NULL AND
             (ls.DistinctLatestStatuses <> 1 OR ls.DistinctLatestStatuses IS NULL
              OR ls.MissingLatestStatusIDs > 0)
         THEN 1 ELSE 0 END AS BIT) AS LatestStatusNeedsReview,
    CAST(CASE WHEN l.line_id IS NULL OR l.line_id <= 0
                   OR l.order_id IS NULL OR l.order_id <= 0
                   OR o.order_id IS NULL OR d.DateKey IS NULL
                   OR b.BookKey IS NULL OR c.CustomerKey IS NULL
                   OR a.address_id IS NULL OR dc.DeliveryCountryKey IS NULL
                   OR l.price IS NULL OR l.price < 0 OR l.LoadBatchID <= 0
                   OR hs.MissingStatusDates > 0 OR hs.FirstStatusDate < o.order_date
                   OR (hs.HistoryRows IS NOT NULL AND
                       (ls.DistinctLatestStatuses <> 1 OR ls.DistinctLatestStatuses IS NULL
                        OR ls.MissingLatestStatusIDs > 0 OR os.OrderStatusKey IS NULL))
         THEN 1 ELSE 0 END AS BIT) AS HasUnexpectedIssue
FROM stg.OrderLine AS l
LEFT JOIN stg.CustOrder AS o ON o.order_id = l.order_id
LEFT JOIN dw.DimDate AS d ON d.FullDate = CAST(o.order_date AS DATE)
LEFT JOIN dw.DimBook AS b ON b.SourceBookID = l.book_id
LEFT JOIN dw.DimCustomer AS c ON c.SourceCustomerID = o.customer_id
LEFT JOIN stg.Address AS a ON a.address_id = o.dest_address_id
LEFT JOIN dw.DimDeliveryCountry AS dc ON dc.SourceCountryID = a.country_id
LEFT JOIN HistorySummary AS hs ON hs.order_id = o.order_id
LEFT JOIN LatestStatus AS ls ON ls.order_id = o.order_id
LEFT JOIN dw.DimOrderStatus AS os ON os.SourceStatusID = ls.LatestSourceStatusID;
GO

CREATE OR ALTER PROCEDURE etl.uspValidateAndUpdateFactOrderLine
    @ApplyUpdates BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET ANSI_NULLS ON;
    SET QUOTED_IDENTIFIER ON;
    SET ANSI_PADDING ON;
    SET ANSI_WARNINGS ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET NUMERIC_ROUNDABORT OFF;

    IF @ApplyUpdates IS NULL
        THROW 51100, 'ApplyUpdates must be 0 (validate only) or 1 (validate and update).', 1;

    IF NOT EXISTS (SELECT 1 FROM stg.OrderLine)
        THROW 51101, 'Staged order lines are empty. Check extraction before loading facts.', 1;

    -- The extraction is a full staging refresh using one shared positive batch.
    IF (SELECT COUNT(DISTINCT LoadBatchID) FROM (
        SELECT LoadBatchID FROM stg.Customer UNION ALL
        SELECT LoadBatchID FROM stg.CustomerSurvey UNION ALL
        SELECT LoadBatchID FROM stg.CustomerAddress UNION ALL
        SELECT LoadBatchID FROM stg.AddressStatus UNION ALL
        SELECT LoadBatchID FROM stg.Address UNION ALL
        SELECT LoadBatchID FROM stg.Country UNION ALL
        SELECT LoadBatchID FROM stg.Book UNION ALL
        SELECT LoadBatchID FROM stg.BookLanguage UNION ALL
        SELECT LoadBatchID FROM stg.CustOrder UNION ALL
        SELECT LoadBatchID FROM stg.OrderLine UNION ALL
        SELECT LoadBatchID FROM stg.OrderHistory UNION ALL
        SELECT LoadBatchID FROM stg.OrderStatus
    ) AS batches) <> 1
        THROW 51102, 'Staging contains different batch IDs. Complete and validate extraction first.', 1;

    IF EXISTS (SELECT 1 FROM stg.OrderLine WHERE LoadBatchID <= 0)
        THROW 51103, 'The shared extraction batch ID must be positive.', 1;

    IF EXISTS (SELECT order_id FROM stg.CustOrder GROUP BY order_id HAVING COUNT(*) > 1)
       OR EXISTS (SELECT address_id FROM stg.Address GROUP BY address_id HAVING COUNT(*) > 1)
       OR EXISTS (SELECT history_id FROM stg.OrderHistory GROUP BY history_id HAVING COUNT(*) > 1)
       OR EXISTS (SELECT status_id FROM stg.OrderStatus GROUP BY status_id HAVING COUNT(*) > 1)
        THROW 51104, 'Duplicate staged order, address, history or status identifiers need review.', 1;

    IF EXISTS (
        SELECT 1 FROM stg.OrderHistory AS h
        LEFT JOIN stg.CustOrder AS o ON o.order_id = h.order_id
        LEFT JOIN stg.OrderStatus AS s ON s.status_id = h.status_id
        WHERE h.history_id IS NULL OR h.history_id <= 0
           OR o.order_id IS NULL OR s.status_id IS NULL
           OR h.status_date IS NULL OR h.status_date < o.order_date
    )
        THROW 51105, 'History contains an invalid identifier, relationship or timestamp. Review staging.', 1;

    IF NOT EXISTS (SELECT 1 FROM dw.DimOrderStatus WHERE OrderStatusKey = 0)
        THROW 51106, 'The technical unknown status member is missing. Check initialization.', 1;

    -- Materialize once for consistent validation and updates in this procedure.
    SELECT * INTO #PreparedFact FROM etl.vwFactOrderLinePrepared;

    IF (SELECT COUNT(*) FROM #PreparedFact) <> (SELECT COUNT(*) FROM stg.OrderLine)
       OR EXISTS (SELECT SourceOrderLineID FROM #PreparedFact
                  GROUP BY SourceOrderLineID HAVING COUNT(*) > 1)
        THROW 51107, 'Fact preparation duplicated or lost order lines. Review keys and joins.', 1;

    IF EXISTS (SELECT 1 FROM #PreparedFact WHERE HasUnexpectedIssue = 1)
        THROW 51108, 'Fact preparation has unresolved issues. Query the prepared view WHERE HasUnexpectedIssue = 1.', 1;

    IF EXISTS (
        SELECT 1 FROM stg.CustOrder AS o
        WHERE NOT EXISTS (SELECT 1 FROM stg.OrderLine AS l WHERE l.order_id = o.order_id)
    )
        THROW 51109, 'A staged order has no lines. Resolve how to retain it in order counts before loading.', 1;

    IF EXISTS (
        SELECT 1 FROM dw.FactOrderLine AS f
        WHERE NOT EXISTS (SELECT 1 FROM #PreparedFact AS p
                          WHERE p.SourceOrderLineID = f.SourceOrderLineID)
    )
        THROW 51110, 'An existing fact line is absent from staging. Investigate; no facts were deleted.', 1;

    IF @ApplyUpdates = 0
    BEGIN
        PRINT 'Fact preparation checks passed. Validate-only mode: no fact rows changed.';
        RETURN;
    END;

    -- Type 1 latest-status changes must reach EXISTING lines as well as new ones.
    -- EXCEPT compares nullable prices correctly; batch alone is not a business change.
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE f
        SET SourceOrderID = p.SourceOrderID,
            OrderDateKey = p.OrderDateKey,
            BookKey = p.BookKey,
            CustomerKey = p.CustomerKey,
            DeliveryCountryKey = p.DeliveryCountryKey,
            OrderStatusKey = p.OrderStatusKey,
            OrderLineCount = p.OrderLineCount,
            RecordedLinePrice = p.RecordedLinePrice,
            LoadBatchID = p.LoadBatchID
        FROM dw.FactOrderLine AS f
        JOIN #PreparedFact AS p ON p.SourceOrderLineID = f.SourceOrderLineID
        WHERE EXISTS (
            SELECT p.SourceOrderID, p.OrderDateKey, p.BookKey, p.CustomerKey,
                   p.DeliveryCountryKey, p.OrderStatusKey, p.OrderLineCount, p.RecordedLinePrice
            EXCEPT
            SELECT f.SourceOrderID, f.OrderDateKey, f.BookKey, f.CustomerKey,
                   f.DeliveryCountryKey, f.OrderStatusKey, f.OrderLineCount, f.RecordedLinePrice
        );
        COMMIT TRANSACTION;
        PRINT 'Checks passed and changed existing facts updated. The Data Flow inserts new facts.';
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER VIEW etl.vwFactOrderLineLoadCheck
AS
SELECT
    (SELECT COUNT(*) FROM stg.OrderLine) AS StagedLines,
    (SELECT COUNT(*) FROM dw.FactOrderLine) AS WarehouseLines,
    (SELECT COUNT(DISTINCT SourceOrderLineID) FROM dw.FactOrderLine) AS DistinctLineIDs,
    (SELECT COUNT(DISTINCT SourceOrderID) FROM dw.FactOrderLine) AS DistinctOrders,
    (SELECT COUNT(*) FROM dw.FactOrderLine WHERE OrderStatusKey = 0) AS UnknownStatusLines,
    (SELECT COUNT(DISTINCT SourceOrderID) FROM dw.FactOrderLine WHERE OrderStatusKey = 0) AS UnknownStatusOrders,
    (SELECT COUNT(*) FROM dw.FactOrderLine WHERE RecordedLinePrice = 0) AS ZeroPriceLines,
    (SELECT COUNT(*) FROM dw.FactOrderLine WHERE RecordedLinePrice IS NULL) AS MissingPriceLines,
    (SELECT COUNT(*) FROM dw.FactOrderLine WHERE RecordedLinePrice < 0) AS NegativePriceLines,
    (SELECT SUM(CAST(price AS DECIMAL(18,2))) FROM stg.OrderLine) AS StagedPriceTotal,
    (SELECT SUM(CAST(RecordedLinePrice AS DECIMAL(18,2))) FROM dw.FactOrderLine) AS WarehousePriceTotal,
    (SELECT COUNT(*) FROM (
        SELECT SourceOrderLineID, SourceOrderID, OrderDateKey, BookKey, CustomerKey,
               DeliveryCountryKey, OrderStatusKey, OrderLineCount, RecordedLinePrice
        FROM etl.vwFactOrderLinePrepared
        EXCEPT
        SELECT SourceOrderLineID, SourceOrderID, OrderDateKey, BookKey, CustomerKey,
               DeliveryCountryKey, OrderStatusKey, OrderLineCount, RecordedLinePrice
        FROM dw.FactOrderLine
    ) AS differences) AS MissingOrDifferentLines,
    (SELECT COUNT(*) FROM dw.FactOrderLine AS f
     WHERE NOT EXISTS (SELECT 1 FROM stg.OrderLine AS l
                       WHERE l.line_id = f.SourceOrderLineID)) AS ExtraWarehouseLines;
GO

-- VALIDATE ONLY: deliberately leaves FactOrderLine unchanged.
EXEC etl.uspValidateAndUpdateFactOrderLine @ApplyUpdates = 0;
GO

-- Checkpoint 1. Expected: 15400 / 15400 / 7550 / 0 / 0 / 7 / 3 / 3 / 0 / 0.
SELECT COUNT(*) AS PreparedLines,
       COUNT(DISTINCT SourceOrderLineID) AS DistinctLineIDs,
       COUNT(DISTINCT SourceOrderID) AS DistinctOrders,
       SUM(CAST(HasUnexpectedIssue AS INT)) AS UnexpectedIssueLines,
       SUM(CAST(LatestStatusNeedsReview AS INT)) AS LatestStatusReviewLines,
       SUM(CAST(NoRecordedHistory AS INT)) AS NoHistoryLines,
       COUNT(DISTINCT CASE WHEN NoRecordedHistory = 1 THEN SourceOrderID END) AS NoHistoryOrders,
       SUM(CASE WHEN RecordedLinePrice = 0 THEN 1 ELSE 0 END) AS ZeroPriceLines,
       SUM(CASE WHEN RecordedLinePrice IS NULL THEN 1 ELSE 0 END) AS MissingPriceLines,
       SUM(CASE WHEN RecordedLinePrice < 0 THEN 1 ELSE 0 END) AS NegativePriceLines
FROM etl.vwFactOrderLinePrepared;

-- Checkpoint 2. Expected: 0 rows. If rows appear, stop before the SSIS fact load.
SELECT * FROM etl.vwFactOrderLinePrepared WHERE HasUnexpectedIssue = 1;

-- Checkpoint 3. Expected: 198, 1505 and 4816, totalling 7 order lines.
SELECT SourceOrderID, COUNT(*) AS OrderLines
FROM etl.vwFactOrderLinePrepared WHERE NoRecordedHistory = 1
GROUP BY SourceOrderID ORDER BY SourceOrderID;

-- Checkpoint 4. Expected: 2641, 3406 and 15233; preserve the recorded zeros.
SELECT SourceOrderLineID, SourceOrderID, RecordedLinePrice
FROM etl.vwFactOrderLinePrepared WHERE RecordedLinePrice = 0
ORDER BY SourceOrderLineID;
