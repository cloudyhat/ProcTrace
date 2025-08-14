WITH ProcInfo AS (
    SELECT 
        p.object_id,
        OBJECT_SCHEMA_NAME(p.object_id) + '.' + OBJECT_NAME(p.object_id) AS ProcName,
        m.definition AS FullDefinition
    FROM sys.procedures p
    JOIN sys.sql_modules m ON p.object_id = m.object_id
),

ProcCalls AS (
    SELECT
        OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id) AS ParentName,
        COALESCE(
            d.referenced_schema_name + '.' + d.referenced_entity_name,
            dp.default_schema_name + '.' + d.referenced_entity_name
        ) AS ChildName,
        ISNULL(d.referenced_id,
               OBJECT_ID(
                   COALESCE(d.referenced_schema_name, dp.default_schema_name) + '.' + d.referenced_entity_name
               )) AS ChildID
    FROM sys.sql_expression_dependencies d
    CROSS JOIN sys.database_principals dp
    WHERE dp.name = USER_NAME()
      AND OBJECTPROPERTY(d.referencing_id, 'IsProcedure') = 1
      AND d.referenced_entity_name IS NOT NULL
),

RecursiveCalls AS (
    SELECT 
        pi.object_id AS RootID,
        pi.ProcName AS RootProc,
        pi.ProcName AS CalledProc,
        pi.FullDefinition,
        0 AS Level
    FROM ProcInfo pi

    UNION ALL

    SELECT 
        rc.RootID,
        rc.RootProc,
        pi.ProcName AS CalledProc,
        pi.FullDefinition,
        rc.Level + 1
    FROM RecursiveCalls rc
    JOIN ProcCalls pc ON rc.CalledProc = pc.ParentName
    JOIN ProcInfo pi ON pc.ChildName = pi.ProcName
    WHERE rc.Level < 10
),

DmlLines AS (
    SELECT 
        rc.RootProc,
        rc.CalledProc,
        LTRIM(RTRIM(Line.value)) AS DML_Line,
        CASE 
            WHEN Line.value LIKE '%INSERT INTO%' THEN 1
            WHEN Line.value LIKE '%UPDATE%' THEN 2
            ELSE 0
        END AS DmlType
    FROM RecursiveCalls rc
    CROSS APPLY STRING_SPLIT(rc.FullDefinition, CHAR(10)) AS Line
    WHERE 
        (Line.value LIKE '%INSERT INTO%' OR Line.value LIKE '%UPDATE%')
        AND LEFT(LTRIM(Line.value), 2) NOT IN ('--', '/*')
        AND CHARINDEX('*/', LTRIM(Line.value)) = 0            
),

Aggregated AS (
    SELECT 
        rc.RootProc,
        (
            SELECT STRING_AGG(CalledProc, ', ')
            FROM (
                SELECT DISTINCT CalledProc
                FROM RecursiveCalls rc2
                WHERE rc2.RootProc = rc.RootProc
            ) AS distinctCalls
        ) AS CalledSPs,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM DmlLines dl 
                WHERE dl.RootProc = rc.RootProc AND dl.DmlType = 1
            ) THEN 'Yes' ELSE 'No' 
        END AS AnyInsert,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM DmlLines dl 
                WHERE dl.RootProc = rc.RootProc AND dl.DmlType = 2
            ) THEN 'Yes' ELSE 'No' 
        END AS AnyUpdate,
        (
            SELECT STRING_AGG(DML_Line, CHAR(10))
            FROM (
                SELECT DISTINCT DML_Line
                FROM DmlLines dl
                WHERE dl.RootProc = rc.RootProc
            ) AS distinctLines
        ) AS DML_Lines
    FROM RecursiveCalls rc
    GROUP BY rc.RootProc
)

SELECT 
    RootProc AS [Procedure],
    CalledSPs AS [Calls_These_SPs],
    AnyInsert,
    AnyUpdate,
    DML_Lines
FROM Aggregated
ORDER BY RootProc;
