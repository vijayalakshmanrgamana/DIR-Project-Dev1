public without  sharing class PayeeAssociation {
    
     @AuraEnabled public Id caseIssueId { get; set; }
     @AuraEnabled public string caseIssueName { get; set; }
     @AuraEnabled public Decimal netWages { get; set; }
     @AuraEnabled public Decimal totalWageAssessment { get; set; }
     @AuraEnabled public Decimal deductionsTotal { get; set; }
     @AuraEnabled public Decimal factor { get; set; }
     @AuraEnabled public Decimal caseIssueBreakdown { get; set; }
     @AuraEnabled public String citationForm { get; set; }
     @AuraEnabled public String violationTypeName { get; set; }
	 @AuraEnabled public Decimal netWagesBreakdown { get; set; }
     @AuraEnabled public Decimal totalWageAssessmentBreakdown { get; set; }
     @AuraEnabled public Decimal deductionsTotalBreakdown { get; set; }
     @AuraEnabled public Decimal vijay { get; set; }

   
}