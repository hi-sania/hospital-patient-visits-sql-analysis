/*
  Complete build for the Hospital Patient Visits portfolio project.

  Run this file from the repository root with sqlcmd, or enable SQLCMD Mode in
  SQL Server Management Studio. Select an empty development database first.
*/

:ON ERROR EXIT

PRINT '01/08 - Creating raw schema';
:r ./schema/01_create_tables.sql

PRINT '02/08 - Loading patients and doctors';
:r ./data/02_insert_patients_doctors.sql

PRINT '03/08 - Loading reference dimensions';
:r ./data/03_insert_reference_dimensions.sql

PRINT '04/08 - Generating 50,000 synthetic visits';
:r ./data/04_generate_visits.sql

PRINT '05/08 - Cleaning and consolidating data';
:r ./cleaning/05_data_cleaning.sql

PRINT '06/08 - Creating analytical indexes';
:r ./schema/06_create_indexes.sql

PRINT '07/08 - Running data-quality checks';
:r ./validation/08_data_quality_checks.sql

PRINT '08/08 - Running business analysis';
:r ./analysis/07_business_analysis.sql
