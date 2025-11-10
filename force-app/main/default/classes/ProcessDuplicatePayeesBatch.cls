/*
    Case 1 

ci2,ci2,ci3,ci4

Upload Initial Form 40 Linking to 2 case Issues ci1 and ci2 for partial amount 

Upload normal form 40 by linking the same set of payees to another Case Issues ci3 and ci4
(Expectation new Associations Would be created and Net Wages on Payee will be summed up)

Upload corrective form 40 by adjusting to remaining amount for ci1 and ci2 
(Expectation : Existing Payee Associations would be overridden and Payee Net Wages would be overridden)


public without sharing class ProcessDuplicatePayees {
    // ---------------- CLASS LEVEL STATE ----------------
    private List<Import__c> imports;
     private string importType;
    private Set<Id> caseIssueIds;
    private Boolean createAssociations;

    private Map<String, Payee__c> payeeMap = new Map<String, Payee__c>();
    private List<Payee_Association__c> associationsToUpsert = new List<Payee_Association__c>();
    private List<Payee__c> payeesToUpsert = new List<Payee__c>();

    // ---------------- CONSTRUCTOR ----------------
    public ProcessDuplicatePayees(
        List<Import__c> imports,
        string  importType,
        Set<Id> caseIssueIds,
        Boolean createAssociations
    ) {
        this.imports = imports != null ? imports : new List<Import__c>();
        this.importType = importType;
        this.caseIssueIds = caseIssueIds != null ? caseIssueIds : new Set<Id>();
        this.createAssociations = createAssociations;
    }

    // ---------------- PUBLIC ENTRY ----------------
    public list<string> processDuplicateEmployees() {
        list<string> errors = new list<string>();
        try{
            
            System.Debug('Processing Duplicate Employees '+imports.size() + ' '+imports);
            if (imports.isEmpty()) return errors;

        payeeMap = loadPayeeMap(imports[0].Unique_Key__c);
        System.Debug('Payee Map Loaded '+payeeMap);
        if (payeeMap.isEmpty()) return errors;

        for (Import__c imp : imports) {
            String uniqueKeyEmp = buildUniqueKey(imp);
            System.debug('Processing Import Record for with Unique Key: ' + uniqueKeyEmp);
            if (!payeeMap.containsKey(uniqueKeyEmp)) continue;
            
            Payee__c matchedPayee = payeeMap.get(uniqueKeyEmp);
            System.debug('Found matching Payee for Import Record: ' + matchedPayee);
            Map<Id, Payee_Association__c> existingAssocMap = getExistingAssocMap(matchedPayee);
            System.debug('Existing Associations for Payee: ' + existingAssocMap);

            if (importType =='Corrective Form 40') {
                handleCorrective(imp, matchedPayee, existingAssocMap);
            } else {
                handleNonCorrective(imp, matchedPayee, existingAssocMap);
            }
        }

        commitChanges();
        
        }catch(Exception e){
            errors.add(e.getMessage() + ' Stack Trace: ' + e.getStackTraceString());
            System.Debug('Exception in ProcessDuplicatePayees '+e.getMessage() + ' '+e.getStackTraceString());
            throw e;
        }
        return errors;
        
    }

    // ---------------- HELPERS ----------------

    private Map<String, Payee__c> loadPayeeMap(String uniqueKey) {
        Import__c initialRecord = [
            SELECT Results__c 
            FROM Import__c 
            WHERE Unique_Key__c = :uniqueKey 
            AND Job_Sequence__c = 0 
            LIMIT 1
        ];
        if (String.isBlank(initialRecord.Results__c)) return new Map<String, Payee__c>();

        ContentVersion cv = [
            SELECT VersionData 
            FROM ContentVersion 
            WHERE ContentDocumentId = :initialRecord.Results__c 
            AND IsLatest = TRUE 
            LIMIT 1
        ];
        return (Map<String, Payee__c>) JSON.deserialize(
            cv.VersionData.toString(), 
            Map<String, Payee__c>.class
        );
    }

    private void handleCorrective(
        Import__c imp,
        Payee__c matchedPayee,
        Map<Id, Payee_Association__c> existingAssocMap
    ) {
        System.Debug('Handling Corrective Import for Payee: ' + matchedPayee.Payee_Name__c);
        Decimal payeeNetWages = matchedPayee.NetWages__c != null ? matchedPayee.NetWages__c : 0;

        if (existingAssocMap.isEmpty()) {
            System.Debug('No existing associations found for Payee.'+' '+matchedPayee.Payee_Name__c);
            if (createAssociations) {
                System.Debug('createAssociations'+' '+createAssociations);
                
                for (Id ci : caseIssueIds) {
                    associationsToUpsert.add(new Payee_Association__c(
                        Case_Issue__c = ci,
                        Payee__c = matchedPayee.Id,
                        Factor__c = imp.Factor__c
                    ));
                }
                payeeNetWages += safeDecimal(imp.Net_Wages_Paid__c);
                System.Debug('Created new associations for Payee.'+' '+matchedPayee.Payee_Name__c);
            } else {
                System.Debug('Not creating associations, just updating Payee Net Wages.'+' '+matchedPayee.Payee_Name__c);
                matchedPayee.NetWages__c = safeDecimal(imp.Net_Wages_Paid__c);
                matchedPayee.Factor__c = imp.Factor__c;
                payeesToUpsert.add(matchedPayee);
                return;
            }
        } else {
            System.Debug('Existing associations found for Payee.'+' '+matchedPayee.Payee_Name__c);
            // Update existing associations to reflect new Factor from corrective import
            Set<Id> updateIds = new Set<Id>(existingAssocMap.keySet());
            updateIds.retainAll(caseIssueIds);

            for (Id ci : updateIds) {
                Payee_Association__c existingAssoc = existingAssocMap.get(ci);
                existingAssoc.Factor__c = imp.Factor__c;
                associationsToUpsert.add(existingAssoc);
            }
            payeeNetWages = safeDecimal(imp.Net_Wages_Paid__c);
            System.Debug('Updated existing associations for Payee.'+' '+matchedPayee.Payee_Name__c);
        }

        matchedPayee.NetWages__c = payeeNetWages;
        matchedPayee.Factor__c = imp.Factor__c;
        payeesToUpsert.add(matchedPayee);
    }

    private void handleNonCorrective(
        Import__c imp,
        Payee__c matchedPayee,
        Map<Id, Payee_Association__c> existingAssocMap
    ) {
        System.Debug('Handling Non-Corrective Import for Payee: ' + matchedPayee.Payee_Name__c);
        Decimal payeeNetWages = matchedPayee.NetWages__c != null ? matchedPayee.NetWages__c : 0;

        Set<Id> newCaseIssueIds = new Set<Id>(caseIssueIds);
        newCaseIssueIds.removeAll(existingAssocMap.keySet());

        if (!newCaseIssueIds.isEmpty()) {
            System.debug('New Case Issues to associate: ' + newCaseIssueIds);
            for (Id ci : newCaseIssueIds) {
                associationsToUpsert.add(new Payee_Association__c(
                    Case_Issue__c = ci,
                    Payee__c = matchedPayee.Id,
                    Factor__c = imp.Factor__c
                ));
            }
            payeeNetWages += safeDecimal(imp.Net_Wages_Paid__c);
            System.Debug('Created new associations for Payee.'+' '+matchedPayee.Payee_Name__c);
        }

        matchedPayee.NetWages__c = payeeNetWages;
        matchedPayee.Factor__c = imp.Factor__c;
        payeesToUpsert.add(matchedPayee);
    }

    private Map<Id, Payee_Association__c> getExistingAssocMap(Payee__c matchedPayee) {
        Map<Id, Payee_Association__c> assocMap = new Map<Id, Payee_Association__c>();
        if (matchedPayee.Payee_Associations__r != null) {
            for (Payee_Association__c assoc : matchedPayee.Payee_Associations__r) {
                assocMap.put(assoc.Case_Issue__c, assoc);
            }
        }
        return assocMap;
    }

    private String buildUniqueKey(Import__c imp) {
        return String.join(new List<String>{
            imp.Employee_Last_Name__c?.trim() ?? '',
            imp.Employee_First_Name__c?.trim() ?? '',
            imp.Employee_Street__c?.trim() ?? '',
            imp.Employee_Zip__c?.trim() ?? ''
        }, ',');
    }

    private Decimal safeDecimal(Decimal inputVal) {
        return (inputVal != null ? inputVal : 0);
    }

    private void commitChanges() {
        if (!associationsToUpsert.isEmpty()) {
            try {
                upsert associationsToUpsert;
                System.debug('Upserted ' + associationsToUpsert.size() + ' Payee_Association__c records.');
            } catch (DmlException e) {
                System.debug('Error during Payee Association DML: ' + e.getMessage());
            }
        }

        if (!payeesToUpsert.isEmpty()) {
            try {
                upsert payeesToUpsert;
                System.debug('Upserted ' + payeesToUpsert.size() + ' Payee__c records.');
            } catch (DmlException e) {
                System.debug('Error during Payee DML: ' + e.getMessage());
            }
        }
    }
}
*/




















// For Teseting


/*
public without sharing class ProcessDuplicatePayees {

    List<Import__c> duplicateimports;
    string importType;
    List<DIR_Violation__c> caseIssueList;
    

    public ProcessDuplicatePayees(List<Import__c> duplicateimports, string importType, List<DIR_Violation__c> caseIssueList) {
        this.duplicateimports = duplicateimports;
        this.importType = importType;
        this.caseIssueList = caseIssueList;

    }

    public lIST<STRING> processDuplicateEmployees() {
        lIST<STRING> errors = new LIST<STRING>();
        try{

            List<Payee__c> payeesToUpdate = new List<Payee__c>();
        string uniqueKey = duplicateimports[0].Unique_Key__c;
        Map<string,Payee__c> payeeMap = loadPayeeMap(uniqueKey);
        for(Import__c imp :duplicateimports){
            string matchingformula = buildUniqueKey(imp);
            Payee__c matchedPayee = payeeMap.get(matchingformula);
            List<PayeeAssociation> associationData =(List<PayeeAssociation>) JSON.deserialize(matchedPayee.Payee_Association_JSON__c,List<PayeeAssociation>.class);
            map<Id,PayeeAssociation> associationMap = new  map<Id,PayeeAssociation>();
            for(PayeeAssociation pa :associationData){
                associationMap.put(pa.caseIssueId,pa);
            }
            for(DIR_Violation__c ci :caseIssueList){
                // new JSON Entry for the Case Issue
                if(!associationMap.containsKey(ci.Id)){
                    PayeeAssociation newassociationData = new PayeeAssociation();
                    assignAssociation(newassociationData,ci,imp);
                    associationMap.put(ci.Id,newassociationData);
                }else{
                    PayeeAssociation existingassociation = associationMap.get(ci.Id);
                    assignAssociation(existingassociation,ci,imp);
                    associationMap.put(ci.Id,existingassociation);
                }
            }

            matchedPayee.Payee_Association_JSON__c = JSON.serialize(associationMap.values());
            matchedPayee.NetWages__c = sumofAssociations(associationMap.values());
            payeesToUpdate.add(matchedPayee);
        }

        Database.Update(payeesToUpdate,false);

        }catch  (Exception e){
            errors.add(e.getMessage() + ' Stack Trace: ' + e.getStackTraceString());
            System.Debug('Exception in ProcessDuplicatePayees '+e.getMessage() + ' '+e.getStackTraceString());
            throw e;
        }
         // Get the JSON on the payees, Then Update fields on the Case Issues
         Set<Id> sendCaseIssueId = new Set<Id>();
       for(DIR_Violation__c ci :caseIssueList){
           sendCaseIssueId.add(ci.Id);
            }
        DirViolationController.updateViolationJsonField(sendCaseIssueId);
        return errors;
        
    }

    private void assignAssociation(PayeeAssociation association,DIR_Violation__c caseIssue,Import__c imp){

        association.caseIssueId = caseIssue.Id;
        association.caseIssueName = caseIssue.Name;
        association.netWages = imp.Net_Wages_Paid__c;
        association.totalWageAssessment = imp.Total_Wage_Assessment__c;
        association.deductionsTotal = imp.Deductions_Total__c;
        association.factor = imp.Factor__c;
        association.citationForm = caseIssue.Violation_Type__r.Violation_Type__c;
        association.violationTypeName = caseIssue.Violation_Type__r.Violation_Type_Name__c;
        Decimal breakdown = caseIssue.Wage_Balance_Due__c * (imp.Factor__c / 100);
        association.caseIssueBreakdown = breakdown.setScale(2, RoundingMode.HALF_UP);
        

    }

    private Decimal sumofAssociations(List<PayeeAssociation> associations){
        Decimal associationSum = 0;
        for(PayeeAssociation association :associations){
            associationSum+=association.caseIssueBreakdown;
        }
        return associationSum;

    }



    private Map<String, Payee__c> loadPayeeMap(String uniqueKey) {
        Import__c initialRecord = [
            SELECT Results__c 
            FROM Import__c 
            WHERE Unique_Key__c = :uniqueKey 
            AND Job_Sequence__c = 0 
            LIMIT 1
        ];
        if (String.isBlank(initialRecord.Results__c)) return new Map<String, Payee__c>();

        ContentVersion cv = [
            SELECT VersionData 
            FROM ContentVersion 
            WHERE ContentDocumentId = :initialRecord.Results__c 
            AND IsLatest = TRUE 
            LIMIT 1
        ];
        return (Map<String, Payee__c>) JSON.deserialize(
            cv.VersionData.toString(), 
            Map<String, Payee__c>.class
        );
    }

    
    private String buildUniqueKey(Import__c imp) {
        return String.join(new List<String>{
            imp.Employee_Last_Name__c?.trim() ?? '',
            imp.Employee_First_Name__c?.trim() ?? '',
            imp.Employee_Street__c?.trim() ?? '',
            imp.Employee_Zip__c?.trim() ?? ''
        }, ',');
    }
}

*/






global without sharing class ProcessDuplicatePayeesBatch implements Database.Batchable<sObject>, Database.Stateful {

    // --- Global Variables ---
    global String caseId { get; set; }
    global String importType { get; set; }
    global Set<Id> caseIssueIds { get; set; }
    global List<String> errorMessages = new List<String>();

    // For tracking results
    global Integer successCount = 0;
    global Integer failureCount = 0;
    global Integer updatedCaseIssues = 0;

    global Map<String, Payee__c> lastLoadedPayeeMap = new Map<String, Payee__c>();
    global Set<Id> checkPayeeIds = new Set<Id>();
    global string uniqueKey;
    global List<DIR_Violation__c> caseIssueList;
    global String errorTable = '';

    global Map<Id, Decimal> caseIssueAmountUtilizedFromPayee = new Map<Id, Decimal>();
    global Map<Integer, String> sendEmailToDuplicate = new Map<Integer, String>();
    global boolean stopBatch = false;
	global boolean isLinkedToAllCaseIssue;

    global Integer batchRunCount = 0;
    global Set<Id> accDeleteIds { get; set; }
    global Set<Id> caseRoleDeleteIds { get; set; }
    global Set<Id> payeeDeleteIds { get; set; }
    global List<Payee__c> oldPayeeRecords = new List<Payee__c>();
    global Map<Id, Payee__c> payeeUpdate = new Map<Id, Payee__c>();

    // Constructor
    public ProcessDuplicatePayeesBatch(
        String caseId,
        String importType,
        Set<Id> caseIssueIds,
        Map<Id, Decimal> caseIssueAmount,
        Map<Integer, String> sendEmailHTML,
        Set<Id> checkPayeeIds,
        string uniqueKey,
        Set<Id> accDeleteIds,
        Set<Id> caseRoleDeleteIds,
        Set<Id> payeeDeleteIds,
        boolean isLinkedToAllCaseIssue

    ) {
        this.importType = importType;
        this.caseIssueIds = caseIssueIds;
        this.caseId = caseId;
        this.caseIssueAmountUtilizedFromPayee = caseIssueAmount;
        this.sendEmailToDuplicate = sendEmailHTML;
        this.checkPayeeIds = checkPayeeIds;
        this.uniqueKey = uniqueKey;
        this.accDeleteIds = accDeleteIds;
        this.caseRoleDeleteIds = caseRoleDeleteIds;
        this.payeeDeleteIds = payeeDeleteIds;
        this.isLinkedToAllCaseIssue = isLinkedToAllCaseIssue;

        // Fetch Case Issues
        this.caseIssueList = [
            SELECT Id, Name, Wage_Balance_Due__c, Amount_Reserved__c, Amount_Utilized_from_Payee__c,
                   Violation_Type__r.Violation_Type_Name__c,
                   Violation_Type__r.Violation_Type__c, Post_Judgment_Interest_for_Wages__c, Post_Citation_Interest_for_Wages__c
            FROM DIR_Violation__c
            WHERE Id IN :caseIssueIds
        ];
    }

    // START METHOD
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Unique_Key__c, Employee_First_Name__c, Employee_Last_Name__c, Has_Matching_Account__c,
                   Employee_Street__c, Employee_Zip__c, Net_Wages_Paid__c, Employee_City__c, Employee_State__c,
                   Total_Wage_Assessment__c, Deductions_Total__c, Factor__c, Job_Sequence__c, Results__c, Direct_Pay__c
            FROM Import__c
            WHERE Case_Management__c = :caseId AND Has_Matching_Account__c = true AND Unique_Key__c =: uniqueKey
        ]);
    }

    // EXECUTE METHOD
    public void execute(Database.BatchableContext bc, List<Import__c> scope) {
        batchRunCount++;
        if (stopBatch) {
            System.debug('Batch stop flag is set. Skipping remaining records.');
            return;
        }


        Savepoint sp = Database.setSavepoint();
        try {
            Map<String, List<Import__c>> importsByUniqueKey = new Map<String, List<Import__c>>();
            for (Import__c imp : scope) {
                if (String.isNotBlank(imp.Unique_Key__c)) {
                    if (!importsByUniqueKey.containsKey(imp.Unique_Key__c)) {
                        importsByUniqueKey.put(imp.Unique_Key__c, new List<Import__c>());
                    }
                    importsByUniqueKey.get(imp.Unique_Key__c).add(imp);
                }
            }

            for (String uniqueKeyimp : importsByUniqueKey.keySet()) {
                List<Import__c> duplicateImports = importsByUniqueKey.get(uniqueKeyimp);

                Boolean hasErrors = false;
                List<Payee__c> payeesToUpdate = new List<Payee__c>();
                /*
                String uniqueKey = duplicateImports[0].Unique_Key__c;

                Map<String, Payee__c> payeeMap = loadPayeeMap(uniqueKey);
                lastLoadedPayeeMap = payeeMap;
*/              set<string> chinkedMatchingKeys = new set<string>();
                map<string,Payee__c> matchedPayeesMap = new Map<string,Payee__c>();
                for(Import__c imp : duplicateImports){
                     String matchingformula = buildUniqueKey(imp);
                     chinkedMatchingKeys.add(matchingformula);
                }
                List<Payee__c> matchingPayees = [SELECT
        Id,
        Name,
        Payee_Name__c,
        Case_Role__c,
        Case_Role__r.Entity__r.AccountMatch__c,
        Payee_Association_JSON__c,
        Direct_Pay__c,
        NetWages__c,
        WageAssessment__c,
        TotalDeductions__c,
        Factor__c,
        Post_Judgment_Interest_for_Wages__c,
        Post_Citation_Interest_for_Wages__c
      FROM Payee__c
      WHERE Case_Management__c = :caseId
       AND Case_Role__r.Entity__r.AccountMatch__c IN : chinkedMatchingKeys];
                if(!matchingPayees.isEmpty() && matchingPayees != null){
                    for(Payee__c p : matchingPayees){
                         matchedPayeesMap.put(p.Case_Role__r.Entity__r.AccountMatch__c.tolowercase(),p);
                    }    
                }
                lastLoadedPayeeMap =  matchedPayeesMap;
                Map<Id, Import__c> payeeToImportMap = new Map<Id, Import__c>();

                for (Import__c imp : duplicateImports) {
                    
                    String matchingformula = buildUniqueKey(imp);
                    Payee__c payee = new Payee__c();
                    Payee__c matchedPayee = matchedPayeesMap.get(matchingformula);
                    
                    System.debug('payeeMap.get(matchingformula) : '+matchedPayeesMap.get(matchingformula));
                    System.debug('payeeMap KeySet: '+matchedPayeesMap.KeySet());
                    System.debug('payeeMap Values: '+matchedPayeesMap.Values());
                    System.debug('payeeMap Key: '+ matchingformula);
                    oldPayeeRecords.add(matchedPayee);
                    if (matchedPayee == null) continue;

                    List<PayeeAssociation> associationData =
                        (List<PayeeAssociation>)
                        JSON.deserialize(matchedPayee.Payee_Association_JSON__c, List<PayeeAssociation>.class);

                    Map<Id, PayeeAssociation> associationMap = new Map<Id, PayeeAssociation>();
                    for (PayeeAssociation pa : associationData) {
                        associationMap.put(pa.caseIssueId, pa);
                    }

                    for (DIR_Violation__c ci : caseIssueList) {
                        if (!associationMap.containsKey(ci.Id)) {
                            PayeeAssociation newAssociation = new PayeeAssociation();
                            assignAssociation(newAssociation, ci, imp, matchedPayee);
                            associationMap.put(ci.Id, newAssociation);
                        } else {
                            PayeeAssociation existing = associationMap.get(ci.Id);
                            assignAssociation(existing, ci, imp, matchedPayee);
                            associationMap.put(ci.Id, existing);
                        }
                    }

                    payee.Id = matchedPayee.Id;
                    payee.Payee_Association_JSON__c = JSON.serialize(associationMap.values());
                    payee.NetWages__c = sumofAssociations(associationMap.values());
                    payee.WageAssessment__c = imp.Total_Wage_Assessment__c;
                    payee.TotalDeductions__c = imp.Deductions_Total__c;
                    payee.Factor__c = imp.Factor__c;
                    payee.Direct_Pay__c = imp.Direct_Pay__c;
                    if(isLinkedToAllCaseIssue){
                    payee.Post_Citation_Interest_for_Wages__c = payeeUpdate.get(matchedPayee.Id).Post_Citation_Interest_for_Wages__c;
                    payee.Post_Judgment_Interest_for_Wages__c = payeeUpdate.get(matchedPayee.Id).Post_Judgment_Interest_for_Wages__c;
                    }
                    
                    payeesToUpdate.add(payee);
                    payeeToImportMap.put(payee.Id, imp);
                }

                if (!payeesToUpdate.isEmpty()) {
                    Database.SaveResult[] results = Database.update(payeesToUpdate, false);


                    for (Integer i = 0; i < results.size(); i++) {
                        Payee__c payee = payeesToUpdate[i];
                        if (results[i].isSuccess()) {
                            successCount++;
                        } else {
                            stopBatch = true;
                            failureCount++;
                            Database.Error error = results[i].getErrors()[0];
                            String ErrorPayeeRecord = 'Payee : ' + error.getMessage();
                            Import__c failedImport = payeeToImportMap.get(payee.Id);
                            System.debug('failedImport :' + failedImport);
                            System.debug('payeeToImportMap.Keyset() :' + payeeToImportMap.Keyset());
                            System.debug('payeeToImportMap.Values() :' + payeeToImportMap.values());

                            if (hasErrors == false) {
                                errorTable =
                                    '<h3 style="color:red;"> An error occurred while processing the following record(s):</h3>' +
                                    '<table border="1" cellpadding="5" cellspacing="0" ' +
                                    'style="border-collapse:collapse; width:100%; font-family:Arial, sans-serif; font-size:13px; background-color:#FFEEEE;">' +
                                    '<tr style="background-color:#F5B7B1; font-weight:bold;">' +
                                    '<th>Employee First Name</th>' +
                                    '<th>Employee Last Name</th>' +
                                    '<th>Employee Street</th>' +
                                    '<th>Employee City</th>' +
                                    '<th>Employee State</th>' +
                                    '<th>Employee Zip</th>' +
                                    '<th>Error</th>' +
                                    '</tr>';
                                hasErrors = true;
                            }
                            errorTable +=
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
                }
                if (stopBatch == true) {
                    Database.rollback(sp);
                }
            }

        } catch (Exception e) {
            stopBatch = true;
            errorMessages.add('Error building records: ' + e.getMessage());
            System.debug('Batch Exception: ' + e.getMessage());
            System.debug('errorMessages : '+ errorMessages);
        }
    }

    // FINISH METHOD - MODIFIED TO USE WRAPPER LIST
    public void finish(Database.BatchableContext bc) {


        If(stopBatch == false){

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
            List<Database.SaveResult> updateCaseIssueResults = Database.update(caseIssueUpdate, true);
            for (Integer i = 0; i < updateCaseIssueResults.size(); i++) {
                if (updateCaseIssueResults[i].isSuccess()) {
                    updatedCaseIssues++;
                } else {
                    Database.Error error = updateCaseIssueResults[i].getErrors()[0];
                    System.debug('Case Issue update failed: ' + error.getMessage());
                }
            }

            System.debug(updatedCaseIssues + ' Case Issue records updated.');

        }
        
        If (stopBatch == true){
            successCount = (batchRunCount - 1) * 200;
        }

        List<DIR_Case__c> DC = [SELECT Case_Number__c FROM DIR_Case__c
            WHERE Id = :caseId limit 1];
        List<Import__c> importsToDelete = new List<Import__c>();

        List<Import__c> csvRecords = [
             SELECT Name, Case_Management__c, Deductions_Federal_Withholding__c,
                    Deductions_Medicare__c, Deductions_Social_Security__c,
                    Deductions_State_Disability_Insurance__c, Deductions_State_Withholding__c,
                    Deductions_Total__c, Employee_City__c, Employee_First_Name__c,
                    Employee_Last_Name__c, Employee_State__c, Employee_Street__c,
                    Employee_Zip__c, Factor__c, Gross_Wages_Paid__c, Net_Wages_Paid__c,
                    Period_Covered_by_Adjustment__c, Total_Wage_Assessment__c
            FROM Import__c
            WHERE Case_Management__c = :caseId
        ];

        for (Import__c importRecord : csvRecords) {
            Boolean deleteRecord = true;
            if (deleteRecord) {
                importsToDelete.add(importRecord);
            }
        }

        // Safely delete processed Import__c records
        if (!importsToDelete.isEmpty()) {
            try {
                delete importsToDelete;
            } catch (DmlException e) {
                errorMessages.add('Error deleting Import__c records: ' + e.getMessage());
                System.debug('Error deleting Import__c records: ' + e.getMessage());
            }
        }
        String nonDMLErrorMessages = '';
        if (errorMessages != null) {
            for (String message : errorMessages) {
                nonDMLErrorMessages += message + '\n';
            }
        }


        String caseLink;

        if (DC != null && !DC.isEmpty() && DC[0].Id != null) {
            String baseUrl = System.Url.getOrgDomainUrl().toExternalForm();
            String caseUrl = baseUrl + '/lightning/r/DIR_Case__c/' + DC[0].Id + '/view';
            String caseNumber = escapeHtml(DC[0].Case_Number__c);
            caseLink = '<a href="' + caseUrl + '" target="_blank">' + caseNumber + '</a>';
        } else {
            caseLink = (DC != null && !DC.isEmpty() ? escapeHtml(DC[0].Case_Number__c) : 'N/A');
        }


        // Build HTML email body
        String htmlBody =
            '<html>' +
            '<head><meta charset="UTF-8"></head>' +
            '<body style="font-family:Arial, sans-serif; font-size:14px; margin:0; padding:0;">';

        if (stopBatch) {
            htmlBody +=
                '<h3 style="color:#C0392B;">⚠️ The batch process was stopped before completion.</h3>';
        } else {
            htmlBody +=
                '<h4 style="color:#2E86C1;">The bulk payee creation process has been completed successfully.</h4>';
        }

        htmlBody +=
            '<h2 style="color:#2E86C1;">Batch Process Summary</h2>' +
            '<table border="0" cellpadding="5" cellspacing="0" style="border-collapse:collapse;">' +
            '<tr><td><b>Case Management:</b></td><td>' +
            (DC != null && !DC.isEmpty() ? caseLink : 'N/A') +
            '</td></tr>' +
            '<tr><td><b>Import Type:</b></td><td>' + escapeHtml(importType) + '</td></tr>' +
            '</table><br/>' +
            '<div style="border:2px solid #0176D3; padding:10px; display:inline-block; border-radius:6px;">' +
            '<table border="0" cellpadding="5" cellspacing="0" style="border-collapse:collapse;">';

        if (stopBatch) {
            htmlBody +=
                sendEmailToDuplicate.get(0) +
                '<tr><td>✅ <b>Payees Updated Successfully:</b></td><td>'+ successCount +'</td></tr>' +
                '<tr><td>❌ <b>Payees Failed to Update:</b></td><td>' + failureCount + '</td></tr>';
        } else {
            htmlBody +=
                sendEmailToDuplicate.get(0) +
                '<tr><td>✅ <b>Payees Updated Successfully:</b></td><td>' + successCount + '</td></tr>' +
                '<tr><td>✅ <b>Payees Failed to Update:</b></td><td>' + failureCount + '</td></tr>';
        }

        htmlBody +=
            '</table>' +
            '</div><br/>' +
            '</body>' +
            '</html>';


        // Add notice if no records were inserted
        List<String> noInsertMsgs = new List<String>();
        if (successCount == 0) noInsertMsgs.add('⚠️ No Payee records were Updated.');
        if(sendEmailToDuplicate.containsKey(1)) noInsertMsgs.add(sendEmailToDuplicate.get(1));

        if (!noInsertMsgs.isEmpty()) {
            htmlBody += '<h4 style="color:#E67E22; margin-bottom: 5px;">⚠️ Summary Notice:</h4>'; // Reduced margin-bottom for better spacing
            htmlBody += '<div style="border: 1px solid #FFD700; padding:10px; background-color:#FFFACD;">';
            for (String msg : noInsertMsgs) {
                htmlBody += '<p style="margin:2px 0;">' + msg + '</p>'; // Ensures tight vertical spacing between messages
            }
            htmlBody += '</div><br/>';
        }

        System.debug('nonDMLErrorMessages :' + nonDMLErrorMessages);
        System.debug('errorMessages : ' + errorMessages);
        if (sendEmailToDuplicate.containsKey(2) || errorTable !='' || nonDMLErrorMessages != '') {

            htmlBody += '<h3 style="color:red; margin-top:20px;">🚨 Payee Update Errors</h3>';
            htmlBody += '<div style="color:red; border: 1px solid red; padding:10px; background-color:#FFEEEE;">' +
                '<pre style="font-family:Arial, sans-serif; white-space: pre-wrap; margin: 0;">';
            htmlBody += nonDMLErrorMessages;
            htmlBody += errorTable;
            htmlBody += '</table>';
             htmlBody +=   '</pre>' +
                '</div>';
            
        } else {
            htmlBody += '<p style="color:green;"><b>No Payee Update Errors 🎉</b></p>';
        }

        htmlBody += '<hr/><p><b>Executed by:</b> ' + UserInfo.getName() + '<br/>' +
            '<b>DateTime:</b> ' + System.now().format('MM/dd/yyyy h:mm a', UserInfo.getTimeZone().getId()) +
            '</p>';
        htmlBody += '</body></html>';

        System.debug('Duplicate Batch job finished for Case Id: ' + caseId);


        If(stopBatch == false || (stopBatch == true && batchRunCount == 1)){
            String userEmail = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Email;
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{userEmail});
            mail.setSubject('Apex Batch Job Completed - Record Update & Insert Summary');
            mail.setHtmlBody(htmlBody);
            mail.setCharset('UTF-8');
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

            System.debug('ProcessDuplicatePayeesBatch completed. Email sent successfully.');
            
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            
            if (results != null && results.size() > 0) {
                if (results[0].isSuccess()) {
                    System.debug('Email sent successfully.');
                } else {
                    System.debug('Email failed: ' + results[0].getErrors()[0].getMessage());
                }
            }

        }
        else {

            Database.executeBatch(new RevertPayeeBatch(oldPayeeRecords, htmlBody, accDeleteIds, caseRoleDeleteIds, payeeDeleteIds), 200);

        }
        System.debug('nonDMLErrorMessages 01 :' + nonDMLErrorMessages);
        System.debug('errorMessages 01 : ' + errorMessages);
        
        if(stopBatch == false && isLinkedToAllCaseIssue == false){
            Set<Id> setOfCaseId = new Set<Id>();
            setOfCaseId.add(caseId);
            IC_RollUpPayeeBatch rollUpPyaee = new IC_RollUpPayeeBatch(setOfCaseId);
            Database.executeBatch(rollUpPyaee, 200);
        }
    }
    
    private void assignAssociation(PayeeAssociation association, DIR_Violation__c caseIssue, Import__c imp, Payee__c matchedPayee) {

        
        If (!payeeUpdate.containsKey(matchedPayee.Id)){
            payeeUpdate.put(matchedPayee.Id, matchedPayee);
        }
        association.caseIssueId = caseIssue.Id;
        association.caseIssueName = caseIssue.Name;
        association.netWages = imp.Net_Wages_Paid__c;
        association.totalWageAssessment = imp.Total_Wage_Assessment__c;
        association.deductionsTotal = imp.Deductions_Total__c;
        association.factor = imp.Factor__c;
        association.citationForm = caseIssue.Violation_Type__r.Violation_Type__c;
        association.violationTypeName = caseIssue.Violation_Type__r.Violation_Type_Name__c;

        Decimal NWBreakdown  = (imp.Net_Wages_Paid__c == null) ? 0 : imp.Net_Wages_Paid__c / caseIssueList.size();
        Decimal TNWBreakdown = (imp.Total_Wage_Assessment__c == null) ? 0 : imp.Total_Wage_Assessment__c / caseIssueList.size();
        Decimal DTBreakdown  = (imp.Deductions_Total__c == null) ? 0 : imp.Deductions_Total__c / caseIssueList.size();

        Decimal CIBreakdown = NWBreakdown;

        association.caseIssueBreakdown = CIBreakdown.setScale(6, RoundingMode.HALF_UP);
        association.netWagesBreakdown = NWBreakdown.setScale(6, RoundingMode.HALF_UP);
        association.totalWageAssessmentBreakdown = TNWBreakdown.setScale(6, RoundingMode.HALF_UP);
        association.deductionsTotalBreakdown = DTBreakdown.setScale(6, RoundingMode.HALF_UP);
        
        
        Decimal percentageshare = imp.Factor__c == null ? imp.Factor__c : 0;   
        Decimal pcinterestShare = (caseIssue.Post_Citation_Interest_for_Wages__c != null ? caseIssue.Post_Citation_Interest_for_Wages__c : 0) * percentageshare;
        Decimal pjinterestShare = (caseIssue.Post_Judgment_Interest_for_Wages__c != null ? caseIssue.Post_Citation_Interest_for_Wages__c : 0) * percentageshare;
        
        System.Debug('Interest Calculated pc '+pcinterestShare);
        System.Debug('Interest Calculated pj '+pjinterestShare);
        
        Decimal pcinterestShareRounded = pcinterestShare.setScale(2, RoundingMode.HALF_UP);
        Decimal pjinterestShareRounded = pjinterestShare.setScale(2, RoundingMode.HALF_UP);
        
        System.Debug('pcInterest After Rounded '+pcinterestShareRounded);
        System.Debug('pjInterest After Rounded '+pjinterestShareRounded); 
        
        Decimal totalCitation = payeeUpdate.get(matchedPayee.Id).Post_Citation_Interest_for_Wages__c == null ? 0 : payeeUpdate.get(matchedPayee.Id).Post_Citation_Interest_for_Wages__c + pcinterestShare;
        Decimal totalJudgment = payeeUpdate.get(matchedPayee.Id).Post_Judgment_Interest_for_Wages__c == null ? 0 : payeeUpdate.get(matchedPayee.Id).Post_Judgment_Interest_for_Wages__c + pjinterestShare;
        
        If (payeeUpdate.containsKey(matchedPayee.Id)){
            Payee__c payee = new Payee__c();
            payee.Id = matchedPayee.Id;
            payee.Post_Citation_Interest_for_Wages__c = totalCitation;
            payee.Post_Judgment_Interest_for_Wages__c = totalJudgment;
            payeeUpdate.put(matchedPayee.Id, payee);
        }
        
        Decimal calculateAmountUtilized = caseIssue.Wage_Balance_Due__c * (imp.Factor__c / 100);
        if(importType == 'Form_40_Partial'){
            calculateAmountUtilized = caseIssue.Amount_Reserved__c * (imp.Factor__c / 100);
        }
        else if (importType == 'Corrective_Form_40'){
            calculateAmountUtilized = caseIssue.Amount_Utilized_from_Payee__c * (imp.Factor__c / 100);
        }
        Decimal amountUtilized = calculateAmountUtilized.setScale(6, RoundingMode.HALF_UP);
        
        Decimal TotalAmount = 0;
        if(caseIssueAmountUtilizedFromPayee.ContainsKey(association.caseIssueId)){
            TotalAmount = caseIssueAmountUtilizedFromPayee.get(association.caseIssueId) + amountUtilized;
            caseIssueAmountUtilizedFromPayee.put(association.caseIssueId, TotalAmount);
        }
        else{
            caseIssueAmountUtilizedFromPayee.put(association.caseIssueId, amountUtilized);
        }
        
        

    }

    // SUM ASSOCIATIONS
    private Decimal sumofAssociations(List<PayeeAssociation> associations) {
        Decimal sum = 0;
        for (PayeeAssociation a : associations) {
            sum += a.caseIssueBreakdown;
        }
        return sum;
    }

    // BUILD UNIQUE KEY
    private String buildUniqueKey(Import__c imp) {
        return String.join(new List<String>{
            imp.Employee_Last_Name__c != null ? imp.Employee_Last_Name__c.trim().toLowerCase() : '',
            imp.Employee_First_Name__c != null ? imp.Employee_First_Name__c.trim().toLowerCase() : '',
            imp.Employee_Street__c != null ? imp.Employee_Street__c.trim().toLowerCase() : '',
            imp.Employee_Zip__c != null ? imp.Employee_Zip__c.trim().toLowerCase() : ''
        }, ',');
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
}