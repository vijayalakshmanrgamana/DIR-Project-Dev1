public without sharing class ProcessDuplicatePayeesService {
    
    /**
    * @description Static variable to determine the type of import being processed.
    */
    public static String importType;
	public static Decimal sumOfTotalNetWage = 0;
    public static Decimal totalWageFactor = 0;
    /**
    * @description Inner class to hold the results of the processing logic, including records for DML operations.
    */
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
    * @description Entry point for processing duplicate payee imports by matching them to existing Payee records.
    * @param importRecords List of Import__c records to process.
    * @param caseIssueIds Set of DIR_Violation__c IDs associated with the imports.
    * @param caseId The ID of the parent Case_Management__c record.
    * @return PayeeProcessingResult containing lists of records to update and any error messages.
    */
    public static PayeeProcessingResult executeLogic(
        List<Import__c> importRecords, 
        Set<Id> caseIssueIds, 
        String caseId
    ) {
        System.debug('>>> [executeLogic] Start processing for Case ID: ' + caseId);
        PayeeProcessingResult result = new PayeeProcessingResult();
        
        if (importRecords == null || importRecords.isEmpty() || caseIssueIds == null || caseIssueIds.isEmpty()) {
            System.debug('>>> [executeLogic] No records or case issues provided. Returning empty result.');
            return result;
        }
        
        try {
            // 1. Query Case Issues (DIR_Violation__c) to get necessary breakdown fields.
            List<DIR_Violation__c> caseIssueList = [
                SELECT Id, Name, Wage_Balance_Due__c, Amount_Reserved__c, Amount_Utilized_from_Payee__c, Wages_Due__c, Total_Wage_Interest_Amount__c,
                Violation_Type__r.Violation_Type_Name__c, Violation_Type__r.Violation_Type__c, Post_Judgment_Interest_for_Wages__c, Post_Citation_Interest_for_Wages__c
                FROM DIR_Violation__c
                WHERE Id IN :caseIssueIds
            ];
            System.debug('>>> [executeLogic] Found ' + caseIssueList.size() + ' Case Issues.');
            
            
         AggregateResult[] results = [
            SELECT SUM(Total_Wage_Assessment__c) sumOfTotalNetWages
            FROM Import__c
            WHERE Case_Management__c = :caseId 
              AND Job_Sequence__c = NULL
        ];
        
        if (results.size() > 0) {
             sumOfTotalNetWage = (Decimal) results[0].get('sumOfTotalNetWages');
        }
            
            // 2. Generate Matching Keys from Import records and Query Matching Payees
            Set<String> chinkedMatchingKeys = new Set<String>();
            for (Import__c imp : importRecords) {
                chinkedMatchingKeys.add(buildUniqueKey(imp));
            }
            
            Map<String, Payee__c> matchedPayeesMap = new Map<String, Payee__c>();
            List<Payee__c> matchingPayees = [
                SELECT Id, Name, Payee_Name__c, Case_Role__c,
                Case_Role__r.Entity__r.AccountMatch__c, Payee_Association_JSON__c, Direct_Pay__c,
                NetWages__c, WageAssessment__c, TotalDeductions__c, Factor__c,
                Post_Judgment_Interest_for_Wages__c, Post_Citation_Interest_for_Wages__c, PeriodCovered__c
                FROM Payee__c
                WHERE Case_Management__c = :caseId
                AND Case_Role__r.Entity__r.AccountMatch__c IN :chinkedMatchingKeys
            ];
            
            if (!matchingPayees.isEmpty()) {
                for (Payee__c p : matchingPayees) {
                    // Populate map with lower-cased AccountMatch key
                    matchedPayeesMap.put(p.Case_Role__r.Entity__r.AccountMatch__c.toLowerCase(), p);
                }
            }
            System.debug('>>> [executeLogic] Found ' + matchingPayees.size() + ' matching Payee records.');
            
            // 3. Process Imports and Update Payees
            for (Import__c imp : importRecords) {
                String matchingformula = buildUniqueKey(imp);
                Payee__c matchedPayee = matchedPayeesMap.get(matchingformula);
                
                if (matchedPayee == null) {
                    System.debug('>>> [executeLogic] No matching Payee found for Import: ' + imp.Id);
                    continue;
                }
                
                // Call helper method to handle the complex per-import processing logic
                processSingleImport(
                    imp, 
                    matchedPayee, 
                    caseIssueList, 
                    result
                );
            }
        } catch (Exception ex) {
            String trace = ex.getStackTraceString();
            String firstLine = trace.split('\n')[0];
            
            String errorMsg = 'Error in ProcessDuplicatePayeesService while retrieving Import and Case Issue records: ' +
                ex.getMessage() +
                ' | Location: ' + firstLine +
                ' | Stack Trace: ' + trace;
            
            result.errorMessages.add(errorMsg);
            
            // Log the error using the BatchEmailService
            BatchEmailService.logError(ex);
            
            System.debug('### [ERROR] ProcessDuplicatePayeesService: ' + ex.getMessage());
            System.debug('### [TRACE] ' + trace);
        }

        
        System.debug('>>> [executeLogic] End. Payees to update: ' + result.updatePayeeRecords.size());
        return result;
    }
    
    
    /**
    * @description Processes a single Import__c record, updates the corresponding Payee__c associations,
    * and populates the result object with the SObject for DML.
    * @param imp The current Import__c record.
    * @param matchedPayee The existing Payee__c record to update.
    * @param caseIssueList List of related DIR_Violation__c records.
    * @param result The result object to populate with the updated Payee__c record.
    */
    public static void processSingleImport(
        Import__c imp, 
        Payee__c matchedPayee, 
        List<DIR_Violation__c> caseIssueList, 
        PayeeProcessingResult result
    ) {
        // Store the original record state before modifications
        result.oldPayeeRecords.add(matchedPayee);
        
        // Deserialize existing associations from the Payee record
        List<PayeeAssociation> associationData = new List<PayeeAssociation>();
        if (matchedPayee.Payee_Association_JSON__c != null && importType != 'Corrective_Form_40') {
            associationData = (List<PayeeAssociation>) JSON.deserialize(matchedPayee.Payee_Association_JSON__c, List<PayeeAssociation>.class);
        }
        
        Map<Id, PayeeAssociation> associationMap = new Map<Id, PayeeAssociation>();
        for (PayeeAssociation pa : associationData) {
            associationMap.put(pa.caseIssueId, pa);
        }
        
        System.debug('>>> [processSingleImport] Existing Associations on Payee ' + matchedPayee.Id + ': ' + associationMap.keySet());
        
        // Assign/Update associations for all relevant Case Issues
        for (DIR_Violation__c ci : caseIssueList) {
            // Get existing or create new association object
            PayeeAssociation currentAssociation = associationMap.containsKey(ci.Id) 
                ? associationMap.get(ci.Id) 
                : new PayeeAssociation();
            
            // Assign/Update the association details based on the Import and Case Issue
            assignAssociation(currentAssociation, ci, imp, matchedPayee.Id, caseIssueList.size());
            
            associationMap.put(ci.Id, currentAssociation);
        }
        
        // Prepare the Payee record for update
        Payee__c payee = new Payee__c();
        payee.Id = matchedPayee.Id;
        // Serialize the updated associations back into the JSON field
        payee.Payee_Association_JSON__c = JSON.serialize(associationMap.values());
        
        // Update summary fields on the Payee record by summing the association breakdowns
        payee.NetWages__c = sumofNetWageTotal(associationMap.values());
        payee.WageAssessment__c = sumOfTotalWageAssessment(associationMap.values());
        payee.TotalDeductions__c = sumOfDeductionsTotal(associationMap.values());

        // Fields directly taken from the Import__c record
        payee.Factor__c = imp.Factor__c;
        payee.Direct_Pay__c = imp.Direct_Pay__c;
        payee.PeriodCovered__c = imp.Period_Covered_by_Adjustment__c;
        
        // Add the Payee record to the result list for DML
        result.updatePayeeRecords.add(payee);
        result.payeeToImportMap.put(payee.Id, imp);
        System.debug('>>> [processSingleImport] Prepared Payee Update: ' + payee.Id + ' with new NetWages: ' + payee.NetWages__c);
    }
    
    
    // --- Private Static Helper Methods ---
    
    /**
    * @description Assigns/updates breakdown values and metadata for a single PayeeAssociation based on Import and Case Issue data.
    * @param association The PayeeAssociation object to update.
    * @param caseIssue The DIR_Violation__c record.
    * @param imp The Import__c record.
    * @param payeeId The ID of the parent Payee__c record.
    * @param totalCaseIssues Total number of related Case Issues for breakdown calculation.
    */
    private static void assignAssociation(
        PayeeAssociation association, 
        DIR_Violation__c caseIssue, 
        Import__c imp, 
        Id payeeId, 
        Integer totalCaseIssues 
    ) {
        System.debug('>>> [assignAssociation] Start for CaseIssue: ' + caseIssue.Id + ' | Payee: ' + payeeId);
        
        // Assign metadata fields
        association.caseIssueId = caseIssue.Id;
        association.caseIssueName = caseIssue.Name;
        association.factor = imp.Factor__c;
        association.citationForm = caseIssue.Violation_Type__r.Violation_Type__c;
        association.violationTypeName = caseIssue.Violation_Type__r.Violation_Type_Name__c;
        
        Decimal wageInterestatCitation = caseIssue.Total_Wage_Interest_Amount__c != null ? caseIssue.Total_Wage_Interest_Amount__c : 0;
        Decimal wagesDue = caseIssue.Wages_Due__c != 0 ? caseIssue.Wages_Due__c : 0;
        Decimal totalWagesDue = wageInterestatCitation + wagesDue;
        totalWageFactor = (imp.Total_Wage_Assessment__c/sumOfTotalNetWage)*100;

        Decimal calculateAmountUtilized = 0 ;
        Decimal wageBalanceDue = (caseIssue.Wage_Balance_Due__c != null) ? caseIssue.Wage_Balance_Due__c : 0;
        Decimal amountReserved = (caseIssue.Amount_Reserved__c != null) ? caseIssue.Amount_Reserved__c : 0;
        Decimal amountUtilizedFromPayee = (caseIssue.Amount_Utilized_from_Payee__c != null) ? caseIssue.Amount_Utilized_from_Payee__c : 0;
        
        if (importType == 'Form_40') {
            calculateAmountUtilized = totalWagesDue - amountUtilizedFromPayee;
            
        } 
        else if (importType == 'Form_40_Partial' && (amountUtilizedFromPayee == totalWagesDue || amountReserved + amountUtilizedFromPayee > totalWagesDue)){
            calculateAmountUtilized = totalWagesDue - amountUtilizedFromPayee;
            System.debug('DR Dev: Form_40_Partial : ' + calculateAmountUtilized);
        }
        else if (importType == 'Form_40_Partial'){
            calculateAmountUtilized = amountReserved;
        }
        else if (importType == 'Corrective_Form_40') {
            
            calculateAmountUtilized = (amountReserved != 0)
                ? amountUtilizedFromPayee
                : totalWagesDue;
        }
        
        // Calculate breakdown amounts (evenly distributed across all case issues)
        Decimal NWBreakdown = (imp.Net_Wages_Paid__c == null) ? 0 : imp.Net_Wages_Paid__c / totalCaseIssues;
        Decimal TNWBreakdown = (imp.Total_Wage_Assessment__c == null) ? 0 : imp.Total_Wage_Assessment__c / totalCaseIssues;
        Decimal DTBreakdown = (imp.Deductions_Total__c == null) ? 0 : imp.Deductions_Total__c / totalCaseIssues;
        Decimal CIBreakdown   = calculateAmountUtilized*(totalWageFactor/100); // Assuming CIBreakdown is NWBreakdown
        
        
        System.debug('DR Dev: totalWageFactor : ' + totalWageFactor);
        System.debug('DR Dev: sumOfTotalNetWage : ' + sumOfTotalNetWage);
		System.debug('DR Dev: calculateAmountUtilized : ' + calculateAmountUtilized);

        if(importType != 'Corrective_Form_40'){
            // Accumulate amounts for partial forms
            association.caseIssueBreakdown+= CIBreakdown.setScale(6, RoundingMode.HALF_UP);
            association.netWagesBreakdown+= NWBreakdown.setScale(6, RoundingMode.HALF_UP);
            association.totalWageAssessmentBreakdown+= TNWBreakdown.setScale(6, RoundingMode.HALF_UP);
            association.deductionsTotalBreakdown+= DTBreakdown.setScale(6, RoundingMode.HALF_UP);
            
        }else{
            // Set new amounts
            association.caseIssueBreakdown = CIBreakdown.setScale(6, RoundingMode.HALF_UP);
            association.netWagesBreakdown = NWBreakdown.setScale(6, RoundingMode.HALF_UP);
            association.totalWageAssessmentBreakdown = TNWBreakdown.setScale(6, RoundingMode.HALF_UP);
            association.deductionsTotalBreakdown = DTBreakdown.setScale(6, RoundingMode.HALF_UP);
            
        }
        
        System.debug('>>> [assignAssociation] Association breakdown set for ' + caseIssue.Id);
    }
    
    /**
    * @description Sums the totalWageAssessmentBreakdown from all PayeeAssociation records.
    * @param associations List of PayeeAssociation records.
    * @return Decimal The total wage assessment, rounded to 2 decimal places.
    */
    private static Decimal sumOfTotalWageAssessment(List<PayeeAssociation> associations) {
        Decimal sum = 0;
        for (PayeeAssociation a : associations) {
            sum += a.totalWageAssessmentBreakdown;
        }
        return sum.setScale(2, RoundingMode.HALF_UP);
    }
    
    /**
    * @description Sums the deductionsTotalBreakdown from all PayeeAssociation records.
    * @param associations List of PayeeAssociation records.
    * @return Decimal The total deductions, rounded to 2 decimal places.
    */
    private static Decimal sumOfDeductionsTotal(List<PayeeAssociation> associations) {
        Decimal sum = 0;
        for (PayeeAssociation a : associations) {
            sum += a.deductionsTotalBreakdown;
        }
        return sum.setScale(2, RoundingMode.HALF_UP);
    }
    
    /**
    * @description Sums the netWagesBreakdown from all PayeeAssociation records.
    * @param associations List of PayeeAssociation records.
    * @return Decimal The total net wages, rounded to 2 decimal places.
    */
    private static Decimal sumofNetWageTotal(List<PayeeAssociation> associations) {
        Decimal sum = 0;
        for (PayeeAssociation a : associations) {
            sum += a.netWagesBreakdown;
        }
        return sum.setScale(2, RoundingMode.HALF_UP);
    }
    
    /**
    * @description Builds a unique matching key string based on employee identifying information from the Import record.
    * @param imp The Import__c record.
    * @return String The unique key (LastName, FirstName, Street, Zip).
    */
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