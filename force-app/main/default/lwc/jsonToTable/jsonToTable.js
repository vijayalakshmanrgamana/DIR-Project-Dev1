import { LightningElement, api, track, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const JSON_FIELD = 'Payee__c.Payee_Association_JSON__c';

export default class JsonToTable extends LightningElement {
    @api recordId;

    @track autoTableData;
    @track autoColumns;
    @track autoJsonData;
    @track autoError;
    @track isLoading = true;
    @track dynamicTitle = 'Payee Association';

    // --- Column Mapping Definition ---
    columnMapping = [
        { jsonKey: 'caseIssueName', label: 'Case Issue', type: 'url', urlFieldName: 'Case_Issue_Link_URL', labelFieldName: 'Case_Issue_Label' },
        { jsonKey: 'citationForm', label: 'Citation Form', type: 'text' }, // Target for 'Sum' label
       // { jsonKey: 'netWagesBreakdown', label: 'Net Wages Breakdown', type: 'currency' },
        { jsonKey: 'factor', label: 'Factor', type: 'number', typeAttributes: { minimumIntegerDigits: 1, maximumFractionDigits: 5 } },
        //{ jsonKey: 'totalWageAssessmentBreakdown', label: 'Total Wage Assessment Breakdown', type: 'currency' },
        //{ jsonKey: 'caseIssueBreakdown', label: 'Case Issue Breakdown', type: 'currency' },
       // { jsonKey: 'deductionsTotalBreakdown', label: 'Deductions Total Breakdown', type: 'currency' },
        { jsonKey: 'caseIssueId', label: 'Case Issue Id', type: 'hidden' }
    ];

    get shouldShowFinalError() {
        return this.autoError && this.autoError !== 'Waiting for record ID...';
    }

    // --- Wire record ---
    @wire(getRecord, { recordId: '$recordId', fields: [JSON_FIELD] })
    wiredPayeeRecord({ error, data }) {
        if (!this.recordId) {
            this.autoError = 'Waiting for record ID...';
            this.isLoading = true;
            return;
        }

        if (data) {
            const jsonValue = data.fields.Payee_Association_JSON__c.value;
            this.autoError = null;
            this.autoJsonData = jsonValue;
            this.processAutoJson();
            this.isLoading = false;
        } else if (error) {
            this.autoError =
                error.body && error.body.message
                    ? error.body.message
                    : error.message || 'An unknown error occurred while fetching record data.';
            this.autoJsonData = null;
            this.dynamicTitle = 'Payee Association (0)';
            this.isLoading = false;
        }
    }

    // --- JSON Processing ---
    processAutoJson() {
        if (this.autoJsonData) {
            this.convertJsonToTable(this.autoJsonData);
        }
    }

    // --- Convert JSON to Table ---
    convertJsonToTable(jsonString) {
        try {
            let parsedData = JSON.parse(jsonString);
            if (typeof parsedData === 'string') parsedData = JSON.parse(parsedData);

            if (!Array.isArray(parsedData)) {
                throw new Error('JSON structure is invalid: expected an array of objects.');
            }

            const recordCount = parsedData.length;
            this.dynamicTitle = `Payee Association (${recordCount})`;

            // --- Map JSON to Table Data ---
            const dataForTable = parsedData.map((row, index) => {
                const newRow = { id: index + 1 };
                const caseIssueId = row['caseIssueId'] || null;
                const caseIssueName = row['caseIssueName'] || null;

                newRow.Case_Issue_Link_URL = caseIssueId ? `/${caseIssueId}` : null;
                newRow.Case_Issue_Label = caseIssueName;

                this.columnMapping.forEach(colDef => {
                    newRow[colDef.jsonKey] = row[colDef.jsonKey];
                });

                return newRow;
            });

            // --- Define datatable columns ---
            const cols = this.columnMapping
                .filter(col => col.type !== 'hidden')
                .map(colDef => {
                    let columnDef = {
                        label: colDef.label,
                        fieldName: colDef.jsonKey,
                        type: colDef.type,
                        sortable: true
                    };

                    if (colDef.jsonKey === 'caseIssueName') {
                        columnDef.fieldName = colDef.urlFieldName; // Case_Issue_Link_URL
                        columnDef.typeAttributes = {
                            label: { fieldName: colDef.labelFieldName }, // Case_Issue_Label
                            target: '_blank',
                            tooltip: 'Open Case Issue Record'
                        };
                    }

                    if (colDef.typeAttributes) {
                        columnDef.typeAttributes = {
                            ...columnDef.typeAttributes,
                            ...colDef.typeAttributes
                        };
                    }

                    return columnDef;
                });

            // Conditional Spacer & Total Row Logic
            let tableData = [...dataForTable];

            /*
            // --- START: COMMENTED OUT SUM/TOTAL LOGIC (User Request) ---
            if (recordCount > 1) {
                const spacerRow = this.createSpacerRow();
                const totalRow = this.calculateTotalsRow(dataForTable);
                tableData.push(spacerRow, totalRow);
            }
            // --- END: COMMENTED OUT SUM/TOTAL LOGIC ---
            */

            // Assign for display
            this.autoColumns = cols;
            this.autoTableData = tableData;

        } catch (e) {
            console.error('Invalid JSON:', e.message);
            this.autoError = e.message;
            this.autoTableData = null;
            this.autoColumns = null;
            this.dynamicTitle = 'Payee Association (0)';
        }
    }

    // --- Spacer Row (Kept for future use) ---
    createSpacerRow() {
        return {
            id: 'spacer-row',
            Case_Issue_Label: '',
            isSpacerRow: true
        };
    }

    // --- Calculate the Total Row (MODIFIED) (Kept for future use) ---
    calculateTotalsRow(data) {
        const fieldsToSum = [
            'netWagesBreakdown',
            'totalWageAssessmentBreakdown',
            'deductionsTotalBreakdown',
            'factor',
            'caseIssueBreakdown'
        ];

        const totals = {};
        fieldsToSum.forEach(field => {
            totals[field] = data.reduce((sum, row) => sum + (parseFloat(row[field]) || 0), 0);
        });

        return {
            id: 'sum-row',
            Case_Issue_Label: '', // Set Case Issue Label to empty
            caseIssueName: '',   // Set Case Issue Name to empty
            citationForm: 'Breakdown Total', // <-- 'Sum' is now under Citation Form
            ...totals,
            isTotalRow: true
        };
    }
}