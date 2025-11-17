/*
* Global Batchable class to process imported records, create Accounts, Case Roles, and Payees,
* handle DML errors, update Case Issues and Case, and send an email summary.
*/
global class ProcessImportRecordsRedesigned implements Database.Batchable<SObject>, Database.Stateful {
    
    // --- Global Variables ---
    global String caseId { get; set; }
    global List<String> errorMessages { get; set; }
    global String importType { get; set; }
    global List<recordWrapper> failedDMLRecords { get; set; }
    global Set<Id> caseIssueIds { get; set; }
    global string uniqueKey { get; set; }
    global boolean batchError = false;
    global String creationErrorTable = ''; 
    global String updateerrorTable = '';    
    public Boolean isLinkedToAllCaseIssue { get; set; }
    public Boolean duplicatePayees = false;
    
    // Counters for DML summary (Stateful)
    global Integer insertedAccounts     = 0;
    global Integer insertedCaseRoles    = 0;
    global Integer insertedPayees       = 0;
    global Integer updatedCaseIssues    = 0;
    global Integer updatedCases         = 0;
    global Integer successCountPayee = 0;
    global Integer failureCountPayee = 0;
    global Integer NumberofImportRecordsInserted = 0;
    global Integer insertPayeeFiles = 0;
    
    // Update the Case Issue Records
    Map<Id, Decimal> caseIssueAmountUtilizedFromPayee = new Map<Id, Decimal>();
        
    // To Store account, case Role, Payee Ids and imports Record for Delete
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
        System.debug('Total Case Issue Count : ' + caseIssueCount);
        System.debug('Select Case Issue Count : ' + caseIssueIds.size());
        System.debug('The global Field isLinkedToAllCaseIssue Value : '+ isLinkedToAllCaseIssue);
        
        
        return Database.getQueryLocator([
            SELECT Name, Case_Management__c, Deductions_Total__c, Employee_City__c,
            Employee_First_Name__c, Employee_Last_Name__c, Employee_State__c,
            Employee_Street__c, Employee_Zip__c, Factor__c, Gross_Wages_Paid__c,
            Net_Wages_Paid__c, Period_Covered_by_Adjustment__c, Total_Wage_Assessment__c,
            Has_Matching_Account__c, Unique_Key__c, Direct_Pay__c
            FROM Import__c
            WHERE Case_Management__c = :caseId AND Unique_Key__c =:uniqueKey AND Job_Sequence__c = NULL
            ORDER BY Has_Matching_Account__c DESC, Employee_First_Name__c ASC, Employee_Last_Name__c ASC
        ]);
    }
    
    // --- Execute Method ---
    global void execute(Database.BatchableContext BC, List<sObject> scope) {
        if (batchError) {
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
                    duplicatePayees = true;
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
            batchError = true;
            errorMessages.add('Error building records: ' + e.getMessage());
        }
        
        Savepoint sp = Database.setSavepoint(); // Set rollback point at start
        
        try {
            
            // ---- Check Duplicate Records ----
            if (!duplicateEmployees.isEmpty()) {
                System.debug('Duplicate Employees List: ' + duplicateEmployees.size()
                             + ' ' + duplicateEmployees);
                
                // 1. Call the static executeLogic method directly and store the returned result object.
                ProcessDuplicatePayeesService.PayeeProcessingResult processorResult = 
                    ProcessDuplicatePayeesService.executeLogic(
                        duplicateEmployees,
                        caseIssueIds,
                        caseId
                    );
                
                // 2. Retrieve the results directly from the result object properties.
                List<Payee__c> payeesToUpdate = processorResult.updatePayeeRecords;
                Map<Id, Import__c> payeeToImportMap = processorResult.payeeToImportMap;
                List<Payee__c> oldPayeeRecords = processorResult.oldPayeeRecords;
                
                
                // 3. Perform DML operation with the results
                if (!payeesToUpdate.isEmpty()) {
                    try {
                        System.debug('payeesToUpdate : '+payeesToUpdate);
                        Database.SaveResult[] results = Database.update(payeesToUpdate, false);
                        
                        for (Integer i = 0; i < results.size(); i++) {
                            Payee__c payee = payeesToUpdate[i];
                            
                            if (results[i].isSuccess()) {
                                successCountPayee++;
                                Import__c failedImport = payeeToImportMap.get(payee.Id); // Use the retrieved map
                            } else {
                                batchError = true;
                                failureCountPayee++;
                                System.debug('>>> [Batch Failed for Payee Update] Payee Update: ' + failureCountPayee);
                                
                                Database.Error error = results[i].getErrors()[0];
                                String ErrorPayeeRecord = 'Payee : ' + error.getMessage();
                                
                                // Use the retrieved map here as well
                                Import__c failedImport = payeeToImportMap.get(payee.Id); 
                                
                                System.debug('>>> [Batch Failed Payeee Update Record Import] Payee Update: ' + failedImport);
                                System.debug('failedImport :' + failedImport);
                                
                                updateerrorTable +=
                                    '<tr>' +
                                    '<td>' + escapeHtml(failedImport.Employee_First_Name__c) + '</td>' +
                                    '<td>' + escapeHtml(failedImport.Employee_Last_Name__c) + '</td>' +
                                    '<td>' + escapeHtml(failedImport.Employee_Street__c) + '</td>' +
                                    '<td>' + escapeHtml(failedImport.Employee_City__c) + '</td>' +
                                    '<td>' + escapeHtml(failedImport.Employee_State__c) + '</td>' +
                                    '<td>' + escapeHtml(failedImport.Employee_Zip__c) + '</td>' +
                                    '<td>' + escapeHtml(ErrorPayeeRecord) + '</td>' +
                                    '</tr>';
                            }
                        }
                        
                        if(batchError == false){
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
                                payeeRevertDataMap.put(Oldpayee.Id, details);
                            }
                            String serializedData = JSON.serialize(payeeRevertDataMap);
                            
                            ContentVersion cv = new ContentVersion();
                            cv.Title = 'PayeeRevertData'+uniqueKey+'BatchCount'+batchRunCount;
                            cv.PathOnClient = 'PayeeRevertData'+uniqueKey+'BatchCount'+batchRunCount+'.json';
                            cv.VersionData = Blob.valueOf(serializedData);
                            insert cv;
                            insertPayeeFiles ++;
                            
                        }
                    } catch (Exception e) {
                        batchError = true;
                        errorMessages.add('Error building payees Update records: ' + e.getMessage());
                        System.debug('### DML Error: ' + e.getMessage());
                    }
                }
                
                if (!processorResult.errorMessages.isEmpty()) {
                    batchError = true;
                    errorMessages.add('processorResult Errors on Payee Update: ' + processorResult.errorMessages);
                    System.debug('processorResult Errors on Payee Update: ' + processorResult.errorMessages);
                }
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
                    batchError = true;
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
                    batchError = true;
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
                        
                        
                        Decimal wageBalanceDue = (ci.Wage_Balance_Due__c != null) ? ci.Wage_Balance_Due__c : 0;
                        Decimal amountReserved = (ci.Amount_Reserved__c != null) ? ci.Amount_Reserved__c : 0;
                        Decimal amountUtilizedFromPayee = (ci.Amount_Utilized_from_Payee__c != null) ? ci.Amount_Utilized_from_Payee__c : 0;
                        
                        Decimal calculateAmountUtilized = 0;
                        
                        
                        if (importType == 'Form_40') {
                            calculateAmountUtilized = wageBalanceDue;
                        }
                        else if (importType == 'Form_40_Partial') {
                            calculateAmountUtilized = amountReserved;
                        }
                        else if (importType == 'Corrective_Form_40') {
                            calculateAmountUtilized = amountUtilizedFromPayee;
                        }
                        
                        caseIssueAmountUtilizedFromPayee.put(associationData.caseIssueId, calculateAmountUtilized);
                        /*
Decimal percentageshare = String.isEmpty(accP.factor) ? 0 : toDecimal(accP.factor)/100;
Decimal pcinterestShare = (ci.Post_Citation_Interest_for_Wages__c != null ? ci.Post_Citation_Interest_for_Wages__c : 0) * percentageshare;
Decimal pjinterestShare = (ci.Post_Judgment_Interest_for_Wages__c != null ? ci.Post_Judgment_Interest_for_Wages__c : 0) * percentageshare;

System.Debug('Interest Calculated pc '+pcinterestShare);
System.Debug('Interest Calculated pj '+pjinterestShare);

totalCitation += pcinterestShare;
totalJudgment += pjinterestShare;
*/
                        caseIssueJsonList.add(associationData);
                    }
                    
                    payee.Payee_Association_JSON__c = JSON.serialize(caseIssueJsonList);
                    /*
if(!isLinkedToAllCaseIssue){
payee.Post_Citation_Interest_for_Wages__c = totalCitation.setScale(2, RoundingMode.HALF_UP);
payee.Post_Judgment_Interest_for_Wages__c = totalJudgment.setScale(2, RoundingMode.HALF_UP);
}
*/
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
                    batchError = true;
                    failedDMLRecords.add(noMatchAccount);
                }
            }
            
            // Insert Payees
            List<Database.SaveResult> insertPayeeResults = Database.insert(createPayeeList, false);
            for (Integer i = 0; i < insertPayeeResults.size(); i++) {
                if (insertPayeeResults[i].isSuccess()) {
                    payeeDeleteIds.add(insertPayeeResults[i].getId());
                    insertedPayees++;
                } else {
                    Database.Error error = insertPayeeResults[i].getErrors()[0];
                    System.debug('Insert Payee Record Is failed: ' + error.getMessage());
                    setWrapperInfo(accsToUpload[i], 'Payee : ' + error.getMessage());
                    batchError = true;
                }
            }
            
            System.debug(insertedPayees + ' Payess records Inserted.');
            If(batchError == true){
                Database.rollback(sp);
            }
            
        } catch (Exception e) {
            batchError = true;
            Database.rollback(sp);
            errorMessages.add('Rollback performed due to error: ' + e.getMessage());
            System.debug('Batch chunk rolled back due to error: ' + e.getMessage());
        }
        
        If(batchError == true){
            Database.rollback(sp);
        }
    }
    
    // --- Finish Method ---
    global void finish(Database.BatchableContext BC) {
        
        String contentTitlePattern = 'PayeeRevertData' + uniqueKey + '%';
        
        
        Set<Id> contentDocumentIds = new Set<Id>();
        
        // Collect parent ContentDocument IDs
        for (ContentVersion cv : [
            SELECT Id, VersionData, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Title LIKE :contentTitlePattern
        ]) {
            if (cv.ContentDocumentId != null) {
                contentDocumentIds.add(cv.ContentDocumentId);
            }
        }
        
        List<ContentDocument> docsToDelete = [
            SELECT Id
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
        ];
                if (batchError == false) {
        List<Database.DeleteResult> deleteResults = Database.delete(docsToDelete, false);
        
        for (Integer i = 0; i < deleteResults.size(); i++) {
            if (deleteResults[i].isSuccess()) {
                System.debug('Deleted ContentDocument: ' + docsToDelete[i].Id);
            } else {
                Database.Error err = deleteResults[i].getErrors()[0];
                System.debug('Failed to delete ContentDocument ' + docsToDelete[i].Id + ' : ' + err.getMessage());
                errorMessages.add('Failed to delete ContentDocument ' + docsToDelete[i].Id + ' : ' + err.getMessage());
                batchError = true;
            }
        }
                }
        
        
        String nonDMLErrorMessages = '';
        
        Id jobId = BC.getJobId();
        
        // 2. Query the AsyncApexJob record to check ExtendedStatus
        AsyncApexJob job = [
            SELECT Id, ExtendedStatus, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];
        if (job.ExtendedStatus != null) {
            
            errorMessages.add('Apex Job : ' + job.ExtendedStatus + ' insert Payee Files Count : '+ insertPayeeFiles);
            batchError = true;
        }
        
        If(batchError == true){
            NumberofImportRecordsInserted = (batchRunCount - 1) * 200;
            insertedAccounts   = (batchRunCount - 1) * 200;
            insertedCaseRoles  = (batchRunCount - 1) * 200;
            insertedPayees     = (batchRunCount - 1) * 200;
            successCountPayee  = (batchRunCount - 1) * 200;
        }
        
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
        if (batchError == false) {
            List<Database.SaveResult> updateCaseIssueResults = Database.update(caseIssueUpdate, false);
            for (Integer i = 0; i < updateCaseIssueResults.size(); i++) {
                if (updateCaseIssueResults[i].isSuccess()) {
                    updatedCaseIssues++;
                } else {
                    Database.Error error = updateCaseIssueResults[i].getErrors()[0];
                    System.debug('Case Issue update failed: ' + error.getMessage());
                    batchError = true;
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
        cj.Status				   = 'Start';
        
        
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
                batchError = true;
            }
        }
        System.debug(updatedCases + ' Case record updated.');
        
        System.debug('Batch job finished for Case Id: ' + caseId);
        
        List<DIR_Case__c> DC = [
            SELECT Case_Number__c FROM DIR_Case__c
            WHERE Id = :caseId LIMIT 1
        ];
        
        
        // Query all Import__c records for this Case to check against failedDMLRecords
        List<Import__c> csvRecords = [
            SELECT Name, Case_Management__c, Deductions_Federal_Withholding__c,
            Deductions_Medicare__c, Deductions_Social_Security__c,
            Deductions_State_Disability_Insurance__c, Deductions_State_Withholding__c,
            Deductions_Total__c, Employee_City__c, Employee_First_Name__c,
            Employee_Last_Name__c, Employee_State__c, Employee_Street__c,
            Employee_Zip__c, Factor__c, Gross_Wages_Paid__c, Net_Wages_Paid__c,
            Period_Covered_by_Adjustment__c, Total_Wage_Assessment__c, Unique_Key__c
            FROM Import__c
            WHERE Case_Management__c = :caseId AND Unique_Key__c =:uniqueKey
        ];
        
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
                    
                    // Add a table row for each failed record
                    creationErrorTable +=
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
        }
        
        // Safely delete processed Import__c records when no error is occurred
        if (batchError == false && !csvRecords.isEmpty()) {
            try {
                delete csvRecords;
            } catch (DmlException e) {
                batchError = true;
                System.debug('Error deleting Import__c records: ' + e.getMessage());
                errorMessages.add('Error deleting Import__c records: ' + e.getMessage());
            }
        }
        String allErrorMessages = '';
        if (errorMessages != null) {
            for (String message : errorMessages) {
                nonDMLErrorMessages += message + '\n';
            }
        }
        
        if (String.isNotBlank(nonDMLErrorMessages)) {
            allErrorMessages += 'In ProcessImportRecordsRedesigned :' + nonDMLErrorMessages + '\n';
            System.debug('nonDMLErrorMessages : String.isNotBlank(nonDMLErrorMessages) : ' + allErrorMessages);
        }
        
        boolean apexBatchCall = false;
        List<BatchEmailService.WrapperError> failedRecords = new List<BatchEmailService.WrapperError>();
        if(batchRunCount == 1 || batchError == false){
            
            Map<String, Integer> processSummary = new Map<String, Integer>();
            Boolean reverted = false;
            BatchEmailService.sendBatchSummaryEmail(
                caseId,
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
                failedRecords
            );
            apexBatchCall = true;
        }
        
       
        if(batchError == true && batchRunCount > 1 && duplicatePayees == false){
            Database.executeBatch(
                new DeletePayeeBatch(
                    accDeleteIds,
                    caseRoleDeleteIds,
                    payeeDeleteIds,
                    caseId,
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
                    false,
                    'ProcessImportRecordsRedesigned',
                    failedRecords
                ),
                200
            );
            apexBatchCall = true;
        }
        
        if(duplicatePayees && batchRunCount > 1 && batchError == true){
            Database.executeBatch(
                new RevertPayeeBatch(
                    accDeleteIds,
                    caseRoleDeleteIds,
                    payeeDeleteIds,                    
                    caseId,
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
                    uniqueKey                
                ),
                1
            );  
            apexBatchCall = true;
        }
        if(!isLinkedToAllCaseIssue){
             Set<Id> caseIds = new Set<Id>();
        caseIds.add(Id.valueof(caseId));
        Database.executeBatch(new IC_RollUpPayeeBatch(caseIds));
        }
       
        
        if(!apexBatchCall){
                        
            Map<String, Integer> processSummary = new Map<String, Integer>();
            Boolean reverted = false;
            BatchEmailService.sendBatchSummaryEmail(
                caseId,
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
                failedRecords
            );
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
        public String Status;
    }
}