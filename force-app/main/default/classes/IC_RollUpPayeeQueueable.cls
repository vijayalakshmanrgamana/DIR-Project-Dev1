public class IC_RollUpPayeeQueueable implements Queueable {
    Id caseId;
	String allErrorMessages;
    BatchEmailService.BatchSummaryWrapper wrap = new BatchEmailService.BatchSummaryWrapper();
 
    // Constructor
    public IC_RollUpPayeeQueueable(BatchEmailService.BatchSummaryWrapper wrap) {
        this.caseId = wrap.caseId;
        this.wrap = wrap;
    }

    // Queueable execute method
    public void execute(QueueableContext context) {

        try {
            DIR_Case__c dirCase = [SELECT Id FROM DIR_Case__c WHERE Id = :caseId LIMIT 1];
            IC_RollUpPayeeInterest calculator = new IC_RollUpPayeeInterest(dirCase.Id);
                calculator.calculateInterest();
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
        wrap.allErrorMessages += allErrorMessages;
       	wrap.processName = 'IC_RollUpPayeeQueueable';
        
        System.debug('Payee Rollup Queueable Completed successfully.');
    }
}