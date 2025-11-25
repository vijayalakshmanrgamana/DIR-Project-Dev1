public class DeletePayeeBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    
    private Set<Id> accountIds;
    private Set<Id> caseRoleIds;
    private Set<Id> payeeIds;
    private Id caseId;
    private String importType;
    private Integer insertedAccounts;
    private Integer insertedCaseRoles;
    private Integer insertedPayees;
    private Integer successCountPayee;
    private Integer failureCountPayee;
    private Boolean batchError;
    private Integer batchRunCount;
    private Integer numberOfImportRecordsInserted;
    private String allErrorMessages;
    private String creationErrorTable;
    private String updateerrorTable;
    public Boolean reverted;
    public String batchName;
    public List<BatchEmailService.WrapperError> failedRecordsRevert;
    public Boolean clean = false;
    public List<DIR_Violation__c> caseIssueList;
    
    // Summary Map
    Map<String, Integer> processSummary = new Map<String, Integer>{
        'Account_Deleted' => 0,
            'CaseRole_Deleted' => 0,
            'Payee_Deleted' => 0,
            'Account_Failed' => 0,
            'CaseRole_Failed' => 0,
            'Payee_Failed' => 0
            };
                
                // Use WrapperError from BatchEmailService (not local)
                List<BatchEmailService.WrapperError> failedRecordsDelete = new List<BatchEmailService.WrapperError>();
    
    // Constructor
    public DeletePayeeBatch(
        Set<Id> accountIds,
        Set<Id> caseRoleIds,
        Set<Id> payeeIds,
        Id caseId,
        String importType,
        Integer insertedAccounts,
        Integer insertedCaseRoles,
        Integer insertedPayees,
        Integer successCountPayee,
        Integer failureCountPayee,
        Boolean batchError,
        Integer batchRunCount,
        Integer numberOfImportRecordsInserted,
        String allErrorMessages,
        String creationErrorTable,
        String updateerrorTable,
        boolean reverted,
        String batchName,
        List<BatchEmailService.WrapperError> failedRecordsRevert,
        Map<String, Integer> processSummaryRevert
    ) {
        this.accountIds = accountIds;
        this.caseRoleIds = caseRoleIds;
        this.payeeIds = payeeIds;
        this.caseId = caseId;
        this.importType = importType;
        this.insertedAccounts = insertedAccounts;
        this.insertedCaseRoles = insertedCaseRoles;
        this.insertedPayees = insertedPayees;
        this.successCountPayee = successCountPayee;
        this.failureCountPayee = failureCountPayee;
        this.batchError = batchError;
        this.batchRunCount = batchRunCount;
        this.numberOfImportRecordsInserted = numberOfImportRecordsInserted;
        this.allErrorMessages = allErrorMessages;
        this.creationErrorTable = creationErrorTable;
        this.updateerrorTable = updateerrorTable;
        this.reverted = reverted;
        this.batchName = batchName;
        this.failedRecordsRevert = failedRecordsRevert;
        
        for(String revertMap : processSummaryRevert.keySet()){
            processSummary.put(revertMap, processSummaryRevert.get(revertMap));
        }
        
    }
    
    public DeletePayeeBatch(Id caseId, boolean clean){
        this.caseId = caseId;
        this.clean = clean;
        
        this.payeeIds = new Set<Id>();
        this.accountIds = new Set<Id>();
        this.caseRoleIds = new Set<Id>();
        this.failedRecordsRevert = new List<BatchEmailService.WrapperError>();
        
        this.insertedAccounts = 0;
        this.insertedCaseRoles = 0;
        this.insertedPayees = 0;
        this.successCountPayee = 0;
        this.failureCountPayee = 0;
        this.batchError = false;
        this.batchRunCount = 0;
        this.numberOfImportRecordsInserted = 0;
        this.allErrorMessages = '';
        this.creationErrorTable ='';
        this.updateerrorTable ='';
        this.reverted = false;
        this.batchName = '';

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

    
    // Batch Start
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query Accounts for deletion
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
    
    // Batch Execute
    public void execute(Database.BatchableContext bc, List<Payee__c> scope) {
        try {
            
            // Get Payee Ids
            Set<Id> scopeIds = new Set<Id>();
            for (Payee__c p : scope) {
                scopeIds.add(p.Id);
            }
            
            // Get Account record IDs that are linked to Payee records
            
            Set<Id> accIds = new Set<Id>();
            
            // --- Delete Payees ---
            if (!scopeIds.isEmpty()) {
                List<Payee__c> payeeList = [
                    SELECT Id, Name, Case_Role__r.Entity__c FROM Payee__c WHERE Id IN :scopeIds
                ];
                
                for(Payee__c payee : payeeList){
                    accIds.add(payee.Case_Role__r.Entity__c);
                }
                
                List<Database.DeleteResult> payeeResults = Database.delete(payeeList, false);
                
                for (Integer i = 0; i < payeeResults.size(); i++) {
                    if (payeeResults[i].isSuccess()) {
                        processSummary.put('Payee_Deleted', processSummary.get('Payee_Deleted') + 1);
                    } else {
                        processSummary.put('Payee_Failed', processSummary.get('Payee_Failed') + 1);
                        Database.Error err = payeeResults[i].getErrors()[0];
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
                List<Account> accList = [
                    SELECT Id, Name FROM Account WHERE Id IN :accIds
                ];
                List<Database.DeleteResult> accDeleteResults = Database.delete(accList, false);
                
                for (Integer i = 0; i < accDeleteResults.size(); i++) {
                    if (accDeleteResults[i].isSuccess()) {
                        processSummary.put('Account_Deleted', processSummary.get('Account_Deleted') + 1);
                    } else {
                        processSummary.put('Account_Failed', processSummary.get('Account_Failed') + 1);
                        Database.Error err = accDeleteResults[i].getErrors()[0];
                        failedRecordsDelete.add(new BatchEmailService.WrapperError(
                            accList[i].Id,
                            accList[i].Name,
                            err.getMessage(),
                            'Account'
                        ));
                    }
                }
            }
            
        } 
        catch (Exception ex) {
            String trace = ex.getStackTraceString();
            String firstLine = trace.split('\n')[0];
            
            this.allErrorMessages += 
                'General Error : ' + ex.getMessage() +
                ' | Location: ' + firstLine + '\n';
            
            this.batchError = true;
            reverted = false;
        }
    }
    
    // Batch Finish
    public void finish(Database.BatchableContext bc) {
        
        if (failedRecordsDelete.isEmpty()) {
            reverted = true;
        }
        
        if(!failedRecordsRevert.isEmpty()){
            reverted = false;
        }
        
        Id jobId = BC.getJobId();
        
        // 2. Query the AsyncApexJob record to check ExtendedStatus
        AsyncApexJob job = [
            SELECT Id, ExtendedStatus, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];
        if (job.ExtendedStatus != null) {
            reverted = false;
            this.allErrorMessages += 'Apex Job : ' + job.ExtendedStatus;
            this.batchError = true;
        }
        
        
        if(!clean){
            // Send summary email using BatchEmailService
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
                numberOfImportRecordsInserted,
                allErrorMessages,
                creationErrorTable,
                updateerrorTable,
                processSummary,
                'DeletePayeeBatch',
                reverted,
                failedRecordsDelete,
                failedRecordsRevert
            );
        }
        else{
            List<BatchEmailService.WrapperError> failedCaseIssueRecordsUpdate = new List<BatchEmailService.WrapperError>();
            if (!processSummary.containsKey('CaseIssue_Updated')) {
                processSummary.put('CaseIssue_Updated', 0);
            }
            if (!processSummary.containsKey('CaseIssue_Failed')) {
                processSummary.put('CaseIssue_Failed', 0);
            }
            
            List<DIR_Violation__c> caseIssueUpdate = new List<DIR_Violation__c>();
            
            for (DIR_Violation__c ci : caseIssueList) {
                DIR_Violation__c caseIssue = new DIR_Violation__c();
                caseIssue.Id = ci.Id;
                caseIssue.Amount_Utilized_from_Payee__c = 0;
                caseIssueUpdate.add(caseIssue);
            }
            // --- Update Case Issues ---
            List<Database.SaveResult> updateCaseIssueResults = Database.update(caseIssueUpdate, false);
            
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
                        originalRecord.Id, // Record Id
                        originalRecord.Name, // Record Name/Key Field
                        err.getMessage(), // Error Message
                        'DIR_Violation' // Object Type
                    ));
                }
            }
            
            System.debug(processSummary.get('CaseIssue_Updated') + ' Case Issue records updated from Delete PayeeBatch');
            System.debug(processSummary.get('CaseIssue_Failed') + ' Case Issue records failed to update from Delete PayeeBatch');
            System.debug('Failed updates: ' + failedCaseIssueRecordsUpdate);
            
            
            BatchEmailService.sendDeletionSummaryEmail(
                caseId,
                'Cleanup',
                processSummary,
                'DeletePayeeBatch',
                failedRecordsDelete,
                failedCaseIssueRecordsUpdate
            );
        }
    }
}