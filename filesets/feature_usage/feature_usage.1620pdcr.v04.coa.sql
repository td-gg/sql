/*  extracts the feature logging from dbqlogtbl WITHOUT the cartesian Join
    by user bucket / department. Mapping to Feature_IDs happen in Transcend.

  parameters
     dbqlogtbl  = {dbqlogtbl}
     siteid     = {siteid}
     startdate  = {startdate}
     enddate    = {enddate}
*/



/*  this command loads the dim_user.csv into volatile table, to cover
    use-cases where the ca_user_xref table does NOT exist   */
/*{{temp:dim_user.csv}}*/ ;

/*   this command inserts override sql at this location, to cover
     use-cases where the ca_user_xref table DOES exist   */
/*{{file:dim_user_override.sql}}*/ ;

/*   merge the dim_user (from .csv or ca_user_xref) with all users
     to create dim_user table    */
create volatile table dim_user as
(
  select
   '{siteid}' as Site_ID
  ,o.UserName
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
    and (SiteID_ in('default','None') or '{siteid}' like SiteID_)
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




/*  this is the MAIN DBQL pull   */

/*{{save:feature_department.csv}}*/
/*{{load:{db_stg}.stg_dat_feature_usage_log}}*/
/*{{call:{db_coa}.sp_dat_feature_usage_log('v1')}}*/
SELECT
 '{siteid}' (VARCHAR(100)) as SiteID
,A.LogDate as LogDate
,u.User_Bucket
,u.User_Department
/*  dbsversion is required */
,(Select trim(infoData) as DBSVersion from dbc.dbcinfo where InfoKey = 'VERSION') AS DBSVersion
,count(*) as Request_Count
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -016)))) AS bit016
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -017)))) AS bit017
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -018)))) AS bit018
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -019)))) AS bit019
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -020)))) AS bit020
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -021)))) AS bit021
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -022)))) AS bit022
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -023)))) AS bit023
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -024)))) AS bit024
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -025)))) AS bit025
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -026)))) AS bit026
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -027)))) AS bit027
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -028)))) AS bit028
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -029)))) AS bit029
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -030)))) AS bit030
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -031)))) AS bit031
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -032)))) AS bit032
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -033)))) AS bit033
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -034)))) AS bit034
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -035)))) AS bit035
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -036)))) AS bit036
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -037)))) AS bit037
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -038)))) AS bit038
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -039)))) AS bit039
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -040)))) AS bit040
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -041)))) AS bit041
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -042)))) AS bit042
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -043)))) AS bit043
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -044)))) AS bit044
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -045)))) AS bit045
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -046)))) AS bit046
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -047)))) AS bit047
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -048)))) AS bit048
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -049)))) AS bit049
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -050)))) AS bit050
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -051)))) AS bit051
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -052)))) AS bit052
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -053)))) AS bit053
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -054)))) AS bit054
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -055)))) AS bit055
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -056)))) AS bit056
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -057)))) AS bit057
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -058)))) AS bit058
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -059)))) AS bit059
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -060)))) AS bit060
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -061)))) AS bit061
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -062)))) AS bit062
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -063)))) AS bit063
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -064)))) AS bit064
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -065)))) AS bit065
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -066)))) AS bit066
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -067)))) AS bit067
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -068)))) AS bit068
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -069)))) AS bit069
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -070)))) AS bit070
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -071)))) AS bit071
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -072)))) AS bit072
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -073)))) AS bit073
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -074)))) AS bit074
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -075)))) AS bit075
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -076)))) AS bit076
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -077)))) AS bit077
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -078)))) AS bit078
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -079)))) AS bit079
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -080)))) AS bit080
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -081)))) AS bit081
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -082)))) AS bit082
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -083)))) AS bit083
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -084)))) AS bit084
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -085)))) AS bit085
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -086)))) AS bit086
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -087)))) AS bit087
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -088)))) AS bit088
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -089)))) AS bit089
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -090)))) AS bit090
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -091)))) AS bit091
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -092)))) AS bit092
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -093)))) AS bit093
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -094)))) AS bit094
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -095)))) AS bit095
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -096)))) AS bit096
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -097)))) AS bit097
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -098)))) AS bit098
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -099)))) AS bit099
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -100)))) AS bit100
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -101)))) AS bit101
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -102)))) AS bit102
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -103)))) AS bit103
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -104)))) AS bit104
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -105)))) AS bit105
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -106)))) AS bit106
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -107)))) AS bit107
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -108)))) AS bit108
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -109)))) AS bit109
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -110)))) AS bit110
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -111)))) AS bit111
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -112)))) AS bit112
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -113)))) AS bit113
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -114)))) AS bit114
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -115)))) AS bit115
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -116)))) AS bit116
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -117)))) AS bit117
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -118)))) AS bit118
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -119)))) AS bit119
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -120)))) AS bit120
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -121)))) AS bit121
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -122)))) AS bit122
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -123)))) AS bit123
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -124)))) AS bit124
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -125)))) AS bit125
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -126)))) AS bit126
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -127)))) AS bit127
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -128)))) AS bit128
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -129)))) AS bit129
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -130)))) AS bit130
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -131)))) AS bit131
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -132)))) AS bit132
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -133)))) AS bit133
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -134)))) AS bit134
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -135)))) AS bit135
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -136)))) AS bit136
,ZEROIFNULL(SUM(GETBIT(A.FEATUREUSAGE,(2047 -137)))) AS bit137
FROM {dbqlogtbl} as A /* PDCRINFO.DBQLOGTBL_HST as A */
JOIN dim_user as U
  on a.UserName = u.UserName
WHERE LogDate BETWEEN {startdate} and {enddate}
GROUP BY 1,2,3,4,5
;


/*   Notes:
 - only generates the feature logging per bitpos per day per user dimension
    - the approach provided in documentation is a cartesian join
    - cartesian join approach spools out at many customer sites
 - must be loaded to Transcend to continue:
    - unpivot to row-based bitpos
    - map bitpos to Feature_ID, based on DBSVersion
 - why DBSVersion?
    - there was a regression in FUL, where a new feature was added to the middle
    - caused bit-shift of all bits after that introduction
    - regression was corrected
    - per engineering:
      The regression of mis-aligned bits occurred from build 16.20.33.01
      and above until the builds before 16.20.53.07 build.
      Builds starting from 16.20.53.07 and above are GOOD.
   - this will be accounted for in the coa_dim_feature table in Transcend

*/