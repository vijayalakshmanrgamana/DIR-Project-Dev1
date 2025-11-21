public without  sharing class PayeeAssociation {
    
    public PayeeAssociation(){
        this.caseIssueBreakdown = 0;
        this.netWagesBreakdown = 0;
        this.totalWageAssessmentBreakdown = 0;
        this.deductionsTotalBreakdown = 0;
        this.isPartial = false;
    }
    
    @AuraEnabled public Id caseIssueId { get; set; }
    @AuraEnabled public string caseIssueName { get; set; }
    @AuraEnabled public Decimal factor { get; set; }
    @AuraEnabled public Decimal caseIssueBreakdown { get; set; }
    @AuraEnabled public String citationForm { get; set; }
    @AuraEnabled public String violationTypeName { get; set; }
    @AuraEnabled public Decimal netWagesBreakdown { get; set; }
    @AuraEnabled public Decimal totalWageAssessmentBreakdown { get; set; }
    @AuraEnabled public Decimal deductionsTotalBreakdown { get; set; }
    @AuraEnabled public Boolean isPartial { get; set; } // boolean flag that lets the system know that the Case Issue is associated to Payee by Partial Amount (Amount_Reserved__c) So that if the Payee is been uploaded again through normal form 40 or Partial fdorm 40 linking to same Case Issue system adds up the breakdow Amount 
    
    
}