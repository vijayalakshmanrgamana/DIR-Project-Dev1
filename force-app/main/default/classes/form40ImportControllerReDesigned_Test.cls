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
    
    public static String uniqueKey = 'CSV_Results_TEST_KEY';
    
    @testSetup
    public static void createRecords(){
        String importType = 'Form_40';
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
        IC_Batch_Notification_Recipients__c recipient = new IC_Batch_Notification_Recipients__c(
            Name = 'Test Recipient',
            Recipient_Email__c = 'test@example.com'
        );
        
        insert recipient;
        
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
            Case_Role_Status__c = 'Active'
            //Location__c         = employerAccountLocation[0].Id
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
        
        List<DIR_Case__c> getCase = [SELECT Id FROM DIR_Case__c];
        
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
            rec.Case_Management__c = getCase[0].Id;
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
        
        
        List<Account> accsToUpload = new List<Account>();
        List<Payee__c> createPayeeList = new List<Payee__c>();
        List<Case_Role__c> createCaseRoleList = new List<Case_Role__c>();
        List<recordWrapper> failedDMLRecords = new List<recordWrapper>();
        Map<String, recordWrapper> accPayeeMap = new Map<String, recordWrapper>();
        
        List<Import__c> importsMerged = [
            SELECT Id, Name, Unique_Key__c, Job_Status__c, Case_Management__c, Job_Sequence__c, Total_Jobs__c,
            Deductions_Total__c, Employee_City__c, Employee_First_Name__c, Employee_Last_Name__c,
            Employee_State__c, Employee_Street__c, Employee_Zip__c, Factor__c, Gross_Wages_Paid__c,
            Net_Wages_Paid__c, Period_Covered_by_Adjustment__c, Total_Wage_Assessment__c,
            Has_Matching_Account__c, Direct_Pay__c
            FROM Import__c
            WHERE Has_Matching_Account__c = true
            OR (Case_Management__c = :getCase[0].Id AND Unique_Key__c = :uniqueKey AND Job_Sequence__c = NULL)
        ];
        System.debug('Test Class  ' + importsMerged.Size() + ' Import Records inserted.');
        
        
        // Fetch Case Issues
        List<DIR_Violation__c> caseIssueList = [
            SELECT Id, Name, Wage_Balance_Due__c, Amount_Reserved__c, Amount_Utilized_from_Payee__c,
            Violation_Type__r.Violation_Type_Name__c,
            Violation_Type__r.Violation_Type__c
            FROM DIR_Violation__c];
        
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
                accPayee.caseManagment      = getCase[0].Id;
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
                    Case__c         = getCase[0].Id,
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
                    if(accP.directPay == 'Yes'){
                        payee.PeriodCovered__c = '12/06/2025-12/12/2025';
                    }
                    else{
                        payee.PeriodCovered__c = accP.periodCovered;
                    }
                    
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
                    
                    payee.Case_Management__c = getCase[0].Id;
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
                    payee.Post_Citation_Interest_for_Wages__c = 0;
                    payee.Post_Judgment_Interest_for_Wages__c = 0;
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
                    noMatchAccount.caseManagment      = getCase[0].Id;
                    
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
        
        
        List<Payee__c> oldPayeeRecords = [SELECT Id, Payee_Association_JSON__c, Direct_Pay__c, NetWages__c, WageAssessment__c, TotalDeductions__c,
                                          Factor__c, Post_Citation_Interest_for_Wages__c, Post_Judgment_Interest_for_Wages__c, Payee_Name__c
                                          FROM 	Payee__c];
        Map<Id, Map<String, String>> payeeRevertDataMap = new Map<Id, Map<String, String>>();
        
        // Use the retrieved list of old payee records
        for(Payee__c Oldpayee : oldPayeeRecords){
            
            Map<String, String> details = new Map<String, String>();
            
            details.put('', Oldpayee.Id);
            details.put('Payee_Association_JSON__c', Oldpayee.Payee_Association_JSON__c);
            details.put('Direct_Pay__c', String.valueOf(Oldpayee.Direct_Pay__c));
            details.put('NetWages__c', String.valueOf(Oldpayee.NetWages__c));
            details.put('WageAssessment__c', String.valueOf(Oldpayee.WageAssessment__c));
            details.put('TotalDeductions__c', String.valueOf(Oldpayee.TotalDeductions__c));
            details.put('Factor__c', String.valueOf(Oldpayee.Factor__c));
            details.put('Post_Citation_Interest_for_Wages__c', String.valueOf(Oldpayee.Post_Citation_Interest_for_Wages__c));
            details.put('Post_Judgment_Interest_for_Wages__c', String.valueOf(Oldpayee.Post_Judgment_Interest_for_Wages__c));
            details.put('Payee_Name__c', String.ValueOf(Oldpayee.Payee_Name__c));
            
            if(String.valueOf(Oldpayee.Direct_Pay__c) == 'Yes'){
                details.put('Direct_Pay__c', 'Yes,No,01');
            }
            payeeRevertDataMap.put(Oldpayee.Id, details);
            
        }
        String serializedData = JSON.serialize(payeeRevertDataMap);
        
        ContentVersion cvMultipleInsert = new ContentVersion();
        cvMultipleInsert.Title = 'PayeeRevertData' + uniqueKey + 'BatchCount';
        cvMultipleInsert.PathOnClient = 'PayeeRevertData' + uniqueKey + 'BatchCount' + '.json';
        cvMultipleInsert.VersionData = Blob.valueOf(serializedData);
        
        List<ContentVersion> cvList = new List<ContentVersion>{ cvMultipleInsert };
            List<Database.SaveResult> cvResults = Database.insert(cvList, true);
        
        for(ContentVersion conver : cvList){
            System.debug('Test ContentVersion : '+ conver);
            System.debug('Test ContentVersion : '+ conver.Title);
            System.debug('Test ContentVersion : '+ conver.VersionData);
        }
        
        List<form40ImportControllerReDesigned.ImportWrapper> wrappers = new List<form40ImportControllerReDesigned.ImportWrapper>();
        form40ImportControllerReDesigned.ImportWrapper w = new form40ImportControllerReDesigned.ImportWrapper();
        w.rowNumber = 1;
        w.isValid = true;
        w.fieldValues.put('Employee First Name', 'John');
        w.fieldValues.put('Employee Last Name', 'Doe');
        w.errorMessages.add('No errors');
        wrappers.add(w);
        
        String jsonData = JSON.serialize(wrappers);
        
        ContentVersion cv = new ContentVersion(
            Title = 'ImportResults_Test_' + System.now().getTime(),
            PathOnClient = 'ImportResults.json',
            VersionData = Blob.valueOf(jsonData)
        );
        insert cv;
        
        Id fileId = [
            SELECT ContentDocumentId    
            FROM ContentVersion    
            WHERE Id = :cv.Id    
            LIMIT 1
        ].ContentDocumentId;
        
        List<Import__c> imports = new List<Import__c>();
        
        // Job 0 (initial tracking)
        imports.add(new Import__c(
            Unique_Key__c      = 'CSV_Results_TEST_KEY',
            Job_Status__c      = 'Processing',
            Case_Management__c = getCase[0].Id,
            Job_Sequence__c    = 0,
            Total_Jobs__c      = 2,
            Results__c         = fileId
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
        
        String contentTitlePattern = 'PayeeRevertData' + uniqueKey + '%';
        ContentVersion cvinsert = new ContentVersion();
        cvinsert.Title = 'PayeeRevertData' + uniqueKey + 'BatchCount';
        cvinsert.VersionData = Blob.valueOf('Test 01');
        cvinsert.PathOnClient = 'PayeeRevertData' + uniqueKey + 'BatchCount' + '.json';
        insert cvinsert;
        
        
    }
    
    @isTest
    Public static void form40CRD(){
        
        List<DIR_Case__c> getCase = [SELECT Id FROM DIR_Case__c];
        List<DIR_Case__c> queryCase = [SELECT Id, Name, Import_Form_40_Details__c FROM DIR_Case__c LIMIT 1];
        List<DIR_Violation__c> queriedCaseIssues = [SELECT Id, Violation_Type__c, Case__c, Assessment__c, Citation_Amount__c,
                                                    Wages_Due__c, Original_Penalty_Assessment_Amount__c,
                                                    Total_Interest_Amount__c, Status__c,
                                                    Post_Citation_Interest_for_Wages__c, Post_Judgment_Interest_for_Wages__c,
                                                    Citation_Date__c, RecordTypeId FROM DIR_Violation__c];
        
        String importType = 'Form_40';
        
        
        Id caseId = getCase[0].Id;
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
            
            // **Standard Field Assignments**
            rec.Case_Management__c = getCase[0].Id;
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
        
        
        String uniqueKey = 'CSV_Results_TEST_KEY';
        Integer insertedAccounts   = 0;
        Integer insertedCaseRoles  = 0;
        Integer insertedPayees     = 0;
        Integer updatedCaseIssues  = 0;
        Integer updatedCases       = 0;
        boolean shouldRunSecondBatch = false;
        Integer NumberofImportRecordsInserted = 0;
        
        
        
        System.debug(queriedCaseIssues.size());
        
        Set<Id> setOfCaseIssueIds = new Set<Id>();
        for(DIR_Violation__c caseIssueId : queriedCaseIssues){
            setOfCaseIssueIds.add(caseIssueId.Id);
        }
        System.debug(getCase[0].Id);
        System.debug(setOfCaseIssueIds);
        System.debug(importType);
        System.debug(uniqueKey);
        List<Id> selectedCaseIssueIds = new List<Id>{ queriedCaseIssues[0].Id };
            
            String cacheKey = form40ImportControllerReDesigned.parseCSVAndValidate(
                csvLines,
                getCase[0].Id,
                selectedCaseIssueIds,
                importType
            );
        
        delete toInsert;
        
        try {
            Map<String, Object> results = form40ImportControllerReDesigned.getImportResults(uniqueKey);            
        } catch (Exception e) {
        }
        
        uniqueKey = 'CSV_Results_TEST_KEY';
        importType = 'Corrective_Form_40';
        
        List<form40ImportControllerReDesigned.ImportWrapper> wrappers = new List<form40ImportControllerReDesigned.ImportWrapper>();
        form40ImportControllerReDesigned.ImportWrapper w = new form40ImportControllerReDesigned.ImportWrapper();
        w.rowNumber = 1;
        w.isValid = true;
        w.fieldValues.put('Employee First Name', 'John');
        w.fieldValues.put('Employee Last Name', 'Doe');
        w.errorMessages.add('No errors');
        wrappers.add(w);
        
        String jsonData = JSON.serialize(wrappers);
        
        ContentVersion cv = new ContentVersion(
            Title = 'ImportResults_Test_' + System.now().getTime(),
            PathOnClient = 'ImportResults.json',
            VersionData = Blob.valueOf(jsonData)
        );
        insert cv;
        
        Id fileId = [
            SELECT ContentDocumentId    
            FROM ContentVersion    
            WHERE Id = :cv.Id    
            LIMIT 1
        ].ContentDocumentId;
        
        List<Import__c> imports = new List<Import__c>();
        
        // Job 0 (initial tracking)
        imports.add(new Import__c(
            Unique_Key__c      = 'CSV_Results_TEST_KEY',
            Job_Status__c      = 'Processing',
            Case_Management__c = getCase[0].Id,
            Job_Sequence__c    = 0,
            Total_Jobs__c      = 2,
            Results__c         = fileId
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
        
        Id contentDocId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
        ].ContentDocumentId;
        
        
        
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
        
        form40ImportControllerReDesigned.revalidateEditedRows(
            editedRows,
            uniqueKey,
            getCase[0].Id                
        );
        
        
        List<Payee__c> allPayeeList = queryPayees(getCase[0].Id);
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
        
        System.debug('caseId :'+getCase[0].Id);
        System.debug('Unique_Key__c :'+uniqueKey);
        
        try {
            form40ImportControllerReDesigned.getCaseIssues(getCase[0].Id, importType);
            form40ImportControllerReDesigned.queryPayees(getCase[0].Id);
            form40ImportControllerReDesigned.runBulkPayeeCreation(getCase[0].Id, selectedCaseIssueIds, uniqueKey, importType);
            form40ImportControllerReDesigned.getImportResults(uniqueKey);             
            
            
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
            
            for(Integer i=0; i<5; i++){
                
                List<form40ImportControllerReDesigned.CaseIssueWrapper> issueList =
                    form40ImportControllerReDesigned.getCaseIssues(getCase[0].Id, importType);
                importType = 'Form_40_Partial';
                
            }
            
        } catch (Exception e) {
            System.debug('Batch Exception: ' + e.getMessage());
        }
        
        try {
            System.debug('---- Calling getCaseIssues ----');
            List<form40ImportControllerReDesigned.CaseIssueWrapper> issues =
                form40ImportControllerReDesigned.getCaseIssues(
                    null,     // caseId
                    null      // importType
                );
            System.debug('getCaseIssues result: ' + issues);
        }
        catch (Exception ex) {
            System.debug('ERROR in getCaseIssues: ' + ex.getMessage());
        }
        
        try {
            System.debug('---- Calling parseCSVAndValidate ----');
            String parseResult =
                form40ImportControllerReDesigned.parseCSVAndValidate(
                    null,     // List<String> lines
                    null,     // caseId
                    null,     // selectedCaseIssueIds
                    null      // importType
                );
            System.debug('parseCSVAndValidate result: ' + parseResult);
        }
        catch (Exception ex) {
            System.debug('ERROR in parseCSVAndValidate: ' + ex.getMessage());
        }
        
        try {
            System.debug('---- Calling getImportResults ----');
            Map<String, Object> importResults =
                form40ImportControllerReDesigned.getImportResults(
                    null      // cacheKey
                );
            System.debug('getImportResults result: ' + importResults);
        }
        catch (Exception ex) {
            System.debug('ERROR in getImportResults: ' + ex.getMessage());
        }
        
        try {
            System.debug('---- Calling revalidateEditedRows ----');
            List<form40ImportControllerReDesigned.ImportWrapper> revalidated =
                form40ImportControllerReDesigned.revalidateEditedRows(
                    null,   // editedRows
                    null,   // key
                    null    // caseId
                );
            System.debug('revalidateEditedRows result: ' + revalidated);
        }
        catch (Exception ex) {
            System.debug('ERROR in revalidateEditedRows: ' + ex.getMessage());
        }
        
        try {
            System.debug('---- Calling saveValidRecords ----');
            String saveResult =
                form40ImportControllerReDesigned.saveValidRecords(
                    null,    // rows
                    null     // uniqueKey
                );
            System.debug('saveValidRecords result: ' + saveResult);
        }
        catch (Exception ex) {
            System.debug('ERROR in saveValidRecords: ' + ex.getMessage());
        }
        
        System.debug('---- All Method Calls Completed ----');
        
        form40ImportControllerReDesigned.cancelImport(uniqueKey);
        form40ImportControllerReDesigned.deleteImports(uniqueKey);
        
    }
    
    @isTest
    public static void processIRRDFirst(){
        
        String importType = 'Form_40';
        Integer insertedAccounts   = 0;
        Integer insertedCaseRoles  = 0;
        Integer insertedPayees     = 0;
        Integer updatedCaseIssues  = 0;
        Integer updatedCases       = 0;
        boolean shouldRunSecondBatch = false;
        Integer NumberofImportRecordsInserted = 0;
        
        List<DIR_Case__c> getCase = [SELECT Id FROM DIR_Case__c];
        List<DIR_Case__c> queryCase = [SELECT Id, Name, Import_Form_40_Details__c FROM DIR_Case__c];
        List<DIR_Violation__c> queriedCaseIssues = [SELECT Id, Violation_Type__c, Case__c, Assessment__c, Citation_Amount__c,
                                                    Wages_Due__c, Original_Penalty_Assessment_Amount__c,
                                                    Total_Interest_Amount__c, Status__c,
                                                    Post_Citation_Interest_for_Wages__c, Post_Judgment_Interest_for_Wages__c,
                                                    Citation_Date__c, RecordTypeId FROM DIR_Violation__c];
        
        Set<Id> setOfCaseIssueIds = new Set<Id>();
        for(DIR_Violation__c caseIssueId : queriedCaseIssues){
            setOfCaseIssueIds.add(caseIssueId.Id);
        }
        
        Import__c  imp01 = new Import__c(Unique_Key__c      = 'CSV_Results_TEST_KEY',
                                         Job_Status__c      = 'Failed',
                                         Case_Management__c = getCase[0].Id,
                                         Job_Sequence__c    = null,
                                         Total_Jobs__c      = 2,
                                         Error_Message__c   = 'Simulated failure for testing');
        
        insert imp01;
        
        String contentTitlePattern = 'PayeeRevertData' + uniqueKey + '%';
        ContentVersion cvinsert = new ContentVersion();
        cvinsert.Title = 'PayeeRevertData' + uniqueKey + 'BatchCount';
        cvinsert.VersionData = Blob.valueOf('Test 01');
        cvinsert.PathOnClient = 'PayeeRevertData' + uniqueKey + 'BatchCount' + '.json';
        insert cvinsert;
        
        ProcessImportRecordsRedesigned batch01 = new ProcessImportRecordsRedesigned();
        batch01.caseId = getCase[0].Id;
        batch01.importType = importType;
        batch01.caseIssueIds = setOfCaseIssueIds;
        batch01.uniqueKey = uniqueKey;
        
        Test.StartTest();
        Database.executeBatch(batch01, 200);
        Test.StopTest();
        
         importType = 'Form_40_Partial';

        ProcessImportRecordsRedesigned batch02 = new ProcessImportRecordsRedesigned();
        batch02.caseId = getCase[0].Id;
        batch02.importType = importType;
        batch02.caseIssueIds = setOfCaseIssueIds;
        batch02.uniqueKey = uniqueKey;
        
        Database.executeBatch(batch02, 200);
        
        try {
            System.debug('---- Calling ProcessImportRecordsRedesigned ----');
            
            ProcessImportRecordsRedesigned batch03 = new ProcessImportRecordsRedesigned();
            batch03.caseId = Null;
            batch03.importType = Null;
            batch03.caseIssueIds = Null;
            batch03.uniqueKey = Null;
            
            Database.executeBatch(batch03, 200);
            
        }
        catch (Exception ex) {
            System.debug('ERROR in ProcessImportRecordsRedesigned: ' + ex.getMessage());
        }
        
        importType = 'Corrective_Form_40';

        ProcessImportRecordsRedesigned batch04 = new ProcessImportRecordsRedesigned();
        batch04.caseId = getCase[0].Id;
        batch04.importType = importType;
        batch04.caseIssueIds = setOfCaseIssueIds;
        batch04.uniqueKey = uniqueKey;
        
        Database.executeBatch(batch04, 200);
        
    }
    
    @isTest
    public static void processIRRDSecond(){
        
        
        String importType = 'Corrective_Form_40';
        Integer insertedAccounts   = 0;
        Integer insertedCaseRoles  = 0;
        Integer insertedPayees     = 0;
        Integer updatedCaseIssues  = 0;
        Integer updatedCases       = 0;
        boolean shouldRunSecondBatch = false;
        Integer NumberofImportRecordsInserted = 0;
        
        List<DIR_Case__c> getCase = [SELECT Id FROM DIR_Case__c];
        List<DIR_Case__c> queryCase = [SELECT Id, Name, Import_Form_40_Details__c FROM DIR_Case__c];
        List<DIR_Violation__c> queriedCaseIssues = [SELECT Id, Violation_Type__c, Case__c, Assessment__c, Citation_Amount__c,
                                                    Wages_Due__c, Original_Penalty_Assessment_Amount__c,
                                                    Total_Interest_Amount__c, Status__c,
                                                    Post_Citation_Interest_for_Wages__c, Post_Judgment_Interest_for_Wages__c,
                                                    Citation_Date__c, RecordTypeId FROM DIR_Violation__c];
        
        
                Set<Id> setOfCaseIssueIds = new Set<Id>();
        for(DIR_Violation__c caseIssueId : queriedCaseIssues){
            setOfCaseIssueIds.add(caseIssueId.Id);
        }
        
        List<Import__c> impList = [
            SELECT Id
            FROM Import__c
            WHERE Case_Management__c = :getCase[0].Id AND (Employee_First_Name__c = null OR Employee_Last_Name__c = null OR Direct_Pay__c = 'Yes')
        ];
        delete impList;
        
        String contentTitlePattern = 'PayeeRevertData' + uniqueKey + '%';
        ContentVersion cvinsert = new ContentVersion();
        cvinsert.Title = 'PayeeRevertData' + uniqueKey + 'BatchCount';
        cvinsert.VersionData = Blob.valueOf('Test 01');
        cvinsert.PathOnClient = 'PayeeRevertData' + uniqueKey + 'BatchCount' + '.json';
        insert cvinsert;
        
        
        ProcessImportRecordsRedesigned batch = new ProcessImportRecordsRedesigned();
        batch.caseId = getCase[0].Id;
        batch.importType = importType;
        batch.caseIssueIds = setOfCaseIssueIds;
        batch.uniqueKey = uniqueKey;
        
        Test.StartTest();
        Database.executeBatch(batch, 200);
        Test.StopTest();
    }
    @isTest
    public static void deletePB(){
        
        String importType = 'Form_40';
        Integer insertedAccounts   = 0;
        Integer insertedCaseRoles  = 0;
        Integer insertedPayees     = 0;
        Integer updatedCaseIssues  = 0;
        Integer updatedCases       = 0;
        boolean shouldRunSecondBatch = false;
        Integer NumberofImportRecordsInserted = 0;
        
        List<DIR_Case__c> getCase = [SELECT Id FROM DIR_Case__c];
        List<DIR_Case__c> queryCase = [SELECT Id, Name, Import_Form_40_Details__c FROM DIR_Case__c];
        List<DIR_Violation__c> queriedCaseIssues = [SELECT Id, Violation_Type__c, Case__c, Assessment__c, Citation_Amount__c,
                                                    Wages_Due__c, Original_Penalty_Assessment_Amount__c,
                                                    Total_Interest_Amount__c, Status__c,
                                                    Post_Citation_Interest_for_Wages__c, Post_Judgment_Interest_for_Wages__c,
                                                    Citation_Date__c, RecordTypeId FROM DIR_Violation__c];
        
        List<BatchEmailService.WrapperError> failedRecords = new List<BatchEmailService.WrapperError>();
        
        
        List<Account> getAccountRecords = [SELECT Id FROM Account];
        List<Case_Role__c> getCaseRoleRecords = [SELECT Id FROM Case_Role__c];
        List<Payee__c> getPayeeRecords = [SELECT Id FROM Payee__c];
        
        Set<Id> accDeleteIds = new Set<Id>();
        Set<Id> caseRoleDeleteIds = new Set<Id>();
        Set<Id> payeeDeleteIds = new Set<Id>();
        
        for (Account acc : getAccountRecords) {
            accDeleteIds.add(acc.Id);
        }
        
        for (Case_Role__c cr : getCaseRoleRecords) {
            caseRoleDeleteIds.add(cr.Id);
        }
        
        for (Payee__c payee : getPayeeRecords) {
            payeeDeleteIds.add(payee.Id);
        }
        
        Integer successCountPayee = 0;
        Integer failureCountPayee = 0;
        Boolean batchError = true;
        Integer batchRunCount = 2;
        String allErrorMessages = 'Test Error';
        String creationErrorTable = 'Test Creation Error Table';
        String updateerrorTable = 'Test Update Error Table';
        Map<String, Integer> processSummary = new Map<String, Integer>();
        
        BatchEmailService.BatchSummaryWrapper wrap = new BatchEmailService.BatchSummaryWrapper();
        
        wrap.caseId                         =  getCase[0].Id;
        wrap.importType                     = importType;
        wrap.insertedAccounts               = insertedAccounts;
        wrap.insertedCaseRoles              = insertedCaseRoles;
        wrap.insertedPayees                 = insertedPayees;
        wrap.successCountPayee              = successCountPayee;
        wrap.failureCountPayee              = failureCountPayee;
        wrap.batchError                     = batchError;
        wrap.batchRunCount                  = batchRunCount;
        wrap.numberOfImportRecordsInserted  = NumberofImportRecordsInserted;
        wrap.allErrorMessages               = allErrorMessages;
        wrap.creationErrorTable             = creationErrorTable;
        wrap.updateErrorTable               = updateerrorTable;
        wrap.processSummary                 = processSummary;
        wrap.processName                    = 'form40ImportControllerReDesigned_Test';
        wrap.reverted                       = false;
        wrap.failedRecordsDelete                 = failedRecords;
        wrap.failedRecordsRevert                 = failedRecords;
        wrap.correctiveForm40DeleteSuccess      = failedRecords;
        wrap.correctiveForm40DeleteError        = failedRecords;
        
        Database.executeBatch(
            new DeletePayeeBatch(
                payeeDeleteIds,
                false,
                failedRecords,
                processSummary,
                wrap
            ),
            200
        );
        
        Database.executeBatch(
            new DeletePayeeBatch(
                getCase[0].Id,
                true
            ),
            200
        );
    }
    
    
    @isTest
    public static void deletePBError(){
        
        String importType = 'Form_40';
        Integer insertedAccounts   = 0;
        Integer insertedCaseRoles  = 0;
        Integer insertedPayees     = 0;
        Integer updatedCaseIssues  = 0;
        Integer updatedCases       = 0;
        boolean shouldRunSecondBatch = false;
        Integer NumberofImportRecordsInserted = 0;
        
        List<DIR_Case__c> getCase = [SELECT Id FROM DIR_Case__c];
        List<DIR_Case__c> queryCase = [SELECT Id, Name, Import_Form_40_Details__c FROM DIR_Case__c];
        List<DIR_Violation__c> queriedCaseIssues = [SELECT Id, Violation_Type__c, Case__c, Assessment__c, Citation_Amount__c,
                                                    Wages_Due__c, Original_Penalty_Assessment_Amount__c,
                                                    Total_Interest_Amount__c, Status__c,
                                                    Post_Citation_Interest_for_Wages__c, Post_Judgment_Interest_for_Wages__c,
                                                    Citation_Date__c, RecordTypeId FROM DIR_Violation__c];
        
        List<BatchEmailService.WrapperError> failedRecords = new List<BatchEmailService.WrapperError>();
        
        
        List<Account> getAccountRecords = [SELECT Id FROM Account];
        List<Case_Role__c> getCaseRoleRecords = [SELECT Id FROM Case_Role__c];
        List<Payee__c> getPayeeRecords = [SELECT Id FROM Payee__c];
        
        Set<Id> accDeleteIds = new Set<Id>();
        Set<Id> caseRoleDeleteIds = new Set<Id>();
        Set<Id> payeeDeleteIds = new Set<Id>();
        
        for (Account acc : getAccountRecords) {
            accDeleteIds.add(acc.Id);
        }
        
        for (Case_Role__c cr : getCaseRoleRecords) {
            caseRoleDeleteIds.add(cr.Id);
        }
        
        for (Payee__c payee : getPayeeRecords) {
            payeeDeleteIds.add(payee.Id);
        }
        
        Integer successCountPayee = 0;
        Integer failureCountPayee = 0;
        Boolean batchError = true;
        Integer batchRunCount = 2;
        String allErrorMessages = 'Test Error';
        String creationErrorTable = 'Test Creation Error Table';
        String updateerrorTable = 'Test Update Error Table';
        Map<String, Integer> processSummary = new Map<String, Integer>{'Test ' => 1};
        
        BatchEmailService.BatchSummaryWrapper wrap = new BatchEmailService.BatchSummaryWrapper();
        
        wrap.caseId                         =  getCase[0].Id;
        wrap.importType                     = importType;
        wrap.insertedAccounts               = insertedAccounts;
        wrap.insertedCaseRoles              = insertedCaseRoles;
        wrap.insertedPayees                 = insertedPayees;
        wrap.successCountPayee              = successCountPayee;
        wrap.failureCountPayee              = failureCountPayee;
        wrap.batchError                     = batchError;
        wrap.batchRunCount                  = batchRunCount;
        wrap.numberOfImportRecordsInserted  = NumberofImportRecordsInserted;
        wrap.allErrorMessages               = allErrorMessages;
        wrap.creationErrorTable             = creationErrorTable;
        wrap.updateErrorTable               = updateerrorTable;
        wrap.processSummary                 = processSummary;
        wrap.processName                    = 'form40ImportControllerReDesigned_Test';
        wrap.reverted                       = false;
        wrap.failedRecordsDelete                 = failedRecords;
        wrap.failedRecordsRevert                 = failedRecords;
        wrap.correctiveForm40DeleteSuccess      = failedRecords;
        wrap.correctiveForm40DeleteError        = failedRecords;
        List<Import__c> deleteImports = [Select Id From Import__c];
        delete deleteImports;
        Database.executeBatch(
            new DeletePayeeBatch(
                null,
                false,
                failedRecords,
                processSummary,
                wrap
            ),
            200
        );
        
        Database.executeBatch(
            new DeletePayeeBatch(
                getCase[0].Id,
                true
            ),
            200
        );
    }
    
    @isTest
    public static void RevertPB(){
        
        
        String importType = 'Form_40';
        Integer insertedAccounts   = 0;
        Integer insertedCaseRoles  = 0;
        Integer insertedPayees     = 0;
        Integer updatedCaseIssues  = 0;
        Integer updatedCases       = 0;
        boolean shouldRunSecondBatch = false;
        Integer NumberofImportRecordsInserted = 0;
        
        
        String contentTitlePattern = 'PayeeRevertData' + uniqueKey + '%';
        
        for(ContentVersion conver : [
            SELECT Id, VersionData, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Title LIKE :contentTitlePattern
        ]){
            System.debug('Test ContentVersion RevertPB: '+ conver);
            System.debug('Test ContentVersion RevertPB: '+ conver.Title);
            System.debug('Test ContentVersion RevertPB: '+ conver.VersionData);
        }
        
        List<DIR_Case__c> getCase = [SELECT Id FROM DIR_Case__c];
        List<DIR_Case__c> queryCase = [SELECT Id, Name, Import_Form_40_Details__c FROM DIR_Case__c];
        List<DIR_Violation__c> queriedCaseIssues = [SELECT Id, Violation_Type__c, Case__c, Assessment__c, Citation_Amount__c,
                                                    Wages_Due__c, Original_Penalty_Assessment_Amount__c,
                                                    Total_Interest_Amount__c, Status__c,
                                                    Post_Citation_Interest_for_Wages__c, Post_Judgment_Interest_for_Wages__c,
                                                    Citation_Date__c, RecordTypeId FROM DIR_Violation__c];
        
        List<BatchEmailService.WrapperError> failedRecords = new List<BatchEmailService.WrapperError>();
        
        List<Account> getAccountRecords = [SELECT Id FROM Account];
        List<Case_Role__c> getCaseRoleRecords = [SELECT Id FROM Case_Role__c];
        List<Payee__c> getPayeeRecords = [SELECT Id FROM Payee__c];
        
        Set<Id> accDeleteIds = new Set<Id>();
        Set<Id> caseRoleDeleteIds = new Set<Id>();
        Set<Id> payeeDeleteIds = new Set<Id>();
        
        for (Account acc : getAccountRecords) {
            accDeleteIds.add(acc.Id);
        }
        
        for (Case_Role__c cr : getCaseRoleRecords) {
            caseRoleDeleteIds.add(cr.Id);
        }
        
        for (Payee__c payee : getPayeeRecords) {
            payeeDeleteIds.add(payee.Id);
        }
        
        Integer successCountPayee = 0;
        Integer failureCountPayee = 0;
        Boolean batchError = true;
        Integer batchRunCount = 2;
        String allErrorMessages = 'Test Error';
        String creationErrorTable = 'Test Creation Error Table';
        String updateerrorTable = 'Test Update Error Table';
        Map<String, Integer> processSummary = new Map<String, Integer>();
        
        BatchEmailService.BatchSummaryWrapper wrap = new BatchEmailService.BatchSummaryWrapper();
        
        wrap.caseId                         =  getCase[0].Id;
        wrap.importType                     = importType;
        wrap.insertedAccounts               = insertedAccounts;
        wrap.insertedCaseRoles              = insertedCaseRoles;
        wrap.insertedPayees                 = insertedPayees;
        wrap.successCountPayee              = successCountPayee;
        wrap.failureCountPayee              = failureCountPayee;
        wrap.batchError                     = batchError;
        wrap.batchRunCount                  = batchRunCount;
        wrap.numberOfImportRecordsInserted  = NumberofImportRecordsInserted;
        wrap.allErrorMessages               = allErrorMessages;
        wrap.creationErrorTable             = creationErrorTable;
        wrap.updateErrorTable               = updateerrorTable;
        wrap.processSummary                 = processSummary;
        wrap.processName                    = 'form40ImportControllerReDesigned_Test';
        wrap.reverted                       = false;
        wrap.failedRecordsDelete                 = failedRecords;
        wrap.failedRecordsRevert                 = failedRecords;
        wrap.correctiveForm40DeleteSuccess      = failedRecords;
        wrap.correctiveForm40DeleteError        = failedRecords;
        
        Database.executeBatch(
            new RevertPayeeBatch(
                payeeDeleteIds,                    
                uniqueKey,
                wrap            
            ),
            2
        );
        
        
        payeeDeleteIds.clear();
        
        Database.executeBatch(
            new RevertPayeeBatch(
                payeeDeleteIds,                    
                uniqueKey,
                wrap            
            ),
            2
        );
        
    }
    
    @isTest
    public static void batchEmailService(){
        List<BatchEmailService.WrapperError> failedRecords = new List<BatchEmailService.WrapperError>();
        Integer successCountPayee = 0;
        Integer failureCountPayee = 0;
        Boolean batchError = true;
        Integer batchRunCount = 2;
        String allErrorMessages = 'Test Error';
        String creationErrorTable = 'Test Creation Error Table';
        String updateerrorTable = 'Test Update Error Table';
        Map<String, Integer> processSummary = new Map<String, Integer>();
        boolean reverted = false;
        
        String importType = 'Form_40';
        Integer insertedAccounts   = 0;
        Integer insertedCaseRoles  = 0;
        Integer insertedPayees     = 0;
        Integer updatedCaseIssues  = 0;
        Integer updatedCases       = 0;
        Integer NumberofImportRecordsInserted = 0;
        List<DIR_Case__c> getCase = [SELECT Id FROM DIR_Case__c];
        
        BatchEmailService.sendBatchSummaryEmail(
            getCase[0].Id,
            importType,
            insertedAccounts,
            insertedCaseRoles,
            insertedPayees,
            successCountPayee,
            failureCountPayee,
            batchError,
            batchRunCount,
            NumberofImportRecordsInserted,
            allErrorMessages,
            creationErrorTable,
            updateerrorTable,
            processSummary,
            'ProcessImportRecordsRedesigned',
            reverted,
            failedRecords,
            failedRecords,
            failedRecords,
            failedRecords
        );
        
        BatchEmailService.sendDeletionSummaryEmail(
            getCase[0].Id,
            'Cleanup',
            processSummary,
            'DeletePayeeBatch',
            failedRecords,
            failedRecords
        );
        
        reverted = true;
        
        processSummary.put('Account_Deleted', 1);
        processSummary.put('CaseRole_Deleted', 1);
        processSummary.put('Payee_Deleted', 1);
        processSummary.put('Account_Failed', 1);
        processSummary.put('CaseRole_Failed', 1);
        processSummary.put('Payee_Failed', 1);
        processSummary.put('Payee_Updated', 1);
        processSummary.put('Payee_Updated_Failed', 1);
            
        BatchEmailService.sendBatchSummaryEmail(
            getCase[0].Id,
            importType,
            insertedAccounts,
            insertedCaseRoles,
            insertedPayees,
            successCountPayee,
            failureCountPayee,
            batchError,
            batchRunCount,
            NumberofImportRecordsInserted,
            allErrorMessages,
            creationErrorTable,
            updateerrorTable,
            processSummary,
            'ProcessImportRecordsRedesigned',
            reverted,
            failedRecords,
            failedRecords,
            failedRecords,
            failedRecords
        );
        
        BatchEmailService.sendDeletionSummaryEmail(
            getCase[0].Id,
            'Cleanup',
            processSummary,
            'DeletePayeeBatch',
            failedRecords,
            failedRecords
        );
        
        failedRecords.add(new BatchEmailService.WrapperError(
            getCase[0].Id,
            'Test 001',
            'Error Test 001',
            'Payee'
        ));
        
        batchRunCount = 1;
        batchError = true;
        reverted = true;
        
        BatchEmailService.sendBatchSummaryEmail(
            getCase[0].Id,
            importType,
            insertedAccounts,
            insertedCaseRoles,
            insertedPayees,
            successCountPayee,
            failureCountPayee,
            batchError,
            batchRunCount,
            NumberofImportRecordsInserted,
            allErrorMessages,
            creationErrorTable,
            updateerrorTable,
            processSummary,
            'ProcessImportRecordsRedesigned',
            reverted,
            failedRecords,
            failedRecords,
            failedRecords,
            failedRecords
        );
        
        BatchEmailService.sendDeletionSummaryEmail(
            getCase[0].Id,
            'Cleanup',
            processSummary,
            'DeletePayeeBatch',
            failedRecords,
            failedRecords
        );
        
        
        batchRunCount = 2;
        batchError = false;
        reverted = false;
        
        BatchEmailService.sendBatchSummaryEmail(
            getCase[0].Id,
            importType,
            insertedAccounts,
            insertedCaseRoles,
            insertedPayees,
            successCountPayee,
            failureCountPayee,
            batchError,
            batchRunCount,
            NumberofImportRecordsInserted,
            allErrorMessages,
            creationErrorTable,
            updateerrorTable,
            processSummary,
            'ProcessImportRecordsRedesigned',
            reverted,
            failedRecords,
            failedRecords,
            failedRecords,
            failedRecords
        );
        
        BatchEmailService.sendDeletionSummaryEmail(
            getCase[0].Id,
            'Cleanup',
            processSummary,
            'DeletePayeeBatch',
            failedRecords,
            failedRecords
        );
    }
    
    @isTest
    public static void IC_RollUpPB(){
        List<DIR_Case__c> getCase = [SELECT Id FROM DIR_Case__c];
        Set<Id> caseIds = new Set<Id>();
        try {
            caseIds.add(Id.valueOf(getCase[0].Id));
            
            Database.executeBatch(new IC_RollUpPayeeBatch(caseIds));
        } catch (Exception ex) {
            System.debug('Error while executing IC_RollUpPayeeBatch: ' + ex.getMessage());
        }
        try {
            System.debug('---- Calling IC_RollUpPayeeBatch ----');
            
            Database.executeBatch(new IC_RollUpPayeeBatch(null));
            
        }
        catch (Exception ex) {
            System.debug('ERROR in IC_RollUpPayeeBatch: ' + ex.getMessage());
        }
    }
    
    @isTest
    public static void CorrectiveForm40PayeeDeletion(){
        
        Integer successCountPayee = 0;
        Integer failureCountPayee = 0;
        Boolean batchError = true;
        Integer batchRunCount = 2;
        String allErrorMessages = 'Test Error';
        String creationErrorTable = 'Test Creation Error Table';
        String updateerrorTable = 'Test Update Error Table';
        Map<String, Integer> processSummary = new Map<String, Integer>();
        
        String importType = 'Form_40';
        Integer insertedAccounts   = 0;
        Integer insertedCaseRoles  = 0;
        Integer insertedPayees     = 0;
        Integer updatedCaseIssues  = 0;
        Integer updatedCases       = 0;
        boolean shouldRunSecondBatch = false;
        Integer NumberofImportRecordsInserted = 0;
        
        List<DIR_Case__c> getCase = [SELECT Id FROM DIR_Case__c];
		List<BatchEmailService.WrapperError> failedRecords = new List<BatchEmailService.WrapperError>();
        
        for(Integer i=0; i<5; i++){
        }
        BatchEmailService.BatchSummaryWrapper wrap = new BatchEmailService.BatchSummaryWrapper();
        
        wrap.caseId                         =  getCase[0].Id;
        wrap.importType                     = importType;
        wrap.insertedAccounts               = insertedAccounts;
        wrap.insertedCaseRoles              = insertedCaseRoles;
        wrap.insertedPayees                 = insertedPayees;
        wrap.successCountPayee              = successCountPayee;
        wrap.failureCountPayee              = failureCountPayee;
        wrap.batchError                     = batchError;
        wrap.batchRunCount                  = batchRunCount;
        wrap.numberOfImportRecordsInserted  = NumberofImportRecordsInserted;
        wrap.allErrorMessages               = allErrorMessages;
        wrap.creationErrorTable             = creationErrorTable;
        wrap.updateErrorTable               = updateerrorTable;
        wrap.processSummary                 = processSummary;
        wrap.processName                    = 'form40ImportControllerReDesigned_Test';
        wrap.reverted                       = false;
        wrap.failedRecordsDelete                 = failedRecords;
        wrap.failedRecordsRevert                 = failedRecords;
        wrap.correctiveForm40DeleteSuccess      = failedRecords;
        wrap.correctiveForm40DeleteError        = failedRecords;
        
                List<DIR_Violation__c> queriedCaseIssues = [SELECT Id, Violation_Type__c, Case__c, Assessment__c, Citation_Amount__c,
                                                    Wages_Due__c, Original_Penalty_Assessment_Amount__c,
                                                    Total_Interest_Amount__c, Status__c,
                                                    Post_Citation_Interest_for_Wages__c, Post_Judgment_Interest_for_Wages__c,
                                                    Citation_Date__c, RecordTypeId FROM DIR_Violation__c];
         
        Set<Id> setOfCaseIssueIds = new Set<Id>();
        for(DIR_Violation__c caseIssueId : queriedCaseIssues){
            setOfCaseIssueIds.add(caseIssueId.Id);
        }
        Test.startTest();
        Database.executeBatch(new CorrectiveForm40PayeeDeletion(wrap, uniqueKey, setOfCaseIssueIds), 200);
		DataBase.executeBatch(new UpdateAmountUtilizedByPayee(wrap), 200);
        System.enqueueJob(new IC_RollUpPayeeQueueable(wrap));
        Test.stopTest();
        
        wrap.caseId =  Null;
        System.enqueueJob(new IC_RollUpPayeeQueueable(wrap));
        Database.executeBatch(new CorrectiveForm40PayeeDeletion(wrap, uniqueKey, setOfCaseIssueIds), 200);
    }
}