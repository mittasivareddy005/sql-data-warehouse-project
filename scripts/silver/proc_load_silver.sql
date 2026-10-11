/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;
===============================================================================
*/

Create OR Alter Procedure silver.load_silver AS
Begin
	Declare @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
	Begin Try
		Set @batch_start_time= GetDate();
		Print '================================================';
		Print 'Loading Silver Layer';
		Print '================================================';

		Print '------------------------------------------------';
		Print 'Loading CRM Tables';
		Print '------------------------------------------------';

		--Loading silver.crm_cust_info;
		Set @start_time= GetDate();
		Print '>> Truncating Table: silver.crm_cust_info';
		Truncate Table silver.crm_cust_info;

		Print '>> Inserting Data Into: silver.crm_cust_info';
		Insert into silver.crm_cust_info (
			cst_id,
			cst_key,           
			cst_firstname,
			cst_lastname,
			cst_marital_status,
			cst_gndr,
			cst_create_date)

		Select 
		cst_id,
		cst_key,           
		TRIM(cst_firstname) as cst_firstname,     
		TRIM(cst_lastname) as cst_lastname,    
		Case When Upper(TRIM(cst_marital_status)) = 'S' then 'Single'
			 When Upper(TRIM(cst_marital_status)) = 'M' then 'Married'
			 Else 'n/a' END AS cst_marital_status,	--Normalize marital status values to readable format
		Case When Upper(TRIM(cst_gndr)) = 'F' then 'Female'
			 When Upper(TRIM(cst_gndr)) = 'M' then 'Male'
			 Else 'n/a' END AS cst_gndr,	--Normalize gender values to readable format
		cst_create_date    
		From 
		(
		Select 
		*,
		ROW_NUMBER() Over (Partition by cst_id order by cst_create_date desc) flag_last
		from [bronze].[crm_cust_info] 
		Where cst_id IS NOT NULL
		) t where flag_last = 1;	--Select the most recent record per customer

		Set @end_time= GetDate();
		Print '>> Load Duration: ' + Cast(DateDiff(Second, @start_time, @end_time) as NVARCHAR) + ' seconds';
		Print '------------------';

		--Loading silver.crm_prd_info;
		Set @start_time = GetDate();
		Print '>> Truncating Table: silver.crm_prd_info';
		Truncate Table silver.crm_prd_info;

		Print '>> Inserting Data Into: silver.crm_prd_info';
		Insert into silver.crm_prd_info(
			prd_id,
			cat_id,
			prd_key,
			prd_nm,
			prd_cost,
			prd_line,
			prd_start_dt,
			prd_end_dt
		)

		Select 
		prd_id,
		Replace(SUBSTRING(prd_key,1,5),'-','_') AS cat_id,	--Extract Category Id
		SUBSTRING(prd_key,7,Len(prd_key)) AS prd_key,		--Extract product key
		prd_nm,
		ISNULL(prd_cost,0) AS prd_cost,
		Case When Upper(TRIM(prd_line)) = 'M' then 'Mountain'
			 When Upper(TRIM(prd_line)) = 'R' then 'Road'
			 When Upper(TRIM(prd_line)) = 'S' then 'Other Sales'
			 When Upper(TRIM(prd_line)) = 'T' then 'Touring'
			 Else 'n/a'
		End AS prd_line,	--Map product line codes to descriptive values
		Cast(prd_start_dt as Date) as prd_start_dt,
		Cast(
			LEAD(prd_start_dt) Over (Partition by prd_key Order by prd_start_dt) - 1 
			AS Date) AS prd_end_dt	--Calculate end date as one day before the next start date 
		From bronze.crm_prd_info;
		Set @end_time= GetDate();
		Print '>> Load Duration: ' + Cast(DateDiff(Second, @start_time, @end_time) as NVARCHAR) + ' seconds';
		Print '------------------';

		--Loading silver.crm_sales_details;
		Set @start_time = GetDate();
		Print '>> Truncating Table: silver.crm_sales_details';
		Truncate Table silver.crm_sales_details;

		Print '>> Inserting Data Into: silver.crm_sales_details';
		Insert into silver.crm_sales_details (
			sls_ord_num,
			sls_prd_key,
			sls_cust_id,
			sls_order_dt,
			sls_ship_dt,
			sls_due_dt,
			sls_sales,
			sls_quantity,
			sls_price
			)

		Select 
		sls_ord_num,
		sls_prd_key,
		sls_cust_id,
		Case When sls_order_dt <= 0 OR LEN(sls_order_dt) != 8 Then NULL 
			 ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
		End AS sls_order_dt,
		Case When sls_ship_dt <= 0 OR LEN(sls_ship_dt) != 8 Then NULL 
			 ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
		End AS sls_ship_dt,
		Case When sls_due_dt <= 0 OR LEN(sls_due_dt) != 8 Then NULL 
			 ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
		End AS sls_due_dt,
		CASE when sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price) 
 			then sls_quantity * ABS(sls_price) 
			Else sls_sales 
		End AS  sls_sales,	--Recalculate sales if original value is missing or incorrect
		sls_quantity,
		Case When sls_price IS NULL OR sls_price <= 0 
			then sls_sales / NULLIF(sls_quantity,0)
			Else sls_price	
		End AS sls_price	--Derive price if original value is invalid
		From bronze.crm_sales_details;
		Set @end_time= GetDate();
		Print '>> Load Duration: ' + Cast(DateDiff(Second, @start_time, @end_time) as NVARCHAR) + ' seconds';
		Print '------------------';

		Print '------------------------------------------------';
		Print 'Loading ERP Tables';
		Print '------------------------------------------------';

		--Loading silver.erp_cust_az12;
		Set @start_time = GetDate();
		Print '>> Truncating Table: silver.erp_cust_az12';
		Truncate Table silver.erp_cust_az12;

		Print '>> Inserting Data Into: silver.erp_cust_az12';
		Insert into silver.erp_cust_az12(
		cid,
		bdate,
		gen)

		Select 
		Case when cid LIKE 'NAS%' Then SUBSTRING(cid, 4, Len(cid))	--Remove 'NAS' prefix if present
			ELSE cid 
		End as cid,
		Case When bdate > Getdate() Then Null 
		Else bdate 
		End AS bdate,	--set future birthdates to Null
		Case 
			 When Upper(TRIM(gen)) IN('F','FEMALE') Then 'Female'
			 When Upper(TRIM(gen)) IN('M','MALE') Then 'Male'
			 Else 'n/a'
		End AS gen	--Normalize gender vales and handle unknown cases 
		from bronze.erp_cust_az12;
		Set @end_time= GetDate();
		Print '>> Load Duration: ' + Cast(DateDiff(Second, @start_time, @end_time) as NVARCHAR) + ' seconds';
		Print '------------------';

		--Loading silver.erp_loc_a101;
		Set @start_time = GetDate();
		Print '>> Truncating Table: silver.erp_loc_a101';
		Truncate Table silver.erp_loc_a101;

		Print '>> Inserting Data Into: silver.erp_loc_a101';
		Insert into silver.erp_loc_a101 (
		cid,
		cntry)

		Select 
		Replace(cid,'-','') AS cid,
		Case when Trim(cntry) IN('DE') Then 'Germany'
		When Trim(cntry) IN ('US', 'USA') Then 'United States'
		when Trim(cntry) = '' OR Trim(cntry) IS NULL Then 'n/a'
		Else Trim(cntry) 
		End AS cntry	--Normalize and handle missing or blank country codes
		from bronze.erp_loc_a101;
		Set @end_time= GetDate();
		Print '>> Load Duration: ' + Cast(DateDiff(Second, @start_time, @end_time) as NVARCHAR) + ' seconds';
		Print '------------------';

		--Loading silver.erp_px_cat_g1v2;
		Set @start_time = GetDate();
		Print '>> Truncating Table: silver.erp_px_cat_g1v2';
		Truncate Table silver.erp_px_cat_g1v2;

		Print '>> Inserting Data Into: silver.erp_px_cat_g1v2';
		Insert into silver.erp_px_cat_g1v2(
		id,
		cat,
		subcat,
		maintenance)

		Select 
		id,
		cat,
		subcat,
		maintenance 
		from bronze.erp_px_cat_g1v2;
		Set @end_time= GetDate();
		Print '>> Load Duration: ' + Cast(DateDiff(Second, @start_time, @end_time) as NVARCHAR) + ' seconds';
		Print '------------------';

		Set @batch_end_time= GetDate();
		Print '================================================';
		Print 'Loading Silver Layer is Completed';
		Print '	 - Total Load Duration: ' + Cast(DateDiff(Second, @batch_start_time, @batch_end_time) as NVARCHAR) + ' seconds';
		Print '================================================';

	END Try
	
	Begin Catch
		Print '================================================';
		Print 'Error Occured During Loading Silver Layer';
		Print 'Error Message' + Error_Message();
		Print 'Error Number' + Cast(Error_Number() as NVARCHAR);
		Print 'Error State' + Cast(Error_State() as NVARCHAR);
		Print '================================================';	
	End Catch
End
