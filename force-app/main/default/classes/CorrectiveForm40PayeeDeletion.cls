public class CorrectiveForm40PayeeDeletion implements Database.Batchable<SObject>, Database.Stateful {
    
    // Inputs
    private Id caseId;
    private String uniqueKey;
    private Set<Id> caseIssueIds;
    private BatchEmailService.BatchSummaryWrapper wrap;
     
    // Working variables
    private Set<String> chunkedMatchingKeys = new Set<String>();    
    // Error
    public List<BatchEmailService.WrapperError> correctiveForm40DeleteSuccess = new List<BatchEmailService.WrapperError>();
    public List<BatchEmailService.WrapperError> correctiveForm40DeleteError = new List<BatchEmailService.WrapperError>();
    public String allErrorMessages = '';
    
    Map<String, Integer> processSummary = new Map<String, Integer>{
        	'Account_Deleted' => 0,
            'CaseRole_Deleted' => 0,
            'Payee_Deleted' => 0,
            'Account_Failed' => 0,
            'CaseRole_Failed' => 0,
            'Payee_Failed' => 0
            };
                
                // Constructor
                public CorrectiveForm40PayeeDeletion(
                    BatchEmailService.BatchSummaryWrapper wrap,
                    String uniqueKey,
                    Set<Id> caseIssueIds
                ) {
                    this.caseId = wrap.caseId;
                    this.uniqueKey = uniqueKey;
                    this.caseIssueIds = caseIssueIds;
                    this.wrap = wrap;
                    
                    // Build unique keys from Import__c upfront
                    List<Import__c> importRecords = [
                        SELECT Employee_Last_Name__c, Employee_First_Name__c,
                        Employee_Street__c, Employee_Zip__c
                        FROM Import__c
                        WHERE Case_Management__c = :wrap.caseId
                        AND Unique_Key__c = :uniqueKey
                        AND Job_Sequence__c = null
                        ORDER BY Has_Matching_Account__c DESC,
                        Employee_First_Name__c ASC,
                        Employee_Last_Name__c ASC
                    ];
                    
                    for (Import__c imp : importRecords) {
                        chunkedMatchingKeys.add(buildUniqueKey(imp));
                    }
                }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        
        return Database.getQueryLocator([
            SELECT Id, Name, Payee_Name__c, Payee_Association_JSON__c, Case_Role__r.Entity__c,
            Case_Role__r.Entity__r.AccountMatch__c
            FROM Payee__c
            WHERE Case_Management__c = :caseId
            AND Case_Role__r.Entity__r.AccountMatch__c NOT IN :chunkedMatchingKeys
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        
		Set<Id> payeeIds = new Set<Id>(); 
        Set<Id> accIds = new Set<Id>();
        
        List<Payee__c> payees = (List<Payee__c>) scope;
        for (Payee__c payee : payees) {
             
            String jsonString = payee.Payee_Association_JSON__c;
            if (jsonString == null) continue;
             
            // Check if any caseIssueId exists in JSON
            for (Id caseIssueId : caseIssueIds) {
                if (jsonString.contains('"caseIssueId":"' + caseIssueId + '"')) {
                    payeeIds.add(payee.Id);
                    accIds.add(payee.Case_Role__r.Entity__c);
                    break;
                }
            }
        }
        
        try {
            if (!payeeIds.isEmpty()) {
                
                List<Payee__c> payeeList = [
                    SELECT Id, Name, Case_Role__r.Entity__c
                    FROM Payee__c WHERE Id IN :payeeIds
                ];
                
                // Delete Payees
                List<Database.DeleteResult> payeeResults = Database.delete(payeeList, false);
                
                for (Integer i = 0; i < payeeResults.size(); i++) {
                    if (payeeResults[i].isSuccess()) {
                        processSummary.put('Payee_Deleted', processSummary.get('Payee_Deleted') + 1);
                        correctiveForm40DeleteSuccess.add(
                            new BatchEmailService.WrapperError(
                                payeeList[i].Id, payeeList[i].Name, 'Corrective Form 40 Delete Success', 'Payee'
                            )
                        );
                    } else {
                        processSummary.put('Payee_Failed', processSummary.get('Payee_Failed') + 1);
                        correctiveForm40DeleteError.add(
                            new BatchEmailService.WrapperError(
                                payeeList[i].Id,
                                payeeList[i].Name,
                                payeeResults[i].getErrors()[0].getMessage(),
                                'Payee'
                            )
                        );
                    }
                }
                
                // Delete Accounts
                if (!accIds.isEmpty()) {
                    List<Account> accList = [SELECT Id, Name FROM Account WHERE Id IN :accIds];
                    List<Database.DeleteResult> accResults = Database.delete(accList, false);
                    
                    for (Integer i = 0; i < accResults.size(); i++) {
                        if (accResults[i].isSuccess()) {
                            processSummary.put('Account_Deleted', processSummary.get('Account_Deleted') + 1);
                            correctiveForm40DeleteSuccess.add(
                                new BatchEmailService.WrapperError(
                                    accList[i].Id, accList[i].Name, 'Corrective Form 40 Delete Success', 'Account'
                                )
                            );
                        } else {
                            processSummary.put('Account_Failed', processSummary.get('Account_Failed') + 1);
                            correctiveForm40DeleteError.add(
                                new BatchEmailService.WrapperError(
                                    accList[i].Id,
                                    accList[i].Name,
                                    accResults[i].getErrors()[0].getMessage(),
                                    'Account'
                                )
                            );
                        }
                    }
                }
            }
        } catch (Exception ex) {
            String trace = ex.getStackTraceString();
            String firstLine = trace.split('\n')[0];
            
            String errorMsg =
                'Error deleting Account and Payee records in execute(): ' + ex.getMessage() +
                ' | Location: ' + firstLine +
                ' | Stack Trace: ' + trace + '\n';
            
            allErrorMessages += errorMsg;
            
            System.debug('### [ERROR] Delete Account & Payee: ' + ex.getMessage());
            System.debug('### [TRACE] ' + trace);
            
            // Log the error using the BatchEmailService
            BatchEmailService.logError(ex);
        }

    }
    
    
    public void finish(Database.BatchableContext bc) {

        // Delete CSV import rows
            List<Import__c> imports = [
                SELECT Id FROM Import__c
                WHERE Case_Management__c = :caseId
                AND Unique_Key__c = :uniqueKey
            ];
            if(!imports.isEmpty()){
               delete imports;
            }
        
        Id jobId = BC.getJobId();

        AsyncApexJob job = [
            SELECT Id, ExtendedStatus, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];
        
        // Check for batch-level errors
        if (job.ExtendedStatus != null) {
            this.allErrorMessages += 'Apex Job : ' + job.ExtendedStatus;
        }
        
            BatchEmailService.BatchSummaryWrapper wrapCF40 = new BatchEmailService.BatchSummaryWrapper();
            // Copy properties from the original wrapper object
            wrapCF40.caseId                      = wrap.caseId;
            wrapCF40.importType                  = wrap.importType;
            wrapCF40.insertedAccounts            = wrap.insertedAccounts;
            wrapCF40.insertedCaseRoles           = wrap.insertedCaseRoles;
            wrapCF40.insertedPayees              = wrap.insertedPayees;
            wrapCF40.successCountPayee           = wrap.successCountPayee;
            wrapCF40.failureCountPayee           = wrap.failureCountPayee;
            wrapCF40.batchError                  = wrap.batchError;
            wrapCF40.batchRunCount               = wrap.batchRunCount;
            wrapCF40.numberOfImportRecordsInserted = wrap.NumberofImportRecordsInserted;
            wrapCF40.creationErrorTable          = wrap.creationErrorTable;
            wrapCF40.updateErrorTable            = wrap.updateerrorTable;
            wrapCF40.reverted                    = wrap.reverted;
            wrapCF40.failedRecordsDelete         = wrap.failedRecordsDelete;
            wrapCF40.failedRecordsRevert         = wrap.failedRecordsRevert;
        
            // Combine error messages and summaries
            wrapCF40.allErrorMessages            = allErrorMessages + wrap.allErrorMessages;
            wrapCF40.processSummary              = processSummary;
            wrapCF40.processName                 = 'PayeeCF40Batch';
            wrapCF40.correctiveForm40DeleteSuccess = correctiveForm40DeleteSuccess;
            wrapCF40.correctiveForm40DeleteError   = correctiveForm40DeleteError;
            
        System.debug('Final wrapCF40 object: ' + wrapCF40);
        System.debug('Sending batch summary UpdateAmountUtilizedByPayee.');
        		System.enqueueJob(new IC_RollUpPayeeQueueable(wrap));

        DataBase.executeBatch(new UpdateAmountUtilizedByPayee(wrapCF40), 200);
        
 

    }
    
    
    private static String buildUniqueKey(Import__c imp) {
        return String.join(new List<String>{
            imp.Employee_Last_Name__c?.trim().toLowerCase(),
                imp.Employee_First_Name__c?.trim().toLowerCase(),
                imp.Employee_Street__c?.trim().toLowerCase(),
                imp.Employee_Zip__c?.trim().toLowerCase()
                }, ',');
    }
}