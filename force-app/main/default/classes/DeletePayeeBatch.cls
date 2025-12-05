public class DeletePayeeBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    
    private Set<Id> payeeIds;
    private Id caseId;
    private boolean reverted;
    private String allErrorMessages = ' ';
    public List<BatchEmailService.WrapperError> failedRecordsRevert;
    public Boolean clean = false;
    public List<DIR_Violation__c> caseIssueList;
    BatchEmailService.BatchSummaryWrapper wrap = new BatchEmailService.BatchSummaryWrapper();
    
    Map<String, Integer> processSummary = new Map<String, Integer>{
        'Account_Deleted' => 0,
        'CaseRole_Deleted' => 0,
        'Payee_Deleted' => 0,
        'Account_Failed' => 0,
        'CaseRole_Failed' => 0,
        'Payee_Failed' => 0
    };
    
    // List to store records that failed deletion, using the external wrapper
    List<BatchEmailService.WrapperError> failedRecordsDelete = new List<BatchEmailService.WrapperError>();
    
    // Constructor for the revert/cleanup process (chained from a previous batch/step)
    public DeletePayeeBatch(
        Set<Id> payeeIds,
        boolean reverted,
        List<BatchEmailService.WrapperError> failedRecordsRevert,
        Map<String, Integer> processSummaryRevert,
        BatchEmailService.BatchSummaryWrapper wrap
    ) {
        
        this.payeeIds = payeeIds;
        this.reverted = reverted;
        this.failedRecordsRevert = failedRecordsRevert;
        // Merge process summary from the previous step
        for(String revertMap : processSummaryRevert.keySet()){
            processSummary.put(revertMap, processSummaryRevert.get(revertMap));
        }
        this.wrap = wrap;
        
    }
    
    // Constructor for the initial "clean up" process
    public DeletePayeeBatch(Id caseId, boolean clean){
        this.caseId = caseId;
        this.clean = clean;
        
        this.payeeIds = new Set<Id>();
        this.failedRecordsRevert = new List<BatchEmailService.WrapperError>();

        // Query all related DIR_Violation__c records for later use in the finish method (for clean-up only)
        caseIssueList = [
            SELECT Id, Name, Wage_Balance_Due__c, Amount_Reserved__c, 
            Amount_Utilized_from_Payee__c,
            Violation_Type__r.Violation_Type_Name__c, 
            Violation_Type__r.Violation_Type__c, 
            Post_Judgment_Interest_for_Wages__c, 
            Post_Citation_Interest_for_Wages__c
            FROM DIR_Violation__c
            WHERE Case__c = :caseId
        ];
    }

    
    // Batch Start method: Defines the records to be processed
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query Payee__c records either by a specific set of IDs (revert) or by Case ID (clean)
        if(!clean){
            return Database.getQueryLocator([
                SELECT Id, Name FROM Payee__c WHERE Id IN :payeeIds
            ]);
        }
        else{
            return Database.getQueryLocator([
                SELECT Id, Name FROM Payee__c WHERE Case_Management__c = :caseId
            ]);
        }
    }
    
    // Batch Execute method: Executes the deletion logic for a batch of records
    public void execute(Database.BatchableContext bc, List<Payee__c> scope) {
        try {
            
            // Collect the Ids of Payee records in the current scope
            Set<Id> scopeIds = new Set<Id>();
            for (Payee__c p : scope) {
                scopeIds.add(p.Id);
            }
            
            // Set to hold Account IDs linked to the Payees for cascading deletion
            Set<Id> accIds = new Set<Id>();
            
            // --- Delete Payees ---
            if (!scopeIds.isEmpty()) {
                // Query Payee records again to get the parent Case_Role__r.Entity__c (Account ID)
                List<Payee__c> payeeList = [
                    SELECT Id, Name, Case_Role__r.Entity__c FROM Payee__c WHERE Id IN :scopeIds
                ];
                
                // Collect the associated Account IDs
                for(Payee__c payee : payeeList){
                    accIds.add(payee.Case_Role__r.Entity__c);
                }
                
                // Perform the delete operation on Payee records (allOrNone=false)
                List<Database.DeleteResult> payeeResults = Database.delete(payeeList, false);
                
                // Process the deletion results for Payees
                for (Integer i = 0; i < payeeResults.size(); i++) {
                    if (payeeResults[i].isSuccess()) {
                        processSummary.put('Payee_Deleted', processSummary.get('Payee_Deleted') + 1);
                    } else {
                        processSummary.put('Payee_Failed', processSummary.get('Payee_Failed') + 1);
                        Database.Error err = payeeResults[i].getErrors()[0];
                        // Log failed Payee record
                        failedRecordsDelete.add(new BatchEmailService.WrapperError(
                            payeeList[i].Id,
                            payeeList[i].Name,
                            err.getMessage(),
                            'Payee'
                        ));
                    }
                }
            }
            
            // --- Delete Accounts ---
            if (!accIds.isEmpty()) {
                // Query Account records for deletion
                List<Account> accList = [
                    SELECT Id, Name FROM Account WHERE Id IN :accIds
                ];
                // Perform the delete operation on Account records (allOrNone=false)
                List<Database.DeleteResult> accDeleteResults = Database.delete(accList, false);
                
                // Process the deletion results for Accounts
                for (Integer i = 0; i < accDeleteResults.size(); i++) {
                    if (accDeleteResults[i].isSuccess()) {
                        processSummary.put('Account_Deleted', processSummary.get('Account_Deleted') + 1);
                    } else {
                        processSummary.put('Account_Failed', processSummary.get('Account_Failed') + 1);
                        Database.Error err = accDeleteResults[i].getErrors()[0];
                        // Log failed Account record
                        failedRecordsDelete.add(new BatchEmailService.WrapperError(
                            accList[i].Id,
                            accList[i].Name,
                            err.getMessage(),
                            'Account'
                        ));
                    }
                }
            }
            
        } catch (Exception ex) {
            // General error handling for deleting Account and Payee records
            String trace = ex.getStackTraceString();
            String firstLine = trace.split('\n')[0];
            
            String errorMsg = 'Error while deleting Account and Payee records: ' +
                ex.getMessage() +
                ' | Location: ' + firstLine +
                ' | Stack Trace: ' + trace + '\n';
            
            this.allErrorMessages += errorMsg;
            reverted = false;
            
            System.debug('### [ERROR] Delete Account & Payee: ' + ex.getMessage());
            System.debug('### [TRACE] ' + trace);
            
            // Log the error using the BatchEmailService
            BatchEmailService.logError(ex);
        }

    }
    
    // Batch Finish method: Sends summary email and handles post-processing logic
    public void finish(Database.BatchableContext bc) {
        System.debug('Total Failed Deletions in this batch: ' + failedRecordsDelete.size());
        
        // Determine the overall status of the delete operation
        if (failedRecordsDelete.isEmpty()) {
            reverted = true;
        }
        // If there were any failures in the previous (revert) step or this (delete) step
        if(!failedRecordsRevert.isEmpty() || !failedRecordsDelete.isEmpty()){
            reverted = false;
        }
        
        Id jobId = BC.getJobId();
        
        // Query the AsyncApexJob record to check for general batch errors (ExtendedStatus)
        AsyncApexJob job = [
            SELECT Id, ExtendedStatus, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];
        
        // Check for batch-level errors
        if (job.ExtendedStatus != null) {
            reverted = false;
            this.allErrorMessages += 'Apex Job : ' + job.ExtendedStatus;
        }
        
        
        if(!clean){
            // Logic for "Revert" or standard delete flow (non-clean)
            BatchEmailService.BatchSummaryWrapper wrapDelete = new BatchEmailService.BatchSummaryWrapper();
            // Copy properties from the original wrapper object
            wrapDelete.caseId                      = wrap.caseId;
            wrapDelete.importType                  = wrap.importType;
            wrapDelete.insertedAccounts            = wrap.insertedAccounts;
            wrapDelete.insertedCaseRoles           = wrap.insertedCaseRoles;
            wrapDelete.insertedPayees              = wrap.insertedPayees;
            wrapDelete.successCountPayee           = wrap.successCountPayee;
            wrapDelete.failureCountPayee           = wrap.failureCountPayee;
            wrapDelete.batchError                  = wrap.batchError;
            wrapDelete.batchRunCount               = wrap.batchRunCount;
            wrapDelete.numberOfImportRecordsInserted = wrap.NumberofImportRecordsInserted;
            wrapDelete.creationErrorTable          = wrap.creationErrorTable;
            wrapDelete.updateErrorTable            = wrap.updateerrorTable;
            wrapDelete.correctiveForm40DeleteSuccess = wrap.correctiveForm40DeleteSuccess;
            wrapDelete.correctiveForm40DeleteError   = wrap.correctiveForm40DeleteError;
            
            // Combine error messages and summaries
            wrapDelete.allErrorMessages            = allErrorMessages + wrap.allErrorMessages;
            wrapDelete.processSummary              = processSummary;
            wrapDelete.reverted                    = reverted;
            wrapDelete.failedRecordsDelete         = failedRecordsDelete;
            wrapDelete.failedRecordsRevert         = failedRecordsRevert;
            wrapDelete.processName                 = 'DeletePayeeBatch';
            
            System.debug('Final wrapDelete object: ' + wrapDelete);
            
            BatchEmailService.sendBatchSummaryEmail(wrapDelete);
        }
        else{
            
            // Delete CSV import rows
            List<Import__c> Imports = [
                SELECT Id FROM Import__c
                WHERE Case_Management__c = :caseId
            ];
            if(!Imports.isEmpty()){
            delete Imports;
            }
            
            // Logic for the "Clean Up" flow: Update Case Issues after Payee deletion
            List<BatchEmailService.WrapperError> failedCaseIssueRecordsUpdate = new List<BatchEmailService.WrapperError>();
            
            // Initialize process summary counts if not present
            if (!processSummary.containsKey('CaseIssue_Updated')) {
                processSummary.put('CaseIssue_Updated', 0);
            }
            if (!processSummary.containsKey('CaseIssue_Failed')) {
                processSummary.put('CaseIssue_Failed', 0);
            }
            
            List<DIR_Violation__c> caseIssueUpdate = new List<DIR_Violation__c>();
            
            // Prepare DIR_Violation__c records for update (resetting Amount_Utilized_from_Payee__c to 0)
            for (DIR_Violation__c ci : caseIssueList) {
                DIR_Violation__c caseIssue = new DIR_Violation__c();
                caseIssue.Id = ci.Id;
                caseIssue.Amount_Utilized_from_Payee__c = 0;
                caseIssueUpdate.add(caseIssue);
            }
            
            // --- Update Case Issues ---
            List<Database.SaveResult> updateCaseIssueResults = Database.update(caseIssueUpdate, false);
            
            // Process the update results for DIR_Violation__c
            for (Integer i = 0; i < updateCaseIssueResults.size(); i++) {
                Database.SaveResult sr = updateCaseIssueResults[i];
                if (sr.isSuccess()) {
                    // Increment success count
                    processSummary.put('CaseIssue_Updated', processSummary.get('CaseIssue_Updated') + 1);
                } else {
                    // Increment failure count
                    processSummary.put('CaseIssue_Failed', processSummary.get('CaseIssue_Failed') + 1);
                    
                    // Get the first error
                    Database.Error err = sr.getErrors()[0];
                    
                    DIR_Violation__c originalRecord = caseIssueList[i];
                    
                    // Store the failed record details
                    failedCaseIssueRecordsUpdate.add(new BatchEmailService.WrapperError(
                        originalRecord.Id, 
                        originalRecord.Name, 
                        err.getMessage(), 
                        'DIR_Violation' 
                    ));
                }
            }
            
                        // Update DIR_Case__c with import info
            DIR_Case__c caseManagement = [
                SELECT Id, Name, Import_Form_40_Details__c
                FROM DIR_Case__c
                WHERE Id = :caseId
                LIMIT 1
            ];
            
            BatchEmailService.importInfo impInfo = new BatchEmailService.importInfo();
            impInfo.Last_Modified_By = UserInfo.getName();
            impInfo.UserId = UserInfo.getUserId();
            impInfo.Last_Modified_Date = System.now().format('MM/dd/yyyy h:mm a', UserInfo.getTimeZone().getId());
            
            caseManagement.Import_Form_40_Details__c = JSON.serialize(impInfo);
            
            List<Database.SaveResult> updateCaseResults = Database.update(
                new List<DIR_Case__c>{ caseManagement }, 
                false
            );
            
            System.debug('Case Issue Records Updated: ' + processSummary.get('CaseIssue_Updated'));
            System.debug('Case Issue Records Failed to Update: ' + processSummary.get('CaseIssue_Failed'));
            System.debug('Details of Failed Updates: ' + failedCaseIssueRecordsUpdate);
            
            // Send a specific summary email for the cleanup process
            BatchEmailService.sendDeletionSummaryEmail(
                caseId,
                'Clean Up',
                processSummary,
                'DeletePayeeBatch',
                failedRecordsDelete,
                failedCaseIssueRecordsUpdate
            );
        }
    }
}