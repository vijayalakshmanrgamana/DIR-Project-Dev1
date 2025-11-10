public class RevertPayeeBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {

    private Map<Id, Payee__c> payeeToUpdateMap;
    private String emailHtmlBody; 
    private String additionalNote; 
    Set<Id> accountIds;
    Set<Id> caseRoleIds;
    Set<Id> payeeIds;

    private Map<String, Integer> processSummary = new Map<String, Integer> {
        'Payee_Updated' => 0,
        'Payee_Failed' => 0
    };

    private List<WrapperError> failedRecords = new List<WrapperError>();

    public RevertPayeeBatch(List<Payee__c> payeeRecords, String emailHtmlBody, 
                            Set<Id> accountIds, Set<Id> caseRoleIds, Set<Id> payeeIds) {
        this.payeeToUpdateMap = new Map<Id, Payee__c>();
        if (payeeRecords != null) {
            for (Payee__c p : payeeRecords) {
                if (p != null && p.Id != null) {
                    this.payeeToUpdateMap.put(p.Id, p);
                }
            }
        }
        this.emailHtmlBody = (emailHtmlBody == null) ? '' : emailHtmlBody;
        this.additionalNote = (additionalNote == null) ? '' : additionalNote;
        this.accountIds = accountIds;
        this.caseRoleIds = caseRoleIds;
        this.payeeIds = payeeIds;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (payeeToUpdateMap == null || payeeToUpdateMap.isEmpty()) {
            return Database.getQueryLocator([SELECT Id, Name FROM Payee__c WHERE Id = :null]);
        }
        return Database.getQueryLocator([SELECT Id, Name FROM Payee__c WHERE Id IN :payeeToUpdateMap.keySet()]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            List<Payee__c> updates = new List<Payee__c>();
            for (SObject s : scope) {
                Payee__c current = (Payee__c) s;
                Payee__c prepared = payeeToUpdateMap.get(current.Id);
                if (prepared != null) {
                    prepared.Id = current.Id;
                    updates.add(prepared);
                }
            }

            if (!updates.isEmpty()) {
                List<Database.SaveResult> results = Database.update(updates, false);

                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        processSummary.put('Payee_Updated', processSummary.get('Payee_Updated') + 1);
                    } else {
                        processSummary.put('Payee_Failed', processSummary.get('Payee_Failed') + 1);
                        Database.Error err = results[i].getErrors()[0];
                        Payee__c failedRec = updates[i];
                        failedRecords.add(new WrapperError(
                            failedRec.Id, 
                            failedRec.Payee_Name__c, 
                            err.getMessage(), 
                            'Payee'
                        ));
                    }
                }
            }
        } catch (Exception ex) {
            failedRecords.add(new WrapperError(null, null, ex.getMessage(), 'General Error'));
        }
    }

    /**
     * finish - build email summary and send to running user
     */
    public void finish(Database.BatchableContext bc) {
        // 🧾 Summary Table
        String summaryHtml = emailHtmlBody + '<br/> <br/>' +
            '<html>' +
            '<head><meta charset="UTF-8"></head>' +
            '<body style="font-family:Arial, sans-serif; font-size:14px; margin:0; padding:0;">' +
            '<div style="border:2px solid #0176D3; padding:10px; display:inline-block; border-radius:6px;">' +
            '<table border="0" cellpadding="5" cellspacing="0" style="border-collapse:collapse;">' +
            '<tr><td>🧾 <b>Payees Updated:</b></td><td>' + String.valueOf(processSummary.get('Payee_Updated')) + '</td></tr>' +
            '<tr><td>⚠️ <b>Payees Failed:</b></td><td>' + String.valueOf(processSummary.get('Payee_Failed')) + '</td></tr>' +
            '</table></div><br/>';

        // ⚠️ Failed Records Table
        if (!failedRecords.isEmpty()) {
            summaryHtml +=
                '<h4 style="color:#E67E22; margin-bottom: 5px;">⚠️ Failed Update Record Details</h4>' +
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
                    '<td>' + (err.objectType != null ? err.objectType : '-') + '</td>' +
                    '<td>' + (err.recordId != null ? err.recordId : '-') + '</td>' +
                    '<td>' + (err.name != null ? err.name : '-') + '</td>' +
                    '<td style="color:red;">' + (err.errorMsg != null ? err.errorMsg : '-') + '</td>' +
                    '</tr>';
            }

            summaryHtml += 
                '</table></div><br/>' +
                '<div style="background-color:#fff3cd; border:1px solid #ffeeba; color:#856404; padding:12px 15px; border-radius:6px; margin-top:10px; margin-bottom:15px;">' +
                '<p style="font-size:13px; margin:0;">' +
                '<b>⚠️ Note:</b> If any <b>Payee</b> update failed due to validation or temporary errors, there is <b>no issue for update</b>. ' +
                'You can fix the data for failed rows (see Ids above) and re-upload; it should work fine on retry.' +
                '</p>' +
                '<p style="font-size:12px; color:#555; margin-top:6px;"><i>' + escapeHtml(additionalNote) + '</i></p>' +
                '</div><br/>';
        } else {
            emailHtmlBody = emailHtmlBody.replaceAll(
                '<tr><td>✅ <b>Payees Updated Successfully:</b></td><td>\\d+</td></tr>', 
                '<tr><td>✅ <b>Payees Updated Successfully:</b></td><td>0</td></tr>'
            );
            
            summaryHtml = 
                '<h3 style="color:#27AE60;">The transaction has been fully reverted without any errors.</h3>' 
                + emailHtmlBody;
            
            if (!accountIds.isEmpty()) {
                summaryHtml = emailHtmlBody;
            }
            
            System.debug(summaryHtml);
        }

        String userEmail = '';
        try {
            userEmail = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Email;
        } catch (Exception e) {
            System.debug('Could not fetch user email: ' + e.getMessage());
        }

        if (String.isNotBlank(userEmail) && accountIds.isEmpty()) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{ userEmail });
            mail.setSubject('Apex Batch Job Completed - Revert Payee Summary Report');
            mail.setHtmlBody(summaryHtml);
            mail.setCharset('UTF-8');

            try {
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            } catch (Exception exSend) {
                System.debug('Email send failed: ' + exSend.getMessage());
            }
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            
            if (results != null && results.size() > 0) {
                if (results[0].isSuccess()) {
                    System.debug('Email sent successfully.');
                } else {
                    System.debug('Email failed: ' + results[0].getErrors()[0].getMessage());
                }
            }    
            
        } else {
            System.debug('No user email found. Summary: ' + summaryHtml);
        }

        if (!accountIds.isEmpty()) {
            Database.executeBatch(new DeletePayeeBatch(accountIds, caseRoleIds, payeeIds, summaryHtml, null), 200);
        }
    }

    // Wrapper for error details
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