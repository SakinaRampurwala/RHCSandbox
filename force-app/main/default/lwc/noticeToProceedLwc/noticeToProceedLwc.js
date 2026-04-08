import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getLogoUrl from '@salesforce/apex/NoticeToProceedCtrl.getLogoUrl';
import getNoticeData from '@salesforce/apex/NoticeToProceedCtrl.getNoticeData';
import saveSignature from '@salesforce/apex/NoticeToProceedCtrl.saveSignature';
import savePdf from '@salesforce/apex/NoticeToProceedCtrl.savePdf';
import CASE_NO_FIELD from '@salesforce/schema/buildertek__Project__c.Case_No__c';
import ADDRESS_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Address__c';
import CITY_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__City_Text__c';
import STATE_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__State__c';
import ZIP_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Zip__c';
import COUNTRY_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Country__c';
import CUSTOMER_NAME_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Customer__r.Name';
import CONTRACTOR_NAME_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.Name';
import CONTRACTOR_PHONE_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.Phone';
import CONTRACTOR_BILLING_STREET_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.BillingStreet';
import CONTRACTOR_BILLING_CITY_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.BillingCity';
import CONTRACTOR_BILLING_STATE_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.BillingState';
import CONTRACTOR_BILLING_POSTAL_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.BillingPostalCode';
import CONTRACTOR_BILLING_COUNTRY_FIELD from '@salesforce/schema/buildertek__Project__c.General_Contractor__r.BillingCountry';
import PROJECT_COMPLETION_DATE from '@salesforce/schema/buildertek__Project__c.buildertek__Project_Completion_Date__c';
import PROJECT_START_DATE from '@salesforce/schema/buildertek__Project__c.buildertek__Project_Start_Date__c';
import CONTRACT_DATE_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Contract_Date__c';

const FIELDS = [
    CASE_NO_FIELD, ADDRESS_FIELD, CITY_FIELD, STATE_FIELD, ZIP_FIELD, COUNTRY_FIELD,
    CUSTOMER_NAME_FIELD, CONTRACTOR_NAME_FIELD, CONTRACTOR_PHONE_FIELD,
    CONTRACTOR_BILLING_STREET_FIELD, CONTRACTOR_BILLING_CITY_FIELD,
    CONTRACTOR_BILLING_STATE_FIELD, CONTRACTOR_BILLING_POSTAL_FIELD,
    CONTRACTOR_BILLING_COUNTRY_FIELD, PROJECT_COMPLETION_DATE,
    PROJECT_START_DATE, CONTRACT_DATE_FIELD
];

export default class NoticeToProceedLwc extends LightningElement {
    @api isPreview;
    @api recordId;
    @api senderId;
    @api sendDate;

    @track isLoading = true;
    @track isSubmitted = false;
    @track isAlreadySubmitted = false;
    @track submitTitle = 'Thank You!';
    @track submitMessage = 'Your signature has been saved successfully.';
    @track logoURL;
    @track noticeData = {};

    // Role flags — read from URL params
    @track isPropertyOwner = false;
    @track isContractorRep = false;
    @track isProgramRep = false;

    // Chain email params — read from URL, passed to Apex savePdf which handles sending
    contractorRepContactIds = [];
    contractorRepEmails = [];
    programRepContactIds = [];
    programRepEmails = [];
    fromAddressId = '';
    fileIds = [];

    // Signature state from saved record
    @track propertyOwnerSignatureUrl = '';
    @track contractorRepSignatureUrl = '';
    @track programRepSignatureUrl = '';
    @track propertyOwnerSigned = false;
    @track contractorRepSigned = false;
    @track programRepSigned = false;

    // Canvas state
    canvasMap = {};
    ctxMap = {};
    isDrawing = false;
    activeSignatureId;
    signatureState = { propertyOwner: false, contractorRep: false, programRep: false };

    @wire(getLogoUrl)
    wiredLogo({ data }) {
        if (data) { this.logoURL = data; }
    }

    @wire(getNoticeData, { recordId: '$recordId' })
    wiredNoticeData({ data }) {
        if (data) {
            if (data.isSubmitted) {
                this.isSubmitted = true;
                this.isAlreadySubmitted = true;
            }
            this.propertyOwnerSignatureUrl = data.propertyOwnerSignatureUrl || '';
            this.contractorRepSignatureUrl = data.contractorRepSignatureUrl || '';
            this.programRepSignatureUrl    = data.programRepSignatureUrl    || '';
            this.propertyOwnerSigned = !!data.propertyOwnerSigned;
            this.contractorRepSigned = !!data.contractorRepSigned;
            this.programRepSigned    = !!data.programRepSigned;
            this.signatureState = {
                propertyOwner: this.propertyOwnerSigned || !!this.propertyOwnerSignatureUrl,
                contractorRep: this.contractorRepSigned || !!this.contractorRepSignatureUrl,
                programRep:    this.programRepSigned    || !!this.programRepSignatureUrl
            };
            // If current role already signed, show submitted screen (can't sign twice)
            if (!this.isSubmitted) {
                if (this.isPropertyOwner && this.propertyOwnerSigned) {
                    this.isSubmitted = true;
                    this.isAlreadySubmitted = true;
                } else if (this.isContractorRep && this.contractorRepSigned) {
                    this.isSubmitted = true;
                    this.isAlreadySubmitted = true;
                } else if (this.isProgramRep && this.programRepSigned) {
                    this.isSubmitted = true;
                    this.isAlreadySubmitted = true;
                }
            }
        }
        this.isLoading = false;
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredProject({ data }) {
        if (data) {
            this.noticeData = {
                ...this.noticeData,
                caseNumber: getFieldValue(data, CASE_NO_FIELD) || '',
                projectLocation: this.buildProjectLocation(data),
                propertyOwner: getFieldValue(data, CUSTOMER_NAME_FIELD) || '',
                contractor: getFieldValue(data, CONTRACTOR_NAME_FIELD) || '',
                telephone: getFieldValue(data, CONTRACTOR_PHONE_FIELD) || '',
                contractorAddress: this.buildContractorAddress(data),
                contractDated: getFieldValue(data, CONTRACT_DATE_FIELD)
                    ? new Date(getFieldValue(data, CONTRACT_DATE_FIELD)).toLocaleDateString() : '',
                projectedStartDate: getFieldValue(data, PROJECT_START_DATE)
                    ? new Date(getFieldValue(data, PROJECT_START_DATE)).toLocaleDateString() : '',
                projectedCompletionDate: getFieldValue(data, PROJECT_COMPLETION_DATE)
                    ? new Date(getFieldValue(data, PROJECT_COMPLETION_DATE)).toLocaleDateString() : ''
            };
        }
    }

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);

        // Read role from URL
        this.isPropertyOwner = params.get('isPropertyOwner') === 'true';
        this.isContractorRep = params.get('isContractorRep') === 'true';
        this.isProgramRep    = params.get('isProgramRep')    === 'true';

        // Fallback: read core params from URL if @api props not yet set by VF page
        if (!this.recordId) { this.recordId = params.get('recordId') || params.get('id') || ''; }
        if (!this.senderId) { this.senderId = params.get('senderId') || ''; }
        if (!this.sendDate) { this.sendDate = params.get('sendDate') || ''; }

        // Chain email params — passed to Apex savePdf so it can send the next email server-side
        const cIds = params.get('contractorRepContactIds');
        const cEmails = params.get('contractorRepEmails');
        const pIds = params.get('programRepContactIds');
        const pEmails = params.get('programRepEmails');
        const fIds = params.get('fileIds');

        this.contractorRepContactIds = cIds    ? cIds.split(',').filter(Boolean)    : [];
        this.contractorRepEmails     = cEmails ? cEmails.split(',').filter(Boolean) : [];
        this.programRepContactIds    = pIds    ? pIds.split(',').filter(Boolean)    : [];
        this.programRepEmails        = pEmails ? pEmails.split(',').filter(Boolean) : [];
        this.fromAddressId           = params.get('fromAddressId') || '';
        this.fileIds                 = fIds    ? fIds.split(',').filter(Boolean)    : [];

        if (!this.recordId) { this.isLoading = false; }
    }

    // ── Section visibility ──────────────────────────────────────────────────────

    get showPropertyOwnerSection() {
        if (this.isReadOnly) return true;
        if (!this.isPropertyOwner && !this.isContractorRep && !this.isProgramRep) return true;
        return this.isPropertyOwner || this.propertyOwnerSigned;
    }

    get showContractorRepSection() {
        if (this.isReadOnly) return true;
        if (!this.isPropertyOwner && !this.isContractorRep && !this.isProgramRep) return true;
        return this.isContractorRep || this.contractorRepSigned;
    }

    get showProgramRepSection() {
        if (this.isReadOnly) return true;
        if (!this.isPropertyOwner && !this.isContractorRep && !this.isProgramRep) return true;
        return this.isProgramRep || this.programRepSigned;
    }

    // ── Computed getters ────────────────────────────────────────────────────────

    get showThankYouPage() {
        const previewFlag = this.isPreview === true || this.isPreview === 'true';
        if (previewFlag) {
            return false;
        }
        return this.isSubmitted;
    }

    get isReadOnly() {
        return this.isPreview === true || this.isPreview === 'true';
    }

    get signatureCanvasClass() {
        return `signature-pad${this.isReadOnly ? ' read-only' : ''}`;
    }

    get hasPropertyOwnerSignature() { return this.propertyOwnerSigned || !!this.propertyOwnerSignatureUrl; }
    get hasContractorRepSignature()  { return this.contractorRepSigned || !!this.contractorRepSignatureUrl; }
    get hasProgramRepSignature()     { return this.programRepSigned    || !!this.programRepSignatureUrl; }

    get isSubmitDisabled() {
        if (this.isReadOnly) return true;
        if (this.isPropertyOwner) return !this.signatureState.propertyOwner && !this.hasPropertyOwnerSignature;
        if (this.isContractorRep) return !this.signatureState.contractorRep && !this.hasContractorRepSignature;
        if (this.isProgramRep)    return !this.signatureState.programRep    && !this.hasProgramRepSignature;
        // Admin view — require all 3
        return (
            (!this.signatureState.propertyOwner && !this.hasPropertyOwnerSignature) ||
            (!this.signatureState.contractorRep && !this.hasContractorRepSignature) ||
            (!this.signatureState.programRep    && !this.hasProgramRepSignature)
        );
    }

    // ── Current signer role string (sent to Apex so it knows who just signed) ──
    get currentSignerRole() {
        if (this.isPropertyOwner) return 'isPropertyOwner';
        if (this.isContractorRep) return 'isContractorRep';
        if (this.isProgramRep)    return 'isProgramRep';
        return '';
    }

    // ── Canvas / drawing ───────────────────────────────────────────────────────

    renderedCallback() {
        const canvases = this.template.querySelectorAll('canvas');
        if (!canvases || canvases.length === 0) return;
        canvases.forEach((canvas) => {
            const signatureId = canvas.dataset.signatureId;
            if (!signatureId || this.canvasMap[signatureId]) return;
            this.canvasMap[signatureId] = canvas;
            const ctx = canvas.getContext('2d');
            this.ctxMap[signatureId] = ctx;
            this.setCanvasSize(canvas, ctx);
        });
    }

    setCanvasSize(canvas, ctx) {
        canvas.width = canvas.offsetWidth;
        canvas.height = canvas.offsetHeight;
        ctx.lineWidth = 2;
        ctx.lineCap = 'round';
        ctx.strokeStyle = '#000';
    }

    handleMouseDown(event) {
        if (this.isReadOnly) return;
        const signatureId = event.target?.dataset?.signatureId;
        if (!signatureId || !this.ctxMap[signatureId]) return;
        this.isDrawing = true;
        this.activeSignatureId = signatureId;
        this.signatureState = { ...this.signatureState, [signatureId]: true };
        const canvas = this.canvasMap[signatureId];
        const ctx = this.ctxMap[signatureId];
        const { offsetX, offsetY } = this.getCoordinates(event, canvas);
        ctx.beginPath();
        ctx.moveTo(offsetX, offsetY);
    }

    handleMouseMove(event) {
        if (!this.isDrawing || this.isReadOnly) return;
        const signatureId = this.activeSignatureId;
        if (!signatureId || !this.ctxMap[signatureId]) return;
        const canvas = this.canvasMap[signatureId];
        const ctx = this.ctxMap[signatureId];
        const { offsetX, offsetY } = this.getCoordinates(event, canvas);
        ctx.lineTo(offsetX, offsetY);
        ctx.stroke();
    }

    handleMouseUp(event) {
        this.isDrawing = false;
        const signatureId = event?.target?.dataset?.signatureId || this.activeSignatureId;
        if (signatureId && this.canvasMap[signatureId]) {
            const hasSignature = this.hasSignatureOnCanvas(this.canvasMap[signatureId]);
            this.signatureState = { ...this.signatureState, [signatureId]: hasSignature };
        }
        this.activeSignatureId = null;
    }

    handleTouchStart(event) {
        if (this.isReadOnly) return;
        event.preventDefault();
        const touch = event.touches[0];
        event.target.dispatchEvent(new MouseEvent('mousedown', { clientX: touch.clientX, clientY: touch.clientY }));
    }

    handleTouchMove(event) {
        event.preventDefault();
        const touch = event.touches[0];
        event.target.dispatchEvent(new MouseEvent('mousemove', { clientX: touch.clientX, clientY: touch.clientY }));
    }

    handleTouchEnd(event) {
        event.preventDefault();
        event.target.dispatchEvent(new MouseEvent('mouseup', {}));
    }

    getCoordinates(event, canvas) {
        const rect = canvas.getBoundingClientRect();
        const clientX = event.clientX || event.touches?.[0].clientX;
        const clientY = event.clientY || event.touches?.[0].clientY;
        return { offsetX: clientX - rect.left, offsetY: clientY - rect.top };
    }

    clearSignature(event) {
        if (this.isReadOnly) return;
        const signatureId = event.target?.dataset?.signatureId;
        if (!signatureId || !this.canvasMap[signatureId] || !this.ctxMap[signatureId]) return;
        const canvas = this.canvasMap[signatureId];
        const ctx = this.ctxMap[signatureId];
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        this.signatureState = { ...this.signatureState, [signatureId]: false };
    }

    hasSignatureOnCanvas(canvas) {
        if (!canvas) return false;
        const ctx = canvas.getContext('2d');
        if (!ctx) return false;
        const pixelData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        for (let i = 3; i < pixelData.data.length; i += 4) {
            if (pixelData.data[i] !== 0) return true;
        }
        return false;
    }

    // ── Submit ─────────────────────────────────────────────────────────────────

    handleSubmit() {
        if (this.isReadOnly) return;

        const signaturePromises = [];
        const signatureResults = {};

        const collectSignature = (signatureId, label, existingUrl, warningMsg) => {
            const canvas = this.canvasMap[signatureId];
            if (canvas && this.hasSignatureOnCanvas(canvas)) {
                const signatureBody = canvas.toDataURL('image/png').replace(/^data:image\/(png|jpg);base64,/, '');
                signaturePromises.push(
                    saveSignature({ recordId: this.recordId, signatureBody, signatureLabel: label })
                        .then((result) => { signatureResults[signatureId] = result; })
                );
                return true;
            }
            if (existingUrl) {
                signatureResults[signatureId] = { imgUrl: existingUrl, cvId: '' };
                return true;
            }
            this.dispatchEvent(new ShowToastEvent({ title: 'Warning', message: warningMsg, variant: 'warning' }));
            return false;
        };

        // Collect only the current signer's section
        if (this.isPropertyOwner || (!this.isPropertyOwner && !this.isContractorRep && !this.isProgramRep)) {
            if (!collectSignature('propertyOwner', 'Property Owner', this.propertyOwnerSignatureUrl,
                'Please provide the Property Owner signature before submitting.')) return;
        }
        if (this.isContractorRep || (!this.isPropertyOwner && !this.isContractorRep && !this.isProgramRep)) {
            if (!collectSignature('contractorRep', 'Contractor Representative', this.contractorRepSignatureUrl,
                'Please provide the Contractor Representative signature before submitting.')) return;
        }
        if (this.isProgramRep || (!this.isPropertyOwner && !this.isContractorRep && !this.isProgramRep)) {
            if (!collectSignature('programRep', 'Home Improvement Program Representative', this.programRepSignatureUrl,
                'Please provide the Program Representative signature before submitting.')) return;
        }

        this.isLoading = true;

        Promise.all(signaturePromises)
            .then(() => {
                // Pass ALL chain email params to Apex — it handles sending the next email internally
                return savePdf({
                    recordId:                 this.recordId,
                    senderId:                 this.senderId  || '',
                    sendDate:                 this.sendDate  || '',
                    propertyOwnerImgUrl:      signatureResults.propertyOwner?.imgUrl || this.propertyOwnerSignatureUrl || '',
                    contractorRepImgUrl:      signatureResults.contractorRep?.imgUrl || this.contractorRepSignatureUrl || '',
                    programRepImgUrl:         signatureResults.programRep?.imgUrl    || this.programRepSignatureUrl    || '',
                    propertyOwnerSignatureId: signatureResults.propertyOwner?.cvId   || '',
                    contractorRepSignatureId: signatureResults.contractorRep?.cvId   || '',
                    programRepSignatureId:    signatureResults.programRep?.cvId      || '',
                    // Chain params — Apex will send next signer email using these
                    currentSignerRole:        this.currentSignerRole,
                    contractorRepContactIds:  this.contractorRepContactIds,
                    contractorRepEmails:      this.contractorRepEmails,
                    programRepContactIds:     this.programRepContactIds,
                    programRepEmails:         this.programRepEmails,
                    fromAddressId:            this.fromAddressId || '',
                    fileIds:                  this.fileIds
                });
            })
            .then((result) => {
                if (result === 'Success') {
                    this.isSubmitted = true;
                    this.submitTitle = 'Thank You!';
                    this.submitMessage = 'Notice To Proceed has been submitted successfully.';
                    this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Notice To Proceed submitted.', variant: 'success' }));
                    return;
                }
                if (result === 'Already Submitted') {
                    this.isSubmitted = true;
                    this.isAlreadySubmitted = true;
                    this.dispatchEvent(new ShowToastEvent({ title: 'Already Submitted', message: 'This form has already been submitted.', variant: 'info' }));
                    return;
                }
                if (result === 'Missing Signatures') {
                    // Apex already sent the next signer email — just show thank you
                    this.isSubmitted = true;
                    this.submitTitle = 'Thank You!';
                    this.submitMessage = 'Your signature has been saved. The next recipient has been notified to sign.';
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Signature Saved',
                        message: 'Signature saved. The next recipient has been notified.',
                        variant: 'success'
                    }));
                }
            })
            .catch((error) => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || error?.message || 'An unknown error occurred.',
                    variant: 'error'
                }));
            })
            .finally(() => { this.isLoading = false; });
    }

    // ── Address helpers ────────────────────────────────────────────────────────

    buildProjectLocation(recordData) {
        const address = getFieldValue(recordData, ADDRESS_FIELD) || '';
        const city    = getFieldValue(recordData, CITY_FIELD) || '';
        const state   = getFieldValue(recordData, STATE_FIELD) || '';
        const zip     = getFieldValue(recordData, ZIP_FIELD) || '';
        const country = getFieldValue(recordData, COUNTRY_FIELD) || '';
        const cityState = [city, state].filter(Boolean).join(' ');
        const firstPart = [address, cityState].filter(Boolean).join(', ');
        return `${firstPart}${zip ? ` - ${zip}` : ''}${country ? `, ${country}` : ''}`.trim();
    }

    buildContractorAddress(recordData) {
        const street     = getFieldValue(recordData, CONTRACTOR_BILLING_STREET_FIELD) || '';
        const city       = getFieldValue(recordData, CONTRACTOR_BILLING_CITY_FIELD) || '';
        const state      = getFieldValue(recordData, CONTRACTOR_BILLING_STATE_FIELD) || '';
        const postalCode = getFieldValue(recordData, CONTRACTOR_BILLING_POSTAL_FIELD) || '';
        const country    = getFieldValue(recordData, CONTRACTOR_BILLING_COUNTRY_FIELD) || '';
        const cityStatePostal = [city, state, postalCode].filter(Boolean).join(' ');
        return [street, cityStatePostal, country].filter(Boolean).join(', ');
    }
}