public without sharing class form40ImportControllerReDesigned {
  // Constants
  private static final Integer ROWS_PER_JOB = 200; // Rows per Queueable job
  //private static map<string,Payee__c> payeeMap;
  // Entry point for parsing CSV, initiates first Queueable job
  //wrapper class to hold Case Issues
  @AuraEnabled(cacheable=true)
  public static List<CaseIssueWrapper> getCaseIssues(
    Id caseId,
    string importType
  ) {
    List<CaseIssueWrapper> caseIssuewrappers = new List<CaseIssueWrapper>();
    try {
      List<DIR_Violation__c> caseIssues = [
        SELECT
          Id,
          Name,
          Violation_Type__r.Wizard_Search_Text__c,
          Citation_Form__c,
          Wage_Balance_Due__c,
          Amount_Utilized_from_Payee__c,
          Remaining_Amount_to_Upload__c,
          Citation_Number__c,
          Amount_Reserved__c
        FROM DIR_Violation__c
        WHERE Case__c = :caseId
      ];
      for (DIR_Violation__c ci : caseIssues) {
        caseIssuewrappers.add(new CaseIssueWrapper(ci, importType));
      }
      return caseIssuewrappers;
    } catch (Exception ex) {
      throw new AuraHandledException(
        'An Error occured in getCaseIssues ' +
          ex.getMessage() +
          ' ' +
          ex.getStackTraceString()
      );
    }
  }

  @AuraEnabled
  public static string parseCSVAndValidate(
    List<String> lines,
    Id caseId,
    List<Id> selectedCaseIssueIds,
    string importType
  ) {
    try {
      SYSTEM.DEBUG('Entered Parse Validate, CPU Time: ' + Limits.getCpuTime());
      System.Debug('Lines ' + lines.size());

      if (lines.isEmpty()) {
        throw new AuraHandledException('Empty CSV input.');
      }

      // Generate unique cache key
      String cacheKey =
        'CSV_Results_' +
        caseId +
        '_' +
        Datetime.now().getTime();
      System.Debug('Unique Key Generated ' + cacheKey);

      Integer totalRows = lines.size() - 1; // Exclude header
      Integer totalJobs = Math.max(
        1,
        (Integer) Math.ceil((Double) totalRows / ROWS_PER_JOB)
      );
      System.debug(
        'parseCSVAndValidate: Total rows: ' +
          totalRows +
          ', Total jobs: ' +
          totalJobs
      );

      // Create initial CSV_Import_Result__c record
      Import__c importResult = new Import__c(
        Unique_Key__c = cacheKey,
        Job_Status__c = 'Processing',
        Case_Management__c = caseId,
        Job_Sequence__c = 0,
        Total_Jobs__c = totalJobs,
        Processed_Rows__c = 0
      );
      insert importResult;
      System.Debug('Job Tracking Import record Inserted ' + importResult.Id);

      // Start first Queueable job
      String jobId = System.enqueueJob(
        new CSVProcessor(
          lines,
          caseId,
          selectedCaseIssueIds,
          importType,
          cacheKey,
          1,
          1
        )
      );
      SYSTEM.DEBUG(
        'Queueable Job Enqueued, Cache Key: ' +
          cacheKey +
          ', CPU Time: ' +
          Limits.getCpuTime()
      );
      /*
        Map<String, Object> resultMap = new Map<String, Object>{
            'uniqueKey' => cacheKey,
            'totalRows' => totalRows
        };*/

      return cacheKey; // Return cache key for polling
    } catch (Exception ex) {
      System.Debug(
        'An Error occured in parseCSVAndValidate ' +
          ex.getMessage() +
          ' ' +
          ex.getStackTraceString()
      );
      throw new AuraHandledException(
        'An Error occured in parseCSVAndValidate ' +
          ex.getMessage() +
          ' ' +
          ex.getStackTraceString()
      );
    }
  }

  // Queueable job to process CSV
  public class CSVProcessor implements Queueable {
    private List<String> lines;
    private Id caseId;
    private List<Id> selectedCaseIssueIds;
    private string importType;
    private String cacheKey;
    private Integer jobSequence;
    private Integer startLine;
    private map<string, Payee__c> payeeMap;
    private Map<Id, DIR_Violation__c> selectedCaseIssueMap;
    private final Integer ROWS_PER_JOB = 200;
    private final List<String> EXPECTED_HEADERS = new List<String>{
      'Direct Pay',
      'Employee First Name',
      'Employee Last Name',
      'Employee Street',
      'Employee City',
      'Employee State',
      'Employee Zip',
      'Period Covered by Adjustment',
      'Total Wage Assessment',
      'Deductions: Total',
      'Net Wages Assessed',
      'Factor'
    };
    Map<String, Integer> headerIndexMap;

    public CSVProcessor(
      List<String> lines,
      Id caseId,
      List<Id> selectedCaseIssueIds,
      string importType,
      String cacheKey,
      Integer jobSequence,
      Integer startLine
    ) {
      this.lines = lines;
      this.caseId = caseId;
      this.selectedCaseIssueIds = selectedCaseIssueIds;
      this.importType = importType;
      this.selectedCaseIssueMap = new Map<Id, DIR_Violation__c>(
        [
          SELECT Id, Name, Violation_Type__r.Name
          FROM DIR_Violation__c
          WHERE Id IN :selectedCaseIssueIds
        ]
      );
      this.cacheKey = cacheKey;
      this.jobSequence = jobSequence;
      this.startLine = startLine;
    }

    public void execute(QueueableContext context) {
      try {
        List<ImportWrapper> errorRecords = new List<ImportWrapper>();
        List<ImportWrapper> validRecords = new List<ImportWrapper>();

        //List<String> lines = getCsvLines();

        if (lines.isEmpty()) {
          storeResults(errorRecords, 'Empty CSV.', null);
          return;
        }

        // Validate headers only in first job
        if (jobSequence == 1 && !validateHeaders(lines[0])) {
          storeResults(errorRecords, 'CSV headers mismatch.', null);
          return;
        }

        if (headerIndexMap == null) {
          List<String> headers = parseCsvLine(lines[0].trim());
          headerIndexMap = new Map<String, Integer>();
          for (Integer i = 0; i < headers.size(); i++) {
            headerIndexMap.put(headers[i].trim(), i);
          }
        }

        /* // Simulate error for testing
        if (jobSequence == 1) {
            throw new IllegalArgumentException('Simulated error in Queueable job for testing purposes.');
          }
            */

        // Build unique keys for this chunk
        List<String> chunkUniqueKeys = new List<String>();
        Map<Integer, ImportWrapper> rowMap = new Map<Integer, ImportWrapper>();
        Map<String, Integer> uniqueKeyToRowNum = new Map<String, Integer>();
        // Process this chunk
        Integer endLine = Math.min(startLine + ROWS_PER_JOB, lines.size());
        for (Integer i = startLine; i < endLine; i++) {
          ImportWrapper wrapper = processLine(lines[i], i);
          rowMap.put(i, wrapper);

          String uniqueKey = form40ImportControllerReDesigned.buildUniqueKey(
            wrapper
          );
          chunkUniqueKeys.add(uniqueKey);
          uniqueKeyToRowNum.put(uniqueKey, i);
        }

        // ONE SOQL: Get ONLY matching Payees
        Map<String, Payee__c> matchingPayees = new Map<String, Payee__c>();
        for (Payee__c p : [
          SELECT
            Id,
            Case_Role__r.Entity__r.AccountMatch__c,
            Payee_Association_JSON__c
          FROM Payee__c
          WHERE
            Case_Role__r.Entity__r.AccountMatch__c IN :chunkUniqueKeys
            AND Case_Management__c = :caseId
        ]) {
          matchingPayees.put(
            p.Case_Role__r.Entity__r.AccountMatch__c.toLowerCase(),
            p
          );
        }

        // Process each row
        for (Integer rowNum : rowMap.keySet()) {
          ImportWrapper row = rowMap.get(rowNum);
          String uniqueKey = form40ImportControllerReDesigned.buildUniqueKey(
            row
          );

          Payee__c duplicatePayee = matchingPayees.get(uniqueKey);
          if (duplicatePayee != null) {
            row.isDuplicate = true;

            if (importType == 'Corrective_Form_40') {
              Set<Id> existingCaseIssueIds = new Set<Id>();
              if (String.isNotBlank(duplicatePayee.Payee_Association_JSON__c)) {
                List<PayeeAssociation> associations = (List<PayeeAssociation>) JSON.deserialize(
                  duplicatePayee.Payee_Association_JSON__c,
                  List<PayeeAssociation>.class
                );
                for (PayeeAssociation pa : associations) {
                  existingCaseIssueIds.add(pa.caseIssueId);
                }
              }

              Set<Id> newAssociations = new Set<Id>(selectedCaseIssueIds);
              newAssociations.removeAll(existingCaseIssueIds);

              if (!newAssociations.isEmpty()) {
                row.isValid = false;
                for (Id newId : newAssociations) {
                  String name = selectedCaseIssueMap.get(newId)?.Name ??
                    'Unknown';
                  row.errorMessages.add(
                    'Associating a New Case Issue ' +
                      name +
                      'to a Payee is not supported in Corrective Form 40. Please use Form 40 instead.'
                  );
                }
              }
            }
          }
          // Other validations
          validateRow(row);
          if (!row.isValid)
            errorRecords.add(row);
          else
            validRecords.add(row);
        }

        List<ImportWrapper> allRecords = new List<ImportWrapper>();
        allRecords.addAll(validRecords);
        allRecords.addAll(errorRecords);
        storeResults(errorRecords, null, allRecords.size()); // Store only error records
        saveValidRecords(validRecords, cacheKey);

        // Chain next job
        if (endLine < lines.size()) {
          System.enqueueJob(
            new CSVProcessor(
              lines,
              caseId,
              selectedCaseIssueIds,
              importType,
              cacheKey,
              jobSequence + 1,
              endLine
            )
          );
        } else {
          markImportComplete();
        }
      } catch (Exception e) {
        // Handle any *unexpected* errors here

        System.Debug(
          'Exception Occured in Queueable Execute Method ' +
            e.getMessage() +
            ' ' +
            e.getStackTraceString()
        );
        storeResults(
          new List<ImportWrapper>(),
          'Unexpected error: ' + e.getMessage() + '' + e.getStackTraceString(),
          null
        );
      }
    }

    private Boolean validateHeaders(String headerLine) {
      boolean isValidHeaders = true;
      List<String> headers = parseCsvLine(headerLine.trim());
      if (headers.size() != EXPECTED_HEADERS.size()) {
        isValidHeaders = false;
      }
      for (string header : headers) {
        if (!EXPECTED_HEADERS.contains(header)) {
          isValidHeaders = false;
          break;
        }
      }
      return isValidHeaders;
    }

    private ImportWrapper processLine(String line, Integer rowNumber) {
      ImportWrapper wrapper = new ImportWrapper();
      wrapper.rowNumber = rowNumber;
      wrapper.caseId = caseId;
      if (String.isBlank(line))
        return wrapper;

      List<String> values = parseCsvLine(line);
      if (values.size() != EXPECTED_HEADERS.size()) {
        wrapper.errorMessages.add(
          'Expected 12 columns, found ' + values.size()
        );
        wrapper.isValid = false;
      } else {
        for (Integer j = 0; j < EXPECTED_HEADERS.size(); j++) {
          Integer index = headerIndexMap.get(EXPECTED_HEADERS[j]);
          wrapper.fieldValues.put(EXPECTED_HEADERS[j], values[index]);
        }
        //validateRow(wrapper, payeeMap,importType,selectedCaseIssueMap);
      }
      return wrapper;
    }

    private void storeResults(
      List<ImportWrapper> results,
      String fatalError,
      integer processedRows
    ) {
      Import__c record = new Import__c(
        Unique_Key__c = cacheKey,
        Results__c = results.size() > 0 ||
          results != null
          ? saveResultsasFile(cacheKey, results)
          : 'No Faulty Records in this Job',
        Job_Sequence__c = jobSequence,
        Case_Management__c = caseId,
        Job_Status__c = fatalError != null ? 'Failed' : 'Completed',
        Error_Message__c = fatalError,
        Processed_Rows__c = processedRows != null ? processedRows : 0
      );
      insert record;
    }

    private Id saveResultsasFile(string cacheKey, List<ImportWrapper> results) {
      String jsonString = JSON.serialize(results);
      Blob jsonBlob = Blob.valueOf(jsonString);

      // Create file
      ContentVersion file = new ContentVersion();
      file.Title = 'ImportResults_' + cacheKey + '_' + System.now().getTime();
      file.PathOnClient = file.Title + '.json';
      file.VersionData = jsonBlob;
      insert file;

      // Query ContentDocumentId (needed to link/retrieve later)
      return [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :file.Id
        LIMIT 1
      ]
      .ContentDocumentId;
    }

    private void markImportComplete() {
      Import__c initial = [
        SELECT Id
        FROM Import__c
        WHERE Unique_Key__c = :cacheKey AND Job_Sequence__c = 0
        LIMIT 1
      ];
      initial.Job_Status__c = 'Completed';
      update initial;
    }
  }

  // Queueable Job Ends >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

  @AuraEnabled
  public static Map<String, Object> getImportResults(String cacheKey) {
    try {
      List<ImportWrapper> pollingData = new List<ImportWrapper>();

      List<Import__c> JobInfos = [
        SELECT
          Results__c,
          Job_Status__c,
          Job_Sequence__c,
          Total_Jobs__c,
          Processed_Rows__c,
          Error_Message__c // Query Error_Message__c to check for failures
        FROM Import__c
        WHERE Unique_Key__c = :cacheKey AND Job_Sequence__c != NULL
        ORDER BY Job_Sequence__c
      ];

      Decimal totalProcessedRows = 0;
      Set<Id> fileIds = new Set<Id>();
      String errorMessage = ''; // Aggregate error messages from failed jobs
      Boolean hasError = false; // Flag to indicate if any job failed

      for (Import__c jobInfo : JobInfos) {
        if (
          jobInfo.Job_Status__c == 'Failed' &&
          String.isNotBlank(jobInfo.Error_Message__c)
        ) {
          hasError = true;
          errorMessage +=
            'Job ' +
            jobInfo.Job_Sequence__c +
            ': ' +
            jobInfo.Error_Message__c +
            '\n';
        }

        if (
          jobInfo.Job_Sequence__c > 0 &&
          jobInfo.Job_Status__c == 'Completed'
        ) {
          totalProcessedRows += jobInfo.Processed_Rows__c != null
            ? jobInfo.Processed_Rows__c
            : 0;
          fileIds.add(jobInfo.Results__c);
        }
      }

      for (ContentVersion file : [
        SELECT ContentDocumentId, VersionData
        FROM ContentVersion
        WHERE ContentDocumentId IN :fileIds
      ]) {
        String fileBody = file.VersionData.toString();
        List<ImportWrapper> chunk = (List<ImportWrapper>) JSON.deserialize(
          fileBody,
          List<ImportWrapper>.class
        );
        pollingData.addAll(chunk);
      }

      Boolean isComplete = JobInfos[0].Total_Jobs__c == JobInfos.size() - 1;

      Map<String, Object> pollingMap = new Map<String, Object>{
        'results' => pollingData,
        'isComplete' => isComplete,
        'processedRows' => totalProcessedRows,
        'hasError' => hasError, // NEW: Add hasError flag
        'errorMessage' => errorMessage // NEW: Add aggregated error message
      };

      if (isComplete) {
        JobInfos.remove(0);
        delete JobInfos;
      }

      return pollingMap;
    } catch (Exception ex) {
      throw new AuraHandledException(
        'An Error Occured in getImportResults ' +
          ex.getMessage() +
          ' ' +
          ex.getStackTraceString()
      );
    }
  }

  private static String buildUniqueKey(ImportWrapper row) {
    return String.join(
      new List<String>{
        row.fieldValues.get('Employee Last Name')?.trim().toLowerCase() ?? '',
        row.fieldValues.get('Employee First Name')?.trim().toLowerCase() ?? '',
        row.fieldValues.get('Employee Street')?.trim().toLowerCase() ?? '',
        row.fieldValues.get('Employee Zip')?.trim().toLowerCase() ?? ''
      },
      ','
    );
  }
  /*
  @AuraEnabled
public static List<ImportWrapper> revalidateEditedRows(
  List<ImportWrapper> editedRows,
  string uniqueKey,
  string importType,
  List<Id> selectedCaseIssueIds
) {
  // NEW: Retrieve payeeMap from ContentVersion instead of rebuilding
  Import__c initialRecord = [
    SELECT Results__c
    FROM Import__c
    WHERE Unique_Key__c = :uniqueKey AND Job_Sequence__c = 0
    LIMIT 1
  ];
  Map<String, Payee__c> payeeMap = new Map<String, Payee__c>();
  if (String.isNotBlank(initialRecord.Results__c)) {
    List<ContentVersion> cv = [
      SELECT VersionData
      FROM ContentVersion
      WHERE ContentDocumentId = :initialRecord.Results__c AND IsLatest = TRUE
      LIMIT 1
    ];
    payeeMap = (Map<String, Payee__c>) JSON.deserialize(
      cv[0].VersionData.toString(),
      Map<String, Payee__c>.class
    );
  }
  Map<Id,DIR_Violation__c> selectedCaseIssueMap = new  Map<Id,DIR_Violation__c>(
    [Select Id,Name,Violation_Type__r.Name from DIR_Violation__c where Id in : selectedCaseIssueIds]
  );
  List<ImportWrapper> errorRecords = new List<ImportWrapper>();
  List<ImportWrapper> validRecords = new List<ImportWrapper>();
  for (ImportWrapper row : editedRows) {
    row.errorMessages.clear();
    row.isValid = true;
    validateRow(row, payeeMap,importType,selectedCaseIssueMap);
    if (row.isValid) {
      validRecords.add(row);
    } else {
      errorRecords.add(row);
    }
  }
  saveValidRecords(validRecords,uniqueKey);
  System.Debug('Error Records after Revalidation ' + errorRecords);

  // Return ALL records (valid + invalid) so LWC can update previewData fully
  List<ImportWrapper> allRecords = new List<ImportWrapper>();
  allRecords.addAll(validRecords);
  allRecords.addAll(errorRecords);
  return allRecords;
}
*/

  @AuraEnabled
  public static List<ImportWrapper> revalidateEditedRows(
    List<ImportWrapper> editedRows,
    string uniqueKey,
    Id caseId
  ) {
    List<String> chunkUniqueKeys = new List<String>();
    Map<String, ImportWrapper> keyToRow = new Map<String, ImportWrapper>();

    for (ImportWrapper row : editedRows) {
      String uKey = buildUniqueKey(row);
      chunkUniqueKeys.add(uKey);
      keyToRow.put(uKey, row);
    }

    // ONE SOQL for all edited rows
    Map<String, Payee__c> matchingPayees = new Map<String, Payee__c>();
    for (Payee__c p : [
      SELECT Case_Role__r.Entity__r.AccountMatch__c, Payee_Association_JSON__c
      FROM Payee__c
      WHERE
        Case_Role__r.Entity__r.AccountMatch__c IN :chunkUniqueKeys
        AND Case_Management__c = :caseId
    ]) {
      matchingPayees.put(
        p.Case_Role__r.Entity__r.AccountMatch__c.toLowerCase(),
        p
      );
    }

    List<ImportWrapper> errorRecords = new List<ImportWrapper>();
    List<ImportWrapper> validRecords = new List<ImportWrapper>();

    // Validate
    for (String uKey : keyToRow.keySet()) {
      ImportWrapper row = keyToRow.get(uKey);
      Payee__c dup = matchingPayees.get(uKey);
      if (dup != null) {
        row.isDuplicate = true;
      }
      validateRow(row);
      if (row.isValid) {
        validRecords.add(row);
      } else {
        errorRecords.add(row);
      }
    }
    saveValidRecords(validRecords, uniqueKey);
    List<ImportWrapper> allRecords = new List<ImportWrapper>();
    allRecords.addAll(validRecords);
    allRecords.addAll(errorRecords);
    return allRecords;
  }

  // Save valid records
  @AuraEnabled
  public static String saveValidRecords(
    List<ImportWrapper> rows,
    string uniqueKey
  ) {
    try {
      List<Import__c> toInsert = new List<Import__c>();
      for (ImportWrapper row : rows) {
        if (row.isValid) {
          Import__c rec = new Import__c();
          rec.Case_Management__c = row.caseId;
          rec.Unique_Key__c = uniqueKey;
          rec.Employee_First_Name__c = row.fieldValues.get(
            'Employee First Name'
          );
          rec.Employee_Last_Name__c = row.fieldValues.get('Employee Last Name');
          rec.Employee_Street__c = row.fieldValues.get('Employee Street');
          rec.Employee_City__c = row.fieldValues.get('Employee City');
          rec.Employee_State__c = row.fieldValues.get('Employee State');
          rec.Employee_Zip__c = row.fieldValues.get('Employee Zip');
          rec.Period_Covered_by_Adjustment__c = row.fieldValues.get(
            'Period Covered by Adjustment'
          );
          rec.Direct_Pay__c = row.fieldValues.get('Direct Pay');
          rec.Has_Matching_Account__c = row.isDuplicate;

          try {
            String totalWage = row.fieldValues.get('Total Wage Assessment');
            rec.Total_Wage_Assessment__c = String.isNotBlank(totalWage)
              ? Decimal.valueOf(totalWage)
              : null;

            String deductionsTotal = row.fieldValues.get('Deductions: Total');
            rec.Deductions_Total__c = String.isNotBlank(deductionsTotal)
              ? Decimal.valueOf(deductionsTotal)
              : null;

            String netWages = row.fieldValues.get('Net Wages Assessed');
            rec.Net_Wages_Paid__c = String.isNotBlank(netWages)
              ? Decimal.valueOf(netWages)
              : null;

            String factor = row.fieldValues.get('Factor');
            rec.Factor__c = String.isNotBlank(factor)
              ? Decimal.valueOf(factor)
              : null;
          } catch (Exception e) {
            row.errorMessages.add('Invalid numeric value: ' + e.getMessage());
            row.isValid = false;
            continue;
          }
          toInsert.add(rec);
        }
      }

      if (!toInsert.isEmpty()) {
        insert toInsert;
        return toInsert.size() + ' records inserted successfully.';
      }
      return 'No valid records to insert.';
    } catch (Exception ex) {
      throw new AuraHandledException(
        'An error occured in SaveValidRecords ' +
          ex.getMessage() +
          ' ' +
          ex.getStackTraceString()
      );
    }
  }

  // Row validation
  private static void validateRow(ImportWrapper row) {
    List<String> requiredFields = new List<String>{
      'Employee First Name',
      'Employee Last Name',
      'Employee Street',
      'Employee City',
      'Employee State',
      'Employee Zip',
      'Total Wage Assessment',
      'Net Wages Assessed',
      'Factor'
    };
    for (String field : requiredFields) {
      if (String.isBlank(row.fieldValues.get(field))) {
        row.errorMessages.add(field + ' is required.');
        row.isValid = false;
      }
    }
    /*
    String ssn = row.fieldValues.get('SSN');
    if (String.isNotBlank(ssn)) {
      String cleanedSSN = ssn.replaceAll('[- ]', '');
      if (!Pattern.matches('\\d{9}', cleanedSSN)) {
        row.errorMessages.add('SSN must be 9 digits.');
        row.isValid = false;
      }
    }
*/
    String directPay = row.fieldValues.get('Direct Pay');
    if (String.isNotBlank(directPay)) {
      string cleanedDirectPay = directPay.toLowerCase();
      if (cleanedDirectPay != 'yes' && cleanedDirectPay != 'no') {
        row.errorMessages.add(
          'Direct Pay is not Valid ,Enter either Yes or No'
        );
        row.isValid = false;
      }
    }
    List<String> numericFields = new List<String>{
      'Total Wage Assessment',
      'Deductions: Total',
      'Net Wages Assessed',
      'Factor'
    };
    for (String field : numericFields) {
      String value = row.fieldValues.get(field);
      if (String.isNotBlank(value)) {
        try {
          Decimal num = Decimal.valueOf(value);
          if (num < 0) {
            row.errorMessages.add(field + ' cannot be negative.');
            row.isValid = false;
          }
        } catch (Exception e) {
          row.errorMessages.add(field + ' must be a valid number.');
          row.isValid = false;
        }
      }
    }
  }

  // CSV parser
  private static List<String> parseCsvLine(String line) {
    List<String> fields = new List<String>();
    String compositeField = '';
    Boolean inQuotes = false;

    line = line.replaceAll('""', 'DBLQT');
    List<String> characters = line.split('');
    for (String character : characters) {
      if (character == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (character == ',' && !inQuotes) {
        fields.add(compositeField.replaceAll('DBLQT', '"').trim());
        compositeField = '';
        continue;
      }
      compositeField += character;
    }
    fields.add(compositeField.replaceAll('DBLQT', '"').trim());

    List<String> cleanFields = new List<String>();
    for (String field : fields) {
      if (field.startsWith('"') && field.endsWith('"')) {
        cleanFields.add(field.substring(1, field.length() - 1));
      } else {
        cleanFields.add(field);
      }
    }
    return cleanFields;
  }

  public static List<Payee__c> queryPayees(Id caseId) {
    // Query all the Payees and their respective Assessment Associations
    return [
      SELECT
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
    ];
  }
  /*
  // Card-1 Select import Type Card
  @AuraEnabled(cacheable=true)
    public static List<Payee__c> getPayees(Id caseManagementId) {
      if (String.isBlank(caseManagementId)) {
            return new List<Payee__c>();
        }
        return [
            SELECT Name, Case_Management__r.Name,Case_Role__r.Entity__r.FirstName, 
              Case_Role__r.Entity__r.LastName, Case_Role__r.Entity__r.ShippingStreet, 
              Case_Role__r.Entity__r.ShippingCity, Case_Role__r.Entity__r.ShippingState, 
              Case_Role__r.Entity__r.ShippingPostalCode, PeriodCovered__c, WageAssessment__c, 
              TotalDeductions__c, NetWages__c, Factor__c
            FROM Payee__c
            WHERE Case_Management__c = :caseManagementId
            
        ];
    }
*/
  @AuraEnabled
  public static String runBulkPayeeCreation(
    Id caseId,
    List<Id> caseIssueIds,
    String uniqueKey,
    string importType
  ) {
    try {
      Set<Id> caseIssueIdSet = new Set<Id>(caseIssueIds);
      // Call your batch class

      //Database.executeBatch(
      //    new BulkPayeeCreation(caseId,caseIssueIdSet,uniqueKey,importType),
      //    200
      // );
      Set<Id> setOfCaseIssueIds = new Set<Id>();
      for (Id caseIssueId : caseIssueIds) {
        setOfCaseIssueIds.add(caseIssueId);
      }

      List<AsyncApexJob> jobLIst = [
        SELECT Id, MethodName, JobType, ApexClass.Name, Status
        FROM AsyncApexJob
        WHERE
          (ApexClass.Name = 'ProcessImportRecordsRedesigned'
          OR ApexClass.Name = 'ProcessDuplicatePayeesBatch')
          AND CreatedById = :UserInfo.getUserId()
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      system.Debug('JOb Found ' + jobLIst.size() + jobLIst[0].Status);
      if (jobLIst[0].Status != 'Completed') {
        return 'Payee processing is in progress. A confirmation email will be sent when it is complete.';
      }

      ProcessImportRecordsRedesigned batch = new ProcessImportRecordsRedesigned();
      batch.caseId = caseId;
      batch.importType = importType;
      batch.caseIssueIds = setOfCaseIssueIds;
      batch.uniqueKey = uniqueKey;
      Database.executeBatch(batch, 200);

      //ProcessPayees.createAccountsWithCaseRole(caseId,uniqueKey,caseIssueIdSet);
      // Return immediate response to LWC
      return 'Processing Payees... You will receive an email once it\'s completed.';
    } catch (Exception e) {
      // Return error message if something fails
      return 'Error while starting the batch job: ' +
        e.getMessage() +
        ' ' +
        e.getStackTraceString();
    }
  }
  // Wrapper class
  public class ImportWrapper {
    @AuraEnabled
    public Integer rowNumber { get; set; }
    @AuraEnabled
    public Map<String, String> fieldValues { get; set; }
    @AuraEnabled
    public String caseId { get; set; }
    @AuraEnabled
    public Boolean isValid { get; set; }
    @AuraEnabled
    public boolean isDuplicate { get; set; }
    @AuraEnabled
    public Boolean proceedWithExistingAccount { get; set; }
    @AuraEnabled
    public List<String> errorMessages { get; set; }

    public ImportWrapper() {
      fieldValues = new Map<String, String>();
      errorMessages = new List<String>();

      isValid = true;
      proceedWithExistingAccount = false;
      isDuplicate = false;
      caseId = null;
    }
  }

  public class CaseIssueWrapper {
    @AuraEnabled
    public DIR_Violation__c caseIssue { get; set; }
    @AuraEnabled
    public Id caseIssueId { get; set; }

    @AuraEnabled
    public String caseIssueName { get; set; }
    @AuraEnabled
    public String violationType { get; set; }
    /*
        @AuraEnabled
        public String citationform {get; set;}
        */
    @AuraEnabled
    public String citationNumber { get; set; }

    @AuraEnabled
    public Decimal amountutilizedbyPayee { get; set; }

    @AuraEnabled
    public Decimal balanceDue { get; set; }

    @AuraEnabled
    public boolean disableCheckBox {
      get {
        return this.balanceDue == 0 ? true : false;
      }
      set;
    }

    public CaseIssueWrapper(DIR_Violation__c ci, string importType) {
      this.caseIssue = ci;
      this.caseIssueId = ci.Id;
      this.citationNumber = ci.Citation_Number__c;
      this.caseIssueName = ci.Name;
      this.violationType = ci.Violation_Type__r.Wizard_Search_Text__c;
      this.amountutilizedbyPayee = ci.Amount_Utilized_from_Payee__c != null
        ? ci.Amount_Utilized_from_Payee__c
        : 0;
      this.balanceDue = 0;
      //this.citationform = ci.Citation_Form__c;
      //this.balanceDue = importType == 'Corrective_Form_40' ? ci.Wage_Balance_Due__c : ci.Remaining_Amount_to_Upload__c;
      //this.disableCheckBox = importType != 'Corrective_Form_40' && ci.Remaining_Amount_to_Upload__c ==0 ? true : false;

      if (ci.Wage_Balance_Due__c != 0) {
        Decimal reservedAmount = (ci.Amount_Reserved__c == null)
          ? 0
          : ci.Amount_Reserved__c;
        Decimal utilizedAmount = (ci.Amount_Utilized_from_Payee__c == null)
          ? 0
          : ci.Amount_Utilized_from_Payee__c;

        if (importType == 'Form_40')
          this.balanceDue = ci.Wage_Balance_Due__c - utilizedAmount;
        if (
          importType == 'Form_40' &&
          ci.Wage_Balance_Due__c - utilizedAmount == 0
        )
          this.disableCheckBox = true;

        if (importType == 'Corrective_Form_40')
          this.balanceDue = utilizedAmount;
        if (importType == 'Corrective_Form_40' && utilizedAmount == 0)
          this.disableCheckBox = true;

        if (
          importType == 'Form_40_Partial' &&
          utilizedAmount != ci.Wage_Balance_Due__c
        )
          this.balanceDue = reservedAmount - utilizedAmount;
        if (
          importType == 'Form_40_Partial' &&
          utilizedAmount == ci.Wage_Balance_Due__c
        )
          this.balanceDue = 0;
        if (importType == 'Form_40_Partial' && this.balanceDue == 0)
          this.disableCheckBox = true;
      }

      //Decimal partialAmount = reservedAmount - utilizedAmount;
      // this.balanceDue = importType == 'Corrective_Form_40' && reservedAmount == utilizedAmount ? reservedAmount :  ci.Remaining_Amount_to_Upload__c;
      // / this.balanceDue = importType == 'Form_40_Partial' ? partialAmount : ci.Remaining_Amount_to_Upload__c;
      // this.disableCheckBox = importType == 'Form_40_Partial' && partialAmount == 0 ? true : false;
    }
  }
}