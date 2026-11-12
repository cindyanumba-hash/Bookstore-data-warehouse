/*
Creates an etl schema and a reusable VIEW: etl.vwBookPrepared.
No source/staging records or warehouse table definitions are changed.

The same preparation feeds Type 1 label updates and new-member insertion,
so language classification and text cleaning have one definition.
Normal book keys remain stable on repeat loads.
*/

USE [GravityDW];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF DB_NAME() <> N'GravityDW'
BEGIN
    THROW 51020, 'This script must run in GravityDW.', 1;
END;

IF SCHEMA_ID(N'etl') IS NULL
    EXEC(N'CREATE SCHEMA [etl] AUTHORIZATION [dbo];');
GO

CREATE OR ALTER VIEW [etl].[vwBookPrepared]
AS
SELECT
    b.book_id AS SourceBookID,
    CONVERT(NVARCHAR(400),
        COALESCE(NULLIF(LTRIM(RTRIM(b.title)), ''), N'Unknown title')
    ) AS Title,
    CONVERT(NVARCHAR(13), NULLIF(LTRIM(RTRIM(b.isbn13)), '')) AS ISBN13,
    CONVERT(NVARCHAR(8),
        NULLIF(LTRIM(RTRIM(bl.language_code)), '')
    ) AS LanguageCode,
    CONVERT(NVARCHAR(50),
        COALESCE(NULLIF(LTRIM(RTRIM(bl.language_name)), ''), N'Unknown language')
    ) AS LanguageName,
    CONVERT(NVARCHAR(30),
        CASE
            WHEN LOWER(LTRIM(RTRIM(bl.language_code)))
                 IN ('eng', 'en-us', 'en-gb', 'en-ca')
                THEN N'English'
            WHEN LOWER(LTRIM(RTRIM(bl.language_code))) = 'enm'
                THEN N'Historical English'
            WHEN LOWER(LTRIM(RTRIM(bl.language_code))) = 'mul'
                THEN N'Multilingual'
            WHEN LOWER(LTRIM(RTRIM(bl.language_code))) IN (
                'fre', 'spa', 'grc', 'ger', 'jpn', 'ara', 'nl',
                'zho', 'lat', 'por', 'srp', 'ita', 'rus', 'msa',
                'glg', 'wel', 'swe', 'nor', 'tur', 'gla', 'ale'
            )
                THEN N'Non-English'
            ELSE N'Unknown / needs review'
        END
    ) AS LanguageGroup
FROM [stg].[Book] b
LEFT JOIN [stg].[BookLanguage] bl
    ON bl.language_id = b.language_id;
GO

-- First result: 
SELECT COUNT(*) AS PreparedRows,
       COUNT(DISTINCT SourceBookID) AS DistinctBookIDs
FROM etl.vwBookPrepared;

-- Second result: 
SELECT LanguageGroup, COUNT(*) AS BookTitles
FROM etl.vwBookPrepared
GROUP BY LanguageGroup
ORDER BY LanguageGroup;
