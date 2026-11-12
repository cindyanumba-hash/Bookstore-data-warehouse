/*
Creates/updates etl.vwCustomerPrepared, a reusable SELECT definition.

Survey matching uses validated customer identifiers. Source answers remain
in staging; this view trims outer spaces and standardises reviewed labels.
An absent response is distinguished from a present but unanswered question.

Active address status is source status_id 1 (Active), confirmed in profiling.
Aggregate DISTINCT valid country IDs per customer BEFORE the customer join.
Unresolved active links produce 'Address data needs review'.
These countries describe currently active address records, not verified
residence or the customer's address at the historical order date.
*/

USE [GravityDW];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF DB_NAME() <> N'GravityDW'
BEGIN
    THROW 51030, 'This script must run in GravityDW.', 1;
END;

IF SCHEMA_ID(N'etl') IS NULL
    EXEC(N'CREATE SCHEMA [etl] AUTHORIZATION [dbo];');
GO

CREATE OR ALTER VIEW [etl].[vwCustomerPrepared]
AS
WITH SurveyRaw AS (
    SELECT
        TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(CustomerIDRaw)), N''))
            AS SourceCustomerID,
        NULLIF(LTRIM(RTRIM(PurchasePreferenceRaw)), N'') AS PreferenceAnswer,
        NULLIF(LTRIM(RTRIM(DiscoverySourceRaw)), N'') AS DiscoveryAnswer
    FROM stg.CustomerSurvey
),
SurveyClean AS (
    SELECT
        SourceCustomerID,
        CASE
            WHEN PreferenceAnswer IS NULL THEN N'Not answered'
            WHEN LOWER(PreferenceAnswer) = N'book club' THEN N'Book Club'
            WHEN LOWER(PreferenceAnswer) = N'online' THEN N'Online'
            WHEN LOWER(PreferenceAnswer) = N'other' THEN N'Other'
            WHEN LOWER(PreferenceAnswer) = N'physical store' THEN N'Physical Store'
            ELSE N'Needs review'
        END AS PurchasePreference,
        CASE
            WHEN DiscoveryAnswer IS NULL THEN N'Not answered'
            WHEN LOWER(DiscoveryAnswer) = N'friend recommendation'
                THEN N'Friend Recommendation'
            WHEN LOWER(DiscoveryAnswer) = N'online advertisement'
                THEN N'Online Advertisement'
            WHEN LOWER(DiscoveryAnswer) = N'other' THEN N'Other'
            WHEN LOWER(DiscoveryAnswer) = N'physical store' THEN N'Physical Store'
            WHEN LOWER(DiscoveryAnswer) = N'web search' THEN N'Web Search'
            ELSE N'Needs review'
        END AS DiscoverySource
    FROM SurveyRaw
),
ActiveCountrySummary AS (
    SELECT
        ca.customer_id,
        COUNT(DISTINCT co.country_id) AS ActiveCountryCount,
        MIN(co.country_id) AS CandidateCountryID,
        MIN(co.country_name) AS CandidateCountryName,
        SUM(CASE
            WHEN a.address_id IS NULL OR co.country_id IS NULL
              OR NULLIF(LTRIM(RTRIM(co.country_name)), '') IS NULL
            THEN 1 ELSE 0
        END) AS InvalidActiveLinks
    FROM stg.CustomerAddress ca
    LEFT JOIN stg.Address a ON a.address_id = ca.address_id
    LEFT JOIN stg.Country co ON co.country_id = a.country_id
    WHERE ca.status_id = 1
    GROUP BY ca.customer_id
)
SELECT
    c.customer_id AS SourceCustomerID,
    CONVERT(BIT, CASE WHEN s.SourceCustomerID IS NULL THEN 0 ELSE 1 END)
        AS SurveyResponseAvailable,
    CONVERT(NVARCHAR(255),
        CASE WHEN s.SourceCustomerID IS NULL THEN N'No survey response'
             ELSE s.PurchasePreference END
    ) AS PurchasePreference,
    CONVERT(NVARCHAR(255),
        CASE WHEN s.SourceCustomerID IS NULL THEN N'No survey response'
             ELSE s.DiscoverySource END
    ) AS DiscoverySource,
    COALESCE(ac.ActiveCountryCount, 0) AS ActiveCountryCount,
    CONVERT(NVARCHAR(40), CASE
        WHEN COALESCE(ac.InvalidActiveLinks, 0) > 0
            THEN N'Address data needs review'
        WHEN COALESCE(ac.ActiveCountryCount, 0) = 0
            THEN N'No active country available'
        WHEN ac.ActiveCountryCount = 1 THEN N'One active country'
        ELSE N'Multiple active countries'
    END) AS AddressCountryCategory,
    CASE WHEN ac.ActiveCountryCount = 1 AND ac.InvalidActiveLinks = 0
         THEN ac.CandidateCountryID ELSE NULL END AS SingleActiveCountryID,
    CONVERT(NVARCHAR(200),
        CASE WHEN ac.ActiveCountryCount = 1 AND ac.InvalidActiveLinks = 0
             THEN LTRIM(RTRIM(ac.CandidateCountryName)) ELSE NULL END
    ) AS SingleActiveCountryName
FROM stg.Customer c
LEFT JOIN SurveyClean s ON s.SourceCustomerID = c.customer_id
LEFT JOIN ActiveCountrySummary ac ON ac.customer_id = c.customer_id;
GO


SELECT
    COUNT(*) AS PreparedRows,
    COUNT(DISTINCT SourceCustomerID) AS DistinctCustomerIDs,
    SUM(CASE WHEN SurveyResponseAvailable = 1 THEN 1 ELSE 0 END)
        AS SurveyRespondents,
    SUM(CASE WHEN SurveyResponseAvailable = 0 THEN 1 ELSE 0 END)
        AS CustomersWithoutSurvey,
    SUM(CASE WHEN PurchasePreference = N'Needs review'
                   OR DiscoverySource = N'Needs review'
             THEN 1 ELSE 0 END) AS SurveyAnswersNeedingReview
FROM etl.vwCustomerPrepared;

SELECT AddressCountryCategory, COUNT(*) AS Customers
FROM etl.vwCustomerPrepared
GROUP BY AddressCountryCategory
ORDER BY AddressCountryCategory;
