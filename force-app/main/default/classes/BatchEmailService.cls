public with sharing class BatchEmailService {
    public static void sendBatchSummaryEmail(
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
        Map<String, Integer> processSummary,
        String batchName,
        Boolean reverted,
        List<WrapperError> failedRecordsDelete,
        List<WrapperError> failedRecordsRevert
    ) {
        // --- Get case info ---
        List<DIR_Case__c> DC = [
            SELECT Id, Case_Number__c 
            FROM DIR_Case__c 
            WHERE Id = :caseId 
            LIMIT 1
        ];
        
        // --- Build Case Link ---
        String caseLink;
        if (DC != null && !DC.isEmpty() && DC[0].Id != null) {
            String baseUrl = System.Url.getOrgDomainUrl().toExternalForm();
            String caseUrl = baseUrl + '/lightning/r/DIR_Case__c/' + DC[0].Id + '/view';
            String caseNumber = escapeHtml(DC[0].Case_Number__c);
            caseLink = '<a href="' + caseUrl + '" target="_blank" style="color:#0176D3; text-decoration:none;">' + caseNumber + '</a>'; 
        } else {
            caseLink = 'N/A';
        }
        
        // --- Build HTML Body ---
        String htmlBody = '';
        htmlBody += '<html><head><meta charset="UTF-8"></head>' +
            '<body style="font-family:Arial, sans-serif; font-size:14px; margin:0; padding:15px; line-height:1.5; color:#333;">';
        
        // Header
        htmlBody +=
            '<div style="background-color: #F9F9F9; padding: 10px; margin-bottom: 20px; border-radius: 4px; border: 1px solid #EEE;">' +
            '<p style="color: #777; font-size: 12px; margin: 0;">' +
            '<b>Executed by:</b> ' + UserInfo.getName() + '<br/>' +
            '<b>DateTime:</b> ' + System.now().format('MM/dd/yyyy h:mm a', UserInfo.getTimeZone().getId()) + '<br/>' +
             '<b>Last Batch:</b> ' + batchName +
            '</p></div>';
        
        // Transaction Revert
        if (batchError && batchRunCount == 1) {
            htmlBody += '<h3 style="color:#27AE60;">The transaction has been fully reverted without any errors.</h3>';
        }
        else if(reverted == true){
            htmlBody += '<h3 style="color:#27AE60;">The transaction has been fully reverted without any errors.</h3>';
        }
        
        // Header message
        if (batchError == true) {
            htmlBody += '<h2 style="color:#C0392B;">⚠️ Batch Process Stopped</h2>';
        } else {
            htmlBody += '<h4 style="color:#2E86C1;">The bulk Account, Case Role, Payee creation process has been completed successfully.</h4>';
        }
        
        // Summary table
        htmlBody +=
            '<h3 style="color:#2E86C1;">Process Summary</h3>' +
            '<table border="0" cellpadding="5" cellspacing="0" style="border-collapse:collapse; width:100%; max-width:500px;">' +
            '<tr><td style="width:40%;"><b>Case Management:</b></td><td>' + caseLink + '</td></tr>' +
            '<tr><td><b>Import Type:</b></td><td>' + escapeHtml(importType) + '</td></tr>' +
            '</table><br/>' +
            
            '<div style="border:2px solid #0176D3; padding:15px; border-radius:6px; background-color:#F8F9F9; max-width:470px;">' +
            '<h4 style="margin-top:0; color:#0176D3;">Record Insertion Results</h4>' +
            '<table border="0" cellpadding="5" cellspacing="0" style="border-collapse:collapse; width:100%;">' +
            '<tr><td style="width:70%;">🔄 <b>Number of Uploaded Records:</b></td><td>' + numberOfImportRecordsInserted + '</td></tr>';
        
        if (batchError == true && batchRunCount == 1 && reverted == true) {
            htmlBody +=
                '<tr><td style="color:#C0392B;">❌ <b>Accounts Inserted:</b></td><td style="color:#C0392B;">0</td></tr>' +
                '<tr><td style="color:#C0392B;">❌ <b>Case Roles Inserted:</b></td><td style="color:#C0392B;">0</td></tr>' +
                '<tr><td style="color:#C0392B;">❌ <b>Payees Created:</b></td><td style="color:#C0392B;">0</td></tr>'+
                '<tr><td style="color:#C0392B;">❌ <b>Payees Updated Successfully:</b></td><td style="color:#C0392B;">0</td></tr>'+
                '<tr><td style="color:#C0392B;">❌ <b>Payees Failed to Update:</b></td><td style="color:#C0392B;">'+ failureCountPayee + '</td></tr>';
        }
        if (batchError == false || reverted == false){
            htmlBody +=
                '<tr><td>✅ <b>Accounts Inserted:</b></td><td>' + insertedAccounts + '</td></tr>' +
                '<tr><td>✅ <b>Case Roles Inserted:</b></td><td>' + insertedCaseRoles + '</td></tr>' +
                '<tr><td>✅ <b>Payees Created:</b></td><td>' + insertedPayees + '</td></tr>'+
                '<h4 style="margin-top:0; color:#0176D3;">Record Updation Results</h4>' +
                '<tr><td>✅ <b>Payees Updated Successfully:</b></td><td>' + successCountPayee + '</td></tr>'+
                '<tr><td>✅ <b>Payees Failed to Update:</b></td><td>' + failureCountPayee + '</td></tr>';
        }
        if(batchError == true && reverted == true){
            htmlBody +=
                '<tr><td style="color:#C0392B;">❌ <b>Accounts Inserted:</b></td><td style="color:#C0392B;">0</td></tr>' +
                '<tr><td style="color:#C0392B;">❌ <b>Case Roles Inserted:</b></td><td style="color:#C0392B;">0</td></tr>' +
                '<tr><td style="color:#C0392B;">❌ <b>Payees Created:</b></td><td style="color:#C0392B;">0</td></tr>'+
                '<tr><td style="color:#C0392B;">❌ <b>Payees Updated Successfully:</b></td><td style="color:#C0392B;">0</td></tr>'+
                '<tr><td style="color:#C0392B;">❌ <b>Payees Failed to Update:</b></td><td style="color:#C0392B;">'+ failureCountPayee + '</td></tr>';
        }
        
        if(reverted == false && batchRunCount != 1 && batchError == true){
            htmlBody += '<h4 style="margin-top:0; color:#0176D3;">Record Revertion Results</h4>';
        }
        if(reverted == false && !failedRecordsDelete.isEmpty()){
            htmlBody +=   
                '<tr><td>🧾 <b>Accounts Deleted:</b></td><td>' + processSummary.get('Account_Deleted') + '</td></tr>' +
                '<tr><td>⚠️ <b>Accounts Failed:</b></td><td>' + processSummary.get('Account_Failed') + '</td></tr>' +
                '<tr><td>🧾 <b>Case Roles Deleted:</b></td><td>' + processSummary.get('CaseRole_Deleted') + '</td></tr>' +
                '<tr><td>⚠️ <b>Case Roles Failed:</b></td><td>' + processSummary.get('CaseRole_Failed') + '</td></tr>' +
                '<tr><td>🧾 <b>Payees Deleted:</b></td><td>' + processSummary.get('Payee_Deleted') + '</td></tr>' +
                '<tr><td>⚠️ <b>Payees Failed:</b></td><td>' + processSummary.get('Payee_Failed') + '</td></tr>';
        }
        if(reverted == false && !failedRecordsRevert.isEmpty()){
            htmlBody +=  '<tr><td>🧾 <b>Payees Updated:</b></td><td>' + String.valueOf(processSummary.get('Payee_Updated')) + '</td></tr>' +
                '<tr><td>⚠️ <b>Payees Failed:</b></td><td>' + String.valueOf(processSummary.get('Payee_Failed')) + '</td></tr>';
        }        
        
        htmlBody += '</table></div><br/>';
        
        
        // --- Error Block (for creation/general exceptions) ---
        if (String.isNotBlank(allErrorMessages) || String.isNotBlank(creationErrorTable)) {
            htmlBody +=
                '<h3 style="color:#C0392B;">🚨 General/Creation Errors</h3>' +
                '<div style="color:#C0392B; border:1px solid #C0392B; padding:10px; background-color:#F9EBEA;">' +
                '<pre style="font-family:Consolas, monospace; white-space:pre-wrap;">' +
                '<h3 style="color:red;"> An error occurred while processing the following record(s):</h3>' +
                
                + allErrorMessages;
            if(String.isNotBlank(creationErrorTable)){
                htmlBody += '<table border="1" cellpadding="5" cellspacing="0" ' +
                    'style="border-collapse:collapse; width:100%; font-family:Arial, sans-serif; font-size:13px; background-color:#FFEEEE;">' +
                    '<tr style="background-color:#F5B7B1; font-weight:bold;">' +
                    '<th>Employee First Name</th>' +
                    '<th>Employee Last Name</th>' +
                    '<th>Employee Street</th>' +
                    '<th>Employee City</th>' +
                    '<th>Employee State</th>' +
                    '<th>Employee Zip</th>' +
                    '<th>Error</th>' +
                    '</tr>'+
                    creationErrorTable +
                    '</pre></div><br/>';
            }
        }
        
        if (String.isNotBlank(updateerrorTable)){
            htmlBody +=
                '<h3 style="color:#C0392B;">🚨 Update Errors/Warnings</h3>' +
                '<div style="color:#C0392B; border:1px solid #C0392B; padding:10px; background-color:#F9EBEA;">' +
                '<pre style="font-family:Consolas, monospace; white-space:pre-wrap;">' +
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
                '</tr>' +
                updateerrorTable +
                '</pre></div><br/>';          
        }
        
        if(reverted == false && !failedRecordsDelete.isEmpty()){
            htmlBody +='<div style="background-color:#fff3cd; border:1px solid #ffeeba; color:#856404; padding:12px 15px; border-radius:6px; margin-bottom:15px;">' +
                '<b>⚠️ Note:</b> Some <b>Account</b>, <b>Case Role</b>, or <b>Payee</b> records may have been partially processed due to validation or system errors during the batch run. ' +
                'As a result, a few records were inserted but could not be deleted automatically. The corresponding record Ids are provided below. ' +
                'Please manually delete these records (or remove them using a query) before re-uploading the corrected data. After cleanup, you can re-upload' +
                '</div>';
        }
         
        
        // ⚠️ Failed Records Table
        if (!failedRecordsDelete.isEmpty() && reverted == false) {
            htmlBody +=
                '<h4 style="color:#E67E22; margin-bottom: 5px;">⚠️ Failed Deletion Record Details</h4>' +
                '<div style="border:1px solid #FFD700; padding:10px; background-color:#FFFACD;">' +
                '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse; width:100%;">' +
                '<tr style="background-color:#F2F3F4;">' +
                '<th align="left">Object Type</th>' +
                '<th align="left">Record Id</th>' +
                '<th align="left">Name</th>' +
                '<th align="left">Error Message</th>' +
                '</tr>';
            
            for (WrapperError err : failedRecordsDelete) {
                htmlBody += '<tr>' +
                    '<td>' + err.objectType + '</td>' +
                    '<td>' + (err.recordId != null ? err.recordId : '-') + '</td>' +
                    '<td>' + (err.name != null ? err.name : '-') + '</td>' +
                    '<td style="color:red;">' + err.errorMsg + '</td>' +
                    '</tr>';
            }
            htmlBody += '</table></div><br/>';
        }
        
        if (!failedRecordsRevert.isEmpty() && reverted == false) {
            htmlBody +=
                '<h4 style="color:#E67E22; margin-bottom: 5px;">⚠️ Failed Update Record Details</h4>' +
                '<div style="border:1px solid #FFD700; padding:10px; background-color:#FFFACD;">' +
                '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse; width:100%;">' +
                '<tr style="background-color:#F2F3F4;">' +
                '<th align="left">Object Type</th>' +
                '<th align="left">Record Id</th>' +
                '<th align="left">Name</th>' +
                '<th align="left">Error Message</th>' +
                '</tr>';
            
            for (WrapperError err : failedRecordsRevert) {
                htmlBody += '<tr>' +
                    '<td>' + (err.objectType != null ? err.objectType : '-') + '</td>' +
                    '<td>' + (err.recordId != null ? err.recordId : '-') + '</td>' +
                    '<td>' + (err.name != null ? err.name : '-') + '</td>' +
                    '<td style="color:red;">' + (err.errorMsg != null ? err.errorMsg : '-') + '</td>' +
                    '</tr>';
            }
            
            htmlBody += 
                '</table></div><br/>' +
                '<div style="background-color:#fff3cd; border:1px solid #ffeeba; color:#856404; padding:12px 15px; border-radius:6px; margin-top:10px; margin-bottom:15px;">' +
                '<p style="font-size:13px; margin:0;">' +
                '<b>⚠️ Note:</b> If any <b>Payee</b> update failed due to validation or temporary errors, there is <b>no issue for update</b>. ' +
                'You can fix the data for failed rows (see Ids above) and re-upload; it should work fine on retry.' +
                '</p>' +
                '</div><br/>';
        }
        
        else if (batchError == false) {
            htmlBody += '<h4 style="color:#27AE60;"> No errors were encountered and all operations completed successfully.</h4>';
        }
        
        htmlBody += '</body></html>';
        
        
        // --- Send Email ---
        String userEmail = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Email;
        
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[]{ userEmail });
        mail.setSubject('Apex Batch Job Completed - Form 40 Import Summary Report');
        mail.setHtmlBody(htmlBody);
        mail.setCharset('UTF-8');
        
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        String emailstatus ='pending';
        if (!results.isEmpty() && results[0].isSuccess()) {
            System.debug('Batch summary email sent successfully.');
            emailstatus = 'success';
        } else if (!results.isEmpty()) {
            System.debug('Failed to send batch email: ' + results[0].getErrors()[0].getMessage());
            emailstatus = 'error';
        }
        
        caseJson cj = new caseJson();
        cj.Last_Upload_Import_type = importType;
        cj.Last_Modified_By        = UserInfo.getName();
        cj.UserId                  = UserInfo.getUserId();
        cj.Last_Modified_Date      = System.now().format('MM/dd/yyyy h:mm a', UserInfo.getTimeZone().getId());
        cj.Status				   = emailstatus;
        
        DIR_Case__c caseManagement = new DIR_Case__c(
            Id = caseId,
            Import_Form_40_Details__c = JSON.serialize(cj)
        );
        
        List<Database.SaveResult> updateCaseResults = Database.update(
            new List<DIR_Case__c>{ CaseManagement },
            false
        );
        
        for (Integer i = 0; i < updateCaseResults.size(); i++) {
            if (updateCaseResults[i].isSuccess()) {
            } else {
                Database.Error error = updateCaseResults[i].getErrors()[0];
                System.debug('Case update failed: ' + error.getMessage());
            }
        }
    }
    
    // --- HTML escaping utility ---
    private static String escapeHtml(String input) {
        if (input == null) return '';
        input = input.replaceAll('&', '&amp;');
        input = input.replaceAll('<', '&lt;');
        input = input.replaceAll('>', '&gt;');
        input = input.replaceAll('"', '&quot;');
        input = input.replaceAll('\'', '&#39;'); // Escape single quote safely
        return input;
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
    
    public class caseJson {
        public String UserId;
        public String Last_Modified_By;
        public String Last_Modified_Date;
        public String Last_Upload_Import_type;
        public String Status;
    }
}