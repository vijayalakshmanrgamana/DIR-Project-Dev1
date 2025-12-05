/**
* @description Service class for sending batch processing summary emails and managing
* related case metadata in Salesforce.
*/
public with sharing class BatchEmailService {
    
    /**
* @description Overload method to send the batch summary email, accepting a single
* BatchSummaryWrapper object for all parameters.
* @param wrap Contains all summary data collected during the batch process.
*/
    public static void sendBatchSummaryEmail(BatchSummaryWrapper wrap) {
        sendBatchSummaryEmail(
            wrap.caseId,
            wrap.importType,
            wrap.insertedAccounts,
            wrap.insertedCaseRoles,
            wrap.insertedPayees,
            wrap.successCountPayee,
            wrap.failureCountPayee,
            wrap.batchError,
            wrap.batchRunCount,
            wrap.numberOfImportRecordsInserted,
            wrap.allErrorMessages,
            wrap.creationErrorTable,
            wrap.updateErrorTable,
            wrap.processSummary,
            wrap.processName,
            wrap.reverted,
            wrap.failedRecordsDelete,
            wrap.failedRecordsRevert,
            wrap.correctiveForm40DeleteSuccess,
            wrap.correctiveForm40DeleteError
        );
    }
    
    /**
* @description Sends an HTML summary email to the user who executed the batch job,
* detailing the outcomes of record creation and any errors encountered.
* @param caseId The ID of the related DIR_Case__c record.
* @param importType The type of import being processed.
* @param insertedAccounts Count of successfully inserted Account records.
* @param insertedCaseRoles Count of successfully inserted Case Role records.
* @param insertedPayees Count of successfully inserted Payee records.
* @param successCountPayee Count of successfully updated Payee records.
* @param failureCountPayee Count of failed Payee updates.
* @param batchError Flag indicating if a critical batch error occurred.
* @param batchRunCount The current run count of the batch job.
* @param numberOfImportRecordsInserted Total records uploaded for processing.
* @param allErrorMessages General exception messages.
* @param creationErrorTable HTML table string for record creation errors.
* @param updateErrorTable HTML table string for record update errors.
* @param processSummary Map containing counts for various DML operations (e.g., Account_Deleted).
* @param batchName The name of the batch process.
* @param reverted Flag indicating if the entire transaction was successfully rolled back.
* @param failedRecordsDelete List of WrapperError objects for records that failed deletion on revert.
* @param failedRecordsRevert List of WrapperError objects for records that failed update on revert.
* @param correctiveForm40DeleteSuccess List of WrapperError objects for successful corrective deletions.
* @param correctiveForm40DeleteError List of WrapperError objects for failed corrective deletions.
*/
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
        List<WrapperError> failedRecordsRevert,
        List<WrapperError> correctiveForm40DeleteSuccess,
        List<WrapperError> correctiveForm40DeleteError
    ) {
        
        
        try {
            
            Map<String, String> importTypeMap = new Map<String, String>{
            'Form_40_Partial'      => 'Form 40 Partial',
            'Corrective_Form_40'   => 'Corrective Form 40',
            'Form_40'              => 'Form 40'
        };
            
            String readableImportType = importTypeMap.containsKey(importType)
            ? importTypeMap.get(importType)
            : importType;
            
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
            
            // Header section with execution details
            htmlBody +=
                '<div style="background-color: #F9F9F9; padding: 10px; margin-bottom: 20px; border-radius: 4px; border: 1px solid #EEE;">' +
                '<p style="color: #777; font-size: 12px; margin: 0;">' +
                '<b>Executed by:</b> ' + UserInfo.getName() + '<br/>' +
                '<b>DateTime:</b> ' + System.now().format('MM/dd/yyyy h:mm a', UserInfo.getTimeZone().getId()) + '<br/>' +
                '<b>Last Apex Class :</b> ' + batchName +
                '</p></div>';
            
            // Transaction Revert status
            if (batchError && batchRunCount == 1) {
                htmlBody += '<h3 style="color:#27AE60;">The transaction has been fully reverted without any errors.</h3>';
            }
            else if(reverted == true){
                htmlBody += '<h3 style="color:#27AE60;">The transaction has been fully reverted without any errors.</h3>';
            }
            
            // Header message based on error status
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
                '<tr><td><b>Import Type:</b></td><td>' + readableImportType + '</td></tr>' +
                '</table><br/>' +
                
                '<div style="border:2px solid #0176D3; padding:15px; border-radius:6px; background-color:#F8F9F9; max-width:470px;">' +
                '<table border="0" cellpadding="5" cellspacing="0" style="border-collapse:collapse; width:100%;">' +
                '<h4 style="margin-top:0; color:#0176D3;">Record Insertion Results</h4>' +
                '<tr><td style="width:70%;">🔄 <b>Number of Uploaded Records:</b></td><td>' + numberOfImportRecordsInserted + '</td></tr>';
            
            // Display insertion results based on error/revert status
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
            
            Integer accountDeleted = processSummary.get('Account_Deleted') != null ? processSummary.get('Account_Deleted') : 0 ;
            Integer accountFailed = processSummary.get('Account_Failed') != null ? processSummary.get('Account_Failed') : 0 ;
            Integer payeeDeleted = processSummary.get('Payee_Deleted') != null ? processSummary.get('Payee_Deleted') : 0 ;
            Integer payeeFailed = processSummary.get('Payee_Failed') != null ? processSummary.get('Payee_Failed') : 0 ;
            Integer payeeUpdate = processSummary.get('Payee_Updated') != null ? processSummary.get('Payee_Updated') : 0 ;
            Integer payeeUpdateFailed = processSummary.get('Payee_Updated_Failed') != null ? processSummary.get('Payee_Updated_Failed') : 0 ;
            // Display partial revert details
            if(reverted == false && batchRunCount != 1 && batchError == true){
                htmlBody += '<h4 style="margin-top:0; color:#0176D3;">Record Revertion Results</h4>';
            }
            if(reverted == false && !failedRecordsDelete.isEmpty()){
                if(accountDeleted > 0 || accountFailed > 0) {
                    htmlBody += '<tr><td>🧾 <b>Accounts Deleted:</b></td><td>' + accountDeleted + '</td></tr>';
                }
                if(accountFailed > 0) {
                    htmlBody += '<tr><td>⚠️ <b>Accounts Failed:</b></td><td>' + accountFailed + '</td></tr>';
                }
                if(accountDeleted > 0 || accountFailed > 0) {
                    htmlBody += '<tr><td>🧾 <b>Case Roles Deleted:</b></td><td>' + accountDeleted + '</td></tr>';
                }
                if(accountFailed > 0) {
                    htmlBody += '<tr><td>⚠️ <b>Case Roles Failed:</b></td><td>' + accountFailed + '</td></tr>';
                }
                if(payeeDeleted > 0 || payeeFailed > 0) {
                    htmlBody += '<tr><td>🧾 <b>Payees Deleted:</b></td><td>' + payeeDeleted + '</td></tr>';
                }
                if(payeeFailed > 0) {
                    htmlBody += '<tr><td>⚠️ <b>Payees Failed:</b></td><td>' + payeeFailed + '</td></tr>';
                }
            }
            if(reverted == false && !failedRecordsRevert.isEmpty()){
                if(payeeUpdate > 0 || payeeUpdateFailed > 0) {
                    htmlBody += '<tr><td>🧾 <b>Payees Updated:</b></td><td>' + payeeUpdate + '</td></tr>';
                }
                if(payeeUpdateFailed > 0) {
                    htmlBody += '<tr><td>⚠️ <b>Payees Failed:</b></td><td>' + payeeUpdateFailed + '</td></tr>';
                }
            }
            
            
            if(importType == 'Corrective_Form_40' && (accountDeleted > 0 || accountFailed > 0 || payeeDeleted > 0 || payeeFailed > 0)){
                htmlBody += '<h4 style="margin-top:0; color:#0176D3;">Record Deleted Results</h4>';
                
                if(accountDeleted > 0 || accountFailed > 0) {
                    htmlBody += '<tr><td>🧾 <b>Accounts Deleted:</b></td><td>' + accountDeleted + '</td></tr>';
                }
                if(accountFailed > 0) {
                    htmlBody += '<tr><td>⚠️ <b>Accounts Failed:</b></td><td>' + accountFailed + '</td></tr>';
                }
                if(accountDeleted > 0 || accountFailed > 0) {
                    htmlBody += '<tr><td>🧾 <b>Case Roles Deleted:</b></td><td>' + accountDeleted + '</td></tr>';
                }
                if(accountFailed > 0) {
                    htmlBody += '<tr><td>⚠️ <b>Case Roles Failed:</b></td><td>' + accountFailed + '</td></tr>';
                }
                if(payeeDeleted > 0 || payeeFailed > 0) {
                    htmlBody += '<tr><td>🧾 <b>Payees Deleted:</b></td><td>' + payeeDeleted + '</td></tr>';
                }
                if(payeeFailed > 0) {
                    htmlBody += '<tr><td>⚠️ <b>Payees Failed:</b></td><td>' + payeeFailed + '</td></tr>';
                }
            }
            
            
            htmlBody += '</table></div><br/>';
            
            
            // --- Error Block (for creation/general exceptions) ---
            if ((String.isNotBlank(allErrorMessages) && allErrorMessages != null && allErrorMessages != '') || String.isNotBlank(creationErrorTable)) {
                htmlBody +=
                    '<h3 style="color:#C0392B;">🚨 General/Creation Errors</h3>' +
                    '<div style="color:#C0392B; border:1px solid #C0392B; padding:10px; background-color:#F9EBEA;">' +
                    '<pre style="font-family:Consolas, monospace; white-space:pre-wrap;">' +
                    '<h3 style="color:red;"> An error occurred while processing the following record(s):</h3>' +
                    
                    allErrorMessages;
                if((String.isNotBlank(allErrorMessages) && allErrorMessages != null && allErrorMessages != '') && String.isBlank(creationErrorTable)){
                   htmlBody += '</div>';
                }
                System.debug('allErrorMessages : '+ allErrorMessages);
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
            
            // Error Block (for update errors)
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
            
            // Warning message for partially failed deletion on revert
            if(reverted == false && !failedRecordsDelete.isEmpty()){
                htmlBody +='<div style="background-color:#fff3cd; border:1px solid #ffeeba; color:#856404; padding:12px 15px; border-radius:6px; margin-bottom:15px;">' +
                    '<b>⚠️ Note:</b> Some <b>Account</b>, <b>Case Role</b>, or <b>Payee</b> records may have been partially processed due to validation or system errors during the batch run. ' +
                    'As a result, a few records were inserted but could not be deleted automatically. The corresponding record Ids are provided below. ' +
                    'Please manually delete these records (or remove them using a query) before re-uploading the corrected data. After cleanup, you can re-upload' +
                    '</div>';
            }
            
            
            // ⚠️ Failed Deletion Records Table (on partial revert)
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
            
            // ⚠️ Failed Update Records Table (on partial revert)
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
            
            // Corrective Form 40 Deletion Success Details
            if(!correctiveForm40DeleteSuccess.isEmpty()){
                String htmlBody01;
                htmlBody +=
                    '<div style="background-color:#fff3cd; border:1px solid #ffeeba; color:#856404; padding:12px 15px; border-radius:6px; margin-top:10px; margin-bottom:15px;">' +
                    '<p style="font-size:13px; margin:0;">' +
                    '<b>⚠️ Notice:</b> We received your <b>Corrective Form 40</b> upload. After reviewing, we found that ' +
                    'the data you previously uploaded is still present. To correct this, we have deleted the related ' +
                    '<b>Account, Case Role and Payee records</b>' +
                    '</p>' +
                    '</div>';
                
                
                htmlBody01 +=
                    '<h4 style="color:#E67E22; margin-bottom: 5px;"> Deleted Record Details</h4>' +
                    '<div style="border:1px solid #FFD700; padding:10px; background-color:#FFFACD;">' +
                    '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse; width:100%;">' +
                    '<tr style="background-color:#F2F3F4;">' +
                    '<th align="left">Object Type</th>' +
                    '<th align="left">Record Id</th>' +
                    '<th align="left">Name</th>' +
                    '</tr>';
                
                for (WrapperError err : correctiveForm40DeleteSuccess) {
                    htmlBody01 += '<tr>' +
                        '<td>' + (err.objectType != null ? err.objectType : '-') + '</td>' +
                        '<td>' + (err.recordId != null ? err.recordId : '-') + '</td>' +
                        '<td>' + (err.name != null ? err.name : '-') + '</td>' +
                        '</tr>';
                }
                
                htmlBody01 += '</table></div><br/>';
            }
            
            // Corrective Form 40 Deletion Error Details
            if(!correctiveForm40DeleteError.isEmpty()){
                htmlBody +=
                    '<div style="background-color:#fff3cd; border:1px solid #ffeeba; color:#856404; padding:12px 15px; border-radius:6px; margin-top:10px; margin-bottom:15px;">' +
                    '<p style="font-size:13px; margin:0;">' +
                    '<b>⚠️ Notice:</b> Some <b>Account</b>, <b>Case Role</b>, or <b>Payee</b> records may have been partially processed due to validation or system errors during the batch run. ' +
                    'As a result, some records were inserted but could not be deleted automatically. The corresponding record IDs are listed below. ' +
                    'Please manually delete these records (or remove them using a query) before processing the payments.' +
                    '</p>' +
                    '</div>';
                
                htmlBody +=
                    '<h4 style="color:#E67E22; margin-bottom: 5px;">⚠️ Failed Deleted Record Details</h4>' +
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
                htmlBody += '</table></div><br/>';
            }
             
            // Final success message if no errors
            else if (batchError == false && (String.isNotBlank(allErrorMessages) && allErrorMessages != null && allErrorMessages != '')) {
                htmlBody += '<h4 style="color:#27AE60;"> No errors were encountered and all operations completed successfully.</h4>';
            }
            
            
            htmlBody += '</body></html>';
            
            
            // --- Send Email ---
            String userEmail = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Email;
            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{ userEmail });
            
            String statusText = batchError ? 'Error' : 'Completed Successfully';
            String caseNumber = escapeHtml(DC[0].Case_Number__c);
            
            // Build subject exactly in your required format
            String subject = readableImportType 
                + ' - Upload summary form Case Management : ' 
                + caseNumber
                + ' – Status: ' 
                + statusText;
            
            mail.setSubject(subject);
            
            mail.setHtmlBody(htmlBody);
            mail.setCharset('UTF-8');
            
            
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            String emailstatus ='pending';
            if (!results.isEmpty() && results[0].isSuccess()) {
                System.debug('Batch summary email sent successfully to ' + userEmail + '.');
                emailstatus = 'success';
            } else if (!results.isEmpty()) {
                System.debug('Failed to send batch email: ' + results[0].getErrors()[0].getMessage() + '.');
                emailstatus = 'error';
            }
            
            // Update DIR_Case__c with import details
            importInfo cj = new importInfo();
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
            
            // Process case update results
            for (Integer i = 0; i < updateCaseResults.size(); i++) {
                if (updateCaseResults[i].isSuccess()) {
                    System.debug('Case ' + caseId + ' updated successfully with import details.');
                } else {
                    Database.Error error = updateCaseResults[i].getErrors()[0];
                    System.debug('Case update failed: ' + error.getMessage() + ' for case ' + caseId + '.');
                }
            }
        }
        catch (Exception ex) {
            String trace = ex.getStackTraceString();
            String firstLine = trace.split('\n')[0];
            
            String errorMsg =
                'General Error during Payee DML Update: ' + ex.getMessage() +
                ' | Location: ' + firstLine +
                ' | Stack Trace: ' + trace + '\n';
                        
            System.debug('### [ERROR] Payee DML Update: ' + ex.getMessage());
            System.debug('### [TRACE] ' + trace);
            
            // Log the error using the BatchEmailService
            BatchEmailService.logError(ex);
        }
    }
    
    
    /**
* @description Sends an HTML summary email to the user who executed the deletion cleanup batch,
* detailing the records deleted/updated and any failures.
* @param caseId The ID of the related DIR_Case__c record.
* @param importType The type of import being cleaned up.
* @param processSummary Map containing counts for various deletion/update operations.
* @param batchName The name of the batch process.
* @param failedRecordsDelete List of WrapperError objects for records that failed deletion.
* @param failedCaseIssueRecordsUpdate List of WrapperError objects for Case Issue records that failed update.
*/
    public static void sendDeletionSummaryEmail(
        Id caseId,
        String importType,
        Map<String, Integer> processSummary,
        String batchName,
        List<WrapperError> failedRecordsDelete,
        List<WrapperError> failedCaseIssueRecordsUpdate
    ) {
        
        // --- Get Case Details ---
        DIR_Case__c dc = [
            SELECT Id, Case_Number__c
            FROM DIR_Case__c
            WHERE Id = :caseId
            LIMIT 1
        ];
        
        String baseUrl = System.Url.getOrgDomainUrl().toExternalForm();
        String caseLink = '<a href="' + baseUrl + '/lightning/r/DIR_Case__c/' + dc.Id +
            '/view" target="_blank" style="color:#0176D3; text-decoration:none;">' +
            escapeHtml(dc.Case_Number__c) + '</a>';
        
        // --- Begin HTML ---
        String htmlBody = '';
        htmlBody += '<html><head><meta charset="UTF-8"></head>';
        htmlBody += '<body style="font-family:Arial, sans-serif; font-size:14px; padding:15px; color:#333; line-height:1.5;">';
        
        // Header Section
        htmlBody +=
            '<div style="background-color:#F9F9F9; padding:12px; border-radius:6px; border:1px solid #EEE; margin-bottom:20px;">' +
            '<p style="font-size:12px; color:#777; margin:0;">' +
            '<b>Executed by:</b> ' + UserInfo.getName() + '<br/>' +
            '<b>DateTime:</b> ' + System.now().format('MM/dd/yyyy h:mm a', UserInfo.getTimeZone().getId()) + '<br/>' +
            '<b>Last Apex Class :</b> ' + escapeHtml(batchName) +
            '</p>' +
            '</div>';
        
        // Title
        htmlBody += '<h2 style="color:#2E86C1; margin-top:0;">Deletion Cleanup Summary</h2>';
        
        // Summary Table (Case Info)
        htmlBody +=
            '<h3 style="color:#2E86C1;">Process Summary</h3>' +
            '<table border="0" cellpadding="6" cellspacing="0" style="width:100%; max-width:500px; border-collapse:collapse;">' +
            '<tr><td style="width:40%;"><b>Case Management:</b></td><td>' + caseLink + '</td></tr>' +
            '<tr><td><b>Import Type:</b></td><td>' + escapeHtml(importType) + '</td></tr>' +
            '</table><br/>';
        
        // Deleted Count Box
        htmlBody +=
            '<div style="border:2px solid #0176D3; padding:15px; border-radius:6px; background-color:#F8F9F9; max-width:470px;">' +
            '<h4 style="margin-top:0; color:#0176D3;">Record Deletion Results</h4>' +
            '<table border="0" cellpadding="6" cellspacing="0" style="width:100%; border-collapse:collapse;">' +
            '<tr><td><b>🧾 Accounts Deleted:</b></td><td>' + processSummary.get('Account_Deleted') + '</td></tr>' +
            '<tr><td><b>⚠️ Accounts Failed:</b></td><td>' + processSummary.get('Account_Failed') + '</td></tr>' +
            '<tr><td><b>🧾 Case Roles Deleted:</b></td><td>' + processSummary.get('Account_Deleted') + '</td></tr>' +
            '<tr><td><b>⚠️ Case Roles Failed:</b></td><td>' + processSummary.get('Account_Failed') + '</td></tr>' +
            '<tr><td><b>🧾 Payees Deleted:</b></td><td>' + processSummary.get('Payee_Deleted') + '</td></tr>' +
            '<tr><td><b>⚠️ Payees Failed:</b></td><td>' + processSummary.get('Payee_Failed') + '</td></tr>' +
            '<tr><td><b>🧾 Case Issues Update:</b></td><td>' + processSummary.get('CaseIssue_Updated') + '</td></tr>' +
            '<tr><td><b>⚠️ Case Issues Failed:</b></td><td>' + processSummary.get('CaseIssue_Failed') + '</td></tr>' +
            '</table>' +
            '</div><br/>';
        
        
        // Failed Deletion Records Table
        if (!failedRecordsDelete.isEmpty()) {
            htmlBody +=
                '<div style="background-color:#fff3cd; border:1px solid #ffeeba; padding:12px 15px; border-radius:6px; margin-bottom:15px; color:#856404;">' +
                '<b>⚠️ Note:</b> Some records could not be deleted automatically due to validation or system errors. ' +
                'Please review the failed deletion details below and clean the data manually before re-uploading.' +
                '</div>';
            
            htmlBody +=
                '<h4 style="color:#E67E22; margin-bottom:5px;">⚠️ Failed Deletion Record Details</h4>' +
                '<div style="border:1px solid #FFD700; background-color:#FFFACD; padding:10px;">' +
                '<table border="1" cellpadding="6" cellspacing="0" style="width:100%; border-collapse:collapse;">' +
                '<tr style="background-color:#F2F3F4;">' +
                '<th align="left">Object Type</th>' +
                '<th align="left">Record Id</th>' +
                '<th align="left">Name</th>' +
                '<th align="left">Error Message</th>' +
                '</tr>';
            
            for (WrapperError err : failedRecordsDelete) {
                htmlBody += '<tr>' +
                    '<td>' + escapeHtml(err.objectType) + '</td>' +
                    '<td>' + (err.recordId != null ? err.recordId : '-') + '</td>' +
                    '<td>' + (err.name != null ? escapeHtml(err.name) : '-') + '</td>' +
                    '<td style="color:red;">' + escapeHtml(err.errorMsg) + '</td>' +
                    '</tr>';
            }
            
            htmlBody += '</table></div><br/>';
        }
        
        // Failed Case Issue Update Records Table
        if (!failedCaseIssueRecordsUpdate.isEmpty()) {
            
            // Note message
            htmlBody +=
                '<div style="background-color:#fff3cd; border:1px solid #ffeeba; padding:12px 15px; border-radius:6px; margin-bottom:15px; color:#856404;">' +
                '<b>⚠️ Note:</b> Some case issue updates could not be processed automatically due to validation or system errors. ' +
                'Please review the failed update details below and correct the data manually if needed before retrying.' +
                '</div>';
            
            // Failed records table
            htmlBody +=
                '<h4 style="color:#E67E22; margin-bottom:5px;">⚠️ Failed Case Issue Update Details</h4>' +
                '<div style="border:1px solid #FFD700; background-color:#FFFACD; padding:10px;">' +
                '<table border="1" cellpadding="6" cellspacing="0" style="width:100%; border-collapse:collapse;">' +
                '<tr style="background-color:#F2F3F4;">' +
                '<th align="left">Object Type</th>' +
                '<th align="left">Record Id</th>' +
                '<th align="left">Name</th>' +
                '<th align="left">Error Message</th>' +
                '</tr>';
            
            for (BatchEmailService.WrapperError err : failedCaseIssueRecordsUpdate) {
                htmlBody += '<tr>' +
                    '<td>' + escapeHtml(err.objectType) + '</td>' +
                    '<td>' + (err.recordId != null ? err.recordId : '-') + '</td>' +
                    '<td>' + (err.name != null ? escapeHtml(err.name) : '-') + '</td>' +
                    '<td style="color:red;">' + escapeHtml(err.errorMsg) + '</td>' +
                    '</tr>';
            }
            
            htmlBody += '</table></div><br/>';
        }
        
        
        htmlBody += '</body></html>';
        
        // --- Send Email ---
        User u = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()];
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[]{ u.Email });
        mail.setSubject('Apex Batch Job Completed - The deletion cleanup process has completed…');
        mail.setHtmlBody(htmlBody);
        mail.setCharset('UTF-8');
        
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
        if (!results.isEmpty() && results[0].isSuccess()) {
            System.debug('Deletion summary email sent successfully to ' + u.Email + '.');
        } else if (!results.isEmpty()) {
            System.debug('Failed to send deletion summary email: ' + results[0].getErrors()[0].getMessage() + '.');
        }
    }
    
    
    
    public static void logError(Exception ex) {
        // 1. Core Error Details
        String errorMessage = ex.getMessage();
        String trace = ex.getStackTraceString();
        
        // 2. Variables for Class and Method
        String className = '';
        String methodName = '';
        
        // 3. Parse Stack Trace to find the Class and Method Name
        if (trace != null && trace.containsIgnoreCase('Class.')) {
            List<String> traceLines = trace.split('\n');
            
            for (String line : traceLines) {
                if (line.containsIgnoreCase('Class.')) {
                    Integer startIndex = line.indexOfIgnoreCase('Class.') + 'Class.'.length();
                    String classMethodLine = line.substring(startIndex).trim();
                    String classAndMethod = classMethodLine.substringBefore(':');
                    
                    if (classAndMethod.contains('.')) {
                        className = classAndMethod.substringBefore('.');
                        methodName = classAndMethod.substringAfter('.');
                    } else {
                        className = classAndMethod;
                    }
                    
                    break; 
                }
            }
        }
        
        // 4. Build the Clean, Aligned HTML Email Body
        String htmlBody = ''
            + '<html><body style="font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #F5F5F5;">'
            
            // Card Container
            + '<div style="background: white; padding: 25px; border-radius: 8px; max-width: 800px; margin: auto; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">'
            
            // Title
            + '<h2 style="color: #D32F2F; border-bottom: 2px solid #EEE; padding-bottom: 10px;">🚨 Apex Exception Alert</h2>'
            
            // Error Message Box
            + '<div style="background-color: #FFEBEE; padding: 15px; border-left: 5px solid #C62828; border-radius: 5px; margin-top: 20px;">'
            + '<h3 style="margin: 0; color: #B71C1C;">Error Message</h3>'
            + '<p style="margin-top: 8px; font-size: 15px; color: #C62828;"><b>' + escapeHtml(errorMessage) + '</b></p>'
            + '</div>'
            
            // Context Table
            + '<h3 style="margin-top: 25px;">Context Details</h3>'
            + '<table style="width: 100%; border-collapse: collapse; font-size: 14px;">'
            + (String.isNotBlank(className) ? 
               '<tr><td style="padding: 10px; background: #FAFAFA; width: 30%; font-weight: bold;">Apex Class</td>'
               + '<td style="padding: 10px;">' + escapeHtml(className) + '</td></tr>' 
               : '')
            + (String.isNotBlank(methodName) ? 
               '<tr><td style="padding: 10px; background: #FAFAFA; font-weight: bold;">Apex Method</td>'
               + '<td style="padding: 10px;">' + escapeHtml(methodName) + '</td></tr>' 
               : '')
            + '</table>'
            
            // Stack Trace Box
            + '<h3 style="margin-top: 25px;">Full Stack Trace</h3>'
            + '<div style="background: #F0F0F0; padding: 15px; border-radius: 5px; overflow-x: auto; border: 1px solid #DDD;">'
            + '<pre style="white-space: pre-wrap; margin: 0; font-size: 13px;">' + escapeHtml(trace) + '</pre>'
            + '</div>'
            
            // Footer Info
            + '<div style="margin-top: 25px; padding: 15px; background: #FAFAFA; border-radius: 6px; border: 1px solid #EEE;">'
            + '<p style="font-size: 12px; color: #555; margin: 0;">'
            + '<b>Executed By:</b> ' + UserInfo.getName() + ' (' + UserInfo.getUserId() + ')<br/>'
            + '<b>DateTime:</b> ' + System.now().format('MM/dd/yyyy h:mm a', UserInfo.getTimeZone().getId()) + '<br/>'
            + '</p>'
            + '</div>'
            
            + '</div>'  // end card
            
            + '</body></html>';
        
        // 8. Send Email
        User u = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()];
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] {u.Email});
        mail.setSubject('ALERT: Exception in Apex Class ' + (String.isNotBlank(className) ? className : 'Unknown'));
        mail.setHtmlBody(htmlBody);
        mail.setCharset('UTF-8');
        
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
    
    
    
    /**
* @description Utility method to safely escape HTML characters in a string.
* @param input The string to be escaped.
* @return The HTML-escaped string.
*/
    private static String escapeHtml(String input) {
        if (input == null) return '';
        input = input.replaceAll('&', '&amp;');
        input = input.replaceAll('<', '&lt;');
        input = input.replaceAll('>', '&gt;');
        input = input.replaceAll('"', '&quot;');
        input = input.replaceAll('\'', '&#39;'); // Escape single quote safely
        return input;
    }
    
    
    /**
* @description Wrapper class to hold details of a failed record for logging/emailing.
*/
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
    
    /**
* @description Wrapper class for serializing case import details into a JSON field (Import_Form_40_Details__c).
*/
    public class importInfo {
        public String UserId;
        public String Last_Modified_By;
        public String Last_Modified_Date;
        public String Last_Upload_Import_type;
        public String Status;
    }
    
    
    /**
* @description Main wrapper class to consolidate all relevant data from an executing batch
* job for the email summary generation.
*/
    public class BatchSummaryWrapper {
        
        public Id caseId;
        public String importType;
        public Integer insertedAccounts;
        public Integer insertedCaseRoles;
        public Integer insertedPayees;
        public Integer successCountPayee;
        public Integer failureCountPayee;
        public Boolean batchError;
        public Integer batchRunCount;
        public Integer numberOfImportRecordsInserted;
        public String allErrorMessages;
        public String creationErrorTable;
        public String updateErrorTable;
        public Map<String, Integer> processSummary;
        public String processName;
        public Boolean reverted;
        public List<WrapperError> failedRecordsDelete;
        public List<WrapperError> failedRecordsRevert;
        public List<WrapperError> correctiveForm40DeleteSuccess;
        public List<WrapperError> correctiveForm40DeleteError;
        
        // ✅ Default constructor
        public BatchSummaryWrapper() {
            caseId = null;
            importType = '';
            insertedAccounts = 0;
            insertedCaseRoles = 0;
            insertedPayees = 0;
            successCountPayee = 0;
            failureCountPayee = 0;
            batchError = false;
            batchRunCount = 0;
            numberOfImportRecordsInserted = 0;
            allErrorMessages = '';
            creationErrorTable = '';
            updateErrorTable = '';
            processSummary = new Map<String, Integer>();
            processName = '';
            reverted = false;
            failedRecordsDelete = new List<WrapperError>();
            failedRecordsRevert = new List<WrapperError>();
            correctiveForm40DeleteSuccess = new List<WrapperError>();
            correctiveForm40DeleteError = new List<WrapperError>();
        }
    }
    
}