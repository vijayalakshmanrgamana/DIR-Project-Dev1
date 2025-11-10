public class DeletePayeeBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {

    Set<Id> accountIds;
    Set<Id> caseRoleIds;
    Set<Id> payeeIds;
    String emailHtmlBody;
    String insertRecordDeletion;

    Map<String, Integer> processSummary = new Map<String, Integer> {
        'Account_Deleted' => 0,
        'CaseRole_Deleted' => 0,
        'Payee_Deleted' => 0,
        'Account_Failed' => 0,
        'CaseRole_Failed' => 0,
        'Payee_Failed' => 0
    };

    // For failed records
    List<WrapperError> failedRecords = new List<WrapperError>();

    public DeletePayeeBatch(Set<Id> accountIds, Set<Id> caseRoleIds, Set<Id> payeeIds, String emailHtmlBody, String insertRecordDeletion) {
        this.emailHtmlBody = emailHtmlBody;
        this.accountIds = accountIds;
        this.caseRoleIds = caseRoleIds;
        this.payeeIds = payeeIds;
        this.insertRecordDeletion = insertRecordDeletion;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([SELECT Id, Name FROM Account WHERE Id IN :accountIds]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {

            // Delete Case Roles
            if (!caseRoleIds.isEmpty()) {
                List<Case_Role__c> caseRoleList = [SELECT Id, Name FROM Case_Role__c WHERE Id IN :caseRoleIds LIMIT 200];
                List<Database.DeleteResult> caseRoleResults = Database.delete(caseRoleList, false);

                for (Integer i = 0; i < caseRoleResults.size(); i++) {
                    if (caseRoleResults[i].isSuccess()) {
                        processSummary.put('CaseRole_Deleted', processSummary.get('CaseRole_Deleted') + 1);
                    } else {
                        processSummary.put('CaseRole_Failed', processSummary.get('CaseRole_Failed') + 1);
                        Database.Error err = caseRoleResults[i].getErrors()[0];
                        failedRecords.add(new WrapperError(caseRoleList[i].Id, caseRoleList[i].Name, err.getMessage(), 'Case Role'));
                    }
                }
            }

            // Delete Accounts
            if (!accountIds.isEmpty()) {
                List<Account> accList = [SELECT Id, Name FROM Account WHERE Id IN :accountIds LIMIT 200];
                List<Database.DeleteResult> accDeleteResults = Database.delete(accList, false);

                for (Integer i = 0; i < accDeleteResults.size(); i++) {
                    if (accDeleteResults[i].isSuccess()) {
                        processSummary.put('Account_Deleted', processSummary.get('Account_Deleted') + 1);
                    } else {
                        processSummary.put('Account_Failed', processSummary.get('Account_Failed') + 1);
                        Database.Error err = accDeleteResults[i].getErrors()[0];
                        failedRecords.add(new WrapperError(accList[i].Id, accList[i].Name, err.getMessage(), 'Account'));
                    }
                }
            }

            // Delete Payees
            if (!payeeIds.isEmpty()) {
                List<Payee__c> payeeList = [SELECT Id, Name FROM Payee__c WHERE Id IN :payeeIds LIMIT 200];
                List<Database.DeleteResult> payeeResults = Database.delete(payeeList, false);

                for (Integer i = 0; i < payeeResults.size(); i++) {
                    if (payeeResults[i].isSuccess()) {
                        processSummary.put('Payee_Deleted', processSummary.get('Payee_Deleted') + 1);
                    } else {
                        processSummary.put('Payee_Failed', processSummary.get('Payee_Failed') + 1);
                        Database.Error err = payeeResults[i].getErrors()[0];
                        failedRecords.add(new WrapperError(payeeList[i].Id, payeeList[i].Name, err.getMessage(), 'Payee'));
                    }
                }
            }

        } catch (Exception ex) {
            failedRecords.add(new WrapperError(null, null, ex.getMessage(), 'General Error'));
        }
    }

    public void finish(Database.BatchableContext bc) {
        // 🧾 Summary Table
        String summaryHtml = insertRecordDeletion + '<br/> <br/>';

        summaryHtml +=
        '<html>' +
        '<head><meta charset="UTF-8"></head>' +
        '<body style="font-family:Arial, sans-serif; font-size:14px; margin:0; padding:0;">' +

        '<div style="background-color:#fff3cd; border:1px solid #ffeeba; color:#856404; padding:12px 15px; border-radius:6px; margin-bottom:15px;">' +
        '<b>⚠️ Note:</b> Some <b>Account</b>, <b>Case Role</b>, or <b>Payee</b> records may have been partially processed due to validation or system errors during the batch run. ' +
        'As a result, a few records were inserted but could not be deleted automatically. The corresponding record Ids are provided below. ' +
        'Please manually delete these records (or remove them using a query) before re-uploading the corrected data. After cleanup, you can re-upload' +
        '</div>' +

        '<div style="border:2px solid #0176D3; padding:10px; display:inline-block; border-radius:6px;">' +
        '<table border="0" cellpadding="5" cellspacing="0" style="border-collapse:collapse;">' +
        '<tr><td>🧾 <b>Accounts Deleted:</b></td><td>' + processSummary.get('Account_Deleted') + '</td></tr>' +
        '<tr><td>⚠️ <b>Accounts Failed:</b></td><td>' + processSummary.get('Account_Failed') + '</td></tr>' +
        '<tr><td>🧾 <b>Case Roles Deleted:</b></td><td>' + processSummary.get('CaseRole_Deleted') + '</td></tr>' +
        '<tr><td>⚠️ <b>Case Roles Failed:</b></td><td>' + processSummary.get('CaseRole_Failed') + '</td></tr>' +
        '<tr><td>🧾 <b>Payees Deleted:</b></td><td>' + processSummary.get('Payee_Deleted') + '</td></tr>' +
        '<tr><td>⚠️ <b>Payees Failed:</b></td><td>' + processSummary.get('Payee_Failed') + '</td></tr>' +
        '</table></div><br/>';

        // ⚠️ Failed Records Table
        if (!failedRecords.isEmpty()) {
            summaryHtml +=
            '<h4 style="color:#E67E22; margin-bottom: 5px;">⚠️ Failed Deletion Record Details</h4>' +
            '<div style="border:1px solid #FFD700; padding:10px; background-color:#FFFACD;">' +
            '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse; width:100%;">' +
            '<tr style="background-color:#F2F3F4;">' +
            '<th align="left">Object Type</th>' +
            '<th align="left">Record Id</th>' +
            '<th align="left">Name</th>' +
            '<th align="left">Error Message</th>' +
            '</tr>';

            for (WrapperError err : failedRecords) {
                summaryHtml += '<tr>' +
                '<td>' + err.objectType + '</td>' +
                '<td>' + (err.recordId != null ? err.recordId : '-') + '</td>' +
                '<td>' + (err.name != null ? err.name : '-') + '</td>' +
                '<td style="color:red;">' + err.errorMsg + '</td>' +
                '</tr>';
            }
            summaryHtml += '</table></div><br/>';
        } else {
            emailHtmlBody = emailHtmlBody.replaceAll(
                '<tr><td>✅ <b>Accounts Inserted:</b></td><td>\\d+</td></tr>',
                '<tr><td>✅ <b>Accounts Inserted:</b></td><td>0</td></tr>'
            );

            emailHtmlBody = emailHtmlBody.replaceAll(
                '<tr><td>✅ <b>Case Roles Inserted:</b></td><td>\\d+</td></tr>',
                '<tr><td>✅ <b>Case Roles Inserted:</b></td><td>0</td></tr>'
            );

            emailHtmlBody = emailHtmlBody.replaceAll(
                '<tr><td>✅ <b>Payees Created:</b></td><td>\\d+</td></tr>',
                '<tr><td>✅ <b>Payees Created:</b></td><td>0</td></tr>'
            );

            System.debug('Final HTML: ' + emailHtmlBody);

            summaryHtml = '<h3 style="color:#27AE60;">The transaction has been fully reverted without any errors.</h3>' + emailHtmlBody;
        }

        String userEmail = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Email;

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[]{ userEmail });
        mail.setSubject('Apex Batch Job Completed - Delete Payee Batch Summary Report');

        mail.setHtmlBody(summaryHtml);
        mail.setCharset('UTF-8');
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });

        System.debug(mail);
        
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        
        if (results != null && results.size() > 0) {
            if (results[0].isSuccess()) {
                System.debug('Email sent successfully.');
            } else {
                System.debug('Email failed: ' + results[0].getErrors()[0].getMessage());
            }
        }

    }

    // Wrapper for failed record details
    public class WrapperError {
        public Id recordId;
        public String name;
        public String errorMsg;
        public String objectType;

        public WrapperError(Id recordId, String name, String errorMsg, String objectType) {
            this.recordId = recordId;
            this.name = name;
            this.errorMsg = errorMsg;
            this.objectType = objectType;
        }
    }
}