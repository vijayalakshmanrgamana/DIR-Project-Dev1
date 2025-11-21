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
    
    // Batch Start
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query Accounts for deletion
        return Database.getQueryLocator([
            SELECT Id, Name FROM Account WHERE Id IN :accountIds
        ]);
    }
    
    // Batch Execute
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            // --- Delete Case Roles ---
            if (!caseRoleIds.isEmpty()) {
                List<Case_Role__c> caseRoleList = [
                    SELECT Id, Name FROM Case_Role__c WHERE Id IN :caseRoleIds LIMIT 200
                ];
                List<Database.DeleteResult> caseRoleResults = Database.delete(caseRoleList, false);
                
                for (Integer i = 0; i < caseRoleResults.size(); i++) {
                    if (caseRoleResults[i].isSuccess()) {
                        processSummary.put('CaseRole_Deleted', processSummary.get('CaseRole_Deleted') + 1);
                    } else {
                        processSummary.put('CaseRole_Failed', processSummary.get('CaseRole_Failed') + 1);
                        Database.Error err = caseRoleResults[i].getErrors()[0];
                        failedRecordsDelete.add(new BatchEmailService.WrapperError(
                            caseRoleList[i].Id,
                            caseRoleList[i].Name,
                            err.getMessage(),
                            'Case Role'
                        ));
                    }
                }
            }
            
            // --- Delete Accounts ---
            if (!accountIds.isEmpty()) {
                List<Account> accList = [
                    SELECT Id, Name FROM Account WHERE Id IN :accountIds LIMIT 200
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
            
            // --- Delete Payees ---
            if (!payeeIds.isEmpty()) {
                List<Payee__c> payeeList = [
                    SELECT Id, Name FROM Payee__c WHERE Id IN :payeeIds LIMIT 200
                ];
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
}