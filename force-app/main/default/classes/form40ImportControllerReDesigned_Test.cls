@isTest
public class form40ImportControllerReDesigned_Test {
    
    // --- Wrapper Class Definitions ---
    public class ImportWrapper {
        public Integer rowNumber                { get; set; }
        public Map<String, String> fieldValues  { get; set; }
        public String caseId                    { get; set; }
        public Boolean isValid                  { get; set; }
        public boolean isDuplicate              { get; set; }
        public Boolean proceedWithExistingAccount { get; set; }
        public List<String> errorMessages       { get; set; }
        
        
        public ImportWrapper() {
            fieldValues             = new Map<String, String>();
            errorMessages           = new List<String>(); 
            isValid                 = true;
            proceedWithExistingAccount = false;
            isDuplicate             = false;
            caseId                  = null;
        }
    }
    
    public static Decimal toDecimal(String s) {
        return Decimal.valueOf(String.valueOf(s));
    }
    
    public class recordWrapper {
        public String key;
        public String firstname;
        public String lastName;
        public String shippingStreet;
        public String shippingCity;
        public String shippingState;
        public String shippingPostalCode;
        public String periodCovered;
        public String directPay;
        public String wageAsssesment;
        public String grossWages;
        public String disabilityInsurance;
        public String socialSecurity;
        public String medicare;
        public String stateWitholding;
        public String federalWitholding;
        public String totalDeductions;
        public String netWages;
        public String factor;
        public String caseManagment;
        public String errorMessage;
    }
    
    // --- Utility Method ---
    public static List<Payee__c> queryPayees(Id caseId) {
        // Query all the Payees and their respective Assessment Associations
        return [
            SELECT
            Id,
            Name,
            Payee_Name__c,
            Case_Role__c,
            Case_Role__r.Entity__r.AccountMatch__c,
            Payee_Association_JSON__c, 
            Direct_Pay__c,
            NetWages__c,
            WageAssessment__c,
            TotalDeductions__c,
            Factor__c,
            Post_Judgment_Interest_for_Wages__c,
            Post_Citation_Interest_for_Wages__c
            FROM Payee__c
            WHERE Case_Management__c = :caseId
        ];
    }
    
    // --- Main Test Method ---
    @isTest
    Public static void method1(){
        
        Integer insertedAccounts   = 0;
        Integer insertedCaseRoles  = 0;
        Integer insertedPayees     = 0;
        Integer updatedCaseIssues  = 0;
        Integer updatedCases       = 0;
        boolean shouldRunSecondBatch = false;
        Integer NumberofImportRecordsInserted = 0;
        
        // 1. Setup Trigger Settings
        List<Trigger_Settings__c> triggerSettings = new List<Trigger_Settings__c>();
        List<IC_Batch_Notification_Recipients__c> batchEmailSettings = new List<IC_Batch_Notification_Recipients__c>();
        
        triggerSettings.add(new Trigger_Settings__c(Name = 'CaseRoleAll', Is_Active__c = false));
        triggerSettings.add(new Trigger_Settings__c(Name = 'dlrs_DIR_ViolationTrigger', Is_Active__c = false));
        triggerSettings.add(new Trigger_Settings__c(Name = 'dlrs_JudgementTrigger', Is_Active__c = false));
        triggerSettings.add(new Trigger_Settings__c(Name = 'GenerateFieldHistoryAction', Is_Active__c = false));
        triggerSettings.add(new Trigger_Settings__c(Name = 'LiabilityPaymentTrigger', Is_Active__c = false));
        triggerSettings.add(new Trigger_Settings__c(Name = 'Receipt Trigger', Is_Active__c = false));
        triggerSettings.add(new Trigger_Settings__c(Name = 'DIR_EmployeeTrigger', Is_Active__c = false));
        triggerSettings.add(new Trigger_Settings__c(Name = 'ViolationTypeInterestRatesTrigger', Is_Active__c = false));
        triggerSettings.add(new Trigger_Settings__c(Name = 'ViolationTypeTrigger', Is_Active__c = false));
        triggerSettings.add(new Trigger_Settings__c(Name = 'IC_Assessment_Case_RollupTrigger', Is_Active__c = false));
        triggerSettings.add(new Trigger_Settings__c(Name = 'appealTrigger', Is_Active__c = false));
        
        insert triggerSettings;
        
        // 2. Setup Accounts and Locations
        List<Account> accounts = new List<Account>();
        Id businessAccountRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Person Account').getRecordTypeId();
        
        Account employerAccount = new Account(
            RecordTypeId       = businessAccountRtId,
            FirstName          = 'DIR',
            LastName           = 'Test',
            //Name             = 'Big Mega General Corp',
            ShippingStreet     = '123 Sesame Street',
            ShippingCity       = 'New York',
            ShippingState      = 'NY',
            ShippingPostalCode = '1234'
        );
        accounts.add(employerAccount);
        insert accounts;    
        System.Debug('Inserted Account is '+employerAccount.Id);
        
        List<Address__c> employerAccountLocation = [SELECT Id, Name FROM Address__c WHERE Entity__c = :employerAccount.Id];
        
        // 3. Setup DIR Employees (Manager and Deputy)
        DIR_Employee__c manager = new DIR_Employee__c(
            Name      = 'Touk Ken',
            User__c   = UserInfo.getUserId(),
            Position__c = 'Senior Deputy',
            Title__c  = 'Senior Deputy Labor Commissioner'
        );
        insert manager;
        
        DIR_Employee__c deputy = new DIR_Employee__c(
            Name      = 'Bao Le',
            User__c   = UserInfo.getUserId(),
            Position__c = 'Deputy',
            Manager__c = manager.Id
        );
        insert deputy;
        
        // 4. Setup Offices
        List<Office__c> offices = new List<Office__c>();
        Office__c bofeOffice = new Office__c(
            Name         = 'Stockton BOFE',
            Office_Number__c = 'CCU 32',
            RecordTypeId = Schema.SObjectType.Office__c.getRecordTypeInfosByName().get('BOFE').getRecordTypeId()
        );
        offices.add(bofeOffice);
        
        Office__c ccuOffice = new Office__c(
            Name         = 'Sacramento CCU',
            Office_Number__c = 'CCU 32',
            RecordTypeId = Schema.SObjectType.Office__c.getRecordTypeInfosByName().get('CCU').getRecordTypeId()
        );
        offices.add(ccuOffice);
        
        insert offices;
        
        // 5. Setup DIR Case (BOFE)
        String fakeJsonCM = '{"UserId":"005cp00000AStjrAAD","Last_Upload_Import_type":"Form_40_Partial","Last_Modified_Date":"10/23/2025 11:28"}';
        DIR_Case__c bofeCase = new DIR_Case__c(
            Assigned_Deputy__c      = deputy.Id,
            Employer__c             = employerAccount.Id,
            Office__c               = bofeOffice.Id,
            RecordTypeId            = Schema.SObjectType.DIR_Case__c.getRecordTypeInfosByName().get('BOFE').getRecordTypeId(),
            Funds_Drawn_on_Deposits__c = 0.00,
            Import_Form_40_Details__c = fakeJsonCM
        );
        insert bofeCase;
        
        // 6. Setup Case Role
        List<Case_Role__c> caseRoles = new List<Case_Role__c>();
        Id bofeCaseRoleRecordTypeId = Schema.SObjectType.Case_Role__c.getRecordTypeInfosByName().get('BOFE').getRecordTypeId();
        
        Case_Role__c bofeDefendantCaseRole = new Case_Role__c(
            RecordTypeId        = bofeCaseRoleRecordTypeId,
            Case__c             = bofeCase.Id,
            Entity__c           = employerAccount.Id,
            Role__c             = 'Defendant',
            Case_Role_Status__c = 'Active',
            Location__c         = employerAccountLocation[0].Id
        );
        caseRoles.add(bofeDefendantCaseRole);
        insert caseRoles;
        
        // 7. Setup Violation Type & Interest Rates
        List<Violation_Type__c> violationTypes = new List<Violation_Type__c>();
        Violation_Type__c bofeViolationType = new Violation_Type__c(
            Appeal_Deadline_Days__c     = 15,
            Appeal_Deadline_Selector__c = 'Business Days',
            //Even though the method is "getRecordTypeInfosByName()", it actually gets the info by the Label.
            RecordTypeId                = Schema.SObjectType.Violation_Type__c.getRecordTypeInfosByName().get('BOFE Violations').getRecordTypeId(),
            Active__c                   = true
        );
        violationTypes.add(bofeViolationType);
        insert violationTypes; 
        
        list<Violation_Type_Interest_Rates__c> violationTypeInterestRates = new list<Violation_Type_Interest_Rates__c>();
        for(Violation_Type__c vt : violationTypes){
            Violation_Type_Interest_Rates__c vtIr = new Violation_Type_Interest_Rates__c(
                Start_Date__c                   = Date.newInstance(2000,01,01),
                Post_Citation_Wage_IC_Rate__c   = 10,
                Post_Judgment_Penalty_IC_Rate__c = 10,
                Post_Judgment_Wage_IC_Rate__c   = 10,
                Violation_Type__c               = vt.Id
            );
            violationTypeInterestRates.add(vtIr);
        }
        Insert violationTypeInterestRates;
        
        // 8. Setup Assessment
        Assessments__c bofeAssessment = new Assessments__c(
            Case_Management__c      = bofeCase.Id,
            Appeal_Deadline_Days__c = 14,
            Appeal_Deadline_Selector__c = 'Business Days',
            RecordTypeId            = Schema.SObjectType.Assessments__c.getRecordTypeInfosByName().get('BOFE Assessments').getRecordTypeId()
        );
        insert bofeAssessment;
        
        // 9. Setup Case Issues (DIR_Violation__c)
        List<DIR_Violation__c> caseIssues = new List<DIR_Violation__c>();
        Id bofeCaseIssueRecordTypeId = Schema.SObjectType.DIR_Violation__c.getRecordTypeInfosByName().get('BOFE Violations').getRecordTypeId();
        //Id wcaCaseIssueRecordTypeId = Schema.SObjectType.DIR_Violation__c.getRecordTypeInfosByName().get('WCA Violations').getRecordTypeId();
        
        DIR_Violation__c bofeCaseIssue1 = new DIR_Violation__c(
            Violation_Type__c                   = bofeViolationType.Id,
            Case__c                             = bofeCase.Id,
            Assessment__c                       = bofeAssessment.Id,
            Citation_Amount__c                  = 6666,
            Wages_Due__c                        = 4999.50,
            Original_Penalty_Assessment_Amount__c = 2000,
            Total_Interest_Amount__c            = 1666.50,
            Status__c                           = 'Open',
            Post_Citation_Interest_for_Wages__c = 10,
            Post_Judgment_Interest_for_Wages__c = 10,
            Citation_Date__c                    = Date.today().addDays(-15),
            RecordTypeId                        = bofeCaseIssueRecordTypeId
        );
        caseIssues.add(bofeCaseIssue1);
        
        DIR_Violation__c bofeCaseIssue2 = new DIR_Violation__c(
            Violation_Type__c                   = bofeViolationType.Id,
            Case__c                             = bofeCase.Id,
            Assessment__c                       = bofeAssessment.Id,
            Citation_Amount__c                  = 6666,
            Wages_Due__c                        = 4999.50,
            Original_Penalty_Assessment_Amount__c = 2000,
            Total_Interest_Amount__c            = 1666.50,
            Status__c                           = 'Open',
            Citation_Date__c                    = Date.today(),
            Post_Citation_Interest_for_Wages__c = 10,
            Post_Judgment_Interest_for_Wages__c = 10,
            RecordTypeId                        = bofeCaseIssueRecordTypeId
        );
        caseIssues.add(bofeCaseIssue2);
        insert caseIssues;
        
        // 10. Setup Payee
        List<Payee__c> payeeList = new List<Payee__c>();
        
        Payee__c payeeSingle = new Payee__c();
        payeeSingle.Case_Management__c = bofeCase.Id;
        payeeSingle.Case_Role__c       = caseRoles[0].Id;
        payeeSingle.NetWages__c        = 98765;
        payeeSingle.Post_Citation_Interest_for_Wages__c = 0;
        payeeSingle.Post_Judgment_Interest_for_Wages__c = 0;
        
        String fakeJsonPayee = '[' +
            '  {' +
            '    "violationTypeName": "VT-1106",' +
            '    "totalWageAssessment": 15000.00,' +
            '    "netWages": 10000.00,' +
            '    "factor": 25.00000,' +
            '    "deductionsTotal": 0.00,' +
            '    "citationForm": "BOFE 240B",' +
            '    "caseIssueName": "V-1558981",' +
            '    "caseIssueId": "' + caseIssues[0].Id + '",' +
            '    "caseIssueBreakdown": 10000.000000' +
            '  }' +
            ']';
        payeeSingle.Payee_Association_JSON__c = fakeJsonPayee;
        payeeList.add(payeeSingle);
        
        insert payeeList;
        
        
        
        // 11. Read CSV Data from Static Resource and Insert Import Records
        Id caseId = bofeCase.Id;
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'DIRCreatePayee'
            LIMIT 1
        ];
        if (resources.isEmpty()) {
            System.debug('ERROR: Static Resource named \'DIRCreatePayee\' not found.');
        }
        
        StaticResource resource = resources[0];
        String csvData = resource.Body.toString();
        // Convert the Blob body to a String
        
        List<String> csvLines = csvData.split('\n');
        if (csvLines.size() < 1) {
            System.debug('ERROR: CSV file is empty.');
            return;
        }
        
        
        // Assuming the first line is the header row
        List<String> headers = csvLines[0].split(',');
        // Clean up headers (remove quotes/trim whitespace)
        for (Integer h = 0; h < headers.size(); h++) {
            headers[h] = headers[h].trim().replaceAll('"', '');
        }
        
        // List to hold the records we are inserting
        List<Import__c> toInsert = new List<Import__c>();
        Integer rowCount = 0;
        
        // Loop Through Data Rows (Starting from index 1, skipping the header)
        for (Integer i = 1; i < csvLines.size(); i++) {
            String line = csvLines[i];
            if (String.isBlank(line)) continue;
            
            // A simple split by comma can break if fields contain commas (need better CSV parsing for that)
            List<String> values = line.split(',');
            Map<String, String> fieldValues = new Map<String, String>();
            
            // Map the header name to the corresponding value
            for (Integer j = 0; j < headers.size() && j < values.size(); j++) {
                // Trim each value and remove surrounding quotes
                String val = values[j].trim().replaceAll('"', '');
                fieldValues.put(headers[j], val);
            }
            
            Import__c rec = new Import__c();
            String uniqueKey = 'CSV_Results_TEST_KEY';
            
            // **Standard Field Assignments**
            rec.Case_Management__c = caseId;
            rec.Unique_Key__c = uniqueKey;
            if(i < 2){
                rec.Job_Sequence__c  = null;
            }
            else if (i < 5){
                rec.Has_Matching_Account__c = true;
            }
            else
            {
                rec.Has_Matching_Account__c = false;
            }
            
            // Assuming this default value
            
            // **String Field Assignments**
            rec.Employee_First_Name__c = fieldValues.get('Employee First Name');
            rec.Employee_Last_Name__c = fieldValues.get('Employee Last Name');
            rec.Employee_Street__c = fieldValues.get('Employee Street');
            rec.Employee_City__c = fieldValues.get('Employee City');
            rec.Employee_State__c = fieldValues.get('Employee State');
            rec.Employee_Zip__c = fieldValues.get('Employee Zip');
            rec.Period_Covered_by_Adjustment__c = fieldValues.get('Period Covered by Adjustment');
            rec.Direct_Pay__c = fieldValues.get('Direct Pay');
            
            // **Decimal Field Assignments with Null Check and Conversion**
            String totalWage = fieldValues.get('Total Wage Assessment');
            rec.Total_Wage_Assessment__c = String.isNotBlank(totalWage) ? Decimal.valueOf(totalWage) : null;
            
            String deductionsTotal = fieldValues.get('Deductions: Total');
            rec.Deductions_Total__c = String.isNotBlank(deductionsTotal) ? Decimal.valueOf(deductionsTotal) : null;
            
            String netWages = fieldValues.get('Net Wages Assessed');
            rec.Net_Wages_Paid__c = String.isNotBlank(netWages) ? Decimal.valueOf(netWages) : null;
            
            String factor = fieldValues.get('Factor');
            rec.Factor__c = String.isNotBlank(factor) ? Decimal.valueOf(factor) : null;
            
            toInsert.add(rec);
        }
        
        if (!toInsert.isEmpty()) {
            try {
                insert toInsert;
                System.debug('SUCCESS: ' + toInsert.size() + ' Import__c records were created.');
            } catch (DmlException e) {
                System.debug('DML ERROR: Failed to insert records. Error: ' + e.getMessage());
            }
        }
        
        
        
        // 12. Simulate CSV Validation Call
        String uniqueKey = 'CSV_Results_' + caseId + '_' + Datetime.now().getTime();
        List<DIR_Case__c> getCase = [SELECT Id FROM DIR_Case__c];
        List<DIR_Violation__c> getCaseIssue = [SELECT Id FROM DIR_Violation__c];
        List<Import__c> getImport = [SELECT Id FROM Import__c];
        
        System.debug('getCase Size :' +getCase.Size() + 'getCase Size : ' + getCaseIssue.Size() + 'getImport Size :' +getImport.Size());
        
        // Query a Case and Violation record (ensure they exist in test data)
        List<DIR_Case__c> queryCase = [SELECT Id, Name, Import_Form_40_Details__c FROM DIR_Case__c LIMIT 1];
        List<DIR_Violation__c> queriedCaseIssues = [SELECT Id, Name FROM DIR_Violation__c LIMIT 1];
        String importType = 'Form_40';
        List<Id> selectedCaseIssueIds = new List<Id>{ queriedCaseIssues[0].Id };
            
            String cacheKey = form40ImportControllerReDesigned.parseCSVAndValidate(
                csvLines,
                caseId,
                selectedCaseIssueIds,
                importType
            );
        
        // 13. Simulate Polling (getImportResults)
        try {
            // Call the static method and store the returned Map
            Map<String, Object> results = form40ImportControllerReDesigned.getImportResults(uniqueKey);
            
            // Debug the contents of the map
            System.debug('*** SUCCESSFUL CALL ***');
            System.debug('Complete Results Map: ' + results);
            System.debug('Is Complete: ' + results.get('isComplete'));
            System.debug('Processed Rows: ' + results.get('processedRows'));
            System.debug('Has Error: ' + results.get('hasError'));
            System.debug('Error Message: ' + results.get('errorMessage'));
            
            // Note: The 'results' key contains a List<ImportWrapper>, which might not print
            // fully in the debug log due to log size limits, but the size should be visible.
            List<Object> pollingData = (List<Object>)results.get('results');
            if (pollingData != null) {
                System.debug('Polling Data List Size: ' + pollingData.size());
            }
            
        } catch (Exception e) {
            // This catch block will capture the System.AuraHandledException or any other errors
            // and print the full error details to the debug log, which is helpful since
            // your method wraps the inner error.
            System.debug(LoggingLevel.ERROR, '*** CAUGHT EXCEPTION FROM APEX METHOD ***');
            System.debug(LoggingLevel.ERROR, 'Error Type: ' + e.getTypeName());
            System.debug(LoggingLevel.ERROR, 'Error Message: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
        }
        
        // 14. Additional Setup for Bulk Payee Creation & Polling Test
        uniqueKey = 'CSV_Results_TEST_KEY';
        importType = 'Corrective_Form_40';
        System.debug('form40ImportControllerReDesigned.runBulkPayeeCreation :'+ caseId);
        System.debug('form40ImportControllerReDesigned.runBulkPayeeCreation :'+selectedCaseIssueIds);
        System.debug('form40ImportControllerReDesigned.runBulkPayeeCreation :'+importType);
        System.debug('form40ImportControllerReDesigned.runBulkPayeeCreation :'+uniqueKey);
        
        
        //String result = form40ImportControllerReDesigned.getLastModifiedDetails(queryCase[0].Id);
        
        
        // Prepare fake JSON file content (List<ImportWrapper> format)
        List<form40ImportControllerReDesigned.ImportWrapper> wrappers = new List<form40ImportControllerReDesigned.ImportWrapper>();
        form40ImportControllerReDesigned.ImportWrapper w = new form40ImportControllerReDesigned.ImportWrapper();
        w.rowNumber = 1;
        w.isValid = true;
        w.fieldValues.put('Employee First Name', 'John');
        w.fieldValues.put('Employee Last Name', 'Doe');
        w.errorMessages.add('No errors');
        wrappers.add(w);
        
        // Serialize JSON
        String jsonData = JSON.serialize(wrappers);
        
        // Create ContentVersion (to simulate uploaded JSON results file)
        ContentVersion cv = new ContentVersion(
            Title = 'ImportResults_Test_' + System.now().getTime(),
            PathOnClient = 'ImportResults.json',
            VersionData = Blob.valueOf(jsonData)
        );
        insert cv;
        
        // Get the linked ContentDocumentId
        Id fileId = [
            SELECT ContentDocumentId    
            FROM ContentVersion    
            WHERE Id = :cv.Id    
            LIMIT 1
        ].ContentDocumentId;
        
        // Create Import__c records simulating jobs (Job_Sequence__c 0 = initial tracking record)
        List<Import__c> imports = new List<Import__c>();
        
        // Job 0 (initial tracking)
        imports.add(new Import__c(
            Unique_Key__c      = 'CSV_Results_TEST_KEY',
            Job_Status__c      = 'Processing',
            Case_Management__c = getCase[0].Id,
            Job_Sequence__c    = 0,
            Total_Jobs__c      = 2,
            Results__c         = 'CSV_Results_TEST_KEY'
        ));
        
        // Job 1 (Completed, has file result)
        imports.add(new Import__c(
            Unique_Key__c      = 'CSV_Results_TEST_KEY',
            Job_Status__c      = 'Completed',
            Case_Management__c = getCase[0].Id,
            Job_Sequence__c    = 1,
            Total_Jobs__c      = 2,
            Processed_Rows__c  = 1,
            Results__c         = fileId
        ));
        
        // Job 2 (Failed, with error message)
        imports.add(new Import__c(
            Unique_Key__c      = 'CSV_Results_TEST_KEY',
            Job_Status__c      = 'Failed',
            Case_Management__c = getCase[0].Id,
            Job_Sequence__c    = 2,
            Total_Jobs__c      = 2,
            Error_Message__c   = 'Simulated failure for testing'
        ));
        
        insert imports;
        
        
        Map<String, Object> resultsPolling = form40ImportControllerReDesigned.getImportResults(cacheKey);
        
        // The query below is for a different purpose than the one that caused the error, but we'll leave it
        Id contentDocId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
        ].ContentDocumentId;
        
        // FIX: Query the inserted record (no error now)
        DIR_Violation__c violation = [SELECT Id, Name FROM DIR_Violation__c WHERE Id = :caseIssues[0].Id LIMIT 1];
        uniqueKey = 'CSV_Results_TEST_KEY';
        importType = 'Form_40';
        
        List<DIR_Violation__c> violation01 = [SELECT Id, Name FROM DIR_Violation__c];
        
        System.debug(violation01.size());
        
        // 15. Simulate Revalidation of Edited Rows
        // Create one valid and one invalid ImportWrapper
        List<form40ImportControllerReDesigned.ImportWrapper> editedRows = new List<form40ImportControllerReDesigned.ImportWrapper>();
        
        //Valid record
        form40ImportControllerReDesigned.ImportWrapper validRow = new form40ImportControllerReDesigned.ImportWrapper();
        validRow.fieldValues.put('Employee First Name', 'John');
        validRow.fieldValues.put('Employee Last Name', 'Smith');
        validRow.fieldValues.put('Employee Street', '123 Main');
        validRow.fieldValues.put('Employee Zip', '90210');
        
        //Invalid record (missing required fields)
        form40ImportControllerReDesigned.ImportWrapper invalidRow = new form40ImportControllerReDesigned.ImportWrapper();
        invalidRow.fieldValues.put('Employee First Name', '');
        invalidRow.fieldValues.put('Employee Last Name', '');
        
        editedRows.add(validRow);
        editedRows.add(invalidRow);
        
        try {
            
            List<form40ImportControllerReDesigned.ImportWrapper> resultsOfrevalidateEditedRows =
                form40ImportControllerReDesigned.revalidateEditedRows(
                    editedRows,
                    uniqueKey,
                    importType                
                );
            
            System.debug('*** SUCCESSFUL CALL ***');
            System.debug('Complete Results Map: ' + resultsOfrevalidateEditedRows);
            
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '*** CAUGHT EXCEPTION FROM APEX METHOD ***');
            System.debug(LoggingLevel.ERROR, 'Error Type: ' + e.getTypeName());
            System.debug(LoggingLevel.ERROR, 'Error Message: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
        }
        
        List<Import__c> imports001 = [SELECT Id, Unique_Key__c, Job_Status__c, Case_Management__c, Job_Sequence__c, Total_Jobs__c FROM Import__c];
        System.debug(uniqueKey);
        for(Import__c imp : imports001){
            System.debug(imp);
        }
        
        
        
        Set<Id> setOfCaseIssueIds = new Set<Id>();
        for(DIR_Violation__c caseIssueId : violation01){
            setOfCaseIssueIds.add(caseIssueId.Id);
        }
        System.debug(caseId);
        System.debug(setOfCaseIssueIds);
        System.debug(importType);
        System.debug(uniqueKey);
        
        // 16. Manual Execution of Payee Creation Logic (Mimicking Batch Start)
        
        List<Import__c> importsMerged = [
            SELECT Id, Name, Unique_Key__c, Job_Status__c, Case_Management__c, Job_Sequence__c, Total_Jobs__c,
            Deductions_Total__c, Employee_City__c, Employee_First_Name__c, Employee_Last_Name__c,
            Employee_State__c, Employee_Street__c, Employee_Zip__c, Factor__c, Gross_Wages_Paid__c,
            Net_Wages_Paid__c, Period_Covered_by_Adjustment__c, Total_Wage_Assessment__c,
            Has_Matching_Account__c, Direct_Pay__c
            FROM Import__c
            WHERE Has_Matching_Account__c = true
            OR (Case_Management__c = :caseId AND Unique_Key__c = :uniqueKey AND Job_Sequence__c = NULL)
        ];
        System.debug('Test Class  ' + importsMerged.Size() + ' Import Records inserted.');
        
        
        List<Account> accsToUpload = new List<Account>();
        List<Payee__c> createPayeeList = new List<Payee__c>();
        List<Case_Role__c> createCaseRoleList = new List<Case_Role__c>();
        List<recordWrapper> failedDMLRecords = new List<recordWrapper>();
        Map<String, recordWrapper> accPayeeMap = new Map<String, recordWrapper>();
        
        // Fetch Case Issues
        List<DIR_Violation__c> caseIssueList = [
            SELECT Id, Name, Wage_Balance_Due__c, Amount_Reserved__c, Amount_Utilized_from_Payee__c,
            Violation_Type__r.Violation_Type_Name__c,
            Violation_Type__r.Violation_Type__c
            FROM DIR_Violation__c
            WHERE Id = :setOfCaseIssueIds
        ];
        
        Id personAccRTID = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Person Account').getRecordTypeId();
        
        try {
            // Build Account and Wrapper List
            for (sObject line : importsMerged) {
                Import__c record = (Import__c) line;
                System.debug('Test Class  ' + record + ' Import Record.');
                System.debug('Test Class  ' + line + ' Import line.');
                
                Account acct = new Account();
                acct.FirstName          = record.Employee_First_Name__c;
                acct.LastName           = record.Employee_Last_Name__c;
                acct.ShippingStreet     = record.Employee_Street__c;
                acct.ShippingCity       = record.Employee_City__c;
                acct.ShippingState      = record.Employee_State__c;
                acct.ShippingPostalCode = record.Employee_Zip__c;
                acct.RecordTypeId       = personAccRTID;
                accsToUpload.add(acct);
                
                recordWrapper accPayee = new recordWrapper();
                accPayee.key                = acct.LastName + ',' + acct.FirstName + ',' + record.Employee_Street__c + ',' + record.Employee_Zip__c;
                accPayee.firstname          = record.Employee_First_Name__c;
                accPayee.lastName           = record.Employee_Last_Name__c;
                accPayee.shippingStreet     = record.Employee_Street__c;
                accPayee.shippingCity       = record.Employee_City__c;
                accPayee.shippingState      = record.Employee_State__c;
                accPayee.shippingPostalCode = record.Employee_Zip__c;
                accPayee.periodCovered      = record.Period_Covered_by_Adjustment__c;
                accPayee.directPay          = record.Direct_Pay__c;
                accPayee.wageAsssesment     = String.valueOf(record.Total_Wage_Assessment__c);
                accPayee.grossWages         = String.valueOf(record.Gross_Wages_Paid__c);
                accPayee.totalDeductions    = String.valueOf(record.Deductions_Total__c);
                accPayee.netWages           = String.valueOf(record.Net_Wages_Paid__c);
                accPayee.factor             = String.valueOf(record.Factor__c);
                accPayee.caseManagment      = caseId;
                accPayeeMap.put(accPayee.key, accPayee);
            }
        } catch (Exception e) {
            System.debug('Error building records: ' + e.getMessage());
        }
        
        try {
            // --- Insert Accounts ---
            List<Database.SaveResult> insertAccountResults = Database.insert(accsToUpload, true);
            for (Integer i = 0; i < insertAccountResults.size(); i++) {
                if (insertAccountResults[i].isSuccess()) {
                    insertedAccounts++;
                } else {
                    Database.Error error = insertAccountResults[i].getErrors()[0];
                    System.debug(error.getMessage());
                }
            }
            System.debug( insertedAccounts + ' Account records inserted.');
            
            // --- Insert Case Roles ---
            for (Account acc : accsToUpload) {
                createCaseRoleList.add(new Case_Role__c(
                    Account_Name__c = acc.Name,
                    Case__c         = caseId,
                    Role__c         = 'Payee - Employee',
                    Entity__c       = acc.Id
                ));
            }
            
            List<Database.SaveResult> insertCaseRoleResults = Database.insert(createCaseRoleList, true);
            for (Integer i = 0; i < insertCaseRoleResults.size(); i++) {
                if (insertCaseRoleResults[i].isSuccess()) {
                    insertedCaseRoles++;
                } else {
                    Database.Error error = insertCaseRoleResults[i].getErrors()[0];
                    System.debug(error.getMessage());
                }
            }
            System.debug( insertedCaseRoles + ' Case Role records inserted.');
            
            // --- Create Payees ---
            Set<Id> caseRoleIds = new Set<Id>();
            for (Case_Role__c role : createCaseRoleList) {
                caseRoleIds.add(role.Id);
            }
            
            List<Case_Role__c> caseRoleList = [
                SELECT Id, Name, Entity__c, Entity__r.ShippingPostalCode,
                Entity__r.ShippingState, Entity__r.ShippingCity,
                Entity__r.ShippingStreet, Entity__r.LastName,
                Entity__r.FirstName, Entity__r.AccountMatch__c
                FROM Case_Role__c
                WHERE Id = :caseRoleIds
            ];
            
            for (Case_Role__c cr : caseRoleList) {
                System.debug(caseRoleList.size());
                System.debug(accPayeeMap);
                
                // AccountMatch is calculated as: LastName,FirstName,ShippingStreet,ShippingZip (AccountMatch__c field on Person Account)
                recordWrapper accP = accPayeeMap.get(cr.Entity__r.AccountMatch__c); 
                System.debug('Dev VR :' + accP + '\n');
                
                if (accP != null) {
                    Payee__c payee = new Payee__c();
                    payee.PeriodCovered__c = accP.periodCovered;
                    
                    if (!String.isEmpty(accP.wageAsssesment)) payee.WageAssessment__c = toDecimal(accP.wageAsssesment);
                    if (!String.isEmpty(accP.grossWages)) payee.GrossWages__c = toDecimal(accP.grossWages);
                    if (!String.isEmpty(accP.disabilityInsurance)) payee.DisabilityInsurance__c = toDecimal(accP.disabilityInsurance);
                    if (!String.isEmpty(accP.socialSecurity)) payee.SocialSecurity__c = toDecimal(accP.socialSecurity);
                    if (!String.isEmpty(accP.medicare)) payee.Medicare__c = toDecimal(accP.medicare);
                    if (!String.isEmpty(accP.stateWitholding)) payee.StateWithholding__c = toDecimal(accP.stateWitholding);
                    if (!String.isEmpty(accP.federalWitholding)) payee.FederalWithholding__c = toDecimal(accP.federalWitholding);
                    if (!String.isEmpty(accP.totalDeductions)) payee.TotalDeductions__c = toDecimal(accP.totalDeductions);
                    if (!String.isEmpty(accP.netWages)) payee.NetWages__c = toDecimal(accP.netWages);
                    if (!String.isEmpty(accP.factor)) payee.Factor__c = toDecimal(accP.factor);
                    if (!String.isEmpty(accP.directPay)) payee.Direct_Pay__c = accP.directPay;
                    
                    payee.Case_Management__c = caseId;
                    payee.Case_Role__c       = cr.Id;
                    payee.Payee_Type__c      = 'Employee';
                    payee.Status__c          = 'Unverified';
                    
                    // Build JSON field
                    List<PayeeAssociation> caseIssueJsonList = new List<PayeeAssociation>();
                    
                    for (DIR_Violation__c ci : caseIssueList) {
                        PayeeAssociation associationData = new PayeeAssociation();
                        associationData.caseIssueId         = ci.Id;
                        associationData.caseIssueName       = ci.Name;
                        associationData.factor              = String.isEmpty(accP.factor) ? 0 : toDecimal(accP.factor);
                        associationData.citationForm        = ci.Violation_Type__r.Violation_Type__c;
                        associationData.violationTypeName   = ci.Violation_Type__r.Violation_Type_Name__c;
                        
                        Decimal breakdown = ci.Wage_Balance_Due__c * (String.isEmpty(accP.factor) ? 0 : toDecimal(accP.factor) / 100);
                        Decimal reservedAmount = (ci.Amount_Reserved__c == null) ? 0 : ci.Amount_Reserved__c;
                        Decimal utilizedAmount = (ci.Amount_Utilized_from_Payee__c == null) ? 0 : ci.Amount_Utilized_from_Payee__c;
                        
                        if (importType == 'Form_40_Partial') {
                            breakdown = reservedAmount * (String.isEmpty(accP.factor) ? 0 : toDecimal(accP.factor) / 100);
                        } else if (importType == 'Corrective_Form_40') {
                            breakdown = utilizedAmount * (String.isEmpty(accP.factor) ? 0 : toDecimal(accP.factor) / 100);
                        }
                        
                        associationData.caseIssueBreakdown = breakdown.setScale(6, RoundingMode.HALF_UP);
                        caseIssueJsonList.add(associationData);
                    }
                    
                    payee.Payee_Association_JSON__c = JSON.serialize(caseIssueJsonList);
                    createPayeeList.add(payee);
                } else {
                    System.debug('Else payee');
                    recordWrapper noMatchAccount = new recordWrapper();
                    noMatchAccount.errorMessage       = 'Could not find match on: ' + cr.Entity__r.AccountMatch__c;
                    noMatchAccount.firstname          = cr.Entity__r.FirstName;
                    noMatchAccount.lastName           = cr.Entity__r.LastName;
                    noMatchAccount.shippingStreet     = cr.Entity__r.ShippingStreet;
                    noMatchAccount.shippingCity       = cr.Entity__r.ShippingCity;
                    noMatchAccount.shippingState      = cr.Entity__r.ShippingState;
                    noMatchAccount.shippingPostalCode = cr.Entity__r.ShippingPostalCode;
                    noMatchAccount.caseManagment      = caseId;
                    
                    failedDMLRecords.add(noMatchAccount);
                }
            }
            
            // --- Insert Payees ---
            List<Database.SaveResult> insertPayeeResults = Database.insert(createPayeeList, false);
            for (Integer i = 0; i < insertPayeeResults.size(); i++) {
                if (insertPayeeResults[i].isSuccess()) {
                    insertedPayees++;
                } else {
                    Database.Error error = insertPayeeResults[i].getErrors()[0];
                    System.debug(' Insert Payee Record failed: ' + error.getMessage());
                }
            }
            
            System.debug(insertedPayees + ' Payee records inserted.');
        } catch (Exception e) {
            System.debug('Unexpected error in execute: ' + e.getMessage());
        }
        
        
        // 17. Debugging Logs (Final Counts)
        System.debug('Test Class  ' + insertedAccounts + ' Account records inserted.');
        System.debug('Test Class  ' + insertedCaseRoles + ' CaseRole records inserted.');
        System.debug('Test Class  ' + insertedPayees + ' Payee records inserted.');
        System.debug('Test Class  ' + updatedCaseIssues + ' CaseIssue records updated.');
        System.debug('Test Class  ' + updatedCases + ' Case records updated.');
        System.debug('Test Class  ' + shouldRunSecondBatch + ' Second batch execution flag.');
        System.debug('Test Class  ' + NumberofImportRecordsInserted + ' Import records inserted.');
        
        
        // 18. Update Job Tracking Record with Payee Map (Simulating Batch Scope)
        List<Payee__c> allPayeeList = queryPayees(caseId);
        map<string, Payee__c> payeeMap = new Map<string, Payee__c>();
        for (Payee__c py : allPayeeList) {
            payeeMap.put(py.Case_Role__r.Entity__r.AccountMatch__c.toLowerCase(), py);
        }
        System.Debug(
            'Payee Map with with Key as Account Match to find the Duplicate Payee ' +
            payeeMap
        );
        
        // Save payeeMap as File and Store in the Results field of the first Job Record
        String jsonPayeeMap = JSON.serialize(payeeMap);
        ContentVersion file = new ContentVersion();
        file.Title = 'PayeeMap_' + uniqueKey;
        file.PathOnClient = file.Title + '.json';
        file.VersionData = Blob.valueOf(jsonPayeeMap);
        insert file;
        
        Id payeeMapFileId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :file.Id
            LIMIT 1
        ].ContentDocumentId;
        
        List<Import__c> getImportResutlt = [
            SELECT Id, Name, Unique_Key__c, Job_Status__c, Case_Management__c, Job_Sequence__c, Total_Jobs__c,
            Deductions_Total__c, Employee_City__c, Employee_First_Name__c, Employee_Last_Name__c,
            Employee_State__c, Employee_Street__c, Employee_Zip__c, Factor__c, Gross_Wages_Paid__c,
            Net_Wages_Paid__c, Period_Covered_by_Adjustment__c, Total_Wage_Assessment__c,
            Has_Matching_Account__c, Direct_Pay__c
            FROM Import__c
            WHERE Case_Management__c = :caseId AND Unique_Key__c = :uniqueKey AND Job_Sequence__c = 0
        ];
        
        Import__c importResult = new Import__c(
            Id = getImportResutlt[0].Id,
            Unique_Key__c = uniqueKey,
            Job_Status__c = 'Processing',
            Case_Management__c = caseId,
            Job_Sequence__c = 0,
            Processed_Rows__c = 0,
            Results__c = payeeMapFileId
        );
        update importResult;
        System.Debug('Job Tracking Import record Inserted ' + importResult.Id);    
        System.debug('Job Tracking Import record Inserted '+payeeMapFileId);
        System.debug('Job Tracking Import record Inserted '+jsonPayeeMap);
        
        List<Import__c> initialRecord = [
            SELECT Results__c 
            FROM Import__c 
            WHERE Unique_Key__c = :uniqueKey 
            AND Job_Sequence__c = 0 
            LIMIT 1
        ];
        System.debug('Test Class  ' + initialRecord[0] + 'Test initialRecord.');     
        
        
        // 19. Execute Batch Process and Call UI Methods
        try {
            
            IC_Batch_Notification_Recipients__c recipient = new IC_Batch_Notification_Recipients__c(
                Name = 'Test Recipient',
                Recipient_Email__c = 'test@example.com'
            );
            insert recipient;
            
            List<Payee__c> payeeListIcRoll  = [SELECT Id, Post_Citation_Interest_for_Wages__c, Post_Judgment_Interest_for_Wages__c FROM Payee__c WHERE Id = :payeeSingle.Id];
            System.debug('payeeListIcRoll :'+ payeeListIcRoll);
            
            ProcessImportRecordsRedesigned batch = new ProcessImportRecordsRedesigned();
            batch.caseId = caseId;
            batch.importType = importType;
            batch.caseIssueIds = setOfCaseIssueIds;
            batch.uniqueKey = uniqueKey;
            
            Test.StartTest();
            Database.executeBatch(batch, 200);
            Test.StopTest();
            
            uniqueKey = 'CSV_Results_TEST_KEY';
            
            // Create Import__c records simulating jobs (Job_Sequence__c 0 = initial tracking record)
            List<Import__c> imports02 = new List<Import__c>();
            
            // Job 0 (initial tracking)
            imports02.add(new Import__c(
                Unique_Key__c      = 'CSV_Results_TEST_KEY',
                Job_Status__c      = 'Processing',
                Case_Management__c = getCase[0].Id,
                Job_Sequence__c    = 0,
                Total_Jobs__c      = 2,
                Results__c         = 'CSV_Results_TEST_KEY'
            ));
            
            // Job 1 (Completed, has file result)
            imports02.add(new Import__c(
                Unique_Key__c      = 'CSV_Results_TEST_KEY',
                Job_Status__c      = 'Completed',
                Case_Management__c = getCase[0].Id,
                Job_Sequence__c    = 1,
                Total_Jobs__c      = 2,
                Processed_Rows__c  = 1,
                Results__c         = fileId
            ));
            
            // Job 2 (Failed, with error message)
            imports02.add(new Import__c(
                Unique_Key__c      = 'CSV_Results_TEST_KEY',
                Job_Status__c      = 'Failed',
                Case_Management__c = getCase[0].Id,
                Job_Sequence__c    = 2,
                Total_Jobs__c      = 2,
                Error_Message__c   = 'Simulated failure for testing'
            ));
            
            insert imports02;
            
            List<Import__c> JobInfos = [
                SELECT
                Results__c,
                Job_Status__c,
                Job_Sequence__c,
                Total_Jobs__c,
                Processed_Rows__c,
                Error_Message__c  // Query Error_Message__c to check for failures
                FROM Import__c
                WHERE Unique_Key__c = :uniqueKey
                AND Job_Sequence__c != null
                ORDER BY Job_Sequence__c
            ];
            
            System.debug('jobInfo :' +JobInfos);
            for (Import__c jobInfo : JobInfos) {
                System.debug(jobInfo);
            }
            
            // Call other methods for code coverage
            form40ImportControllerReDesigned.getCaseIssues(caseId, importType);
            form40ImportControllerReDesigned.queryPayees(caseId);
            form40ImportControllerReDesigned.runBulkPayeeCreation(caseId, selectedCaseIssueIds, uniqueKey, importType);
            form40ImportControllerReDesigned.getImportResults(uniqueKey); 
            
            
            IC_RollUpPayeeInterest.rollupPayeeInterest(payeeList);
            
            
            
            List<Account> getAccount = [SELECT Id, Name FROM Account];
            List<Case_Role__c> getCaseRole = [SELECT Id, Name FROM Case_Role__c];
            List<Payee__c> getPayee = [SELECT Id, Name, Direct_Pay__c, Payee_Name__c FROM Payee__c];
            
            List<Payee__c> oldPayee = new List<Payee__c>();
            
            Set<Id> accountIds = new Set<Id>();
            Set<Id> caseRoleIds = new Set<Id>();
            Set<Id> payeeIds = new Set<Id>();
            
            for(Account acc : getaccount){
                accountIds.add(acc.Id);
            }  
            for(Case_Role__c cr : getCaseRole){
                caseRoleIds.add(cr.Id);
            }               
            for(Payee__c pay : getPayee){
                pay.Direct_Pay__c = 'No No No';
                payeeIds.add(pay.Id);
                oldPayee.add(pay);
            }
            String htmlBody = ' ';
            
            List<BatchEmailService.WrapperError> failedRecords = new List<BatchEmailService.WrapperError>();
            
            failedRecords.add(new BatchEmailService.WrapperError(
                getAccount[0].Id,    
                getAccount[0].Name,  
                htmlBody,     
                'Account'
            ));
            
            
            //Database.executeBatch(new RevertPayeeBatch(oldPayee, htmlBody, accountIds, caseRoleIds, payeeIds), 200);
            //Database.executeBatch(new DeletePayeeBatch(accountIds, caseRoleIds, payeeIds, htmlBody), 200);
            
            
        } catch (Exception e) {
            System.debug('Batch Exception: ' + e.getMessage());
        }
    }
}