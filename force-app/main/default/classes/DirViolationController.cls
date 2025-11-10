public with sharing class DirViolationController {

    // Inner class to match the structure of the JSON array elements
    public class PayeeAssociation {
        public Decimal netWages;
        public Decimal factor;
        public String citationForm;
        public String caseIssueId; // This is the ID we're matching
        public Decimal caseIssueBreakdown;
        public String payeeId;
        public String payeeName;
    }
    public static void updateViolationJsonField(Set<Id> caseIssueIds, Set<Id> checkPayeeIds) { 
      
        Map<Id, String> deletePayeeRecords = new Map<Id, String>();
        Map<Id, String> checkPayeeIdRecords = new Map<Id, String>();
        
        List<DIR_Violation__c> DIRCaseId = [SELECT Id, Case__c FROM DIR_Violation__c WHERE Id =: caseIssueIds];
        List<Payee__c> payees = [
            SELECT Id, Payee_Association_JSON__c, Name, Payee_Name__c 
            FROM Payee__c
            WHERE Case_Management__c =:  DIRCaseId[0].Case__c
            LIMIT 50000 
        ];
        
        List<Payee__c> payeeRecords = [ SELECT Id, Payee_Association_JSON__c, Name, Payee_Name__c 
            FROM Payee__c
            WHERE Id =: checkPayeeIds
            LIMIT 50000 
        ];
        for(Id violationId : caseIssueIds){
        // 1. Prepare the search ID
        String caseIssueId = String.valueOf(violationId);

        System.debug(DIRCaseId);
        // 2. Query for Payee__c records. (Using your existing SOQL filter)

		System.debug('Developer VR : '+payees);
        for(Payee__c pay : payees){
            System.debug('Developer VR : '+pay.Name);
            System.debug('Developer VR : '+pay.Payee_Association_JSON__c);
        }
            
            
            
            for(Payee__c payee : payeeRecords){
                checkPayeeIdRecords.put(payee.Id, payee.Payee_Name__c);
            }
            
            
            
            
        // *** CHANGE 1: Initialize a List to hold ALL matching objects ***
        List<PayeeAssociation> matchedAssociations = new List<PayeeAssociation>();
        Map<Id, Decimal> caseIssueTotalAmount = new Map<Id, Decimal>();
        Map<Id, Decimal> caseIssueTotalFactor = new Map<Id, Decimal>();
        // 3. Iterate through all Payee__c records and parse the JSON.
        for (Payee__c payee : payees) {
            
            // Optimization for Long Text Area: check for the ID before parsing
            // This is optional but highly recommended for performance
            String jsonString = payee.Payee_Association_JSON__c;
            String searchString = '"caseIssueId":"' + caseIssueId + '"';
System.debug('Developer VR : '+ payee.Name);
            System.debug('Developer VR : '+ payee.Payee_Association_JSON__c);
            if (jsonString != null && jsonString.contains(searchString)) {
                try {
                    // Deserialize the JSON string into a List of the inner class
                    List<PayeeAssociation> associations = (List<PayeeAssociation>) JSON.deserialize(
                        jsonString, 
                        List<PayeeAssociation>.class
                    );

                    // 4. Look for all matching caseIssueId elements
                    for (PayeeAssociation association : associations) {
                        if (association.caseIssueId == caseIssueId) {
                            // *** CHANGE 2: Add the matching object to the list ***
                            association.payeeId = payee.id;
                            association.payeeName = payee.Payee_Name__c;
                            deletePayeeRecords.put(payee.id, payee.Payee_Name__c);
                            matchedAssociations.add(association);
                            
                            /*
                            Decimal TotalAmount = 0;
                            if(caseIssueTotalAmount.ContainsKey(association.caseIssueId)){
                                TotalAmount = caseIssueTotalAmount.get(association.caseIssueId) + association.caseIssueBreakdown;
                                caseIssueTotalAmount.put(association.caseIssueId, TotalAmount);
                            }
                            else{
                                caseIssueTotalAmount.put(association.caseIssueId, association.caseIssueBreakdown);
                            }
                            
                            Decimal TotalFactor = 0;
                            if(caseIssueTotalFactor.ContainsKey(association.caseIssueId)){
                                TotalFactor = caseIssueTotalFactor.get(association.caseIssueId) + association.factor;
                                caseIssueTotalFactor.put(association.caseIssueId, TotalFactor);
                            }
                            else{
                                caseIssueTotalFactor.put(association.caseIssueId, association.factor);
                            }
*/
                            break;
                            // DO NOT break here, continue searching the rest of the array 
                            // in case the ID appears multiple times in the same JSON string.
                        }
                    }
                    // DO NOT break the outer loop, continue searching other Payee__c records.
                    

                } catch (Exception e) {
                    // Log or handle JSON parsing errors if needed
                    System.debug('Error parsing JSON for Payee: ' + payee.Id + '. Error: ' + e.getMessage());
                }
            }
        }
        
        // 5. Update the DIR_Violation__c record
        // *** CHANGE 3: Check if the list is NOT empty ***

        if (!matchedAssociations.isEmpty()) {
            // Serialize the list, which creates a JSON Array string: [...]
            String jsonToStore = JSON.serialize(matchedAssociations);
            
            DIR_Violation__c violationToUpdate = new DIR_Violation__c(Id = violationId);
            violationToUpdate.For_Testing_JSON__c = jsonToStore;
            // violationToUpdate.Amount_Utilized_from_Payee__c = caseIssueTotalAmount.get(violationId);
            // violationToUpdate.Total_Factor__c = caseIssueTotalFactor.get(violationId);
            
            try {
                update violationToUpdate;
                System.debug('Success: Matched JSON Array stored in For_Testing_JSON__c.');
            } catch (DmlException e) {
                // Correct error handling for DmlException
                System.debug('Error: Could not update DIR_Violation__c. Error: ' + e.getMessage());
            }
        } else {
            String jsonToStore = JSON.serialize(matchedAssociations);
            
            DIR_Violation__c violationToUpdate = new DIR_Violation__c(Id = violationId);
            violationToUpdate.For_Testing_JSON__c = jsonToStore;
            
            try {
                 update violationToUpdate;
            } catch (DmlException e) {
                // Correct error handling for DmlException
            }
            System.debug('Failure: No matching caseIssueId found in any Payee_Association_JSON__c.');
        }
        }
        
        Map<Id, String> payeeRecordsAreDeleteMap = new Map<Id, String>();
        
             Set<Id> setPayeeRecordsDeletedIds = new Set<Id>();
        for(Id deletePayeeRecord : deletePayeeRecords.KeySet()){
            if(!checkPayeeIdRecords.containsKey(deletePayeeRecord)){
                setPayeeRecordsDeletedIds.add(deletePayeeRecord);
               payeeRecordsAreDeleteMap.put(deletePayeeRecord, checkPayeeIdRecords.get(deletePayeeRecord));
            }
        }
        
        
        
        
        List<Payee__c> listPayeeRecordsDeleted = [SELECT Id, Payee_Association_JSON__c, Name, Payee_Name__c 
            FROM Payee__c
            WHERE Id =: setPayeeRecordsDeletedIds
            LIMIT 50000  ];
        
        // Delete Payee records safely with partial success handling
            List<Database.DeleteResult> deletePayeeResults = Database.delete(listPayeeRecordsDeleted, false);
            
            Integer deletedPayees = 0;
            
            for (Integer i = 0; i < deletePayeeResults.size(); i++) {
                if (deletePayeeResults[i].isSuccess()) {
                    deletedPayees++;
                    System.debug('✅ Successfully deleted Payee record: ' + listPayeeRecordsDeleted[i].Id);
                } else {
                    // Handle individual delete errors
                    for (Database.Error error : deletePayeeResults[i].getErrors()) {
                        System.debug('❌ Failed to delete Payee record: ' + listPayeeRecordsDeleted[i].Id +
                                     ' | Error: ' + error.getMessage());
                    }
                }
            }
            
            System.debug('Total deleted Payee records: ' + deletedPayees);
            
// ===============================
// 📧 EMAIL LOGIC AFTER PROCESSING
// ===============================

try {
    // -------------------------------
    // Deleted Payee Records Table
    // -------------------------------
    String deleteTable = '<table border="1" cellpadding="5" style="border-collapse:collapse; min-width:300px;">' +
                         '<tr><th colspan="3" style="background-color:#f2f2f2;">Deleted Payee Records</th></tr>' +
                         '<tr><th>No</th><th>Payee Id</th><th>Payee Name</th></tr>';
    Integer delCount = 1;
    for (String key : deletePayeeRecords.keySet()) {
        deleteTable += '<tr><td>' + delCount + '</td><td>' + key + '</td><td>' + deletePayeeRecords.get(key) + '</td></tr>';
        delCount++;
    }
    deleteTable += '</table>';

    // -------------------------------
    // Checked Payee Records Table
    // -------------------------------
    String checkTable = '<table border="1" cellpadding="5" style="border-collapse:collapse; min-width:300px;">' +
                        '<tr><th colspan="3" style="background-color:#f2f2f2;">Checked Payee Records</th></tr>' +
                        '<tr><th>No</th><th>Payee Id</th><th>Payee Name</th></tr>';
    Integer chkCount = 1;
    for (String key : checkPayeeIdRecords.keySet()) {
        checkTable += '<tr><td>' + chkCount + '</td><td>' + key + '</td><td>' + checkPayeeIdRecords.get(key) + '</td></tr>';
        chkCount++;
    }
    checkTable += '</table>';

    // -------------------------------
    // Combine Deleted & Checked Tables (Side-by-Side)
    // -------------------------------
    String combinedTables = '<table style="width:100%; border:none;"><tr>' +
                            '<td valign="top" style="width:50%;">' + deleteTable + '</td>' +
                            '<td valign="top" style="width:50%;">' + checkTable + '</td>' +
                            '</tr></table><br/>';

    // -------------------------------
    // Payee Records Are Delete Map Table (Printed Last)
    // -------------------------------
    String payeeDeleteMapTable = '<table border="1" cellpadding="5" style="border-collapse:collapse; width:100%;">' +
                                 '<tr><th colspan="3" style="background-color:#f2f2f2;">Payee Records Are Delete Map</th></tr>' +
                                 '<tr><th>No</th><th>Payee Id</th><th>Payee Name</th></tr>';
    Integer mapCount = 1;
    for (Id key : payeeRecordsAreDeleteMap.keySet()) {
        payeeDeleteMapTable += '<tr><td>' + mapCount + '</td><td>' + key + '</td><td>' + payeeRecordsAreDeleteMap.get(key) + '</td></tr>';
        mapCount++;
    }
    payeeDeleteMapTable += '</table>';

    // -------------------------------
    // Build Final Email Body
    // -------------------------------
    String emailBody = '<p>Hello ' + UserInfo.getName() + ',</p>' +
                       '<p>The Payee Association processing has been completed successfully.</p>' +
                       '<h3>Summary of Records</h3>' +
                       combinedTables +   // Two tables side-by-side
                       '<br/>' + payeeDeleteMapTable +  // Third table below
                       '<p>Regards,<br/>Salesforce System</p>';

    // -------------------------------
    // Send Email
    // -------------------------------
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(new String[] { UserInfo.getUserEmail() });
    mail.setSubject('DIR Violation JSON Update - Process Completed');
    mail.setHtmlBody(emailBody);

    Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

    System.debug('Email sent to user: ' + UserInfo.getUserEmail());
} catch (Exception e) {
    System.debug('Error sending email: ' + e.getMessage());
}

 
        
    }
}