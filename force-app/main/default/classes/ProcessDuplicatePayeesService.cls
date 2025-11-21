public without sharing class ProcessDuplicatePayeesService {
    
    /**
* @description Inner class to hold the results of the processing logic.
*/
    public static String importType;
    public class PayeeProcessingResult {
        public List<Payee__c> updatePayeeRecords { get; set; }
        public Map<Id, Import__c> payeeToImportMap { get; set; }
        public List<Payee__c> oldPayeeRecords { get; set; }
        public List<String> errorMessages { get; set; }
        public PayeeProcessingResult() {
            updatePayeeRecords = new List<Payee__c>();
            payeeToImportMap = new Map<Id, Import__c>();
            oldPayeeRecords = new List<Payee__c>();
            errorMessages = new List<String>();
        }
    }
    
    /**
* @description Entry point for processing duplicate payee imports.
*/
    public static PayeeProcessingResult executeLogic(
        List<Import__c> importRecords, 
        Set<Id> caseIssueIds, 
        String caseId
    ) {
        System.debug('>>> [executeLogic - Static] Start');
        PayeeProcessingResult result = new PayeeProcessingResult();
        
        if (importRecords == null || importRecords.isEmpty() || caseIssueIds == null || caseIssueIds.isEmpty()) {
            return result;
        }
        
        try {
            // 1. Query Case Issues
            List<DIR_Violation__c> caseIssueList = [
                SELECT Id, Name, Violation_Type__r.Violation_Type_Name__c, Violation_Type__r.Violation_Type__c, 
                Post_Judgment_Interest_for_Wages__c, Post_Citation_Interest_for_Wages__c, Amount_Utilized_from_Payee__c, Amount_Reserved__c, Wage_Balance_Due__c
                FROM DIR_Violation__c
                WHERE Id IN :caseIssueIds
            ];
            
            // 2. Generate Matching Keys and Query Matching Payees
            Set<String> chinkedMatchingKeys = new Set<String>();
            for (Import__c imp : importRecords) {
                chinkedMatchingKeys.add(buildUniqueKey(imp));
            }
            
            Map<String, Payee__c> matchedPayeesMap = new Map<String, Payee__c>();
            List<Payee__c> matchingPayees = [
                SELECT Id, Name, Payee_Name__c, Case_Role__c,
                Case_Role__r.Entity__r.AccountMatch__c, Payee_Association_JSON__c, Direct_Pay__c,
                NetWages__c, WageAssessment__c, TotalDeductions__c, Factor__c,
                Post_Judgment_Interest_for_Wages__c, Post_Citation_Interest_for_Wages__c
                FROM Payee__c
                WHERE Case_Management__c = :caseId
                AND Case_Role__r.Entity__r.AccountMatch__c IN :chinkedMatchingKeys
            ];
            
            if (!matchingPayees.isEmpty()) {
                for (Payee__c p : matchingPayees) {
                    matchedPayeesMap.put(p.Case_Role__r.Entity__r.AccountMatch__c.toLowerCase(), p);
                }
            }
            
            //Map<Id, Payee__c> payeeUpdateMap = new Map<Id, Payee__c>(matchedPayeesMap.values());
            
            // 3. Process Imports and Update Payees
            for (Import__c imp : importRecords) {
                String matchingformula = buildUniqueKey(imp);
                Payee__c matchedPayee = matchedPayeesMap.get(matchingformula);
                
                if (matchedPayee == null) continue;
                
                // Call the new helper method to handle the complex per-import processing
                processSingleImport(
                    imp, 
                    matchedPayee, 
                    caseIssueList, 
                    //payeeUpdateMap, 
                    result
                );
            }
        } catch (Exception e) {
            String trace = e.getStackTraceString();
            String firstLine = trace.split('\n')[0];
            
            result.errorMessages.add('General Error : ' + e.getMessage() + ' | Location: ' + firstLine + '\n');
            System.debug('### [ERROR] ' + e.getMessage() + ' | StackTrace: ' + e.getStackTraceString());
        }
        
        System.debug('>>> [executeLogic - Static] End');
        return result;
    }
    
    
    /**
* @description Processes a single Import__c record, updates the corresponding Payee__c associations,
* and populates the result object with the SObject for DML.
*/
    public static void processSingleImport(
        Import__c imp, 
        Payee__c matchedPayee, 
        List<DIR_Violation__c> caseIssueList, 
        //Map<Id, Payee__c> payeeUpdateMap, 
        PayeeProcessingResult result
    ) {
        result.oldPayeeRecords.add(matchedPayee);
        
        // Deserialize existing associations
        List<PayeeAssociation> associationData = new List<PayeeAssociation>();
        if (matchedPayee.Payee_Association_JSON__c != null) {
            associationData = (List<PayeeAssociation>) JSON.deserialize(matchedPayee.Payee_Association_JSON__c, List<PayeeAssociation>.class);
        }
        
        Map<Id, PayeeAssociation> associationMap = new Map<Id, PayeeAssociation>();
        for (PayeeAssociation pa : associationData) {
            associationMap.put(pa.caseIssueId, pa);
        }
        
        System.debug('>>> [processSingleImport] Existing Associations on Payee ' + matchedPayee.Id + ': ' + associationMap.keySet());
        
        // Assign/Update associations for all relevant Case Issues
        for (DIR_Violation__c ci : caseIssueList) {
            PayeeAssociation currentAssociation = associationMap.containsKey(ci.Id) 
                ? associationMap.get(ci.Id) 
                : new PayeeAssociation();
            
            // Assign/Update the association details and also update payeeUpdateMap with accumulated interest
            assignAssociation(currentAssociation, ci, imp, matchedPayee.Id, caseIssueList.size()); //payeeUpdateMap);
            
            associationMap.put(ci.Id, currentAssociation);
        }
        
        // Prepare the Payee record for update
        Payee__c payee = new Payee__c();
        payee.Id = matchedPayee.Id;
        payee.Payee_Association_JSON__c = JSON.serialize(associationMap.values());
        payee.NetWages__c = sumofNetWageTotal(associationMap.values());
        
        // Fields directly taken from the Import__c record
        payee.WageAssessment__c = sumOfTotalWageAssessment(associationMap.values());
        payee.TotalDeductions__c = sumOfDeductionsTotal(associationMap.values());
        payee.Factor__c = imp.Factor__c;
        payee.Direct_Pay__c = imp.Direct_Pay__c;
        
        // Accumulated Interest fields from the payeeUpdateMap
        //if (payeeUpdateMap.containsKey(matchedPayee.Id)) {
        //    Payee__c updatedPayeeState = payeeUpdateMap.get(matchedPayee.Id);
        //    payee.Post_Citation_Interest_for_Wages__c = updatedPayeeState.Post_Citation_Interest_for_Wages__c;
        //    payee.Post_Judgment_Interest_for_Wages__c = updatedPayeeState.Post_Judgment_Interest_for_Wages__c;
        // }
        
        result.updatePayeeRecords.add(payee);
        result.payeeToImportMap.put(payee.Id, imp);
        System.debug('>>> [processSingleImport] Prepared Payee Update: ' + payee);
    }
    
    // --- Private Static Helper Methods (Kept from previous version) ---
    
    private static void assignAssociation(
        PayeeAssociation association, 
        DIR_Violation__c caseIssue, 
        Import__c imp, 
        Id payeeId, 
        Integer totalCaseIssues 
        // Map<Id, Payee__c> payeeUpdateMap
    ) {
        // ... (Implementation remains the same) ...
        System.debug('>>> [assignAssociation] Start for CaseIssue: ' + caseIssue.Id + ' | Payee: ' + payeeId);
        
        association.caseIssueId = caseIssue.Id;
        association.caseIssueName = caseIssue.Name;
        association.factor = imp.Factor__c;
        association.citationForm = caseIssue.Violation_Type__r.Violation_Type__c;
        association.violationTypeName = caseIssue.Violation_Type__r.Violation_Type_Name__c;
		//association.isPartial = importType == 'Form_40_Partial' ? true :false; 
        
        Decimal NWBreakdown = (imp.Net_Wages_Paid__c == null) ? 0 : imp.Net_Wages_Paid__c / totalCaseIssues;
        Decimal TNWBreakdown = (imp.Total_Wage_Assessment__c == null) ? 0 : imp.Total_Wage_Assessment__c / totalCaseIssues;
        Decimal DTBreakdown = (imp.Deductions_Total__c == null) ? 0 : imp.Deductions_Total__c / totalCaseIssues;
        
        if((importType == 'Form_40_Partial' || importType == 'Form_40') && association.isPartial == true){
       association.caseIssueBreakdown+= NWBreakdown.setScale(6, RoundingMode.HALF_UP);
        association.netWagesBreakdown+= NWBreakdown.setScale(6, RoundingMode.HALF_UP);
        association.totalWageAssessmentBreakdown+= TNWBreakdown.setScale(6, RoundingMode.HALF_UP);
        association.deductionsTotalBreakdown+= DTBreakdown.setScale(6, RoundingMode.HALF_UP);
        
        }else{
            association.caseIssueBreakdown = NWBreakdown.setScale(6, RoundingMode.HALF_UP);
        association.netWagesBreakdown = NWBreakdown.setScale(6, RoundingMode.HALF_UP);
        association.totalWageAssessmentBreakdown = TNWBreakdown.setScale(6, RoundingMode.HALF_UP);
        association.deductionsTotalBreakdown = DTBreakdown.setScale(6, RoundingMode.HALF_UP);
        
        }
        
        
        /*
Decimal percentageshare = imp.Factor__c == null ? 0 : imp.Factor__c;
Decimal pcinterestShare = (caseIssue.Post_Citation_Interest_for_Wages__c != null ? caseIssue.Post_Citation_Interest_for_Wages__c : 0) * percentageshare;
Decimal pjinterestShare = (caseIssue.Post_Judgment_Interest_for_Wages__c != null ? caseIssue.Post_Judgment_Interest_for_Wages__c : 0) * percentageshare;

Payee__c currentPayeeState = payeeUpdateMap.get(payeeId);
Decimal currentCitation = currentPayeeState.Post_Citation_Interest_for_Wages__c != null ? currentPayeeState.Post_Citation_Interest_for_Wages__c : 0;
Decimal currentJudgment = currentPayeeState.Post_Judgment_Interest_for_Wages__c != null ? currentPayeeState.Post_Judgment_Interest_for_Wages__c : 0;

Decimal totalCitation = currentCitation + pcinterestShare;
Decimal totalJudgment = currentJudgment + pjinterestShare;

currentPayeeState.Post_Citation_Interest_for_Wages__c = totalCitation;
currentPayeeState.Post_Judgment_Interest_for_Wages__c = totalJudgment;
payeeUpdateMap.put(payeeId, currentPayeeState);

System.debug('>>> [assignAssociation] Updated Payee Interest - Citation: ' + totalCitation + ' | Judgment: ' + totalJudgment);
*/
    }
    
    private static Decimal sumOfTotalWageAssessment(List<PayeeAssociation> associations) {
        Decimal sum = 0;
        for (PayeeAssociation a : associations) {
            sum += a.totalWageAssessmentBreakdown;
        }
        return sum.setScale(2, RoundingMode.HALF_UP);
    }
    
    private static Decimal sumOfDeductionsTotal(List<PayeeAssociation> associations) {
        Decimal sum = 0;
        for (PayeeAssociation a : associations) {
            sum += a.deductionsTotalBreakdown;
        }
        return sum.setScale(2, RoundingMode.HALF_UP);
    }
    
    private static Decimal sumofNetWageTotal(List<PayeeAssociation> associations) {
        Decimal sum = 0;
        for (PayeeAssociation a : associations) {
            
            
            sum += a.netWagesBreakdown;
        }
        return sum.setScale(2, RoundingMode.HALF_UP);
    }
    
    private static String buildUniqueKey(Import__c imp) {
        String key = String.join(new List<String>{
            imp.Employee_Last_Name__c != null ? imp.Employee_Last_Name__c.trim().toLowerCase() : '',
                imp.Employee_First_Name__c != null ? imp.Employee_First_Name__c.trim().toLowerCase() : '',
                    imp.Employee_Street__c != null ? imp.Employee_Street__c.trim().toLowerCase() : '',
                        imp.Employee_Zip__c != null ? imp.Employee_Zip__c.trim().toLowerCase() : ''
                            }, ',');
        return key;
    }
}