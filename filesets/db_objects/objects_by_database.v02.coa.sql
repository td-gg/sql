
create volatile table db_objects as
(
    SELECT
    case when d.DatabaseName is null
        then '**** Totals ****'
        else d.DatabaseName end as DBName
    ,case when d.DatabaseName is null
        then '** Entire Teradata System (minus 20% spool) **'
        else Max(d.CommentString) end as CommentString
    ,cast(sum(MaxPerm)/1024/1024/1024 as decimal(16,1))
    * case when DBName='**** Totals ****'  then 0.8 else 1 end as MaxPermGB
    ,ZeroIfNull(cast(NullifZero(sum(CurrentPerm))/1024/1024/1024 as decimal(16,1))) as CurrentPermGB
    ,ZeroIfNull(cast(CurrentPermGB as decimal(16,4))/nullifzero(cast(MaxPermGB as decimal(16,4)))) as FilledPct
    ,Sum(d.TableCount) as TableCount
    ,Sum(d.ViewCount) as ViewCount
    ,Sum(d.IndexCount) as IndexCount
    ,Sum(d.MacroCount) as MacroCount
    ,Sum(d."SP&TrigCount") as "SP&TrigCount"
    ,Sum(d.UDObjectCount) as UDObjectCount
    ,Sum(d.OtherCount) as OtherCount
    FROM
    (
        Select DatabaseName
        ,sum(MaxPerm) as MaxPerm
        ,sum(CurrentPerm) as CurrentPerm
        FROM dbc.diskspace
        Group By 1
    ) s
    JOIN
    (
        Select t.DatabaseName, '' as CommentString
        ,sum( case when t.TableKind in('T','O','J','Q') then 1 else 0 end) as TableCount
        ,sum( case when t.TableKind in('V') then 1 else 0 end) as ViewCount
        ,sum( case when t.TableKind in('I','N') then 1 else 0 end) as IndexCount
        ,sum( case when t.TableKind in('M') then 1 else 0 end) as MacroCount
        ,sum( case when t.TableKind in('P','E','G') then 1 else 0 end) as "SP&TrigCount"
        ,sum( case when t.TableKind in('A','B','F','R','S','U','D') then 1 else 0 end) as UDObjectCount
        ,sum( case when t.TableKind in('H') then 1 else 0 end) as SysConstCount
        ,sum( case when t.TableKind NOT in('A','B','F','R','S','U','P','E','G','M','I','N','V','T','O','J','Q','D','H') then 1 else 0 end) as OtherCount
        FROM dbc.Tables t
        Group By 1,2
    ) d
    ON s.DatabaseName = d.DatabaseName
    GROUP BY rollup (d.Databasename)
) with data no primary index on commit preserve rows
;


/*{{save:db_objects_all.csv}}*/
Select a.*, rank() over(order by MaxPermGB desc) as GBRank
from db_objects a
;

/*{{save:db_objects_total.csv}}*/
Select a.* from db_objects a
where DBName = '**** Totals ****'
;

/*{{save:db_objects_top10.csv}}*/
Select
 DBName
,CommentString
,cast(MaxPermGB      as int format'ZZZ,ZZZ,ZZZ,ZZZ') as "Max Perm GB"
,cast(CurrentPermGB  as int format'ZZZ,ZZZ,ZZZ,ZZZ') as "Current Perm GB"
,cast(FilledPct      as int format'ZZZ,ZZZ,ZZZ,ZZZ') as "Filled Pct"
,cast(TableCount     as int format'ZZZ,ZZZ,ZZZ,ZZZ') as "Table Count"
,cast(ViewCount      as int format'ZZZ,ZZZ,ZZZ,ZZZ') as "View Count"
,cast(IndexCount     as int format'ZZZ,ZZZ,ZZZ,ZZZ') as "Index Count"
,cast(MacroCount     as int format'ZZZ,ZZZ,ZZZ,ZZZ') as "Macro Count"
,cast("SP&TrigCount" as int format'ZZZ,ZZZ,ZZZ,ZZZ') as "SP&Trig Count"
,cast(UDObjectCount  as int format'ZZZ,ZZZ,ZZZ,ZZZ') as "UDObject Count"
,cast(OtherCount     as int format'ZZZ,ZZZ,ZZZ,ZZZ') as "OtherCount"
,rank() over(order by MaxPermGB desc) as GBRank
from db_objects a
where DBName <> '**** Totals ****'
qualify GBRank <= 10
;