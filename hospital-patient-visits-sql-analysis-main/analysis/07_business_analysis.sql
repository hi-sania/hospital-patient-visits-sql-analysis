/*
  Step 07: business analysis

  Each query is self-contained so it can be run independently in SSMS.
  Currency amounts are synthetic Indian rupees (INR).
*/

-- Q1. What are the hospital's headline operating KPIs?
SELECT
    COUNT_BIG(*) AS TotalVisits,
    COUNT(DISTINCT PatientID) AS DistinctPatients,
    CAST(SUM(BillAmount) AS DECIMAL(18,2)) AS TotalBilledRevenueINR,
    CAST(AVG(BillAmount) AS DECIMAL(18,2)) AS AverageBillINR,
    CAST(AVG(CAST(WaitTimeMinutes AS DECIMAL(10,2))) AS DECIMAL(10,2)) AS AverageWaitMinutes,
    CAST(AVG(CAST(SatisfactionScore AS DECIMAL(10,2))) AS DECIMAL(10,2)) AS AverageSatisfaction
FROM dbo.PatientVisits;


-- Q2. How quickly are annual visit volume and revenue growing?
;WITH YearlyPerformance AS (
    SELECT
        YEAR(VisitDate) AS VisitYear,
        COUNT_BIG(*) AS TotalVisits,
        SUM(BillAmount) AS TotalRevenueINR
    FROM dbo.PatientVisits
    GROUP BY YEAR(VisitDate)
),
WithPriorYear AS (
    SELECT
        *,
        LAG(TotalVisits) OVER (ORDER BY VisitYear) AS PriorYearVisits,
        LAG(TotalRevenueINR) OVER (ORDER BY VisitYear) AS PriorYearRevenue
    FROM YearlyPerformance
)
SELECT
    VisitYear,
    TotalVisits,
    CAST(TotalRevenueINR AS DECIMAL(18,2)) AS TotalRevenueINR,
    CAST(
        100.0 * (TotalVisits - PriorYearVisits) / NULLIF(PriorYearVisits, 0)
        AS DECIMAL(10,2)
    ) AS VisitGrowthPercent,
    CAST(
        100.0 * (TotalRevenueINR - PriorYearRevenue) / NULLIF(PriorYearRevenue, 0)
        AS DECIMAL(10,2)
    ) AS RevenueGrowthPercent
FROM WithPriorYear
ORDER BY VisitYear;


-- Q3. How many distinct patients has each doctor treated?
SELECT
    d.DoctorID,
    d.FirstName + ' ' + d.LastName AS DoctorName,
    COUNT(DISTINCT v.PatientID) AS DistinctPatients,
    COUNT_BIG(*) AS TotalVisits
FROM dbo.PatientVisits AS v
INNER JOIN dbo.Dim_Doctor AS d
    ON d.DoctorID = v.DoctorID
GROUP BY d.DoctorID, d.FirstName, d.LastName
ORDER BY DistinctPatients DESC, TotalVisits DESC, d.DoctorID;


-- Q4. How are visit volume and billed revenue split by payment method?
SELECT
    pm.PaymentMethod,
    COUNT_BIG(*) AS TotalVisits,
    CAST(SUM(v.BillAmount) AS DECIMAL(18,2)) AS TotalRevenueINR,
    CAST(
        100.0 * SUM(v.BillAmount) / SUM(SUM(v.BillAmount)) OVER ()
        AS DECIMAL(10,2)
    ) AS RevenueSharePercent
FROM dbo.PatientVisits AS v
INNER JOIN dbo.Dim_PaymentMethod AS pm
    ON pm.PaymentMethodID = v.PaymentMethodID
GROUP BY pm.PaymentMethod
ORDER BY TotalRevenueINR DESC;


-- Q5. How do visit volume and average bill differ by age band at visit date?
;WITH PatientAgeAtVisit AS (
    SELECT
        v.VisitID,
        v.BillAmount,
        DATEDIFF(YEAR, p.DOB, v.VisitDate)
        - CASE
            WHEN DATEADD(YEAR, DATEDIFF(YEAR, p.DOB, v.VisitDate), p.DOB) > v.VisitDate
                THEN 1
            ELSE 0
          END AS PatientAge
    FROM dbo.PatientVisits AS v
    INNER JOIN dbo.Dim_Patient_Clean AS p
        ON p.PatientID = v.PatientID
),
AgeBands AS (
    SELECT
        VisitID,
        BillAmount,
        CASE
            WHEN PatientAge < 18 THEN '0-17'
            WHEN PatientAge BETWEEN 18 AND 35 THEN '18-35'
            WHEN PatientAge BETWEEN 36 AND 55 THEN '36-55'
            ELSE '56+'
        END AS AgeGroup
    FROM PatientAgeAtVisit
)
SELECT
    AgeGroup,
    COUNT_BIG(*) AS TotalVisits,
    CAST(AVG(BillAmount) AS DECIMAL(18,2)) AS AverageBillINR
FROM AgeBands
GROUP BY AgeGroup
ORDER BY CASE AgeGroup
    WHEN '0-17' THEN 1
    WHEN '18-35' THEN 2
    WHEN '36-55' THEN 3
    ELSE 4
END;


-- Q6. Which departments lead revenue within their service category?
;WITH DepartmentPerformance AS (
    SELECT
        d.DepartmentCategory,
        d.DepartmentName,
        COUNT_BIG(*) AS TotalVisits,
        SUM(v.BillAmount) AS TotalRevenueINR
    FROM dbo.PatientVisits AS v
    INNER JOIN dbo.Dim_Department_Clean AS d
        ON d.DepartmentID = v.DepartmentID
    GROUP BY d.DepartmentCategory, d.DepartmentName
)
SELECT
    DepartmentCategory,
    DepartmentName,
    TotalVisits,
    CAST(TotalRevenueINR AS DECIMAL(18,2)) AS TotalRevenueINR,
    DENSE_RANK() OVER (
        PARTITION BY DepartmentCategory
        ORDER BY TotalRevenueINR DESC
    ) AS RevenueRankWithinCategory
FROM DepartmentPerformance
ORDER BY DepartmentCategory, RevenueRankWithinCategory, DepartmentName;


-- Q7. Which departments have service-quality or wait-time risk?
SELECT
    d.DepartmentName,
    COUNT_BIG(*) AS TotalVisits,
    CAST(AVG(CAST(v.SatisfactionScore AS DECIMAL(10,2))) AS DECIMAL(10,2)) AS AverageSatisfaction,
    CAST(AVG(CAST(v.WaitTimeMinutes AS DECIMAL(10,2))) AS DECIMAL(10,2)) AS AverageWaitMinutes,
    CAST(
        100.0 * SUM(CASE WHEN v.WaitTimeMinutes <= 30 THEN 1 ELSE 0 END) / COUNT_BIG(*)
        AS DECIMAL(10,2)
    ) AS VisitsWithin30MinutesPercent
FROM dbo.PatientVisits AS v
INNER JOIN dbo.Dim_Department_Clean AS d
    ON d.DepartmentID = v.DepartmentID
GROUP BY d.DepartmentName
ORDER BY AverageWaitMinutes DESC, AverageSatisfaction;


-- Q8. How does demand differ between weekdays and weekends?
;WITH VisitDayType AS (
    SELECT
        CASE
            WHEN DATEDIFF(DAY, CONVERT(DATE, '19000101', 112), VisitDate) % 7 IN (5, 6)
                THEN 'Weekend'
            ELSE 'Weekday'
        END AS DayType,
        BillAmount
    FROM dbo.PatientVisits
)
SELECT
    DayType,
    COUNT_BIG(*) AS TotalVisits,
    CAST(SUM(BillAmount) AS DECIMAL(18,2)) AS TotalRevenueINR,
    CAST(AVG(BillAmount) AS DECIMAL(18,2)) AS AverageBillINR
FROM VisitDayType
GROUP BY DayType
ORDER BY CASE DayType WHEN 'Weekday' THEN 1 ELSE 2 END;


-- Q9. What is the monthly visit trend, cumulative volume, and year-over-year change?
;WITH MonthlyVisits AS (
    SELECT
        DATEFROMPARTS(YEAR(VisitDate), MONTH(VisitDate), 1) AS MonthStart,
        COUNT_BIG(*) AS TotalVisits
    FROM dbo.PatientVisits
    GROUP BY YEAR(VisitDate), MONTH(VisitDate)
),
MonthlyComparisons AS (
    SELECT
        *,
        LAG(TotalVisits, 12) OVER (ORDER BY MonthStart) AS SameMonthPriorYearVisits
    FROM MonthlyVisits
)
SELECT
    MonthStart,
    TotalVisits,
    SUM(TotalVisits) OVER (
        ORDER BY MonthStart
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS CumulativeVisits,
    CAST(
        100.0 * (TotalVisits - SameMonthPriorYearVisits)
        / NULLIF(SameMonthPriorYearVisits, 0)
        AS DECIMAL(10,2)
    ) AS YearOverYearVisitGrowthPercent
FROM MonthlyComparisons
ORDER BY MonthStart;


-- Q10. Who are the highest-rated doctors with at least 100 visits?
;WITH EligibleDoctors AS (
    SELECT
        d.DoctorID,
        d.FirstName + ' ' + d.LastName AS DoctorName,
        COUNT_BIG(*) AS TotalVisits,
        AVG(CAST(v.SatisfactionScore AS DECIMAL(10,4))) AS AverageSatisfaction,
        AVG(CAST(v.WaitTimeMinutes AS DECIMAL(10,4))) AS AverageWaitMinutes
    FROM dbo.PatientVisits AS v
    INNER JOIN dbo.Dim_Doctor AS d
        ON d.DoctorID = v.DoctorID
    GROUP BY d.DoctorID, d.FirstName, d.LastName
    HAVING COUNT_BIG(*) >= 100
),
RankedDoctors AS (
    SELECT
        *,
        DENSE_RANK() OVER (
            ORDER BY AverageSatisfaction DESC, AverageWaitMinutes, TotalVisits DESC
        ) AS PerformanceRank
    FROM EligibleDoctors
)
SELECT
    PerformanceRank,
    DoctorID,
    DoctorName,
    TotalVisits,
    CAST(AverageSatisfaction AS DECIMAL(10,2)) AS AverageSatisfaction,
    CAST(AverageWaitMinutes AS DECIMAL(10,2)) AS AverageWaitMinutes
FROM RankedDoctors
WHERE PerformanceRank <= 10
ORDER BY PerformanceRank, DoctorID;


-- Q11. What percentage of patients returned for multiple visits?
;WITH PatientVisitFrequency AS (
    SELECT
        PatientID,
        COUNT_BIG(*) AS TotalVisits
    FROM dbo.PatientVisits
    GROUP BY PatientID
)
SELECT
    COUNT_BIG(*) AS DistinctPatients,
    SUM(CASE WHEN TotalVisits >= 2 THEN 1 ELSE 0 END) AS RepeatPatients,
    CAST(
        100.0 * SUM(CASE WHEN TotalVisits >= 2 THEN 1 ELSE 0 END) / COUNT_BIG(*)
        AS DECIMAL(10,2)
    ) AS RepeatPatientRatePercent,
    CAST(AVG(CAST(TotalVisits AS DECIMAL(10,2))) AS DECIMAL(10,2)) AS AverageVisitsPerPatient
FROM PatientVisitFrequency;


-- Q12. What is the most common treatment for each diagnosis (including ties)?
;WITH TreatmentCounts AS (
    SELECT
        d.DiagnosisName,
        t.TreatmentName,
        COUNT_BIG(*) AS TreatmentCount
    FROM dbo.PatientVisits AS v
    INNER JOIN dbo.Dim_Diagnosis AS d
        ON d.DiagnosisID = v.DiagnosisID
    INNER JOIN dbo.Dim_Treatment AS t
        ON t.TreatmentID = v.TreatmentID
    GROUP BY d.DiagnosisName, t.TreatmentName
),
RankedTreatments AS (
    SELECT
        *,
        DENSE_RANK() OVER (
            PARTITION BY DiagnosisName
            ORDER BY TreatmentCount DESC
        ) AS TreatmentRank
    FROM TreatmentCounts
)
SELECT
    DiagnosisName,
    TreatmentName,
    TreatmentCount
FROM RankedTreatments
WHERE TreatmentRank = 1
ORDER BY DiagnosisName, TreatmentName;
