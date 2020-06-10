/* Pulls all DBQL Data Required for CSM - CONSUMPTION ANALYTICS (COA)
   see comments about each SQL step inline below.

Parameters:
  - startdate:    {startdate}
  - enddate:      {enddate}
  - siteid:       {siteid}
  - dbqlogtbl:    {dbqlogtbl}
  - resusagespma: {resusagespma}
*/



/*{{temp:dim_app.csv}}*/
create volatile table dim_app as
(
  select
   o.AppID
  ,coalesce(p.App_Bucket,'Unknown') as App_Bucket
  ,coalesce(p.Use_Bucket,'Unknown')  as Use_Bucket
  ,coalesce(p.Priority,1e6) as Priority_
  ,coalesce(p.Pattern_Type,'Equal')  as Pattern_Type
  ,coalesce(p.Pattern, o.AppID)      as Pattern
  ,coalesce(p.SiteID, 'None')        as SiteID_
  from (select distinct AppID from {dbqlogtbl}
        where LogDate between {startdate} and {enddate}) as o
  left join "dim_app.csv" as p
    on (case
        when p.Pattern_Type = 'Equal' and o.AppID = p.Pattern then 1
        when p.Pattern_Type = 'Like'  and o.AppID like p.Pattern then 1
        when p.Pattern_Type = 'RegEx'
         and character_length(regexp_substr(o.AppID, p.Pattern,1,1,'i'))>0 then 1
        else 0 end) = 1
  qualify Priority_ = min(Priority_)over(partition by o.AppID)
  where SiteID_ in('default','None') or '{siteid}' like SiteID_
) with data
no primary index
on commit preserve rows;

drop table "dim_app.csv";

/*{{save:dim_app_reconcile.csv}}*/
Select * from dim_App
order by case when  App_Bucket='Unknown' then '!!!' else App_Bucket end asc
;



/*{{temp:dim_statement.csv}}*/
create volatile table dim_statement as
(
  select
   o.StatementType
  ,coalesce(p.Statement_Bucket,'Unknown') as Statement_Bucket
  ,coalesce(p.Priority,1e6) as Priority_
  ,coalesce(p.Pattern_Type,'Equal')  as Pattern_Type
  ,coalesce(p.Pattern, o.StatementType) as Pattern
  ,coalesce(p.SiteID, 'None')        as SiteID_
  from (select distinct StatementType from {dbqlogtbl}
        where LogDate between {startdate} and {enddate}) as o
  left join "dim_statement.csv"  as p
    on (case
        when p.Pattern_Type = 'Equal' and o.StatementType = p.Pattern then 1
        when p.Pattern_Type = 'Like'  and o.StatementType like p.Pattern then 1
        when p.Pattern_Type = 'RegEx'
         and character_length(regexp_substr(o.StatementType, p.Pattern,1,1,'i'))>0 then 1
        else 0 end) = 1
  qualify Priority_ = min(Priority_)over(partition by o.StatementType)
  where SiteID_ in('default','None') or '{siteid}' like SiteID_
) with data
no primary index
on commit preserve rows;

drop table "dim_statement.csv";

/*{{save:dim_statement_reconcile.csv}}*/
Select * from dim_statement
order by case when  Statement_Bucket='Unknown' then '!!!' else Statement_Bucket end asc
;



/* below override sql file allows opportunity to
   replace dim_user.csv with ca_user_xref table
   or a customer-specific table.  To use, review
   and fill-in the .sql file content:
*/
/*{{temp:dim_user.csv}}*/ ;
/*{{file:dim_user_override.sql}}*/ ;

create volatile table dim_user as
(
  select
   o.UserName
  ,o.UserHash
  ,coalesce(p.User_Bucket,'Unknown') as User_Bucket
  ,coalesce(p.User_Department, 'Unknown') as User_Department
  ,coalesce(p.User_SubDepartment, 'Unknown') as User_SubDepartment
  ,coalesce(p.User_Region, 'Unknown') as User_Region
  ,coalesce(p.Priority,1e6) as Priority_
  ,coalesce(p.Pattern_Type,'Equal')  as Pattern_Type
  ,coalesce(p.Pattern, o.UserName) as Pattern
  ,coalesce(p.SiteID, 'None')        as SiteID_
  from (select
         trim(DatabaseName) as UserName
        ,substr(Username,1,3) as first3
        ,substr(Username,floor(character_length(Username)/2)-1,3) as middle3
        ,substr(Username,character_length(Username)-3,3) as last3
        /* generate UserHash value */
        ,trim(cast(from_bytes(hashrow( Username),'base16') as char(9))) ||
         trim(cast(from_bytes(hashrow( first3  ),'base16') as char(9))) ||
         trim(cast(from_bytes(hashrow( middle3 ),'base16') as char(9))) ||
         trim(cast(from_bytes(hashrow( last3   ),'base16') as char(9))) as UserHash
        from dbc.DatabasesV where DBKind = 'U'
        ) as o
  left join "dim_user.csv" as p
    on (case
        when p.Pattern_Type = 'Equal' and o.UserName = p.Pattern then 1
        when p.Pattern_Type = 'Like'  and o.UserName like p.Pattern then 1
        when p.Pattern_Type = 'RegEx'
         and character_length(regexp_substr(o.UserName, p.Pattern,1,1,'i'))>0 then 1
        else 0 end) = 1
    and SiteID_ in('default','None') or '{siteid}' like SiteID_
  qualify Priority_ = min(Priority_)over(partition by o.UserName)
) with data
primary index (UserName)
on commit preserve rows
;

drop table "dim_user.csv"
;

collect stats on dim_user column(UserName)
;

/*{{save:all_users.csv}}*/
Select UserName, UserHash, User_Bucket
,User_Department, User_SubDepartment, User_Region
from dim_user
;



/*
 DAT_DBQL  (Final Output)
=========================
Aggregates DBQL into a per-day, per-hour, per-DIM (app/statement/user) buckets
as defined above.  The intention is this to be a smaller table than the
detail, however, this assumption largely relies on how well the bucketing
logic is defined / setup above.  If the result set is too large, try
revisiting the Bucket definitions above, and make groups smaller / less varied.

Also - many compound metrics have been stripped, to minimize transfer file
size.  As these fields are easily calculated, they will be re-constituted
in Transcend.
*/


/*{{save:DBQL_Core_{siteid}.csv}}*/
/*{{load:{db_coa}_stg.stg_dat_DBQL_Core}}*/
/*{{call:{db_coa}.sp_dat_dbql_core('{fileset_version}')}}*/
SELECT
 '{siteid}'  as Site_ID
,dbql.LogDate
,cast(extract(HOUR from StartTime) as INT format '99') as LogHour
,max(Node_Type)     as Node_Type
,max(Node_Cnt)      as Node_Cnt
,max(vCPU_per_Node) as vCPU_per_Node
,cast(HashAmp()+1 as Integer) as Total_AMPs

/* all other dimensions (bucketed for space) */
,app.App_Bucket
,app.Use_Bucket
,stm.Statement_Bucket
,usr.User_Bucket
,usr.User_Department
,usr.User_SubDepartment

/* ====== Query Metrics ======= */
,zeroifnull(cast(count(1) as BigInt)) as Request_Cnt
,zeroifnull(sum(cast( dbql.Statements as BigInt))) as Query_Cnt
,zeroifnull(sum(cast(case when dbql.StatementGroup like '%=%' then 1 else 0 end as SmallInt))) as Query_MultiStatement_Cnt
/* ErrorCode 3158 == TASM Demotion, aka warning, not real error */
,zeroifnull(sum(cast(case when dbql.ErrorCode not in(0,3158)      then dbql.Statements else 0 end as int))) as Query_Error_Cnt
,zeroifnull(sum(cast(case when dbql.Abortflag = 'Y'               then dbql.Statements else 0 end as int))) as Query_Abort_Cnt
,zeroifnull(sum(cast(case when TotalIOCount = 0                   then dbql.Statements else 0 end as int))) as Query_NoIO_cnt
,zeroifnull(sum(cast(case when TotalIOCount > 0 AND ReqPhysIO = 0 then dbql.Statements else 0 end as int))) as Query_InMem_Cnt
,zeroifnull(sum(cast(case when TotalIOCount > 0 AND ReqPhysIO > 0 then dbql.Statements else 0 end as int))) as Query_PhysIO_Cnt
,zeroifnull(sum(cast(case
         when stm.Statement_Bucket = 'Select'
          and app.App_Bucket not in ('TPT')
          and (ZEROIFNULL( CAST(
             (EXTRACT(HOUR   FROM ((FirstRespTime - FirstStepTime) HOUR(3) TO SECOND(6)) ) * 3600)
            +(EXTRACT(MINUTE FROM ((FirstRespTime - FirstStepTime) HOUR(3) TO SECOND(6)) ) *   60)
            +(EXTRACT(SECOND FROM ((FirstRespTime - FirstStepTime) HOUR(3) TO SECOND(6)) ) *    1)
             as FLOAT))) <= 1  /* Runtime_AMP_Sec */
          and dbql.NumOfActiveAMPs < Total_AMPs
         then 1 else 0 end as Integer))) as Query_Tactical_Cnt
,zeroifnull(avg(cast(dbql.NumSteps * (character_length(dbql.QueryText)/100) as BigInt) )) as Query_Complexity_Score_Avg
,zeroifnull(sum(cast(dbql.NumResultRows as BigInt) )) as Returned_Row_Cnt

/* ====== Metrics: RunTimes ====== */
,sum(cast(dbql.DelayTime as decimal(18,2))) as DelayTime_Sec
,sum(ZEROIFNULL(CAST(
   (EXTRACT(HOUR   FROM ((FirstStepTime - StartTime) HOUR(3) TO SECOND(6)) ) * 3600)
  +(EXTRACT(MINUTE FROM ((FirstStepTime - StartTime) HOUR(3) TO SECOND(6)) ) *   60)
  +(EXTRACT(SECOND FROM ((FirstStepTime - StartTime) HOUR(3) TO SECOND(6)) ) *    1)
   as FLOAT))) as RunTime_Parse_Sec
,sum(ZEROIFNULL(CAST(
   (EXTRACT(HOUR   FROM ((FirstRespTime - FirstStepTime) HOUR(3) TO SECOND(6)) ) * 3600)
  +(EXTRACT(MINUTE FROM ((FirstRespTime - FirstStepTime) HOUR(3) TO SECOND(6)) ) *   60)
  +(EXTRACT(SECOND FROM ((FirstRespTime - FirstStepTime) HOUR(3) TO SECOND(6)) ) *    1)
   as FLOAT))) as Runtime_AMP_Sec
,sum(TotalFirstRespTime)  as RunTime_Total_Sec
,sum(ZEROIFNULL(CAST(
   case when LastRespTime is not null then
   (EXTRACT(HOUR   FROM ((LastRespTime - FirstRespTime) HOUR(3) TO SECOND(6)) ) * 3600)
  +(EXTRACT(MINUTE FROM ((LastRespTime - FirstRespTime) HOUR(3) TO SECOND(6)) ) *   60)
  +(EXTRACT(SECOND FROM ((LastRespTime - FirstRespTime) HOUR(3) TO SECOND(6)) ) *    1)
  else 0 end as FLOAT))) AS TransferTime_Sec


/* ====== Metrics: CPU & IO ====== */
,zeroifnull(sum( cast(dbql.ParserCPUTime  as decimal(18,2)))) as CPU_Parse_Sec
,zeroifnull(sum( cast(dbql.AMPCPUtime     as decimal(18,2)))) as CPU_AMP_Sec
,zeroifnull(max( cast(resusage.CPU_DBS    as decimal(18,2)))) as CPU_Total_DBS_Sec
,zeroifnull(max( cast(resusage.CPU_OS     as decimal(18,2)))) as CPU_Total_OS_Sec
,zeroifnull(max( cast(resusage.CPU_IOWait as decimal(18,2)))) as CPU_Total_IOWait_Sec
,zeroifnull(max( cast(resusage.CPU_Idle   as decimal(18,2)))) as CPU_Total_Idle_Sec
,zeroifnull(max( cast(resusage.CPU_Total  as decimal(18,2)))) as CPU_Total_Sec
/* TODO: check if failed queries log CPU consumption */


,zeroifnull(sum( cast(ReqPhysIO/1e6         as decimal(18,2)))) as IOCntM_Physical
,zeroifnull(sum( cast(TotalIOCount/1e6      as decimal(18,2)))) as IOCntM_Total
,zeroifnull(sum( cast(ReqPhysIOKB/1e6       as decimal(18,2)))) as IOGB_Physical
,zeroifnull(sum( cast(ReqIOKB/1e6           as decimal(18,2)))) as IOGB_Total
,zeroifnull(sum( cast(dbql.UsedIOTA/1e9     as decimal(18,2)))) as IOTA_Used_cntB
,zeroifnull(max( cast(resusage.MaxIOTA_cntB as decimal(18,2)))) as IOTA_SysMax_cntB


/* ====== Metrics: Other ====== */
,zeroifnull(avg(NumOfActiveAMPs)) as NumOfActiveAMPs_Avg
,zeroifnull(sum(SpoolUsage/1e9))  as Spool_GB
,zeroifnull(avg(SpoolUsage/1e9))  as Spool_GB_Avg
,zeroifnull(avg(1-(ReqPhysIO/nullifzero(TotalIOCount)))) as CacheHit_Pct

,zeroifnull(avg((AMPCPUTime / nullifzero(MaxAmpCPUTime*NumOfActiveAMPs))-1)) as CPUSec_Skew_AvgPCt
,zeroifnull(avg((TotalIOCount / nullifzero(MaxAmpIO*NumOfActiveAMPs))-1) ) as IOCnt_Skew_AvgPct


/* Query Runtime by [query count | cpu | iogb] */
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  is NULL OR  dbql.TotalFirstRespTime <1     THEN dbql.Statements ELSE 0 END AS INTEGER)))   as qrycnt_in_runtime_0000_0001
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=1    AND  dbql.TotalFirstRespTime <5     THEN dbql.Statements ELSE 0 END AS INTEGER)))   as qrycnt_in_runtime_0001_0005
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=5    AND  dbql.TotalFirstRespTime <10    THEN dbql.Statements ELSE 0 END AS INTEGER)))   as qrycnt_in_runtime_0005_0010
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=10   AND  dbql.TotalFirstRespTime <30    THEN dbql.Statements ELSE 0 END AS INTEGER)))   as qrycnt_in_runtime_0010_0030
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=30   AND  dbql.TotalFirstRespTime <60    THEN dbql.Statements ELSE 0 END AS INTEGER)))   as qrycnt_in_runtime_0030_0060
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=60   AND  dbql.TotalFirstRespTime <300   THEN dbql.Statements ELSE 0 END AS INTEGER)))   as qrycnt_in_runtime_0060_0300
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=300  AND  dbql.TotalFirstRespTime <600   THEN dbql.Statements ELSE 0 END AS INTEGER)))   as qrycnt_in_runtime_0300_0600
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=600  AND  dbql.TotalFirstRespTime <1800  THEN dbql.Statements ELSE 0 END AS INTEGER)))   as qrycnt_in_runtime_0600_1800
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=1800 AND  dbql.TotalFirstRespTime <3600  THEN dbql.Statements ELSE 0 END AS INTEGER)))   as qrycnt_in_runtime_1800_3600
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >3600                                      THEN dbql.Statements ELSE 0 END AS INTEGER)))   as qrycnt_in_runtime_3600_plus

,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  is NULL OR  dbql.TotalFirstRespTime <1     THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER)))  as cpusec_in_runtime_0000_0001
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=1    AND  dbql.TotalFirstRespTime <5     THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER)))  as cpusec_in_runtime_0001_0005
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=5    AND  dbql.TotalFirstRespTime <10    THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER)))  as cpusec_in_runtime_0005_0010
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=10   AND  dbql.TotalFirstRespTime <30    THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER)))  as cpusec_in_runtime_0010_0030
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=30   AND  dbql.TotalFirstRespTime <60    THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER)))  as cpusec_in_runtime_0030_0060
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=60   AND  dbql.TotalFirstRespTime <300   THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER)))  as cpusec_in_runtime_0060_0300
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=300  AND  dbql.TotalFirstRespTime <600   THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER)))  as cpusec_in_runtime_0300_0600
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=600  AND  dbql.TotalFirstRespTime <1800  THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER)))  as cpusec_in_runtime_0600_1800
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=1800 AND  dbql.TotalFirstRespTime <3600  THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER)))  as cpusec_in_runtime_1800_3600
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >3600                                      THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER)))  as cpusec_in_runtime_3600_plus

,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  is NULL OR  dbql.TotalFirstRespTime <1     THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER)))   as iogb_in_runtime_0000_0001
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=1    AND  dbql.TotalFirstRespTime <5     THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER)))   as iogb_in_runtime_0001_0005
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=5    AND  dbql.TotalFirstRespTime <10    THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER)))   as iogb_in_runtime_0005_0010
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=10   AND  dbql.TotalFirstRespTime <30    THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER)))   as iogb_in_runtime_0010_0030
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=30   AND  dbql.TotalFirstRespTime <60    THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER)))   as iogb_in_runtime_0030_0060
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=60   AND  dbql.TotalFirstRespTime <300   THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER)))   as iogb_in_runtime_0060_0300
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=300  AND  dbql.TotalFirstRespTime <600   THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER)))   as iogb_in_runtime_0300_0600
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=600  AND  dbql.TotalFirstRespTime <1800  THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER)))   as iogb_in_runtime_0600_1800
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >=1800 AND  dbql.TotalFirstRespTime <3600  THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER)))   as iogb_in_runtime_1800_3600
,zeroifnull(SUM(CAST(CASE WHEN  dbql.TotalFirstRespTime  >3600                                      THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER)))   as iogb_in_runtime_3600_plus


/* delaytime by [query count | cpu | iogb] */
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  is NULL OR  dbql.delaytime <1     THEN dbql.Statements ELSE 0 END AS INTEGER))) as qrycnt_in_delaytime_0000_0001
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=1    AND  dbql.delaytime <5     THEN dbql.Statements ELSE 0 END AS INTEGER))) as qrycnt_in_delaytime_0001_0005
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=5    AND  dbql.delaytime <10    THEN dbql.Statements ELSE 0 END AS INTEGER))) as qrycnt_in_delaytime_0005_0010
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=10   AND  dbql.delaytime <30    THEN dbql.Statements ELSE 0 END AS INTEGER))) as qrycnt_in_delaytime_0010_0030
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=30   AND  dbql.delaytime <60    THEN dbql.Statements ELSE 0 END AS INTEGER))) as qrycnt_in_delaytime_0030_0060
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=60   AND  dbql.delaytime <300   THEN dbql.Statements ELSE 0 END AS INTEGER))) as qrycnt_in_delaytime_0060_0300
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=300  AND  dbql.delaytime <600   THEN dbql.Statements ELSE 0 END AS INTEGER))) as qrycnt_in_delaytime_0300_0600
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=600  AND  dbql.delaytime <1800  THEN dbql.Statements ELSE 0 END AS INTEGER))) as qrycnt_in_delaytime_0600_1800
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=1800 AND  dbql.delaytime <3600  THEN dbql.Statements ELSE 0 END AS INTEGER))) as qrycnt_in_delaytime_1800_3600
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >3600                             THEN dbql.Statements ELSE 0 END AS INTEGER))) as qrycnt_in_delaytime_3600_plus

,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  is NULL OR  dbql.delaytime <1     THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER))) as cpusec_in_delaytime_0000_0001
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=1    AND  dbql.delaytime <5     THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER))) as cpusec_in_delaytime_0001_0005
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=5    AND  dbql.delaytime <10    THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER))) as cpusec_in_delaytime_0005_0010
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=10   AND  dbql.delaytime <30    THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER))) as cpusec_in_delaytime_0010_0030
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=30   AND  dbql.delaytime <60    THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER))) as cpusec_in_delaytime_0030_0060
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=60   AND  dbql.delaytime <300   THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER))) as cpusec_in_delaytime_0060_0300
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=300  AND  dbql.delaytime <600   THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER))) as cpusec_in_delaytime_0300_0600
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=600  AND  dbql.delaytime <1800  THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER))) as cpusec_in_delaytime_0600_1800
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >=1800 AND  dbql.delaytime <3600  THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER))) as cpusec_in_delaytime_1800_3600
,zeroifnull(SUM(CAST(CASE WHEN  dbql.delaytime  >3600                             THEN dbql.AMPCPUtime + dbql.ParserCPUTime ELSE 0 END AS INTEGER))) as cpusec_in_delaytime_3600_plus

,zeroifnull(SUM(CAST(CASE WHEN dbql.delaytime  is NULL OR  dbql.delaytime <1     THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER))) as iogb_in_delaytime_0000_0001
,zeroifnull(SUM(CAST(CASE WHEN dbql.delaytime  >=1    AND  dbql.delaytime <5     THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER))) as iogb_in_delaytime_0001_0005
,zeroifnull(SUM(CAST(CASE WHEN dbql.delaytime  >=5    AND  dbql.delaytime <10    THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER))) as iogb_in_delaytime_0005_0010
,zeroifnull(SUM(CAST(CASE WHEN dbql.delaytime  >=10   AND  dbql.delaytime <30    THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER))) as iogb_in_delaytime_0010_0030
,zeroifnull(SUM(CAST(CASE WHEN dbql.delaytime  >=30   AND  dbql.delaytime <60    THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER))) as iogb_in_delaytime_0030_0060
,zeroifnull(SUM(CAST(CASE WHEN dbql.delaytime  >=60   AND  dbql.delaytime <300   THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER))) as iogb_in_delaytime_0060_0300
,zeroifnull(SUM(CAST(CASE WHEN dbql.delaytime  >=300  AND  dbql.delaytime <600   THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER))) as iogb_in_delaytime_0300_0600
,zeroifnull(SUM(CAST(CASE WHEN dbql.delaytime  >=600  AND  dbql.delaytime <1800  THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER))) as iogb_in_delaytime_0600_1800
,zeroifnull(SUM(CAST(CASE WHEN dbql.delaytime  >=1800 AND  dbql.delaytime <3600  THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER))) as iogb_in_delaytime_1800_3600
,zeroifnull(SUM(CAST(CASE WHEN dbql.delaytime  >3600                             THEN ReqIOKB/1e6 ELSE 0 END AS INTEGER))) as iogb_in_delaytime_3600_plus


From {dbqlogtbl} /* pdcrinfo.dbqlogtbl_hst */ as dbql
/* TODO: union with DBQL_Summary table - Paul */

join dim_app as app
  on dbql.AppID = app.AppID

join dim_Statement stm
  on dbql.StatementType = stm.StatementType

join dim_user usr
  on dbql.UserName = usr.UserName

join (
      Select TheDate as LogDate, Floor(TheTime/1e4) as LogHour_
      ,cast(max(NodeType) as varchar(10)) as Node_Type
      ,cast(count(distinct NodeID) as smallint) as Node_Cnt
      ,cast(max(NCPUs) as smallint) as vCPU_per_Node
      ,sum(cast(FullPotentialIOTA/1e9 as decimal(18,0))) as MaxIOTA_cntB
      /* CPU reported in Centiseconds: */
      ,sum(cast(CPUIdle   /100.00 as decimal(18,2))) as CPU_Idle
      ,sum(cast(CPUIOWait /100.00 as decimal(18,2))) as CPU_IOWait
      ,sum(cast(CPUUServ  /100.00 as decimal(18,2))) as CPU_OS
      ,sum(cast(CPUUExec  /100.00 as decimal(18,2))) as CPU_DBS
      ,CPU_Idle+CPU_IOWait+CPU_OS+CPU_DBS as CPU_Total
      from {resusagespma}  /* pdcrinfo.ResUsageSPMA_Hst */
      where TheDate between {startdate} and {enddate}
      Group by LogDate, LogHour_
     ) resusage
  on dbql.LogDate = resusage.LogDate
 and LogHour = resusage.LogHour_

where dbql.LogDate between {startdate} and {enddate}

Group by
 dbql.LogDate
,LogHour
,Site_ID
,app.App_Bucket
,app.Use_Bucket
,stm.Statement_Bucket
,usr.User_Bucket
,usr.User_Department
,usr.User_SubDepartment
;
