// Updates Utilized Amount on DIR_Violation__c and Import_Form_40_Details__c on DIR_Case__c

public with sharing class UpdateAmountUtilizedByPayee implements Database.Batchable<sObject>, Database.Stateful {
    
    Id caseId;
    String importType;
    Map<Id, Decimal> caseIssueMap;
    public String allErrorMessages = '';
    public BatchEmailService.BatchSummaryWrapper wrap = new BatchEmailService.BatchSummaryWrapper();
    
    public UpdateAmountUtilizedByPayee(BatchEmailService.BatchSummaryWrapper wrap) {
        this.caseId = wrap.caseId;
        this.importType = wrap.importType;
        this.caseIssueMap = new Map<Id, Decimal>();
        this.wrap = wrap;
    }
    
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Payee_Association_JSON__c, WageAssessment__c
            FROM Payee__c
            WHERE Case_Management__c = :caseId
        ]);
    }
    
    public void execute(Database.BatchableContext context, List<Payee__c> scope) {
        try {
            for (Payee__c p : scope) {
                if (String.isNotBlank(p.Payee_Association_JSON__c)) {
                    List<PayeeAssociation> associations = (List<PayeeAssociation>) JSON.deserialize(
                        p.Payee_Association_JSON__c,
                        List<PayeeAssociation>.class
                    );
                    
                    for (PayeeAssociation association : associations) {
                        if (!caseIssueMap.containsKey(association.caseIssueId)) {
                            caseIssueMap.put(association.caseIssueId, 0);
                        }
                        
                        Decimal existingUtilized = caseIssueMap.get(association.caseIssueId);
                        Decimal finalUtilized = existingUtilized + association.caseIssueBreakdown;
                        caseIssueMap.put(association.caseIssueId, finalUtilized);
                    }
                }
            }
        } catch (Exception ex) {
            String trace = ex.getStackTraceString();
            String firstLine = trace.split('\n')[0];
            
            String errorMsg = 'Error in UpdateAmountUtilizedByPayee: ' + ex.getMessage() +
                ' | Location: ' + firstLine +
                ' | Stack Trace: ' + trace + '\n';
            
            allErrorMessages += errorMsg;
            System.debug('### [ERROR] UpdateAmountUtilizedByPayee: ' + ex.getMessage());
            System.debug('### [TRACE] ' + trace);
            
            BatchEmailService.logError(ex);
        }
    }
    
    public void finish(Database.BatchableContext context) {
        
        Id jobId = context.getJobId();

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
        
        try {
            // Update Case Issues (DIR_Violation__c)
            List<DIR_Violation__c> caseIssues = [
                SELECT Id, Name, Amount_Utilized_from_Payee__c
                FROM DIR_Violation__c
                WHERE Case__c = :caseId
            ];
            
            for (DIR_Violation__c caseIssue : caseIssues) {
                Decimal utilizedAmount = caseIssueMap.get(caseIssue.Id);
                caseIssue.Amount_Utilized_from_Payee__c = 
                    (utilizedAmount != null) ? utilizedAmount.setScale(2, RoundingMode.HALF_UP) : 0;
            }
            
            System.debug('Attempting to update ' + caseIssues.size() + ' Case Issues.');
            List<Database.SaveResult> updateCaseIssueResults = Database.update(caseIssues, false);
            
            for (Integer i = 0; i < updateCaseIssueResults.size(); i++) {
                if (updateCaseIssueResults[i].isSuccess()) {
                    System.debug('Successfully updated Case Issue ID: ' + caseIssues[i].Id);
                } else {
                    Database.Error error = updateCaseIssueResults[i].getErrors()[0];
                    allErrorMessages += 'Case Issue Update Error : Case Issue Name : ' + caseIssues[i].Name +
                        ' Error : ' + error.getMessage() + '\n';
                    System.debug('Case Issue update failed: ' + error.getMessage());
                }
            }
            
            // Update DIR_Case__c with import info
            DIR_Case__c caseManagement = [
                SELECT Id, Name, Import_Form_40_Details__c
                FROM DIR_Case__c
                WHERE Id = :caseId
                LIMIT 1
            ];
            
            importInfo impInfo = new importInfo();
            impInfo.Last_Upload_Import_type = importType;
            impInfo.Last_Modified_By = UserInfo.getName();
            impInfo.UserId = UserInfo.getUserId();
            impInfo.Last_Modified_Date = System.now().format('MM/dd/yyyy h:mm a', UserInfo.getTimeZone().getId());
            
            caseManagement.Import_Form_40_Details__c = JSON.serialize(impInfo);
            
            List<Database.SaveResult> updateCaseResults = Database.update(
                new List<DIR_Case__c>{ caseManagement }, 
                false
            );
            
            for (Integer i = 0; i < updateCaseResults.size(); i++) {
                if (updateCaseResults[i].isSuccess()) {
                    System.debug('Successfully updated Case Management ID: ' + caseId);
                } else {
                    Database.Error error = updateCaseResults[i].getErrors()[0];
                    allErrorMessages += 'Case Error : Case Name : ' + caseManagement.Name +
                        ' Error : ' + error.getMessage() + '\n';
                    System.debug('Case update failed: ' + error.getMessage());
                }
            }
             
            wrap.allErrorMessages += allErrorMessages;
            wrap.processName = 'UpdateAmountUtilizedByPayee';
            
        } catch (Exception ex) {
            String trace = ex.getStackTraceString();
            String firstLine = trace.split('\n')[0];
            
            String errorMsg = 'Error in UpdateAmountUtilizedByPayee Batch to Update the Case and Case Issue: ' +
                ex.getMessage() +
                ' | Location: ' + firstLine +
                ' | Stack Trace: ' + trace + '\n';
            
            allErrorMessages += errorMsg;
            System.debug('### [ERROR] UpdateAmountUtilizedByPayee: ' + ex.getMessage());
            System.debug('### [TRACE] ' + trace);
            
            BatchEmailService.logError(ex);
        }
		 
        BatchEmailService.sendBatchSummaryEmail(wrap);

    }
    
    public class importInfo {
        public String UserId;
        public String Last_Modified_By;
        public String Last_Modified_Date;
        public String Last_Upload_Import_type;
        public String Status;
    }
}