import { LightningElement, api, track, wire } from 'lwc';
import getLogoUrl from '@salesforce/apex/HIPApplicationCtrl.getLogoUrl';
import getInitialData from '@salesforce/apex/HIPApplicationCtrl.getInitialData';
import uploadFile from '@salesforce/apex/HIPApplicationCtrl.uploadFile';
import removeUploadedFile from '@salesforce/apex/HIPApplicationCtrl.removeUploadedFile';
import submitApplication from '@salesforce/apex/HIPApplicationCtrl.submitApplication';
import saveApplicationPdf from '@salesforce/apex/HIPApplicationCtrl.saveApplicationPdf';

const ASSET_ROW_TYPES = [
    'Checking',
    'Savings',
    'CDs',
    'Credit Union',
    'Digital Assets (VenMo, Zelle, etc.)',
    'Life Insurance (whole life only)',
    'Stocks',
    'Trust Account',
    'Other (specify)'
];

const HOUSEHOLD_MONEY_FIELDS = [
    'weatherizationAmount',
    'repairContribution'
];

const PROPERTY_MONEY_FIELDS = [
    'mortgageBalance',
    'mortgageMonthlyPayment',
    'annualInsurancePremium',
    'annualTaxesPaid',
    'appraisedMarketValue',
    'recentTaxBillAmount'
];

const BORROWER_MONEY_FIELDS = [
    'employmentGrossMonthlyAmount',
    'pension',
    'socialSecurityDisability',
    'ssiSsdAmount',
    'unemployment',
    'selfEmployment',
    'veteransBenefits',
    'rentalIncome',
    'earnedIncomeTaxCredit',
    'alimonyChildSupport',
    'childSupport',
    'investmentIncome',
    'interestIncome',
    'publicAssistance',
    'otherIncome'
];

const FINANCIAL_MONEY_FIELDS = [
    'salaryWages',
    'otherHouseholdSalary',
    'dividends',
    'bankAndInvestmentInterest',
    'investments',
    'reimbursements',
    'otherIncome',
    'totalMonthlyIncome',
    'housingMortgageTaxesInsurance',
    'carLoan',
    'carInsurance',
    'houseInsurance',
    'lifeInsurance',
    'childcare',
    'charity',
    'gasElectric',
    'telephone',
    'cableSatelliteTv',
    'internet',
    'food',
    'entertainment',
    'gifts',
    'clothing',
    'petSupplies',
    'healthInsurance',
    'otherExpense',
    'alimonyChildSupport',
    'totalLivingExpenses',
    'difference'
];

const DEBT_MONEY_FIELDS = [
    'monthlyPayment',
    'balance'
];

function getTodayValue() {
    const dateValue = new Date();
    const year = dateValue.getFullYear();
    const month = String(dateValue.getMonth() + 1).padStart(2, '0');
    const day = String(dateValue.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

function createAssetRows(ownerId) {
    return ASSET_ROW_TYPES.map((accountType, index) => ({
        id: `${ownerId}-asset-${index + 1}`,
        accountType,
        accountNumber: '',
        interestRate: '',
        institutionName: '',
        amount: ''
    }));
}

function createBorrowerRow(id, roleLabel) {
    return {
        id,
        roleLabel,
        name: '',
        ssn: '',
        dateOfBirth: '',
        phone: '',
        emailAddress: '',
        relationship: '',
        employer: '',
        positionHeld: '',
        howLongEmployed: '',
        employmentGrossMonthlyAmount: '',
        pension: '',
        pensionSourceAddress: '',
        socialSecurityDisability: '',
        ssiSsdType: '',
        ssiSsdAmount: '',
        unemployment: '',
        selfEmployment: '',
        veteransBenefits: '',
        rentalIncome: '',
        earnedIncomeTaxCredit: '',
        alimonyChildSupport: '',
        childSupport: '',
        investmentIncome: '',
        interestIncome: '',
        publicAssistance: '',
        otherIncome: '',
        assets: createAssetRows(id)
    };
}

function hasTextValue(value) {
    return String(value === null || value === undefined ? '' : value).trim() !== '';
}

function cleanMoneyValue(value) {
    const rawValue = String(value === null || value === undefined ? '' : value).trim();
    let cleanValue = rawValue.replace(/\$/g, '').replace(/,/g, '').replace(/\s/g, '');
    cleanValue = cleanValue.replace(/[^0-9.-]/g, '');

    const isNegative = cleanValue.indexOf('-') === 0;
    cleanValue = cleanValue.replace(/-/g, '');

    const decimalParts = cleanValue.split('.');
    if (decimalParts.length > 1) {
        cleanValue = decimalParts[0] + '.' + decimalParts.slice(1).join('');
    }

    if (isNegative && cleanValue) {
        cleanValue = '-' + cleanValue;
    }

    return cleanValue;
}

function formatMoneyValue(value) {
    const cleanValue = cleanMoneyValue(value);
    let formattedValue = '';

    if (cleanValue) {
        const numberValue = Number(cleanValue);
        if (Number.isNaN(numberValue)) {
            formattedValue = cleanValue;
        } else {
            formattedValue = numberValue.toLocaleString('en-US', {
                minimumFractionDigits: 2,
                maximumFractionDigits: 2
            });
        }
    }

    return formattedValue;
}

function borrowerHasEnteredData(borrower) {
    const borrowerFields = [
        'name',
        'ssn',
        'dateOfBirth',
        'phone',
        'emailAddress',
        'relationship',
        'employer',
        'positionHeld',
        'howLongEmployed',
        'employmentGrossMonthlyAmount',
        'pension',
        'pensionSourceAddress',
        'socialSecurityDisability',
        'ssiSsdType',
        'ssiSsdAmount',
        'unemployment',
        'selfEmployment',
        'veteransBenefits',
        'rentalIncome',
        'earnedIncomeTaxCredit',
        'alimonyChildSupport',
        'childSupport',
        'investmentIncome',
        'interestIncome',
        'publicAssistance',
        'otherIncome'
    ];

    const hasBorrowerFields = borrowerFields.some(fieldName => hasTextValue(borrower[fieldName]));
    const hasAssetFields = (borrower.assets || []).some(asset => (
        hasTextValue(asset.accountNumber)
        || hasTextValue(asset.interestRate)
        || hasTextValue(asset.institutionName)
        || hasTextValue(asset.amount)
    ));

    return hasBorrowerFields || hasAssetFields;
}

export default class HipApplicationLwc extends LightningElement {
    @api isPreview;
    @api recordId;
    @api senderId;
    @api sendDate;

    @track logoUrl;
    @track uploadedFileMessage;
    @track submitMessage;
    @track submitError;
    @track isSubmitting = false;
    @track isSubmitted = false;
    @track submittedDateDisplay = '';
    @track readOnlyFiles = [];
    @track applicantSignatureUrl = '';
    @track coApplicantSignatureUrl = '';
    @track signatures = {
        applicant: {
            printName: '',
            signDate: getTodayValue(),
            isSigned: false
        },
        coApplicant: {
            printName: '',
            signDate: getTodayValue(),
            isSigned: false
        }
    };

    canvasMap = {};
    ctxMap = {};
    isDrawing = false;
    activeSignatureId;

    yesNoOptions = [
        { label: 'Select', value: '' },
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];

    maritalStatusOptions = [
        { label: 'Select', value: '' },
        { label: 'Single', value: 'Single' },
        { label: 'Married', value: 'Married' },
        { label: 'Divorced', value: 'Divorced' },
        { label: 'Separated', value: 'Seperated' },
        { label: 'Widowed', value: 'Widowed' }
    ];

    householdTypeOptions = [
        { label: 'Select', value: '' },
        { label: 'Female-headed single-parent household', value: 'Female-headed single-parent household' },
        { label: 'Single Adult', value: 'Single Adult' },
        { label: 'Married with children', value: 'Married with children' },
        { label: 'Male-headed single-parent household', value: 'Male-headed single-parent household' },
        { label: 'Two or more unrelated adults', value: 'Two or more unrelated adults' },
        { label: 'Married without children', value: 'Married without children' }
    ];

    raceOptions = [
        { label: 'Select', value: '' },
        { label: 'White', value: 'White' },
        { label: 'Black', value: 'Black' },
        { label: 'Asian/Pacific Islander', value: 'Asian/Pacific Islander' },
        { label: 'Hispanic', value: 'Hispanic' },
        { label: 'Native American', value: 'Native American' },
        { label: 'Other', value: 'Other' }
    ];

    ssiSsdOptions = [
        { label: 'Select', value: '' },
        { label: 'SSI', value: 'SSI' },
        { label: 'SSD', value: 'SSD' }
    ];

    @track household = {
        applicantName: '',
        propertyAddress: '',
        maritalStatus: '',
        householdType: '',
        numberOfUnitsInBuilding: '',
        familyHouseholdSize: '',
        howManyDependents: '',
        homeEverReceivedWeatherization: '',
        weatherizationYear: '',
        weatherizationAmount: '',
        weatherizationPending: '',
        heapAssistance: '',
        heapYear: '',
        repairContribution: ''
    };

    @track propertyInfo = {
        soldProperty: '',
        soldPropertyDetails: '',
        disposedAssets: '',
        assetDisposalDescription: '',
        deedNames: '',
        purchaseDate: '',
        mortgageExists: '',
        mortgageBalance: '',
        mortgageMonthlyPayment: '',
        escrowIncluded: '',
        behindMortgage: '',
        homeownerInsurance: '',
        annualInsurancePremium: '',
        taxesCurrent: '',
        annualTaxesPaid: '',
        otherLiens: '',
        lienExplanation: '',
        appraisedMarketValue: '',
        recentTaxBillAmount: '',
        singleFamilyHouse: '',
        houseAge: '',
        bedrooms: '',
        unitsIfNotSingleFamily: '',
        buildingsOnProperty: '',
        otherBuildingUse: '',
        repairNeeds: ''
    };

    @track characteristics = {
        raceEthnicityHead: '',
        raceEthnicityCoApplicant: '',
        hasGalvanTies: '',
        galvanTiesExplanation: ''
    };

    @track debtSummary = {
        currentHouseholdMonthlyDebt: ''
    };

    @track financialAssessment = {
        salaryWages: '',
        otherHouseholdSalary: '',
        dividends: '',
        bankAndInvestmentInterest: '',
        investments: '',
        reimbursements: '',
        otherIncome: '',
        totalMonthlyIncome: '',
        housingMortgageTaxesInsurance: '',
        carLoan: '',
        carInsurance: '',
        houseInsurance: '',
        lifeInsurance: '',
        childcare: '',
        charity: '',
        gasElectric: '',
        telephone: '',
        cableSatelliteTv: '',
        internet: '',
        food: '',
        entertainment: '',
        gifts: '',
        clothing: '',
        petSupplies: '',
        healthInsurance: '',
        otherExpense: '',
        alimonyChildSupport: '',
        totalLivingExpenses: '',
        difference: ''
    };

    @track borrowers = [
        createBorrowerRow('borrower-1', 'Adult One / Applicant'),
        createBorrowerRow('borrower-2', 'Adult Two / Co-Applicant')
    ];

    @track debts = [
        { id: 'debt-1', debtType: '', monthlyPayment: '', balance: '' },
        { id: 'debt-2', debtType: '', monthlyPayment: '', balance: '' },
        { id: 'debt-3', debtType: '', monthlyPayment: '', balance: '' }
    ];

    @track applicationDocuments = [
        { id: 'homeOwnership', label: 'Proof of Home ownership (legible copy of recorded deed)', uploadedFiles: [], hasFiles: false, isChecked: false, isUploading: false, uploadError: '' },
        { id: 'homeownersInsurance', label: "Proof of Homeowner's insurance (recent declaration page/recent certificate from agent)", uploadedFiles: [], hasFiles: false, isChecked: false, isUploading: false, uploadError: '' },
        { id: 'taxReceipt', label: 'Copies of most recent paid Property, Town and Village AND School tax receipt', uploadedFiles: [], hasFiles: false, isChecked: false, isUploading: false, uploadError: '' },
        { id: 'mortgageStatement', label: 'Most recent mortgage statement, if applicable. The mortgage must be paid up to date.', uploadedFiles: [], hasFiles: false, isChecked: false, isUploading: false, uploadError: '' }
    ];

    @track adultHouseholdDocuments = [
        { id: 'incomeProof', label: 'Proof of income from all sources - 2 months of current and consecutive pay stubs, statements from SS, SSD, SSI, child support, alimony, DSS assistance, etc.', uploadedFiles: [], hasFiles: false, isChecked: false, isUploading: false, uploadError: '' },
        { id: 'federalTaxReturns', label: "Completed, signed and dated copies of the most recent FEDERAL tax returns and W2's (2024 and 2025) OR a notarized statement of non-filing of tax returns, if applicable", uploadedFiles: [], hasFiles: false, isChecked: false, isUploading: false, uploadError: '' },
        { id: 'bankStatements', label: 'Three most recent bank statements for each bank account per household member', uploadedFiles: [], hasFiles: false, isChecked: false, isUploading: false, uploadError: '' },
        { id: 'lifeInsurance', label: 'Recent whole life insurance policy (if applicable) statement showing the cash surrender value (term life policies are excluded)', uploadedFiles: [], hasFiles: false, isChecked: false, isUploading: false, uploadError: '' },
        { id: 'paymentApps', label: 'Recent statements showing your name and your balance of ALL peer-to-peer payment apps including but not limited to: VenMo, Zelle, CashApp, Paypal, etc.', uploadedFiles: [], hasFiles: false, isChecked: false, isUploading: false, uploadError: '' },
        { id: 'utilityBills', label: 'Copies of most recent utility bills and monthly debt obligations, i.e., electric, phone, etc.', uploadedFiles: [], hasFiles: false, isChecked: false, isUploading: false, uploadError: '' },
        { id: 'financialAssessment', label: 'Completed Financial Assessment (page 9)', uploadedFiles: [], hasFiles: false, isChecked: false, isUploading: false, uploadError: '' }
    ];

    connectedCallback() {
        this.loadInitialData();
    }

    @wire(getLogoUrl)
    wiredLogo({ data, error }) {
        if (data) {
            this.logoUrl = data;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Failed to load HIP application logo', error);
            this.logoUrl = null;
        }
    }

    renderedCallback() {
        const canvases = this.template.querySelectorAll('canvas[data-signature-id]');

        if (canvases && canvases.length > 0) {
            canvases.forEach(canvas => {
                const signatureId = canvas.dataset.signatureId;

                if (signatureId && this.canvasMap[signatureId] !== canvas) {
                    this.canvasMap[signatureId] = canvas;
                    const ctx = canvas.getContext('2d');
                    this.ctxMap[signatureId] = ctx;
                    this.setCanvasSize(canvas, ctx);
                }
            });
        }

        this.applyReadOnlyState();
    }

    get hasReadOnlyFiles() {
        return this.readOnlyFiles.length > 0;
    }

    get showReadOnlyFiles() {
        return this.isSubmitted && this.hasReadOnlyFiles;
    }

    get submittedStatusMessage() {
        const dateText = this.submittedDateDisplay ? ` on ${this.submittedDateDisplay}` : '';
        return `HIP Application submitted${dateText}. This form is locked.`;
    }

    get isSubmitDisabled() {
        return this.isSubmitting || this.isSubmitted || !this.signatures.applicant.isSigned;
    }

    get showApplicantSignatureImage() {
        return this.isSubmitted && !!this.applicantSignatureUrl;
    }

    get showCoApplicantSignatureImage() {
        return this.isSubmitted && !!this.coApplicantSignatureUrl;
    }

    get coApplicantRequired() {
        return this.borrowers.slice(1).some(borrowerHasEnteredData);
    }

    get yesNoChecked() {
        const household = this.household;
        const property = this.propertyInfo;

        return {
            homeWeatherizationYes: household.homeEverReceivedWeatherization === 'Yes',
            homeWeatherizationNo: household.homeEverReceivedWeatherization === 'No',
            weatherizationPendingYes: household.weatherizationPending === 'Yes',
            weatherizationPendingNo: household.weatherizationPending === 'No',
            heapAssistanceYes: household.heapAssistance === 'Yes',
            heapAssistanceNo: household.heapAssistance === 'No',
            soldPropertyYes: property.soldProperty === 'Yes',
            soldPropertyNo: property.soldProperty === 'No',
            disposedAssetsYes: property.disposedAssets === 'Yes',
            disposedAssetsNo: property.disposedAssets === 'No',
            mortgageExistsYes: property.mortgageExists === 'Yes',
            mortgageExistsNo: property.mortgageExists === 'No',
            escrowIncludedYes: property.escrowIncluded === 'Yes',
            escrowIncludedNo: property.escrowIncluded === 'No',
            behindMortgageYes: property.behindMortgage === 'Yes',
            behindMortgageNo: property.behindMortgage === 'No',
            homeownerInsuranceYes: property.homeownerInsurance === 'Yes',
            homeownerInsuranceNo: property.homeownerInsurance === 'No',
            taxesCurrentYes: property.taxesCurrent === 'Yes',
            taxesCurrentNo: property.taxesCurrent === 'No',
            otherLiensYes: property.otherLiens === 'Yes',
            otherLiensNo: property.otherLiens === 'No',
            singleFamilyHouseYes: property.singleFamilyHouse === 'Yes',
            singleFamilyHouseNo: property.singleFamilyHouse === 'No'
        };
    }

    loadInitialData() {
        if (this.recordId) {
            getInitialData({ recordId: this.recordId })
                .then(data => {
                    const initialData = data || {};
                    this.isSubmitted = initialData.isSubmitted === true;
                    this.submittedDateDisplay = initialData.submittedDateDisplay || '';
                    this.applicantSignatureUrl = initialData.applicantSignatureUrl || '';
                    this.coApplicantSignatureUrl = initialData.coApplicantSignatureUrl || '';
                    this.signatures = {
                        applicant: {
                            ...this.signatures.applicant,
                            printName: initialData.applicantPrintName || this.signatures.applicant.printName,
                            signDate: initialData.applicantSignDate || this.signatures.applicant.signDate,
                            isSigned: this.signatures.applicant.isSigned || !!initialData.applicantSignatureUrl
                        },
                        coApplicant: {
                            ...this.signatures.coApplicant,
                            printName: initialData.coApplicantPrintName || this.signatures.coApplicant.printName,
                            signDate: initialData.coApplicantSignDate || this.signatures.coApplicant.signDate,
                            isSigned: this.signatures.coApplicant.isSigned || !!initialData.coApplicantSignatureUrl
                        }
                    };
                    this.household = {
                        ...this.household,
                        applicantName: this.household.applicantName || initialData.applicantName || '',
                        propertyAddress: this.household.propertyAddress || initialData.propertyAddress || ''
                    };
                    this.applySavedApplication(initialData.savedApplication);
                    this.applyInitialFiles(Array.isArray(initialData.files) ? initialData.files : []);

                })
                .catch(error => {
                    // eslint-disable-next-line no-console
                    console.error('Failed to load HIP application data', error);
                    this.uploadedFileMessage = this.extractErrorMessage(error);
                });
        }
    }

    applySavedApplication(savedApplication) {
        const savedData = savedApplication || {};

        if (savedData.household) {
            const householdData = this.formatMoneyFields(savedData.household, HOUSEHOLD_MONEY_FIELDS);
            this.household = {
                ...this.household,
                ...householdData,
                applicantName: this.household.applicantName,
                propertyAddress: this.household.propertyAddress
            };
        }
        if (savedData.propertyInfo) {
            const propertyData = this.formatMoneyFields(savedData.propertyInfo, PROPERTY_MONEY_FIELDS);
            this.propertyInfo = { ...this.propertyInfo, ...propertyData };
        }
        if (savedData.characteristics) {
            this.characteristics = { ...this.characteristics, ...savedData.characteristics };
        }
        if (savedData.debtSummary) {
            const debtSummaryData = this.formatMoneyFields(savedData.debtSummary, ['currentHouseholdMonthlyDebt']);
            this.debtSummary = { ...this.debtSummary, ...debtSummaryData };
        }
        if (savedData.financialAssessment) {
            const financialData = this.formatMoneyFields(savedData.financialAssessment, FINANCIAL_MONEY_FIELDS);
            this.financialAssessment = { ...this.financialAssessment, ...financialData };
        }
        if (Array.isArray(savedData.debts)) {
            this.debts = savedData.debts.map(debt => this.formatMoneyFields(debt, DEBT_MONEY_FIELDS));
        }
        if (Array.isArray(savedData.borrowers) && savedData.borrowers.length > 0) {
            this.borrowers = savedData.borrowers.map((borrower, index) => {
                const roleLabel = index === 0
                    ? 'Adult One / Applicant'
                    : (index === 1 ? 'Adult Two / Co-Applicant' : `Additional Adult ${index + 1}`);
                const borrowerData = this.formatBorrowerMoneyFields(borrower);
                return {
                    ...createBorrowerRow(borrowerData.id || `saved-borrower-${index + 1}`, roleLabel),
                    ...borrowerData,
                    roleLabel,
                    assets: createAssetRows(borrowerData.id || `saved-borrower-${index + 1}`)
                };
            });
            this.prefillSignatureNamesFromBorrowers();
        }
    }

    formatMoneyFields(record, moneyFields) {
        const formattedRecord = { ...record };
        moneyFields.forEach(fieldName => {
            if (Object.prototype.hasOwnProperty.call(formattedRecord, fieldName)) {
                formattedRecord[fieldName] = formatMoneyValue(formattedRecord[fieldName]);
            }
        });
        return formattedRecord;
    }

    formatBorrowerMoneyFields(borrower) {
        const formattedBorrower = this.formatMoneyFields(borrower, BORROWER_MONEY_FIELDS);
        if (Array.isArray(formattedBorrower.assets)) {
            formattedBorrower.assets = formattedBorrower.assets.map(asset => this.formatMoneyFields(asset, ['amount']));
        }
        return formattedBorrower;
    }

    getInputValue(event) {
        let fieldValue = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        if (event.target.dataset.amount === 'true') {
            fieldValue = formatMoneyValue(fieldValue);
            event.target.value = fieldValue;
        }
        return fieldValue;
    }

    applyReadOnlyState() {
        if (this.isSubmitted) {
            const controls = this.template.querySelectorAll('input, select, textarea, button');
            controls.forEach(control => {
                control.disabled = true;
            });
        }
    }

    applyInitialFiles(files) {
        const applicationFileMap = {};
        const adultFileMap = {};
        const unmatchedFiles = [];

        files.forEach(file => {
            const normalizedFile = this.normalizeUploadedFile(file);

            if (normalizedFile.documentSection === 'application' && normalizedFile.documentItemId) {
                this.addFileToGroup(applicationFileMap, normalizedFile.documentItemId, normalizedFile);
            } else if (normalizedFile.documentSection === 'adult' && normalizedFile.documentItemId) {
                this.addFileToGroup(adultFileMap, normalizedFile.documentItemId, normalizedFile);
            } else {
                unmatchedFiles.push(normalizedFile);
            }
        });

        this.applicationDocuments = this.mergeInitialDocumentFiles(this.applicationDocuments, applicationFileMap);
        this.adultHouseholdDocuments = this.mergeInitialDocumentFiles(this.adultHouseholdDocuments, adultFileMap);
        this.readOnlyFiles = unmatchedFiles;
    }

    normalizeUploadedFile(file) {
        const serverFileId = file.serverFileId || file.contentDocumentId || file.contentVersionId || file.id;

        return {
            id: file.id || serverFileId || `file-${Date.now()}`,
            serverFileId,
            name: file.name || file.fileName || 'Uploaded file',
            downloadUrl: file.downloadUrl || '',
            documentSection: file.documentSection || '',
            documentItemId: file.documentItemId || ''
        };
    }

    addFileToGroup(fileMap, itemId, file) {
        if (!fileMap[itemId]) {
            fileMap[itemId] = [];
        }

        fileMap[itemId].push(file);
    }

    mergeInitialDocumentFiles(documents, groupedFiles) {
        return documents.map(item => {
            const incomingFiles = groupedFiles[item.id] || [];
            const existingIds = new Set(item.uploadedFiles.map(file => file.serverFileId || file.id));
            const newFiles = incomingFiles.filter(file => !existingIds.has(file.serverFileId || file.id));
            const uploadedFiles = [...item.uploadedFiles, ...newFiles];

            return {
                ...item,
                uploadedFiles,
                hasFiles: uploadedFiles.length > 0,
                isChecked: item.isChecked || uploadedFiles.length > 0
            };
        });
    }

    handleSectionChange(event) {
        if (!this.isSubmitted) {
            const sectionName = event.target.dataset.section;
            const fieldName = event.target.dataset.field;
            const fieldValue = this.getInputValue(event);

            this.updateSectionValue(sectionName, fieldName, fieldValue);
        }
    }

    handleYesNoChange(event) {
        if (!this.isSubmitted) {
            const sectionName = event.target.dataset.section;
            const fieldName = event.target.dataset.field;
            const fieldValue = event.target.checked ? event.target.value : '';

            this.updateSectionValue(sectionName, fieldName, fieldValue);
        }
    }

    updateSectionValue(sectionName, fieldName, fieldValue) {
        if (sectionName === 'household') {
            this.household = { ...this.household, [fieldName]: fieldValue };
        } else if (sectionName === 'property') {
            this.propertyInfo = { ...this.propertyInfo, [fieldName]: fieldValue };
        } else if (sectionName === 'characteristics') {
            this.characteristics = { ...this.characteristics, [fieldName]: fieldValue };
        } else if (sectionName === 'debtSummary') {
            this.debtSummary = { ...this.debtSummary, [fieldName]: fieldValue };
        } else if (sectionName === 'financialAssessment') {
            this.financialAssessment = { ...this.financialAssessment, [fieldName]: fieldValue };
        }
    }

    handleBorrowerChange(event) {
        if (!this.isSubmitted) {
            const rowIndex = Number(event.target.dataset.index);
            const fieldName = event.target.dataset.field;
            const fieldValue = this.getInputValue(event);
            const updatedBorrowers = [...this.borrowers];

            if (updatedBorrowers[rowIndex]) {
                const previousName = updatedBorrowers[rowIndex].name;
                updatedBorrowers[rowIndex] = { ...updatedBorrowers[rowIndex], [fieldName]: fieldValue };
                this.borrowers = updatedBorrowers;
                if (fieldName === 'name') {
                    this.syncBorrowerSignaturePrintName(rowIndex, fieldValue, previousName);
                }
            }
        }
    }

    prefillSignatureNamesFromBorrowers() {
        if (this.borrowers[0]) {
            this.prefillSignaturePrintName('applicant', this.borrowers[0].name, '');
        }
        if (this.borrowers[1]) {
            this.prefillSignaturePrintName('coApplicant', this.borrowers[1].name, '');
        }
    }

    syncBorrowerSignaturePrintName(rowIndex, newName, previousName) {
        if (rowIndex === 0) {
            this.prefillSignaturePrintName('applicant', newName, previousName);
        } else if (rowIndex === 1) {
            this.prefillSignaturePrintName('coApplicant', newName, previousName);
        }
    }

    prefillSignaturePrintName(signatureId, newName, previousName) {
        if (!signatureId || !this.signatures[signatureId]) {
            return;
        }

        const cleanNewName = String(newName || '').trim();
        if (!cleanNewName) {
            return;
        }

        const currentName = this.signatures[signatureId].printName || '';
        const cleanCurrentName = String(currentName).trim();
        const cleanPreviousName = String(previousName || '').trim();
        const shouldPrefill = !cleanCurrentName || (cleanPreviousName && cleanCurrentName === cleanPreviousName);

        if (shouldPrefill) {
            this.signatures = {
                ...this.signatures,
                [signatureId]: {
                    ...this.signatures[signatureId],
                    printName: cleanNewName
                }
            };
        }
    }

    handleAssetChange(event) {
        if (!this.isSubmitted) {
            const rowIndex = Number(event.target.dataset.index);
            const assetIndex = Number(event.target.dataset.assetIndex);
            const fieldName = event.target.dataset.field;
            const fieldValue = this.getInputValue(event);
            const updatedBorrowers = [...this.borrowers];

            if (fieldName !== 'accountType' && updatedBorrowers[rowIndex] && updatedBorrowers[rowIndex].assets[assetIndex]) {
                const updatedAssets = [...updatedBorrowers[rowIndex].assets];
                updatedAssets[assetIndex] = { ...updatedAssets[assetIndex], [fieldName]: fieldValue };
                updatedBorrowers[rowIndex] = { ...updatedBorrowers[rowIndex], assets: updatedAssets };
                this.borrowers = updatedBorrowers;
            }
        }
    }

    handleDebtChange(event) {
        if (!this.isSubmitted) {
            const rowIndex = Number(event.target.dataset.index);
            const fieldName = event.target.dataset.field;
            const fieldValue = this.getInputValue(event);
            const updatedDebts = [...this.debts];

            if (updatedDebts[rowIndex]) {
                updatedDebts[rowIndex] = { ...updatedDebts[rowIndex], [fieldName]: fieldValue };
                this.debts = updatedDebts;
            }
        }
    }

    handleSignatureInputChange(event) {
        if (!this.isSubmitted) {
            const signatureId = event.target.dataset.signatureId;
            const fieldName = event.target.dataset.field;

            if (signatureId && this.signatures[signatureId]) {
                this.signatures = {
                    ...this.signatures,
                    [signatureId]: {
                        ...this.signatures[signatureId],
                        [fieldName]: event.target.value
                    }
                };
            }
        }
    }

    setCanvasSize(canvas, ctx) {
        if (canvas && ctx) {
            canvas.width = canvas.offsetWidth;
            canvas.height = canvas.offsetHeight;
            ctx.lineWidth = 2;
            ctx.lineCap = 'round';
            ctx.strokeStyle = '#000';
        }
    }

    handleMouseDown(event) {
        if (!this.isSubmitted) {
            const signatureId = event.currentTarget.dataset.signatureId;

            if (signatureId && this.ctxMap[signatureId]) {
                const canvas = this.canvasMap[signatureId];
                const ctx = this.ctxMap[signatureId];
                const coordinates = this.getCoordinates(canvas, event.clientX, event.clientY);
                this.isDrawing = true;
                this.activeSignatureId = signatureId;
                this.updateSignatureSigned(signatureId, true);
                ctx.beginPath();
                ctx.moveTo(coordinates.offsetX, coordinates.offsetY);
            }
        }
    }

    handleMouseMove(event) {
        if (!this.isSubmitted) {
            const signatureId = this.activeSignatureId || event.currentTarget.dataset.signatureId;

            if (this.isDrawing && signatureId && this.ctxMap[signatureId]) {
                const canvas = this.canvasMap[signatureId];
                const ctx = this.ctxMap[signatureId];
                const coordinates = this.getCoordinates(canvas, event.clientX, event.clientY);
                ctx.lineTo(coordinates.offsetX, coordinates.offsetY);
                ctx.stroke();
            }
        }
    }

    handleMouseUp(event) {
        if (!this.isSubmitted) {
            const signatureId = event.currentTarget.dataset.signatureId || this.activeSignatureId;

            if (signatureId && this.canvasMap[signatureId]) {
                this.updateSignatureSigned(signatureId, this.hasSignatureOnCanvas(this.canvasMap[signatureId]));
            }

            this.isDrawing = false;
            this.activeSignatureId = null;
        }
    }

    handleTouchStart(event) {
        if (!this.isSubmitted) {
            event.preventDefault();
            const touch = event.touches[0];

            if (touch) {
                this.beginSignatureStroke(event.currentTarget.dataset.signatureId, touch.clientX, touch.clientY);
            }
        }
    }

    handleTouchMove(event) {
        if (!this.isSubmitted) {
            event.preventDefault();
            const touch = event.touches[0];

            if (touch && this.isDrawing) {
                this.extendSignatureStroke(this.activeSignatureId || event.currentTarget.dataset.signatureId, touch.clientX, touch.clientY);
            }
        }
    }

    handleTouchEnd(event) {
        if (!this.isSubmitted) {
            event.preventDefault();
            const signatureId = event.currentTarget.dataset.signatureId || this.activeSignatureId;

            if (signatureId && this.canvasMap[signatureId]) {
                this.updateSignatureSigned(signatureId, this.hasSignatureOnCanvas(this.canvasMap[signatureId]));
            }

            this.isDrawing = false;
            this.activeSignatureId = null;
        }
    }

    beginSignatureStroke(signatureId, clientX, clientY) {
        if (!this.isSubmitted && signatureId && this.ctxMap[signatureId]) {
            const canvas = this.canvasMap[signatureId];
            const ctx = this.ctxMap[signatureId];
            const coordinates = this.getCoordinates(canvas, clientX, clientY);
            this.isDrawing = true;
            this.activeSignatureId = signatureId;
            this.updateSignatureSigned(signatureId, true);
            ctx.beginPath();
            ctx.moveTo(coordinates.offsetX, coordinates.offsetY);
        }
    }

    extendSignatureStroke(signatureId, clientX, clientY) {
        if (!this.isSubmitted && signatureId && this.ctxMap[signatureId]) {
            const canvas = this.canvasMap[signatureId];
            const ctx = this.ctxMap[signatureId];
            const coordinates = this.getCoordinates(canvas, clientX, clientY);
            ctx.lineTo(coordinates.offsetX, coordinates.offsetY);
            ctx.stroke();
        }
    }

    getCoordinates(canvas, clientX, clientY) {
        const rect = canvas.getBoundingClientRect();
        return {
            offsetX: clientX - rect.left,
            offsetY: clientY - rect.top
        };
    }

    clearSignature(event) {
        if (!this.isSubmitted) {
            const signatureId = event.currentTarget.dataset.signatureId;
            const canvas = this.canvasMap[signatureId];
            const ctx = this.ctxMap[signatureId];

            if (canvas && ctx) {
                ctx.clearRect(0, 0, canvas.width, canvas.height);
                this.updateSignatureSigned(signatureId, false);
            }
        }
    }

    updateSignatureSigned(signatureId, isSigned) {
        if (signatureId && this.signatures[signatureId]) {
            this.signatures = {
                ...this.signatures,
                [signatureId]: {
                    ...this.signatures[signatureId],
                    isSigned
                }
            };
        }
    }

    hasSignatureOnCanvas(canvas) {
        let hasSignature = false;

        if (canvas) {
            const ctx = canvas.getContext('2d');

            if (ctx) {
                const pixelData = ctx.getImageData(0, 0, canvas.width, canvas.height);

                for (let i = 3; i < pixelData.data.length && !hasSignature; i += 4) {
                    hasSignature = pixelData.data[i] !== 0;
                }
            }
        }

        return hasSignature;
    }

    hasSignature(signatureId) {
        let hasSignatureValue = false;
        const canvas = this.canvasMap[signatureId];

        if (canvas) {
            hasSignatureValue = this.hasSignatureOnCanvas(canvas);
        }

        return hasSignatureValue;
    }

    addBorrower() {
        if (!this.isSubmitted) {
            const rowNumber = this.borrowers.length + 1;
            const rowId = `borrower-${Date.now()}`;
            this.borrowers = [...this.borrowers, createBorrowerRow(rowId, `Additional Adult ${rowNumber}`)];
        }
    }

    removeBorrower(event) {
        if (!this.isSubmitted) {
            const rowIndex = Number(event.target.dataset.index);

            if (this.borrowers.length > 1) {
                this.borrowers = this.borrowers.filter((item, index) => index !== rowIndex);
            }
        }
    }

    addDebtRow() {
        if (!this.isSubmitted) {
            const newDebt = {
                id: `debt-${Date.now()}`,
                debtType: '',
                monthlyPayment: '',
                balance: ''
            };
            this.debts = [...this.debts, newDebt];
        }
    }

    removeDebtRow(event) {
        if (!this.isSubmitted) {
            const rowIndex = Number(event.target.dataset.index);
            this.debts = this.debts.filter((item, index) => index !== rowIndex);
        }
    }

    handleChecklistChange(event) {
        if (!this.isSubmitted) {
            this.updateDocumentCheckedState(
                event.target.dataset.section,
                event.target.dataset.itemId,
                event.target.checked
            );
        }
    }

    handleFileSelected(event) {
        if (!this.isSubmitted) {
            const selectedFiles = Array.from(event.target.files || []);
            const sectionName = event.target.dataset.section;
            const itemId = event.target.dataset.itemId;
            const itemLabel = event.target.dataset.itemLabel;

            if (selectedFiles.length > 0) {
                this.updateDocumentUploadProgress(sectionName, itemId, true, '');
                selectedFiles.forEach(file => {
                    this.uploadSelectedFile(file, sectionName, itemId, itemLabel);
                });
            }

            event.target.value = null;
        }
    }

    handleRemoveUploadedFile(event) {
        if (!this.isSubmitted) {
            const sectionName = event.target.dataset.section;
            const itemId = event.target.dataset.itemId;
            const fileId = event.target.dataset.fileId;
            const serverFileId = event.target.dataset.serverFileId;
            const fileName = event.target.dataset.fileName;

            if (serverFileId) {
                removeUploadedFile({
                    recordId: this.recordId,
                    contentDocumentId: serverFileId
                })
                    .then(() => {
                        this.updateDocumentRemoveState(sectionName, itemId, fileId);
                        this.uploadedFileMessage = `${fileName} removed from this application.`;
                    })
                    .catch(error => {
                        // eslint-disable-next-line no-console
                        console.error('Failed to remove HIP uploaded file', error);
                        this.uploadedFileMessage = `Unable to remove ${fileName}. Please try again.`;
                    });
            } else {
                this.updateDocumentRemoveState(sectionName, itemId, fileId);
                this.uploadedFileMessage = `${fileName} removed from the visible upload list.`;
            }
        }
    }

    uploadSelectedFile(file, sectionName, itemId, itemLabel) {
        if (!this.isSubmitted) {
            const reader = new FileReader();

            reader.onload = () => {
                const fileBody = reader.result.split(',')[1];

                uploadFile({
                    recordId: this.recordId,
                    fileName: file.name,
                    base64Data: fileBody,
                    documentSection: sectionName,
                    documentItemId: itemId,
                    documentLabel: itemLabel
                })
                    .then(result => {
                        const serverFileId = result.contentDocumentId || result.contentVersionId;
                        const uploadedFileRows = [{
                            id: serverFileId || `${sectionName}-${itemId}-${Date.now()}`,
                            serverFileId,
                            name: result.fileName || file.name,
                            downloadUrl: result.downloadUrl || '',
                            documentSection: result.documentSection || sectionName,
                            documentItemId: result.documentItemId || itemId
                        }];

                        this.updateDocumentUploadState(sectionName, itemId, uploadedFileRows);
                        this.updateDocumentUploadProgress(sectionName, itemId, false, '');
                        this.uploadedFileMessage = `${file.name} uploaded for ${itemLabel}.`;
                    })
                    .catch(error => {
                        // eslint-disable-next-line no-console
                        console.error('Failed to upload HIP file', error);
                        this.updateDocumentUploadProgress(sectionName, itemId, false, `Unable to upload ${file.name}. Please try again.`);
                        this.uploadedFileMessage = `Unable to upload ${file.name}. Please try again.`;
                    });
            };

            reader.onerror = () => {
                this.updateDocumentUploadProgress(sectionName, itemId, false, `Unable to read ${file.name}. Please try again.`);
                this.uploadedFileMessage = `Unable to read ${file.name}. Please try again.`;
            };

            reader.readAsDataURL(file);
        }
    }

    handleSubmit() {
        this.submitError = '';
        this.submitMessage = '';

        if (this.isSubmitted) {
            this.submitMessage = '';
        } else if (!this.recordId) {
            this.submitError = 'Account record id is required before submitting.';
        } else if (!this.signatures.applicant.printName.trim()) {
            this.submitError = 'Applicant print name is required before submitting.';
        } else if (!this.signatures.applicant.signDate) {
            this.submitError = 'Applicant signature date is required before submitting.';
        } else if (!this.hasSignature('applicant')) {
            this.submitError = 'Applicant signature is required before submitting.';
        } else if (this.coApplicantRequired && !this.signatures.coApplicant.printName.trim()) {
            this.submitError = 'Co-Applicant print name is required before submitting.';
        } else if (this.coApplicantRequired && !this.signatures.coApplicant.signDate) {
            this.submitError = 'Co-Applicant signature date is required before submitting.';
        } else if (this.coApplicantRequired && !this.hasSignature('coApplicant')) {
            this.submitError = 'Co-Applicant signature is required before submitting.';
        } else {
            this.isSubmitting = true;
            const borrowersPayload = [];

            this.borrowers.forEach((borrower, index) => {
                const borrowerPayload = {
                    name: borrower.name,
                    dateOfBirth: borrower.dateOfBirth,
                    emailAddress: borrower.emailAddress,
                    relationship: borrower.relationship,
                    employer: borrower.employer,
                    positionHeld: borrower.positionHeld,
                    howLongEmployed: borrower.howLongEmployed,
                    pension: borrower.pension,
                    socialSecurityDisability: borrower.socialSecurityDisability || borrower.ssiSsdAmount,
                    unemployment: borrower.unemployment,
                    selfEmployment: borrower.selfEmployment,
                    rentalIncome: borrower.rentalIncome,
                    publicAssistance: borrower.publicAssistance,
                    alimonyChildSupport: borrower.alimonyChildSupport || borrower.childSupport,
                    salaryWages: borrower.employmentGrossMonthlyAmount,
                    bankAndInvestmentInterest: borrower.interestIncome
                };

                if (index === 0) {
                    borrowerPayload.maritalStatus = this.household.maritalStatus;
                    borrowerPayload.householdType = this.household.householdType;
                    borrowerPayload.howManyDependents = this.household.howManyDependents;
                    borrowerPayload.numberInHousehold = this.household.familyHouseholdSize;
                    borrowerPayload.salaryWages = borrowerPayload.salaryWages || this.financialAssessment.salaryWages;
                    borrowerPayload.bankAndInvestmentInterest = borrowerPayload.bankAndInvestmentInterest || this.financialAssessment.bankAndInvestmentInterest;
                    borrowerPayload.housingMortgageTaxesInsurance = this.financialAssessment.housingMortgageTaxesInsurance;
                    borrowerPayload.healthInsurance = this.financialAssessment.healthInsurance;
                    borrowerPayload.cableSatelliteTv = this.financialAssessment.cableSatelliteTv;
                    borrowerPayload.carLoan = this.financialAssessment.carLoan;
                    borrowerPayload.carInsurance = this.financialAssessment.carInsurance;
                    borrowerPayload.otherExpense = this.financialAssessment.otherExpense;
                    borrowerPayload.telephone = this.financialAssessment.telephone;
                    borrowerPayload.gasElectric = this.financialAssessment.gasElectric;
                    borrowerPayload.food = this.financialAssessment.food;
                    borrowerPayload.entertainment = this.financialAssessment.entertainment;
                    borrowerPayload.clothing = this.financialAssessment.clothing;
                    borrowerPayload.totalMonthlyIncome = this.financialAssessment.totalMonthlyIncome;
                    borrowerPayload.totalLivingExpenses = this.financialAssessment.totalLivingExpenses;
                    borrowerPayload.alimonyChildSupport = borrowerPayload.alimonyChildSupport || this.financialAssessment.alimonyChildSupport;
                }

                borrowersPayload.push(borrowerPayload);
            });

            const payload = {
                accountId: this.recordId,
                debtToIncome: {
                    numberOfUnitsInBuilding: this.household.numberOfUnitsInBuilding,
                    numberInHousehold: this.household.familyHouseholdSize,
                    currentHouseholdMonthlyDebt: this.debtSummary.currentHouseholdMonthlyDebt,
                    homeEverReceivedWeatherization: this.household.homeEverReceivedWeatherization,
                    raceEthnicityHead: this.characteristics.raceEthnicityHead,
                    raceEthnicityCoApplicant: this.characteristics.raceEthnicityCoApplicant,
                    hasGalvanTies: this.characteristics.hasGalvanTies
                },
                borrowers: borrowersPayload,
                signatures: this.buildSignaturePayload()
            };

            submitApplication({ payloadJson: JSON.stringify(payload) })
                .then(result => {
                    this.isSubmitted = true;
                    this.submittedDateDisplay = result.submittedDateDisplay || '';
                    this.submitMessage = '';
                    return saveApplicationPdf({ recordId: this.recordId });
                })
                .then(() => {
                    this.isSubmitting = false;
                    this.scrollToTop();
                    this.loadInitialData();
                })
                .catch(error => {
                    // eslint-disable-next-line no-console
                    console.error('Failed to submit HIP application', error);
                    this.submitError = this.extractErrorMessage(error);
                    this.isSubmitting = false;
                });
        }
    }

    scrollToTop() {
        window.requestAnimationFrame(() => {
            window.scrollTo({ top: 0, behavior: 'smooth' });
        });
    }

    buildSignaturePayload() {
        const signatureRows = [];
        const signatureDefinitions = [
            { id: 'applicant', label: 'Applicant Signature' }
        ];

        if (this.coApplicantRequired || this.signatures.coApplicant.printName.trim() || this.hasSignature('coApplicant')) {
            signatureDefinitions.push({ id: 'coApplicant', label: 'Co-Applicant Signature' });
        }

        signatureDefinitions.forEach(signatureDefinition => {
            const canvas = this.canvasMap[signatureDefinition.id];
            const imageData = canvas
                ? canvas.toDataURL('image/png').replace(/^data:image\/(png|jpg);base64,/, '')
                : '';

            signatureRows.push({
                signatureKey: signatureDefinition.id,
                signatureLabel: signatureDefinition.label,
                printName: this.signatures[signatureDefinition.id].printName,
                signDate: this.signatures[signatureDefinition.id].signDate,
                imageData
            });
        });

        return signatureRows;
    }

    extractErrorMessage(error) {
        let message = 'Unable to submit HIP application. Please try again.';
        if (error && error.body && error.body.message) {
            message = error.body.message;
        } else if (error && error.message) {
            message = error.message;
        }
        return message;
    }

    updateDocumentUploadState(sectionName, itemId, uploadedFileRows) {
        const currentDocuments = sectionName === 'adult'
            ? this.adultHouseholdDocuments
            : this.applicationDocuments;
        const updatedDocuments = [];

        currentDocuments.forEach(item => {
            const updatedItem = { ...item };

            if (item.id === itemId) {
                updatedItem.uploadedFiles = [...item.uploadedFiles, ...uploadedFileRows];
                updatedItem.hasFiles = updatedItem.uploadedFiles.length > 0;
                updatedItem.isChecked = true;
            }

            updatedDocuments.push(updatedItem);
        });

        if (sectionName === 'adult') {
            this.adultHouseholdDocuments = updatedDocuments;
        } else {
            this.applicationDocuments = updatedDocuments;
        }
    }

    updateDocumentCheckedState(sectionName, itemId, isChecked) {
        const currentDocuments = sectionName === 'adult'
            ? this.adultHouseholdDocuments
            : this.applicationDocuments;
        const updatedDocuments = [];

        currentDocuments.forEach(item => {
            const updatedItem = { ...item };

            if (item.id === itemId) {
                updatedItem.isChecked = isChecked;
            }

            updatedDocuments.push(updatedItem);
        });

        if (sectionName === 'adult') {
            this.adultHouseholdDocuments = updatedDocuments;
        } else {
            this.applicationDocuments = updatedDocuments;
        }
    }

    updateDocumentUploadProgress(sectionName, itemId, isUploading, uploadError) {
        const currentDocuments = sectionName === 'adult'
            ? this.adultHouseholdDocuments
            : this.applicationDocuments;
        const updatedDocuments = [];

        currentDocuments.forEach(item => {
            const updatedItem = { ...item };

            if (item.id === itemId) {
                updatedItem.isUploading = isUploading;
                updatedItem.uploadError = uploadError;
            }

            updatedDocuments.push(updatedItem);
        });

        if (sectionName === 'adult') {
            this.adultHouseholdDocuments = updatedDocuments;
        } else {
            this.applicationDocuments = updatedDocuments;
        }
    }

    updateDocumentRemoveState(sectionName, itemId, fileId) {
        const currentDocuments = sectionName === 'adult'
            ? this.adultHouseholdDocuments
            : this.applicationDocuments;
        const updatedDocuments = [];

        currentDocuments.forEach(item => {
            const updatedItem = { ...item };

            if (item.id === itemId) {
                const remainingFiles = [];

                item.uploadedFiles.forEach(file => {
                    if (file.id !== fileId) {
                        remainingFiles.push(file);
                    }
                });

                updatedItem.uploadedFiles = remainingFiles;
                updatedItem.hasFiles = remainingFiles.length > 0;
                updatedItem.isChecked = remainingFiles.length > 0;
            }

            updatedDocuments.push(updatedItem);
        });

        if (sectionName === 'adult') {
            this.adultHouseholdDocuments = updatedDocuments;
        } else {
            this.applicationDocuments = updatedDocuments;
        }
    }
}