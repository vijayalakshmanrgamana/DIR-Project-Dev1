/**
 * @description Batch class to revert Payee__c records to their previous state
 * using data stored in ContentVersion files, and then delete the file.
 * This class implements Database.Stateful to maintain state across transactions
 * and Database.AllowsCallouts if the BatchEmailService requires callouts.
 */
public class RevertPayeeBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
 
    // Member variables for batch state and error tracking
    private List<ContentVersion> payeeRecordFiles; // Unused, can be removed if not needed later.
    private Set<Id> contentDocumentIdsForCleanup = new Set<Id>(); // Unused, but related to file cleanup concept.
    private Set<Id> payeeIds; // IDs of Payee__c records being processed/reverted.
    private String allErrorMessages = ''; // Accumulates all error messages.
    public Boolean reverted = false; // Tracks if the full revert was successful.
    public String uniqueKey; // Unique key to find the correct ContentVersion file(s).
    
    // Wrapper to hold summary and pass information to the next batch or email service.
    BatchEmailService.BatchSummaryWrapper wrap = new BatchEmailService.BatchSummaryWrapper();

    public Integer batchCount = 0; // Tracks the number of executed batches.

    // Summary map to track success/failure counts for Payee updates.
    private Map<String, Integer> processSummary = new Map<String, Integer> {
        'Payee_Updated' => 0,
        'Payee_Updated_Failed' => 0
    };
    private List<BatchEmailService.WrapperError> failedRecordsDelete = new List<BatchEmailService.WrapperError>(); // For logging Payee deletion errors (though delete is in the next batch).
    private List<BatchEmailService.WrapperError> failedRecordsRevert = new List<BatchEmailService.WrapperError>(); // For logging Payee revert update errors.

    /**
     * @description Constructor for the batch.
     * @param payeeIds The set of Payee IDs that were initially intended for deletion/revert.
     * @param uniqueKey The unique key used in the ContentVersion title to identify the revert data file.
     * @param wrap A BatchSummaryWrapper containing initial process summary data.
     */
    public RevertPayeeBatch(
        Set<Id> payeeIds,
        String uniqueKey,
        BatchEmailService.BatchSummaryWrapper wrap
    )
    {
        this.payeeIds = payeeIds;
        this.uniqueKey = uniqueKey;
        this.wrap = wrap;
    }


    /**
     * @description Queries the ContentVersion records containing the revert data.
     * @param bc The Database.BatchableContext.
     * @return Database.QueryLocator for ContentVersion records.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {

        String contentTitlePattern = 'PayeeRevertData' + this.uniqueKey + '%';
        // Query for ContentVersion records matching the unique key pattern
        return Database.getQueryLocator([
            SELECT Id, VersionData, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Title LIKE :contentTitlePattern
        ]);
    }


    /**
     * @description Executes the business logic for each batch of ContentVersion records.
     * It deserializes the revert data, updates the Payee__c records, and then deletes the ContentVersion/ContentDocument.
     * @param bc The Database.BatchableContext.
     * @param scope The list of SObject (ContentVersion) records to process.
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {

        // Cast the scope to List<ContentVersion>
        List<ContentVersion> cvFiles = (List<ContentVersion>)scope;

        // Check if there are any ContentVersion files to process
        if (cvFiles.isEmpty()) {
            System.debug('Execute method received an empty scope.');
            return;
        }

        Map<Id, Payee__c> updatesMap = new Map<Id, Payee__c>();

        // Assuming batch size is 1 for ContentVersion processing (or processing the entire chunk of CV files)
        ContentVersion currentCv = cvFiles[0];

        // Process file and get the map of revert data: Map<PayeeId, Map<FieldName, OldValue>>
        Map<Id, Map<String, String>> aggregatedRevertDataMap = processFile(currentCv);

        // Map is used to hold prepared Payee__c records for DML.
        if (aggregatedRevertDataMap != null) {
            List<Id> keyList = new List<Id>(aggregatedRevertDataMap.keySet());

            // Iterate through the revert data to prepare Payee records for update
            for (Id payeeId : keyList) {
                Map<String, String> details = aggregatedRevertDataMap.get(payeeId);

                if (details != null) {
                    Payee__c preparedPayee = new Payee__c(Id = payeeId);

                    // Revert Payee_Association_JSON__c
                    if (details.containsKey('Payee_Association_JSON__c')) {
                        preparedPayee.Payee_Association_JSON__c = details.get('Payee_Association_JSON__c');
                    }
                    // Revert Direct_Pay__c
                    if (details.containsKey('Direct_Pay__c')) {
                        preparedPayee.Direct_Pay__c = details.get('Direct_Pay__c');
                    }
                    // Revert NetWages__c (Decimal field)
                    if (details.containsKey('NetWages__c') && String.isNotEmpty(details.get('NetWages__c'))) {
                        preparedPayee.NetWages__c = Decimal.valueOf(details.get('NetWages__c'));
                    }
                    System.debug('Processing Payee ID: ' + payeeId + ' | NetWages__c Value: ' + preparedPayee.NetWages__c);
                    // Revert WageAssessment__c (Decimal field)
                    if (details.containsKey('WageAssessment__c') && String.isNotEmpty(details.get('WageAssessment__c'))) {
                        preparedPayee.WageAssessment__c = Decimal.valueOf(details.get('WageAssessment__c'));
                    }
                    // Revert TotalDeductions__c (Decimal field)
                    if (details.containsKey('TotalDeductions__c') && String.isNotEmpty(details.get('TotalDeductions__c'))) {
                        preparedPayee.TotalDeductions__c = Decimal.valueOf(details.get('TotalDeductions__c'));
                    }
                    // Revert Factor__c (Decimal field)
                    if (details.containsKey('Factor__c') && String.isNotEmpty(details.get('Factor__c'))) {
                        preparedPayee.Factor__c = Decimal.valueOf(details.get('Factor__c'));
                    }
                    // Revert Post_Citation_Interest_for_Wages__c (Decimal field)
                    if (details.containsKey('Post_Citation_Interest_for_Wages__c') && String.isNotEmpty(details.get('Post_Citation_Interest_for_Wages__c'))) {
                        preparedPayee.Post_Citation_Interest_for_Wages__c = Decimal.valueOf(details.get('Post_Citation_Interest_for_Wages__c'));
                    }
                    // Revert Post_Judgment_Interest_for_Wages__c (Decimal field)
                    if (details.containsKey('Post_Judgment_Interest_for_Wages__c') && String.isNotEmpty(details.get('Post_Judgment_Interest_for_Wages__c'))) {
                        preparedPayee.Post_Judgment_Interest_for_Wages__c = Decimal.valueOf(details.get('Post_Judgment_Interest_for_Wages__c'));
                    }

                    System.debug('Prepared Payee record for revert: ' + preparedPayee);
                    updatesMap.put(preparedPayee.Id, preparedPayee);
                } else {
                    // Log error: Revert data missing for this ID inside the file
                    failedRecordsRevert.add(new BatchEmailService.WrapperError(
                        payeeId,
                        'N/A',
                        'Revert data not found in ContentVersion file: ' + currentCv.Title,
                        'Payee Lookup in File'
                    ));
                    System.debug('Error: Revert data missing for Payee ID: ' + payeeId + ' in file: ' + currentCv.Title);
                }
            }
        }

        List<Payee__c> updates = updatesMap.values();

        // --- Perform DML Update on Payee records (Revert) ---
        try {
            if (!updates.isEmpty()) {
                // Perform partial success update
                List<Database.SaveResult> results = Database.update(updates, false);

                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        processSummary.put('Payee_Updated', processSummary.get('Payee_Updated') + 1);
                    } else {
                        processSummary.put('Payee_Updated_Failed', processSummary.get('Payee_Updated_Failed') + 1);
                        Database.Error err = results[i].getErrors()[0];
                        Payee__c failedRec = updates[i];

                        // Try to get Payee Name from the revert data for logging
                        String payeeNameForError = (aggregatedRevertDataMap != null && aggregatedRevertDataMap.get(failedRec.Id) != null)
                            ? aggregatedRevertDataMap.get(failedRec.Id).get('Payee_Name__c') : 'N/A';

                        // Log the DML error
                        failedRecordsRevert.add(new BatchEmailService.WrapperError(
                            failedRec.Id,
                            payeeNameForError,
                            err.getMessage(),
                            'Payee DML Update (Revert)'
                        ));
                        System.debug('Failed to revert Payee ID: ' + failedRec.Id + ' | Error: ' + err.getMessage());
                    }
                }
            }
        } catch (Exception ex) {
            String trace = ex.getStackTraceString();
            String firstLine = trace.split('\n')[0];
            
            String errorMsg =
                'General Error during Payee DML Update: ' + ex.getMessage() +
                ' | Location: ' + firstLine +
                ' | Stack Trace: ' + trace + '\n';
            
            this.allErrorMessages += errorMsg;
            reverted = false;
            
            System.debug('### [ERROR] Payee DML Update: ' + ex.getMessage());
            System.debug('### [TRACE] ' + trace);
            
            // Log the error using the BatchEmailService
            BatchEmailService.logError(ex);
        }


        // --- CORE CHANGE: Delete the ContentDocument (which deletes the ContentVersion) ---
        if (currentCv != null && currentCv.ContentDocumentId != null) {
            try {
                // Deleting the ContentDocument deletes all associated ContentVersions
                delete new ContentDocument(
                    Id = currentCv.ContentDocumentId
                );
                System.debug('Successfully deleted ContentDocument ID: ' + currentCv.ContentDocumentId);
            } catch (Exception ex) {
                String trace = ex.getStackTraceString();
                String firstLine = trace.split('\n')[0];
                
                String errorMsg =
                    'General Error during ContentDocument deletion: ' + ex.getMessage() +
                    ' | Location: ' + firstLine +
                    ' | Stack Trace: ' + trace + '\n';
                
                this.allErrorMessages += errorMsg;
                reverted = false; // Mark as failed if the cleanup failed.
                
                System.debug('### [ERROR] Deleting ContentDocument ID: ' + currentCv.ContentDocumentId + 
                             ' | Error: ' + ex.getMessage());
                System.debug('### [TRACE] ' + trace);
                
                // Log the error using the BatchEmailService
                BatchEmailService.logError(ex);
            }

        }
    }


    /**
     * @description Helper Method to Process a Single ContentVersion File.
     * Deserializes the Blob data into a Map<PayeeId, Map<FieldName, OldValue>>.
     * @param cv The ContentVersion record to process.
     * @return Map<Id, Map<String, String>> containing the revert data, or null if deserialization fails.
     */
    private Map<Id, Map<String, String>> processFile(ContentVersion cv) {
        Map<Id, Map<String, String>> revertDataMap = null;
        if (cv.VersionData != null) {
            try {
                // Convert Blob to String and deserialize the JSON data
                String serializedData = cv.VersionData.toString();

                revertDataMap = (Map<Id, Map<String, String>>) JSON.deserialize(
                    serializedData,
                    Map<Id, Map<String, String>>.class
                );
                System.debug('Successfully deserialized revert data from file: ' + cv.Title + '. Number of records: ' + revertDataMap.size());
            } catch (Exception ex) {
                // Log the deserialization error associated with the file
                System.debug('### [ERROR] Error deserializing ContentVersion data from file ' + cv.Title + ': ' + ex.getMessage());
                
                String trace = ex.getStackTraceString();
                String firstLine = trace.split('\n')[0];
                
                String errorMsg =
                    'Error deserializing Payee Revert Data from file (' + cv.Title + '): ' + ex.getMessage() +
                    ' | Location: ' + firstLine +
                    ' | Stack Trace: ' + trace + '\n';
                
                this.allErrorMessages += errorMsg;
                
                System.debug('### [TRACE] ' + trace);
                
                // Log the error using the BatchEmailService
                BatchEmailService.logError(ex);
            }

        } else {
            System.debug('ContentVersion file is empty: ' + cv.Title);
            this.allErrorMessages += 'Payee Revert Data file is empty: ' + cv.Title + '\n';
        }
        return revertDataMap;
    }


    /**
     * @description Executed after all execute methods have completed.
     * It finalizes the revert status, queries for any unhandled batch errors, updates the summary wrapper, and chains the next batch (DeletePayeeBatch) if Payee deletion is still needed, or sends the email.
     * @param bc The Database.BatchableContext.
     */
    public void finish(Database.BatchableContext bc) {

        // If no revert errors were logged in the execute method, set reverted flag to true.
        if (failedRecordsRevert.isEmpty()) {
            reverted = true;
        }

        Id jobId = BC.getJobId();

        // Query the AsyncApexJob record to check for system-level errors (e.g., limit exceptions)
        AsyncApexJob job = [
            SELECT Id, ExtendedStatus, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        // Check if the Apex Job itself reported an error
        if (job.ExtendedStatus != null) {
            reverted = false;
            this.allErrorMessages += 'Apex Job Extended Status Error: ' + job.ExtendedStatus;
            System.debug('AsyncApexJob reported ExtendedStatus: ' + job.ExtendedStatus);
        }

        // Prepare the summary wrapper for the next step (Batch or Email)
        BatchEmailService.BatchSummaryWrapper wrapRevert = new BatchEmailService.BatchSummaryWrapper();
        wrapRevert.caseId                           = wrap.caseId;
        wrapRevert.importType                       = wrap.importType;
        wrapRevert.insertedAccounts                 = wrap.insertedAccounts;
        wrapRevert.insertedCaseRoles                = wrap.insertedCaseRoles;
        wrapRevert.insertedPayees                   = wrap.insertedPayees;
        wrapRevert.successCountPayee                = wrap.successCountPayee;
        wrapRevert.failureCountPayee                = wrap.failureCountPayee;
        wrapRevert.batchError                       = wrap.batchError;
        wrapRevert.batchRunCount                    = wrap.batchRunCount;
        wrapRevert.numberOfImportRecordsInserted    = wrap.NumberofImportRecordsInserted;
        // Aggregate all error messages
        wrapRevert.allErrorMessages                 = allErrorMessages + wrap.allErrorMessages;
        wrapRevert.creationErrorTable               = wrap.creationErrorTable;
        wrapRevert.updateErrorTable                 = wrap.updateerrorTable;
        wrapRevert.processSummary                   = processSummary;
        wrapRevert.processName                      = 'RevertPayeeBatch';
        wrapRevert.reverted                         = reverted;
        wrapRevert.failedRecordsDelete              = failedRecordsDelete; // Inherited/Passed (currently empty)
        wrapRevert.failedRecordsRevert              = failedRecordsRevert; // Errors from this batch
        wrapRevert.correctiveForm40DeleteSuccess    = wrap.correctiveForm40DeleteSuccess;
        wrapRevert.correctiveForm40DeleteError      = wrap.correctiveForm40DeleteError;

        // Determine the next step: either execute the next batch (DeletePayeeBatch) or send the summary email.
        if(payeeIds.IsEmpty()){
            // If the set of Payee IDs to delete is empty, send the final email summary.
            System.debug('Payee IDs set is empty, sending final batch summary email.');
            BatchEmailService.sendBatchSummaryEmail(wrapRevert);
        }
        else {
            // Execute the next batch to perform the actual deletion of Payee records.
            System.debug('Chaining to DeletePayeeBatch with ' + payeeIds.size() + ' records.');
            Database.executeBatch(
                new DeletePayeeBatch(
                    payeeIds,
                    reverted, // Pass the revert status
                    failedRecordsRevert, // Pass the errors from the revert attempt
                    processSummary, // Pass the updated summary
                    wrapRevert // Pass the updated wrapper
                ),
                200 // Batch size for the next batch
            );
        }
    }
}