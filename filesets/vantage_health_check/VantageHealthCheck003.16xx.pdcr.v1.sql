/*
#######################################################################
Query3)
The below query is for Feature Consumption Cross reference.
The username wil be joined to ca_user_xref to aggregate by SubDepartment and Department
#######################################################################
*/

SELECT
	A.LogDate AS LogDate
  ,A.USERNAME as Username
 --  HASHROW(A.USERNAME) as MaskedUserName,
 ,CAST(B.FEATURENAME AS VARCHAR(100)) AS FEATURENAME
 ,SUM(GETBIT(A.FEATUREUSAGE,(2047 - B.FEATUREBITPOS))) AS FeatureUseCount
  ,COUNT(*) AS RequestCount
  ,SUM(AMPCPUTIME) AS AMPCPUTIME

FROM PDCRINFO.DBQLOGTBL_HST A,
     DBC.QRYLOGFEATURELISTV B
WHERE A.LogDate > DATE-10
GROUP BY
	LogDate,
    USERNAME,
    FeatureName having FeatureUseCount > 0
-- ORDER BY 1,2,3
;
