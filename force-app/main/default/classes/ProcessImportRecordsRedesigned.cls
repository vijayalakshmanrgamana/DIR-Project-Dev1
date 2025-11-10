/*
 * Global Batchable class to process imported records, create Accounts, Case Roles, and Payees,
 * handle DML errors, update Case Issues, and send an email summary.
 */
global class ProcessImportRecordsRedesigned implements Database.Batchable<SObject>, Database.Stateful {

    // --- Global Variables ---
    global String caseId { get; set; }
    global List<String> errorMessages { get; set; }
    global String importType { get; set; }
    global List<recordWrapper> failedDMLRecords { get; set; }
    global Set<Id> caseIssueIds { get; set; }
    global string uniqueKey { get; set; }
    global boolean stopBatch = false;
    
    public Boolean isLinkedToAllCaseIssue { get; set; }

    // Counters for DML summary (Stateful)
    global Integer insertedAccounts     = 0;
    global Integer insertedCaseRoles    = 0;
    global Integer insertedPayees       = 0;
    global Integer updatedCaseIssues    = 0;
    global Integer updatedCases         = 0;
    global boolean shouldRunSecondBatch = false;
    global Integer NumberofImportRecordsInserted = 0;

    // Update the Case Issue Records
    Map<Id, Decimal> caseIssueAmountUtilizedFromPayee = new Map<Id, Decimal>();
    Set<Id> checkPayeeIds = new Set<Id>();
    
    // To Store account, case Role, Payee Ids for Delete
    global Integer batchRunCount = 0;
    global Set<Id> accDeleteIds = new Set<Id>();
    global Set<Id> caseRoleDeleteIds = new Set<Id>();
    global Set<Id> payeeDeleteIds = new Set<Id>();

    // --- Constructor ---
    public ProcessImportRecordsRedesigned() {
        this.caseId = caseId; // Note: 'caseId' is null here unless passed via an overloaded constructor
        failedDMLRecords = new List<recordWrapper>();
       	errorMessages    = new List<String>();
		Set<Id> caseIssueIds = new Set<Id>();
    }

    // --- Start Method ---
    global Database.QueryLocator start(Database.BatchableContext BC) {
        
                
            AggregateResult[] agr = [
            SELECT COUNT(Id) caseIssueCount 
            FROM DIR_VIolation__c 
            WHERE Case__c = : caseId
        ];

        Integer caseIssueCount = (Integer) agr[0].get('caseIssueCount');
        isLinkedToAllCaseIssue = (caseIssueCount == caseIssueIds.size());
        System.debug('caseIssueCount :' + caseIssueCount);
        System.debug('caseIssueIds.size() :' + caseIssueIds.size());
        System.debug('isLinkedToAllCaseIssue :'+ isLinkedToAllCaseIssue);
        
        
        return Database.getQueryLocator([
            SELECT Name, Case_Management__c, Deductions_Total__c, Employee_City__c,
                   Employee_First_Name__c, Employee_Last_Name__c, Employee_State__c,
                   Employee_Street__c, Employee_Zip__c, Factor__c, Gross_Wages_Paid__c,
                   Net_Wages_Paid__c, Period_Covered_by_Adjustment__c, Total_Wage_Assessment__c,
                   Has_Matching_Account__c, Unique_Key__c, Direct_Pay__c
            FROM Import__c
            WHERE Case_Management__c = :caseId AND Unique_Key__c =:uniqueKey AND Job_Sequence__c = NULL
            ORDER BY Name
        ]);
    }

    // --- Execute Method ---
    global void execute(Database.BatchableContext BC, List<sObject> scope) {
        if (stopBatch) {
            System.debug('Batch stop flag is set. Skipping remaining records.');
            return;
        }
        batchRunCount ++;
        List<Import__c> duplicateEmployees     = new List<Import__c>();
        List<Account> accsToUpload             = new List<Account>();
        Map<String, recordWrapper> accPayeeMap = new Map<String, recordWrapper>();
        List<Payee__c> createPayeeList         = new List<Payee__c>();
        List<Case_Role__c> createCaseRoleList  = new List<Case_Role__c>();

        // Fetch Case Issues
        List<DIR_Violation__c> caseIssueList = [
            SELECT Id, Name, Wage_Balance_Due__c, Amount_Reserved__c, Amount_Utilized_from_Payee__c,
                   Violation_Type__r.Violation_Type_Name__c, Violation_Type__r.Violation_Type__c, Post_Judgment_Interest_for_Wages__c, Post_Citation_Interest_for_Wages__c
            FROM DIR_Violation__c
            WHERE Id IN :caseIssueIds
        ];

        Id personAccRTID = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Person Account').getRecordTypeId();

        try {
            // Build Account and Wrapper List
            for (sObject line : scope) {
                Import__c record = (Import__c) line;

                NumberofImportRecordsInserted++;
                if (record.Has_Matching_Account__c == true) {
                    duplicateEmployees.add(record);
                    continue;
                }

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
            errorMessages.add('Error building records: ' + e.getMessage());
        }

        Savepoint sp = Database.setSavepoint(); // Set rollback point at start

        try {

            // ---- Check Duplicate Records ----
            if (!duplicateEmployees.isEmpty()) {
                System.debug('Duplicate Employees List: ' + duplicateEmployees.size()
                             + ' ' + duplicateEmployees);
                shouldRunSecondBatch = true;
            }

            // --- Insert Accounts ---
            List<Database.SaveResult> insertAccountResults = Database.insert(accsToUpload, false);
            for (Integer i = 0; i < insertAccountResults.size(); i++) {
                if (insertAccountResults[i].isSuccess()) {
                    insertedAccounts++;
                    accDeleteIds.add(insertAccountResults[i].getId());
                } else {
                    for (Database.Error err : insertAccountResults[i].getErrors()) {
                        setWrapperInfo(accsToUpload[i], 'Account : ' + err.getMessage());
                    }
                    stopBatch = true;
                }
            }

            System.debug(insertedAccounts + ' Account records inserted.');

            // --- Insert Case Roles ---
            for (Account acc : accsToUpload) {
                createCaseRoleList.add(new Case_Role__c(
                    Account_Name__c = acc.Name,
                    Case__c         = caseId,
                    Role__c         = 'Payee - Employee',
                    Entity__c       = acc.Id
                ));
            }

            List<Database.SaveResult> insertCaseRoleResults = Database.insert(createCaseRoleList, false);
            for (Integer i = 0; i < insertCaseRoleResults.size(); i++) {
                if (insertCaseRoleResults[i].isSuccess()) {
                    caseRoleDeleteIds.add(insertCaseRoleResults[i].getId());
                    insertedCaseRoles++;
                } else {
                    Database.Error error = insertCaseRoleResults[i].getErrors()[0];
                    setWrapperInfo(accsToUpload[i], 'Case Role : ' + error.getMessage());
                    stopBatch = true;
                }
            }
            System.debug(insertedCaseRoles + ' Case Role records inserted.');

            // Create Payees
            Set<Id> caseRoleIds = new Set<Id>();
            for (Case_Role__c role : createCaseRoleList) {
                caseRoleIds.add(role.Id);
            }
            // Re-query Case Roles to get related Account fields (e.g., AccountMatch__c)
            List<Case_Role__c> caseRoleList = [
                SELECT Id, Name, Entity__c, Entity__r.ShippingPostalCode,
                       Entity__r.ShippingState, Entity__r.ShippingCity,
                       Entity__r.ShippingStreet, Entity__r.LastName,
                       Entity__r.FirstName, Entity__r.AccountMatch__c
                FROM Case_Role__c
                WHERE Id IN :caseRoleIds
            ];


            for (Case_Role__c cr : caseRoleList) {
                recordWrapper accP = accPayeeMap.get(cr.Entity__r.AccountMatch__c);

                System.debug('recordWrapper accP :' + accP);

                if (accP != null) {

                    Decimal totalCitation = 0;
                    Decimal totalJudgment = 0;

                    Payee__c payee = new Payee__c();
                    payee.PeriodCovered__c = accP.periodCovered;
                    
                    // Assign Payee fields from wrapper
                    if (!String.isEmpty(accP.wageAsssesment)) payee.WageAssessment__c          = toDecimal(accP.wageAsssesment);
                    if (!String.isEmpty(accP.grossWages)) payee.GrossWages__c             = toDecimal(accP.grossWages);
                    if (!String.isEmpty(accP.disabilityInsurance)) payee.DisabilityInsurance__c = toDecimal(accP.disabilityInsurance);
                    if (!String.isEmpty(accP.socialSecurity)) payee.SocialSecurity__c         = toDecimal(accP.socialSecurity);
                    if (!String.isEmpty(accP.medicare)) payee.Medicare__c                 = toDecimal(accP.medicare);
                    if (!String.isEmpty(accP.stateWitholding)) payee.StateWithholding__c       = toDecimal(accP.stateWitholding);
                    if (!String.isEmpty(accP.federalWitholding)) payee.FederalWithholding__c     = toDecimal(accP.federalWitholding);
                    if (!String.isEmpty(accP.totalDeductions)) payee.TotalDeductions__c      = toDecimal(accP.totalDeductions);
                    if (!String.isEmpty(accP.netWages)) payee.NetWages__c                 = toDecimal(accP.netWages);
                    if (!String.isEmpty(accP.factor)) payee.Factor__c                   = toDecimal(accP.factor);
                    if (!String.isEmpty(accP.directPay)) payee.Direct_Pay__c           = accP.directPay;

                    payee.Case_Management__c = caseId;
                    payee.Case_Role__c       = cr.Id;
                    payee.Payee_Type__c      = 'Employee';
                    payee.Status__c          = 'Unverified';


                    // build JSON and then update the field 'Payee_Association_JSON__c'

                    List<PayeeAssociation> caseIssueJsonList = new List<PayeeAssociation>();
                    for (DIR_Violation__c ci : caseIssueList) {
                        PayeeAssociation associationData = new PayeeAssociation();
                        associationData.caseIssueId           = ci.Id;
                        associationData.caseIssueName         = ci.Name;
                        associationData.netWages              = String.isEmpty(accP.netWages) ? 0 : toDecimal(accP.netWages);
                        associationData.totalWageAssessment   = String.isEmpty(accP.wageAsssesment) ? 0 : toDecimal(accP.wageAsssesment);
                        associationData.deductionsTotal       = String.isEmpty(accP.totalDeductions) ? 0 : toDecimal(accP.totalDeductions);
                        associationData.factor                = String.isEmpty(accP.factor) ? 0 : toDecimal(accP.factor);
                        associationData.citationForm          = ci.Violation_Type__r.Violation_Type__c;
                        associationData.violationTypeName     = ci.Violation_Type__r.Violation_Type_Name__c;

                        Decimal NWBreakdown   = String.isEmpty(accP.netWages) ? 0 : toDecimal(accP.netWages) / caseIssueList.Size();
                        Decimal TNWBreakdown  = String.isEmpty(accP.wageAsssesment) ? 0 : toDecimal(accP.wageAsssesment) / caseIssueList.Size();
                        Decimal DTBreakdown   = String.isEmpty(accP.totalDeductions) ? 0 : toDecimal(accP.totalDeductions) / caseIssueList.Size();
                        Decimal CIBreakdown   = NWBreakdown; // Assuming CIBreakdown is NWBreakdown

                        associationData.caseIssueBreakdown           = CIBreakdown.setScale(6, RoundingMode.HALF_UP);
                        associationData.netWagesBreakdown            = NWBreakdown.setScale(6, RoundingMode.HALF_UP);
                        associationData.totalWageAssessmentBreakdown = TNWBreakdown.setScale(6, RoundingMode.HALF_UP);
                        associationData.deductionsTotalBreakdown     = DTBreakdown.setScale(6, RoundingMode.HALF_UP);
                        
                        Decimal calculateAmountUtilized = ci.Wage_Balance_Due__c * (String.isEmpty(accP.factor) ? 0 : toDecimal(accP.factor) / 100);
                        if(importType == 'Form_40_Partial'){
            				calculateAmountUtilized = ci.Amount_Reserved__c * (String.isEmpty(accP.factor) ? 0 : toDecimal(accP.factor) / 100);
        				}
                        else if (importType == 'Corrective_Form_40'){
            				calculateAmountUtilized = ci.Amount_Utilized_from_Payee__c * (String.isEmpty(accP.factor) ? 0 : toDecimal(accP.factor) / 100);                            
       					}
                        Decimal amountUtilized = calculateAmountUtilized.setScale(6, RoundingMode.HALF_UP);
                        

                        Decimal percentageshare = String.isEmpty(accP.factor) ? 0 : toDecimal(accP.factor)/100;
                        Decimal pcinterestShare = (ci.Post_Citation_Interest_for_Wages__c != null ? ci.Post_Citation_Interest_for_Wages__c : 0) * percentageshare;
                        Decimal pjinterestShare = (ci.Post_Judgment_Interest_for_Wages__c != null ? ci.Post_Judgment_Interest_for_Wages__c : 0) * percentageshare;

                        System.Debug('Interest Calculated pc '+pcinterestShare);
                        System.Debug('Interest Calculated pj '+pjinterestShare);

                        Decimal pcinterestShareRounded = pcinterestShare.setScale(2, RoundingMode.HALF_UP);
                        Decimal pjinterestShareRounded = pjinterestShare.setScale(2, RoundingMode.HALF_UP);

                        System.Debug('pcInterest After Rounded '+pcinterestShareRounded);
                        System.Debug('pjInterest After Rounded '+pjinterestShareRounded);

                        totalCitation += pcinterestShareRounded;
                        totalJudgment += pjinterestShareRounded;

                        caseIssueJsonList.add(associationData);

                        // Accumulate Amount Utilized per Case Issue
                        Decimal TotalAmount = 0;
                        if(caseIssueAmountUtilizedFromPayee.ContainsKey(associationData.caseIssueId)){
                            TotalAmount = caseIssueAmountUtilizedFromPayee.get(associationData.caseIssueId) + amountUtilized;
                            caseIssueAmountUtilizedFromPayee.put(associationData.caseIssueId, TotalAmount);
                        }
                        else{
                            caseIssueAmountUtilizedFromPayee.put(associationData.caseIssueId, amountUtilized);
                        }
                    }

                    payee.Payee_Association_JSON__c = JSON.serialize(caseIssueJsonList);
                    if(!isLinkedToAllCaseIssue){
                    payee.Post_Citation_Interest_for_Wages__c = totalCitation;
                    payee.Post_Judgment_Interest_for_Wages__c = totalJudgment;
                    }
                    createPayeeList.add(payee);

                } else {
                    // This block captures records if the Case Role lookup failed after successful Account insertion
                    recordWrapper noMatchAccount = new recordWrapper();
                    noMatchAccount.errorMessage         = 'Could not find match on: ' + cr.Entity__r.AccountMatch__c;
                    noMatchAccount.firstname            = cr.Entity__r.FirstName;
                    noMatchAccount.lastName             = cr.Entity__r.LastName;
                    noMatchAccount.shippingStreet       = cr.Entity__r.ShippingStreet;
                    noMatchAccount.shippingCity         = cr.Entity__r.ShippingCity;
                    noMatchAccount.shippingState        = cr.Entity__r.ShippingState;
                    noMatchAccount.shippingPostalCode   = cr.Entity__r.ShippingPostalCode;
                    noMatchAccount.caseManagment        = caseId;

                    failedDMLRecords.add(noMatchAccount);
                }
            }

            // Insert Payees
            List<Database.SaveResult> insertPayeeResults = Database.insert(createPayeeList, false);
            for (Integer i = 0; i < insertPayeeResults.size(); i++) {
                if (insertPayeeResults[i].isSuccess()) {
                    payeeDeleteIds.add(insertPayeeResults[i].getId());
                    insertedPayees++;
                    checkPayeeIds.add(insertPayeeResults[i].getId()); // Use getId() for the new Payee Id
                } else {
                    Database.Error error = insertPayeeResults[i].getErrors()[0];
                    System.debug('Insert Payee Record Is failed: ' + error.getMessage());
                    // Note: This relies on a match between createPayeeList and accsToUpload, which is complex
                    // A safer approach for the wrapper info would be mapping by the Account ID. 
                    // For now, retaining original logic, which uses the index `i` of the accsToUpload list.
                    setWrapperInfo(accsToUpload[i], 'Payee : ' + error.getMessage());
                    stopBatch = true;
                }
            }

            System.debug(insertedPayees + ' Payess records Inserted.');

            // to Stop the Batch
            If(stopBatch == true){
                Database.rollback(sp);
            }

        } catch (Exception e) {
            stopBatch = true;
            Database.rollback(sp);
            errorMessages.add('Rollback performed due to error: ' + e.getMessage());
            System.debug('Batch chunk rolled back due to error: ' + e.getMessage());
        }
    }

    // --- Finish Method ---
    global void finish(Database.BatchableContext BC) {

        If(StopBatch == true){
            insertedAccounts   = (batchRunCount - 1) * 200;
            insertedCaseRoles  = (batchRunCount - 1) * 200;
            insertedPayees     = (batchRunCount - 1) * 200;
        }

        String insertRecordDeletion = '';
        // --- Prepare Case Issue Updates ---
        List<DIR_Violation__c> caseIssueUpdate = new List<DIR_Violation__c>();

        for (Id caseIssue : caseIssueAmountUtilizedFromPayee.keySet()) {
            DIR_Violation__c caseIssueSingle = new DIR_Violation__c();
            caseIssueSingle.Id = caseIssue;
            Decimal amountUtilized = caseIssueAmountUtilizedFromPayee.get(caseIssue);
            if (amountUtilized != null) {
                caseIssueSingle.Amount_Utilized_from_Payee__c = amountUtilized.setScale(2, RoundingMode.HALF_UP);
            }

            caseIssueUpdate.add(caseIssueSingle);
        }


        // --- Update Case Issues ---
        if (shouldRunSecondBatch == false && stopBatch == false) {
            List<Database.SaveResult> updateCaseIssueResults = Database.update(caseIssueUpdate, false);
            for (Integer i = 0; i < updateCaseIssueResults.size(); i++) {
                if (updateCaseIssueResults[i].isSuccess()) {
                    updatedCaseIssues++;
                } else {
                    Database.Error error = updateCaseIssueResults[i].getErrors()[0];
                    System.debug('Case Issue update failed: ' + error.getMessage());
                }
            }
            System.debug(updatedCaseIssues + ' Case Issue records updated.');
        }

        // --- Update Case Management (DIR_Case__c) ---
        caseJson cj = new caseJson();
        cj.Last_Upload_Import_type = importType;
        cj.Last_Modified_By        = UserInfo.getName();
        cj.UserId                  = UserInfo.getUserId();
        cj.Last_Modified_Date      = System.now().format('MM/dd/yyyy h:mm a', UserInfo.getTimeZone().getId());
        
        
        DIR_Case__c caseManagement = new DIR_Case__c(
            Id = caseId,
            Import_Form_40_Details__c = JSON.serialize(cj)
        );
        
		caseManagement.Need_Payee_Batch_Run__c = isLinkedToAllCaseIssue ? false : true;
        
        List<Database.SaveResult> updateCaseResults = Database.update(
            new List<DIR_Case__c>{ CaseManagement },
            false
        );

        for (Integer i = 0; i < updateCaseResults.size(); i++) {
            if (updateCaseResults[i].isSuccess()) {
                updatedCases++;
            } else {
                Database.Error error = updateCaseResults[i].getErrors()[0];
                System.debug('Case update failed: ' + error.getMessage());
            }
        }
        System.debug(updatedCases + ' Case record updated.');

        System.debug('Batch job finished for Case Id: ' + caseId);

        List<DIR_Case__c> DC = [
            SELECT Case_Number__c FROM DIR_Case__c
            WHERE Id = :caseId LIMIT 1
        ];

        // The current user who started the batch job
        String userEmail = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Email;

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[]{ userEmail });
        mail.setSubject('Apex Batch Job Completed - Import Record Summary');

        List<Import__c> importsToDelete = new List<Import__c>();
        String errorMessage = '';
        String nonDMLErrorMessages = '';
        String mailMessage;

        // Query all Import__c records for this Case to check against failedDMLRecords
        List<Import__c> csvRecords = [
            SELECT Name, Case_Management__c, Deductions_Federal_Withholding__c,
                   Deductions_Medicare__c, Deductions_Social_Security__c,
                   Deductions_State_Disability_Insurance__c, Deductions_State_Withholding__c,
                   Deductions_Total__c, Employee_City__c, Employee_First_Name__c,
                   Employee_Last_Name__c, Employee_State__c, Employee_Street__c,
                   Employee_Zip__c, Factor__c, Gross_Wages_Paid__c, Net_Wages_Paid__c,
                   Period_Covered_by_Adjustment__c, Total_Wage_Assessment__c, Unique_Key__c // Added Unique_Key__c for better matching if needed
            FROM Import__c
            WHERE Case_Management__c = :caseId
        ];

        // --- Prepare Error Table (HTML) ---
        String errorTable = '';
        Boolean hasErrors = false;

        // Loop through Import records and check against failed DML records
        for (Import__c importRecord : csvRecords) {
            for (recordWrapper failedDMLRecord : failedDMLRecords) {
                if (
                    importRecord.Employee_First_Name__c == failedDMLRecord.firstname &&
                    importRecord.Employee_Last_Name__c == failedDMLRecord.lastName &&
                    importRecord.Employee_Street__c == failedDMLRecord.shippingStreet &&
                    importRecord.Employee_State__c == failedDMLRecord.shippingState &&
                    importRecord.Employee_City__c == failedDMLRecord.shippingCity &&
                    importRecord.Employee_Zip__c == failedDMLRecord.shippingPostalCode &&
                    importRecord.Case_Management__c == failedDMLRecord.caseManagment
                ) {
                    if (!hasErrors) {
                        // Start the table with header row
                        errorTable =
                            '<h3 style="color:red;"> An error occurred while processing the following record(s):</h3>' +
                            '<table border="1" cellpadding="5" cellspacing="0" ' +
                            'style="border-collapse:collapse; width:100%; font-family:Arial, sans-serif; font-size:13px; background-color:#FFEEEE;">' +
                            '<tr style="background-color:#F5B7B1; font-weight:bold;">' +
                            '<th>Employee First Name</th>' +
                            '<th>Employee Last Name</th>' +
                            '<th>Employee Street</th>' +
                            '<th>Employee City</th>' +
                            '<th>Employee State</th>' +
                            '<th>Employee Zip</th>' +
                            '<th>Error</th>' +
                            '</tr>';
                        hasErrors = true;
                    }

                    // Add a table row for each failed record
                    errorTable +=
                        '<tr>' +
                            '<td>' + escapeHtml(importRecord.Employee_First_Name__c) + '</td>' +
                            '<td>' + escapeHtml(importRecord.Employee_Last_Name__c) + '</td>' +
                            '<td>' + escapeHtml(importRecord.Employee_Street__c) + '</td>' +
                            '<td>' + escapeHtml(importRecord.Employee_City__c) + '</td>' +
                            '<td>' + escapeHtml(importRecord.Employee_State__c) + '</td>' +
                            '<td>' + escapeHtml(importRecord.Employee_Zip__c) + '</td>' +
                            '<td>' + escapeHtml(failedDMLRecord.errorMessage) + '</td>' +
                        '</tr>';
                    break;
                }
            }
            // Add all Import records associated with this case to the deletion list
            importsToDelete.add(importRecord);
        }

        // Close the table if any errors exist
        if (hasErrors) {
            errorTable += '</table>';
            errorMessage = errorTable;
        }


        Map<Integer, String> sendEmailToDuplicate = new Map<Integer, String>();
        Integer insertRecord = 0; // Key for insert summary
        String insertRecords = '';
				sendEmailToDuplicate.put(3, '<tr><td>🔄 <b>Number of Uploaded Records:</b></td><td>' + NumberofImportRecordsInserted + '</td></tr>' +
                '<tr><td>✅ <b>Accounts Inserted:</b></td><td>0</td></tr>' +
                '<tr><td>✅ <b>Case Roles Inserted:</b></td><td>0</td></tr>' +
                '<tr><td>✅ <b>Payees Created:</b></td><td>0</td></tr>');
        
        
        if (stopBatch == false) {
            insertRecords = '<tr><td>🔄 <b>Number of Uploaded Records:</b></td><td>' + NumberofImportRecordsInserted + '</td></tr>' +
                '<tr><td>✅ <b>Accounts Inserted:</b></td><td>' + insertedAccounts + '</td></tr>' +
                '<tr><td>✅ <b>Case Roles Inserted:</b></td><td>' + insertedCaseRoles + '</td></tr>' +
                '<tr><td>✅ <b>Payees Created:</b></td><td>' + insertedPayees + '</td></tr>';

        } else {
            insertRecords = sendEmailToDuplicate.get(3);      
        }


        List<String> noInsertMsgs = new List<String>();
        if (insertedAccounts == 0 || stopBatch == true) noInsertMsgs.add('⚠️ No Account records were created.');
        if (insertedCaseRoles == 0 || stopBatch == true) noInsertMsgs.add('⚠️ No Case Role records were created.');
        if (insertedPayees == 0 || stopBatch == true) noInsertMsgs.add('⚠️ No Payee records were created.');

        sendEmailToDuplicate.put(insertRecord, insertRecords);

        Integer summaryOfRecord;
        String summaryOfRecords = '';

        if (!noInsertMsgs.isEmpty()) {
            for (String msg : noInsertMsgs) {
                summaryOfRecords += '<p style="margin:2px 0;">' + msg + '</p>';
            }
            summaryOfRecords += '</div><br/>';
            summaryOfRecord = 1;
        }

        sendEmailToDuplicate.put(summaryOfRecord, summaryOfRecords);

        // --- Add all Error Messages in RED color ---
        String allErrorMessages = '';
        Integer errorOfRecord;
        
         // Format non-DML errors for email (Re-run for final accumulation)
        if (errorMessages != null) {
            for (String message : errorMessages) {
                nonDMLErrorMessages += message + '\n';
            }
        }

        if (String.isNotBlank(mailMessage)) { // mailMessage not set in this scope
            allErrorMessages += mailMessage + '\n';
            errorOfRecord = 2;
        }
        if (String.isNotBlank(nonDMLErrorMessages)) {
            allErrorMessages += nonDMLErrorMessages + '\n';
            errorOfRecord = 2;
        }
        if (String.isNotBlank(errorMessage)) {
            allErrorMessages += errorMessage;
            errorOfRecord = 2;
        }

        sendEmailToDuplicate.put(errorOfRecord, allErrorMessages);

        // --- Handle Second Batch for Duplicate Payees ---
        if (shouldRunSecondBatch && stopBatch == false) {
            ProcessDuplicatePayeesBatch processor = new ProcessDuplicatePayeesBatch(
                caseId,
                importType,
                caseIssueIds,
                caseIssueAmountUtilizedFromPayee,
                sendEmailToDuplicate,
                checkPayeeIds,
                uniqueKey,
                accDeleteIds,
                caseRoleDeleteIds,
                payeeDeleteIds,
                isLinkedToAllCaseIssue

            );
            Database.executeBatch(processor, 200);
        }

        // Safely delete processed Import__c records
        if (!importsToDelete.isEmpty() && (shouldRunSecondBatch == false || stopBatch == true)) {
            try {
                // If stopBatch is false AND shouldRunSecondBatch is false: clean up success
                // If stopBatch is true: clean up all, as the main DML was rolled back
                delete importsToDelete;
            } catch (DmlException e) {
                System.debug('Error deleting Import__c records: ' + e.getMessage());
                errorMessages.add('Error deleting Import__c records: ' + e.getMessage());
            }
        }

        // --- Start HTML Email Body Construction ---
        String caseLink;
        if (DC != null && !DC.isEmpty() && DC[0].Id != null) {
            String baseUrl = System.Url.getOrgDomainUrl().toExternalForm();
            String caseUrl = baseUrl + '/lightning/r/DIR_Case__c/' + DC[0].Id + '/view';
            String caseNumber = escapeHtml(DC[0].Case_Number__c);
            caseLink = '<a href="' + caseUrl + '" target="_blank">' + caseNumber + '</a>';
        } else {
            caseLink = (DC != null && !DC.isEmpty() ? escapeHtml(DC[0].Case_Number__c) : 'N/A');
        }


        String htmlBody = '';
        if(stopBatch && batchRunCount == 1){
            htmlBody += '<h3 style="color:#27AE60;">The transaction has been fully reverted without any errors.</h3>';
        }
        htmlBody += '<html>' +
            '<head><meta charset="UTF-8"></head>' +
            '<body style="font-family:Arial, sans-serif; font-size:14px; margin:0; padding:0;">';

        // Add a dynamic header depending on stopBatch
        if (stopBatch == true) {
            htmlBody +=
                '<h3 style="color:#C0392B;">⚠️ The batch process was stopped before completion.</h3>';
        } else {
            htmlBody +=
                '<h4 style="color:#2E86C1;"> The bulk payee creation process has been completed successfully.</h4>';
        }

        htmlBody +=
            '<h2 style="color:#2E86C1;">Batch Process Summary</h2>' +
            '<table border="0" cellpadding="5" cellspacing="0" style="border-collapse:collapse;">' +
            '<tr><td><b>Case Management:</b></td><td>' +
            (DC != null && !DC.isEmpty() ? caseLink : 'N/A') +
            '</td></tr>' +
            '<tr><td><b>Import Type:</b></td><td>' + escapeHtml(importType) + '</td></tr>' +
            '</table><br/>' +
            '<div style="border:2px solid #0176D3; padding:10px; display:inline-block; border-radius:6px;">' +
            '<table border="0" cellpadding="5" cellspacing="0" style="border-collapse:collapse;">';
        insertRecordDeletion += htmlBody; // Start deletion body accumulation

        htmlBody += insertRecords;

        insertRecordDeletion +=
            '<tr><td>🔄 <b>Number of Uploaded Records:</b></td><td>' + NumberofImportRecordsInserted + '</td></tr>' +
            '<tr><td>✅ <b>Accounts Inserted:</b></td><td>' + insertedAccounts + '</td></tr>' +
            '<tr><td>✅ <b>Case Roles Inserted:</b></td><td>' + insertedCaseRoles + '</td></tr>' +
            '<tr><td>✅ <b>Payees Created:</b></td><td>' + insertedPayees + '</td></tr>';

        htmlBody +=
            '</table>' +
            '</div><br/>';

        insertRecordDeletion += '</table>' + // Close inner table for deletion email
            '</div><br/>'; // Close inner div for deletion email

        if (!noInsertMsgs.isEmpty()) {
            htmlBody += '<h4 style="color:#E67E22; margin-bottom: 5px;">⚠️ Summary Notice:</h4>';
            htmlBody += '<div style="border: 1px solid #FFD700; padding:10px; background-color:#FFFACD;">';
            for (String msg : noInsertMsgs) {
                htmlBody += '<p style="margin:2px 0;">' + msg + '</p>';
            }
            htmlBody += '</div><br/>';
        }

        if (String.isNotBlank(allErrorMessages)) {
            // Append error messages to the email body for the failed transaction deletion batch
            insertRecordDeletion +=
                '<h3 style="color:red; margin-top:20px; margin-bottom: 5px;">🚨 Errors/Warnings</h3>' +
                '<div style="color:red; border: 1px solid red; padding:10px; background-color:#FFEEEE;">' +
                '<pre style="font-family:Arial, sans-serif; white-space: pre-wrap; margin: 0;">' +
                allErrorMessages +
                '</pre>' +
                '</div>';
            // Append error messages to the standard email body
            htmlBody +=
                '<h3 style="color:red; margin-top:20px; margin-bottom: 5px;">🚨 Errors/Warnings</h3>' +
                '<div style="color:red; border: 1px solid red; padding:10px; background-color:#FFEEEE;">' +
                '<pre style="font-family:Arial, sans-serif; white-space: pre-wrap; margin: 0;">' +
                allErrorMessages +
                '</pre>' +
                '</div>';
        } else {
            htmlBody += '<h4 style="color:#27AE60;">✅ No errors were encountered.</h4>';
        }

        if(StopBatch == false){
            htmlBody +=
                '<hr/><p><b>Executed by:</b> ' + UserInfo.getName() + '<br/>' +
                '<b>DateTime:</b> ' + System.now().format('MM/dd/yyyy h:mm a', UserInfo.getTimeZone().getId()) +
                '</p>';
        }

        htmlBody += '</body></html>';

        // --- End HTML Email Body Construction ---
        mail.setHtmlBody(htmlBody);
        mail.setCharset('UTF-8');

        // --- Execute Data Deletion Batch on Stop (if more than 1 batch ran) ---
        if(stopBatch == true && batchRunCount > 1){
            Database.executeBatch(new DeletePayeeBatch(accDeleteIds, caseRoleDeleteIds, payeeDeleteIds, htmlBody, insertRecordDeletion), 200);
        }

        if ((shouldRunSecondBatch == false && stopBatch == false) || (batchRunCount == 1 && stopBatch == true && shouldRunSecondBatch == false)) {
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
            
        }
        If(stopBatch == false && isLinkedToAllCaseIssue == false){
            Set<Id> setOfCaseId = new Set<Id>();
            setOfCaseId.add(caseId);
            IC_RollUpPayeeBatch rollUpPyaee = new IC_RollUpPayeeBatch(setOfCaseId);
            Database.executeBatch(rollUpPyaee, 200);
        }
        
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        
        if (results != null && results.size() > 0) {
            if (results[0].isSuccess()) {
                System.debug('Email sent successfully.');
            } else {
                System.debug('Email failed: ' + results[0].getErrors()[0].getMessage());
            }
        }

    }


    // --- Helper Methods ---
    global void setWrapperInfo(Account dummyAccount, String errorMessage) {
        recordWrapper failedInsert = new recordWrapper();
        failedInsert.errorMessage       = errorMessage;
        failedInsert.firstname          = dummyAccount.FirstName;
        failedInsert.lastName           = dummyAccount.LastName;
        failedInsert.shippingStreet     = dummyAccount.ShippingStreet;
        failedInsert.shippingCity       = dummyAccount.ShippingCity;
        failedInsert.shippingState      = dummyAccount.ShippingState;
        failedInsert.shippingPostalCode = dummyAccount.ShippingPostalCode;
        failedInsert.caseManagment      = caseId;
        failedDMLRecords.add(failedInsert);
    }

    global Decimal toDecimal(String s) {
        // Ensures empty strings are handled (will throw NullPointerException otherwise if not checked first)
        if (String.isBlank(s)) return null;
        return Decimal.valueOf(String.valueOf(s));
    }

    // Safe HTML escaping helper
    public static String escapeHtml(String input) {
        if (input == null) return '';
        String output = input;
        output = output.replace('&', '&amp;');
        output = output.replace('<', '&lt;');
        output = output.replace('>', '&gt;');
        output = output.replace('"', '&quot;');
        output = output.replace('\'', '&#39;');
        return output;
    }

    // --- Inner Wrapper Classes ---
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
    public class caseJson {
        public String UserId;
        public String Last_Modified_By;
        public String Last_Modified_Date;
        public String Last_Upload_Import_type;
    }
}