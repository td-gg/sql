

create volatile table CSM_Alignment as
(
    select
    assoc_qlid  as QuicklookID
    ,Full_Name  as FullName
    ,Acct_Name  as AccountName
    ,Site_ID    as SiteID
    from adlste_coa.coat_mat_sales_role_qlid a
    where assoc_qlid in('bb186023','dl185038','jo186015','kb186018','pb186048','pk151002','rb186085','yl186040','ts186006')
    Group by 1,2,3,4
) with data no primary index on commit preserve rows;

/* I am underwhelmed by our data hygiene... */
delete from CSM_Alignment where QuicklookID = 'jo186015' and AccountName like 'LinkedIn%';
delete from CSM_Alignment where QuicklookID = 'jo186015' and AccountName like 'PayPal%';
delete from CSM_Alignment where QuicklookID = 'rb186085' and AccountName like 'Blizzard%';
delete from CSM_Alignment where QuicklookID = 'yl186040' and AccountName like 'Gap%';
delete from CSM_Alignment where QuicklookID = 'jo186015' and AccountName like 'LinkedIn%';

/*{{save:csm_alignment.csv}}*/
select  * from CSM_Alignment  order by 1,2,3,4;



/*{{save:csm_mbo_CPU.csv}}*/
locking row for access
Select
 FullName
 ,case when Account_Name is null then '== TOTALS ==' else Account_Name end as Account_Name
 ,case when Site_ID is null then '== SUBTOTALS ==' else Site_ID end as Site_ID
/* cpu slope growth */
  ,sum((last120_Time - last120_Time_avg) * (last120_CPU - last120_CPU_avg))
      / sum((last120_Time - last120_Time_avg) * (last120_Time - last120_Time_avg)) as last120_Slope
  ,sum((last365_Time - last365_Time_avg) * (last365_CPU - last365_CPU_avg))
      / sum((last365_Time - last365_Time_avg) * (last365_Time - last365_Time_avg)) as last365_Slope
  ,cast( (last120_Slope  / nullifzero(last365_Slope))-1 as decimal(9,4)) as  Slope_Growth
/* raw cpu growth, avg() to account different #of days */
  ,avg(last120_CPU) as  last120_CPUamt
  ,avg(last365_CPU) as last365_CPUamt
  ,cast((last120_CPUamt / nullifzero(last365_CPUamt))-1 as decimal(9,4)) as  CPU_Growth
from
(
    Select
     FullName, Account_Name, Site_ID, LogDate
    ,last120_CPU
    ,avg(last120_cpu) over(partition by Site_ID) as  last120_CPU_avg
    ,last120_Time
    ,avg(last120_time) over(partition by Site_ID) as  last120_Time_avg
    ,last365_CPU
    ,avg(last365_cpu) over(partition by Site_ID) as  last365_CPU_avg
    ,last365_Time
    ,avg(last365_time) over(partition by Site_ID) as  last365_Time_avg
    from
    (
        select
         FullName
        ,acct_name as Account_Name
        ,Site_ID
        ,TheDate as LogDate
        ,Eff_Used_CPU_GHz as CPU
        ,case when date_order <=120 then date_order else  null end as last120_Time
        ,case when date_order <=120 then CPU else  null end as last120_CPU
        ,case when date_order between 120 and 365 then date_order else  null end as last365_Time
        ,case when date_order between 120 and 365 then CPU else  null end as last365_CPU
        ,ROW_NUMBER() OVER (partition by Site_ID order by TheDate Desc ) AS date_order
        from adlste_coa.coat_dim_cis_cpu_gtm_system_usage_hist as a
        ---where theDate between  {yr_startdate} and {qtr_enddate}
        join CSM_Alignment   on a.Site_ID = SiteID
    ) as a
) as b
Group by rollup(Account_Name, Site_ID), FullName
order by  1,2,3;
