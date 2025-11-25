public class RevertPayeeBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    
    
    private List<ContentVersion> payeeRecordFiles;
    private Set<Id> contentDocumentIdsForCleanup = new Set<Id>();
    
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
    private Integer NumberofImportRecordsInserted;
    private String allErrorMessages;
    private String creationErrorTable;
    private String updateerrorTable;
    public Boolean reverted = false;
    public String uniqueKey;    
    
    
    public Integer batchCount = 0;
    
    private Map<String, Integer> processSummary = new Map<String, Integer> {
        'Payee_Updated' => 0,
            'Payee_Updated_Failed' => 0
            };
                private List<BatchEmailService.WrapperError> failedRecordsDelete = new List<BatchEmailService.WrapperError>();
    private List<BatchEmailService.WrapperError> failedRecordsRevert = new List<BatchEmailService.WrapperError>();
    
    
    public RevertPayeeBatch(
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
        String uniqueKey // Key for the ContentVersion Title
    )
    {
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
        this.uniqueKey = uniqueKey;
    }
    
    
    // --- start Method (Queries Payee__c records to be reverted) ---
    public Database.QueryLocator start(Database.BatchableContext bc) {
        
        String contentTitlePattern = 'PayeeRevertData' + this.uniqueKey + '%';
        return Database.getQueryLocator([
            SELECT Id, VersionData, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Title LIKE :contentTitlePattern
        ]);
    }
    
    
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        
        // Scope is List<ContentVersion>
        List<ContentVersion> cvFiles = (List<ContentVersion>)scope;
        
        // This batch expects to process ContentVersion records
        if (cvFiles.isEmpty()) {
            return;
        }
        
        Map<Id, Payee__c> updatesMap = new Map<Id, Payee__c>();
        
        // Assuming batch size is 1 or processing the entire chunk of CV files
        ContentVersion currentCv = cvFiles[0]; 
        
        // Process file and get the map of revert data
        Map<Id, Map<String, String>> aggregatedRevertDataMap = processFile(currentCv);
        
        List<ContentDocument> documentsToProcess = new List<ContentDocument>();
        
        if (aggregatedRevertDataMap != null) {
            List<Id> keyList = new List<Id>(aggregatedRevertDataMap.keySet());
            
            for (Id payeeId : keyList) {
                Map<String, String> details = aggregatedRevertDataMap.get(payeeId);
                
                if (details != null) {
                    Payee__c preparedPayee = new Payee__c(Id = payeeId);
                    
                    if (details.containsKey('Payee_Association_JSON__c')) {
                        preparedPayee.Payee_Association_JSON__c = details.get('Payee_Association_JSON__c');
                    }
                    if (details.containsKey('Direct_Pay__c')) {
                        preparedPayee.Direct_Pay__c = details.get('Direct_Pay__c');
                    }
                    if (details.containsKey('NetWages__c') && String.isNotEmpty(details.get('NetWages__c'))) {
                        preparedPayee.NetWages__c = Decimal.valueOf(details.get('NetWages__c'));
                    }
                    if (details.containsKey('WageAssessment__c') && String.isNotEmpty(details.get('WageAssessment__c'))) {
                        preparedPayee.WageAssessment__c = Decimal.valueOf(details.get('WageAssessment__c'));
                    }
                    if (details.containsKey('TotalDeductions__c') && String.isNotEmpty(details.get('TotalDeductions__c'))) {
                        preparedPayee.TotalDeductions__c = Decimal.valueOf(details.get('TotalDeductions__c'));
                    }
                    if (details.containsKey('Factor__c') && String.isNotEmpty(details.get('Factor__c'))) {
                        preparedPayee.Factor__c = Decimal.valueOf(details.get('Factor__c'));
                    }
                    if (details.containsKey('Post_Citation_Interest_for_Wages__c') && String.isNotEmpty(details.get('Post_Citation_Interest_for_Wages__c'))) {
                        preparedPayee.Post_Citation_Interest_for_Wages__c = Decimal.valueOf(details.get('Post_Citation_Interest_for_Wages__c'));
                    }
                    if (details.containsKey('Post_Judgment_Interest_for_Wages__c') && String.isNotEmpty(details.get('Post_Judgment_Interest_for_Wages__c'))) {
                        preparedPayee.Post_Judgment_Interest_for_Wages__c = Decimal.valueOf(details.get('Post_Judgment_Interest_for_Wages__c'));
                    }
                    System.debug('preparedPayee :'+ preparedPayee);
                    updatesMap.put(preparedPayee.Id, preparedPayee);
                } else {
                    // Log error: Revert data missing for this ID inside the file
                    failedRecordsRevert.add(new BatchEmailService.WrapperError(
                        payeeId, 
                        'N/A', 
                        'Revert data not found in ContentVersion file: ' + currentCv.Title, 
                        'Payee Lookup'
                    ));
                }
            }
        }
        
        List<Payee__c> updates = updatesMap.values();
        
        // --- Perform DML Update on Payee records ---
        try {
            if (!updates.isEmpty()) {
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
                        
                        failedRecordsRevert.add(new BatchEmailService.WrapperError(
                            failedRec.Id, 
                            payeeNameForError, 
                            err.getMessage(), 
                            'Payee DML Update'
                        ));
                        System.debug('failedRecordsRevert : '+failedRecordsRevert);
                        System.debug('failedRecordsRevert Size :'+failedRecordsRevert.size());
                    }
                }
            }
        }         catch (Exception ex) {
            String trace = ex.getStackTraceString();
            String firstLine = trace.split('\n')[0];
            
            this.allErrorMessages += 
                'General Error : ' + ex.getMessage() +
                ' | Location: ' + firstLine + '\n';
            
            this.batchError = true;
            reverted = false;
        }
        
        // --- CORE CHANGE: Delete the ContentVersion record now and collect ContentDocumentId ---
        if (currentCv != null && currentCv.ContentDocumentId != null) {
            try {
                delete new ContentDocument(
                    Id = currentCv.ContentDocumentId
                );
            }         catch (Exception ex) {
                String trace = ex.getStackTraceString();
                String firstLine = trace.split('\n')[0];
                
                this.allErrorMessages += 
                    'General Error : ' + ex.getMessage() +
                    ' | Location: ' + firstLine + '\n';
                
                this.batchError = true;
                reverted = false;
            }
        }
        
    }
    
    // --- Helper Method to Process a Single ContentVersion File (Remains the same) ---
    private Map<Id, Map<String, String>> processFile(ContentVersion cv) {
        Map<Id, Map<String, String>> revertDataMap = null;
        if (cv.VersionData != null) {
            try {
                // Convert Blob to String and deserialize
                String serializedData = cv.VersionData.toString();
                
                revertDataMap = (Map<Id, Map<String, String>>) JSON.deserialize(
                    serializedData, 
                    Map<Id, Map<String, String>>.class
                );
            } catch (Exception e) {
                // Log the deserialization error associated with the file
                System.debug('Error deserializing ContentVersion data from file ' + cv.Title + ': ' + e.getMessage());
                this.batchError = true;
                String trace = e.getStackTraceString();
                String firstLine = trace.split('\n')[0];
                
                this.allErrorMessages += 'Error deserializing Payee Revert Data from file (' + cv.Title + '): ' + e.getMessage() +
                    ' | Location: ' + firstLine + '\n';
            }
        } else { 
            System.debug('ContentVersion file is empty: ' + cv.Title);
            this.batchError = true;
            this.allErrorMessages += 'Payee Revert Data file is empty: ' + cv.Title + '\n';
        }
        return revertDataMap;
    }
    
    
    // --- finish Method (Corrected DML cleanup) ---
    public void finish(Database.BatchableContext bc) {
        
        
        if (failedRecordsRevert.isEmpty()) {
            reverted = true;
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
        
        If(accountIds.IsEmpty()){
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
                'RevertPayeeBatch',
                reverted,
                failedRecordsDelete,
                failedRecordsRevert
            );
        }
        else {
            Database.executeBatch(
                new DeletePayeeBatch(
                    accountIds,
                    caseRoleIds,
                    payeeIds,
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
                    reverted,
                    'RevertPayeeBatch',
                    failedRecordsRevert,
                    processSummary
                ),
                200
            );
        }
    }
}