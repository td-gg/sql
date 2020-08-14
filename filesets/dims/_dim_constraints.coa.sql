/* Contraint analysis */                      

create volatile table constraint_details as 
(
        SELECT  
              DatabaseName,
              TableName,
              CASE WHEN IndexType IN ('U','P','Q') THEN 'Unique'
                   WHEN IndexType IN ('K') THEN 'Primary Key'              END (VARCHAR(30)) AS ConstraintType,
              TRIM(TRAILING ',' 
                   FROM XMLAGG(ColumnName || ','
                   ORDER BY ColumnPosition)(VARCHAR(255))) AS Details        FROM  DBC.IndicesV        WHERE IndexType IN ('K','U','P','Q') 
          AND UniqueFlag = 'Y'        GROUP BY  DatabaseName, TableName, IndexType, IndexNumber
        UNION ALL
        SELECT  ChildDB,                ChildTable,                'Foreign Key',
                '>- ' || ParentDB || '.' || ParentTable        FROM    DBC.RI_Distinct_ChildrenV
        UNION ALL
        SELECT  DatabaseName,                TableName,                'Column Constraint',
                REGEXP_SUBSTR(ColumnConstraint,'\(.*',1,1)        FROM    DBC.ColumnsV        WHERE   ColumnConstraint IS NOT NULL
        UNION ALL
        SELECT  DatabaseName,                TableName,                'Table Constraint',
                REGEXP_SUBSTR(ConstraintText,'\(.*',1,1)        FROM    DBC.Table_LevelConstraintsV
        UNION ALL
        SELECT  COL.DatabaseName,
                COL.TableName,
                'Default',
                COL.ColumnName || ' = ' || COL.DefaultValue
        FROM    DBC.ColumnsV COL
        JOIN    DBC.Tablesv TAB
        ON      TAB.DatabaseName = COL.DatabaseName
        AND     TAB.TableName = COL.TableName
        AND     TAB.TableKind = 'T'
        WHERE   COL.DefaultValue IS NOT NULL
) with data no primary index on commit preserve rows
;