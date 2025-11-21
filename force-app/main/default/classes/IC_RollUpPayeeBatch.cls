public without sharing class IC_RollUpPayeeBatch implements Database.Batchable<SObject>, Database.Stateful {
    Set<Id> caseIds;
    String triggeredCaseIds = '';
    DateTime startTime;
    DateTime endTime;
    
    List<String> caseDmlErrors = new List<String>();
    String errorMessage = '';

    // Execution time calculation
    Decimal executionTime {
        get {
            if (startTime != null && endTime != null) {
                Long durationMillis = endTime.getTime() - startTime.getTime();
                Decimal durationMinutes = Decimal.valueOf(durationMillis) / (1000 * 60);
                return durationMinutes.setScale(2);
            }
            return 0;
        }
    }

    // Constructor
    public IC_RollUpPayeeBatch(Set<Id> caseIds) {
        this.caseIds = (caseIds != null) ? caseIds : new Set<Id>();
        this.triggeredCaseIds = JSON.serializePretty(this.caseIds);
    }

    // Batch start method
    public Database.QueryLocator start(Database.BatchableContext bc) {
        startTime = System.now();
        System.debug('Start Time: ' + startTime + ', Case IDs count: ' + caseIds.size());

        // NOTE: Your query field names repeated; removed duplicate and fixed syntax
        return Database.getQueryLocator([
                               SELECT Id     
                 FROM DIR_Case__c
                    WHERE Id IN :caseIds
             ]);

    }

    // Batch execute method
    public void execute(Database.BatchableContext bc, List<DIR_Case__c> dircases) {
        try {
            for(DIR_Case__c c : dircases){
                IC_RollUpPayeeInterest calculator = new IC_RollUpPayeeInterest(c.Id);
                calculator.calculateInterest();
                
            }
            
        } catch (Exception e) {
            String err = 'Exception in IC_RollUpPayeeBatch execute: ' + e.getMessage() + 
                         ' - ' + e.getStackTraceString();
            errorMessage += err + '\n';
            caseDmlErrors.add(err);
            System.debug(err);
        }
    }

    // Batch finish method
    public void finish(Database.BatchableContext bc) {
        try {
            endTime = System.now();

            AsyncApexJob job = [
                SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, ExtendedStatus
                FROM AsyncApexJob WHERE Id = :bc.getJobId()
            ];

            if (job.NumberOfErrors > 0) {
                String err = '\nBatch had ' + job.NumberOfErrors + ' errors. Extended Status: ' + job.ExtendedStatus;
                errorMessage += err;
                caseDmlErrors.add(err);
            }

            sendEmail(triggeredCaseIds);
            System.debug('Payee Rollup Batch Completed successfully.');

        } catch (Exception e) {
            System.debug('Error in finish: ' + e.getMessage());
        }
    }

    // Send completion email
    void sendEmail(String serializedCaseIds) {
        List<IC_Batch_Notification_Recipients__c> recipientSettings = IC_Batch_Notification_Recipients__c.getAll().values();
        List<String> recipients = new List<String>();

        for (IC_Batch_Notification_Recipients__c ic : recipientSettings) {
            if (ic.Recipient_Email__c != null) {
                recipients.add(ic.Recipient_Email__c);
            }
        }

        if (recipients.isEmpty()) {
            System.debug('No recipients found for batch email notification.');
            return;
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(recipients);
        mail.setSubject('Payee Rollup Batch Summary');

        String emailBody = 'Payee batch processing completed.\n\n';
        emailBody += 'Triggered Case IDs: ' + serializedCaseIds + '\n';
        emailBody += 'Execution Time (min): ' + executionTime + '\n';

        if (!String.isEmpty(errorMessage)) {
            emailBody += '\n⚠️ Job encountered errors:\n' + errorMessage;
        } else {
            emailBody += '\n✅ No errors encountered.';
        }

        mail.setPlainTextBody(emailBody);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
    }
}