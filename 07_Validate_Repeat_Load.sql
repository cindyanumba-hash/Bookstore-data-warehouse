/*
This script reads all six warehouse tables and makes session-only temporary
copies. 
*/
USE [GravityDW];
GO
SET NOCOUNT ON;

-- Change ONLY this value, to 'AFTER', after the SSIS package finishes.
DECLARE @Phase VARCHAR(6) = 'AFTER';

IF @Phase NOT IN ('BEFORE', 'AFTER') OR @Phase IS NULL
    THROW 51200, 'Phase must be BEFORE or AFTER.', 1;

IF DB_NAME() <> N'GravityDW'
    THROW 51201, 'Run this check in GravityDW.', 1;

IF @Phase = 'BEFORE'
BEGIN
    IF OBJECT_ID('tempdb..#GravityRepeat_DimDate') IS NOT NULL
        THROW 51202, 'A baseline exists in this tab. Run the package, then use AFTER; do not replace the baseline.', 1;

    -- Validate current preparation and loaded facts before capturing a baseline.
    EXEC etl.uspValidateAndUpdateFactOrderLine @ApplyUpdates = 0;

    IF EXISTS (
        SELECT 1 FROM etl.vwFactOrderLineLoadCheck
        WHERE StagedLines <> WarehouseLines OR WarehouseLines = 0
           OR MissingOrDifferentLines <> 0 OR ExtraWarehouseLines <> 0
    )
        THROW 51203, 'Current facts do not reconcile with staging. Investigate before the repeat-load test.', 1;

    SELECT * INTO #GravityRepeat_DimDate FROM dw.DimDate;
    SELECT * INTO #GravityRepeat_DimBook FROM dw.DimBook;
    SELECT * INTO #GravityRepeat_DimCustomer FROM dw.DimCustomer;
    SELECT * INTO #GravityRepeat_DimDeliveryCountry FROM dw.DimDeliveryCountry;
    SELECT * INTO #GravityRepeat_DimOrderStatus FROM dw.DimOrderStatus;
    SELECT * INTO #GravityRepeat_FactOrderLine FROM dw.FactOrderLine;

    SELECT N'BEFORE: baseline saved in this SSMS connection' AS TestStage,
           @@SPID AS SessionID, SYSDATETIME() AS CapturedAt;
    SELECT N'dw.DimDate' AS WarehouseTable, COUNT(*) AS BeforeRows FROM #GravityRepeat_DimDate
    UNION ALL SELECT N'dw.DimBook', COUNT(*) FROM #GravityRepeat_DimBook
    UNION ALL SELECT N'dw.DimCustomer', COUNT(*) FROM #GravityRepeat_DimCustomer
    UNION ALL SELECT N'dw.DimDeliveryCountry', COUNT(*) FROM #GravityRepeat_DimDeliveryCountry
    UNION ALL SELECT N'dw.DimOrderStatus', COUNT(*) FROM #GravityRepeat_DimOrderStatus
    UNION ALL SELECT N'dw.FactOrderLine', COUNT(*) FROM #GravityRepeat_FactOrderLine;
    PRINT 'Keep this tab connected. Rerun package 02, then change Phase to AFTER in this tab.';
    RETURN;
END;

-- AFTER mode must have a complete baseline from the SAME connection.
IF OBJECT_ID('tempdb..#GravityRepeat_DimDate') IS NULL
   OR OBJECT_ID('tempdb..#GravityRepeat_DimBook') IS NULL
   OR OBJECT_ID('tempdb..#GravityRepeat_DimCustomer') IS NULL
   OR OBJECT_ID('tempdb..#GravityRepeat_DimDeliveryCountry') IS NULL
   OR OBJECT_ID('tempdb..#GravityRepeat_DimOrderStatus') IS NULL
   OR OBJECT_ID('tempdb..#GravityRepeat_FactOrderLine') IS NULL
    THROW 51204, 'Baseline missing. Start in a new tab using BEFORE, rerun package 02, then use AFTER in that same tab.', 1;

DECLARE @Comparison TABLE (
    WarehouseTable NVARCHAR(40),
    BeforeRows INT,
    AfterRows INT,
    RemovedOrChangedRows INT,
    AddedOrChangedRows INT
);

INSERT INTO @Comparison
SELECT N'dw.DimDate',
       (SELECT COUNT(*) FROM #GravityRepeat_DimDate),
       (SELECT COUNT(*) FROM dw.DimDate),
       (SELECT COUNT(*) FROM (
           SELECT * FROM #GravityRepeat_DimDate
           EXCEPT
           SELECT * FROM dw.DimDate
       ) AS old_differences),
       (SELECT COUNT(*) FROM (
           SELECT * FROM dw.DimDate
           EXCEPT
           SELECT * FROM #GravityRepeat_DimDate
       ) AS new_differences);

INSERT INTO @Comparison
SELECT N'dw.DimBook',
       (SELECT COUNT(*) FROM #GravityRepeat_DimBook),
       (SELECT COUNT(*) FROM dw.DimBook),
       (SELECT COUNT(*) FROM (
           SELECT * FROM #GravityRepeat_DimBook
           EXCEPT
           SELECT * FROM dw.DimBook
       ) AS old_differences),
       (SELECT COUNT(*) FROM (
           SELECT * FROM dw.DimBook
           EXCEPT
           SELECT * FROM #GravityRepeat_DimBook
       ) AS new_differences);

INSERT INTO @Comparison
SELECT N'dw.DimCustomer',
       (SELECT COUNT(*) FROM #GravityRepeat_DimCustomer),
       (SELECT COUNT(*) FROM dw.DimCustomer),
       (SELECT COUNT(*) FROM (
           SELECT * FROM #GravityRepeat_DimCustomer
           EXCEPT
           SELECT * FROM dw.DimCustomer
       ) AS old_differences),
       (SELECT COUNT(*) FROM (
           SELECT * FROM dw.DimCustomer
           EXCEPT
           SELECT * FROM #GravityRepeat_DimCustomer
       ) AS new_differences);

INSERT INTO @Comparison
SELECT N'dw.DimDeliveryCountry',
       (SELECT COUNT(*) FROM #GravityRepeat_DimDeliveryCountry),
       (SELECT COUNT(*) FROM dw.DimDeliveryCountry),
       (SELECT COUNT(*) FROM (
           SELECT * FROM #GravityRepeat_DimDeliveryCountry
           EXCEPT
           SELECT * FROM dw.DimDeliveryCountry
       ) AS old_differences),
       (SELECT COUNT(*) FROM (
           SELECT * FROM dw.DimDeliveryCountry
           EXCEPT
           SELECT * FROM #GravityRepeat_DimDeliveryCountry
       ) AS new_differences);

INSERT INTO @Comparison
SELECT N'dw.DimOrderStatus',
       (SELECT COUNT(*) FROM #GravityRepeat_DimOrderStatus),
       (SELECT COUNT(*) FROM dw.DimOrderStatus),
       (SELECT COUNT(*) FROM (
           SELECT * FROM #GravityRepeat_DimOrderStatus
           EXCEPT
           SELECT * FROM dw.DimOrderStatus
       ) AS old_differences),
       (SELECT COUNT(*) FROM (
           SELECT * FROM dw.DimOrderStatus
           EXCEPT
           SELECT * FROM #GravityRepeat_DimOrderStatus
       ) AS new_differences);

INSERT INTO @Comparison
SELECT N'dw.FactOrderLine',
       (SELECT COUNT(*) FROM #GravityRepeat_FactOrderLine),
       (SELECT COUNT(*) FROM dw.FactOrderLine),
       (SELECT COUNT(*) FROM (
           SELECT * FROM #GravityRepeat_FactOrderLine
           EXCEPT
           SELECT * FROM dw.FactOrderLine
       ) AS old_differences),
       (SELECT COUNT(*) FROM (
           SELECT * FROM dw.FactOrderLine
           EXCEPT
           SELECT * FROM #GravityRepeat_FactOrderLine
       ) AS new_differences);

SELECT WarehouseTable, BeforeRows, AfterRows,
       RemovedOrChangedRows, AddedOrChangedRows,
       CASE WHEN BeforeRows = AfterRows
                  AND RemovedOrChangedRows = 0 AND AddedOrChangedRows = 0
            THEN N'PASS' ELSE N'REVIEW' END AS TestResult
FROM @Comparison ORDER BY WarehouseTable;

SELECT * FROM etl.vwFactOrderLineLoadCheck;

IF EXISTS (
    SELECT 1 FROM @Comparison
    WHERE BeforeRows <> AfterRows OR RemovedOrChangedRows <> 0 OR AddedOrChangedRows <> 0
)
    THROW 51205, 'Repeat-load differences found. Review the comparison; do not assume the rerun preserved the warehouse.', 1;

IF EXISTS (
    SELECT 1 FROM etl.vwFactOrderLineLoadCheck
    WHERE StagedLines <> WarehouseLines
       OR MissingOrDifferentLines <> 0 OR ExtraWarehouseLines <> 0
)
    THROW 51206, 'Facts no longer reconcile with staging. Review extraction/preparation and the package.', 1;

PRINT 'PASS: all six warehouse tables retained their rows, keys and values, and facts reconcile with preparation.';

