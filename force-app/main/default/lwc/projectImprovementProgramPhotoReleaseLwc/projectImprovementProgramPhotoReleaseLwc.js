import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import getLogoUrl from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.getLogoUrl';
import getOrgInfo from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.getOrgInfo';
import getApplicationStatus from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.getApplicationStatus';
import saveSignature from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.saveSignature';
import savePdf from '@salesforce/apex/ProjectImprovementProgramPhotoCtrl.savePdf';
import ADDRESS_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Address__c';
import CITY_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__City_Text__c';
import STATE_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__State__c';
import ZIP_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Zip__c';
import COUNTRY_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Country__c';
import CUSTOMER_NAME_FIELD from '@salesforce/schema/buildertek__Project__c.buildertek__Customer__r.Name';

const FIELDS = [
    ADDRESS_FIELD,
    CITY_FIELD,
    STATE_FIELD,
    ZIP_FIELD,
    COUNTRY_FIELD,
    CUSTOMER_NAME_FIELD
];

export default class ProjectImprovementProgramPhotoReleaseLwc extends LightningElement {
    @api isPreview;
    @api recordId;
    @api senderId;
    @api sendDate;

    @track isLoading = true;
    @track logoURL;
    @track signerName = '';
    @track coSignerName = '';
    @track isSubmitted = false;
    @track isAlreadySubmitted = false;
    @track submitError = '';
    @track showCustomToast = false;
    @track customToastMessage = '';
    @track customToastVariant = 'success';
    @track primarySignatureUrl = '';
    @track secondarySignatureUrl = '';

    address;
    city;
    state;
    zip;
    country;
    customerName;
    orgName = '';
    toastTimeout;
    primarySigned = false;
    secondarySigned = false;

    canvasElements = new Map();
    canvasContexts = new Map();
    isDrawing = false;
    activeSignatureKey;
    wiredAppStatusResult;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredProject({ data, error }) {
        if (data) {
            this.address = data.fields.buildertek__Address__c?.value || '';
            this.city = data.fields.buildertek__City_Text__c?.value || '';
            this.state = data.fields.buildertek__State__c?.value || '';
            this.zip = data.fields.buildertek__Zip__c?.value || '';
            this.country = data.fields.buildertek__Country__c?.value || '';

            const customerField = data.fields.buildertek__Customer__r;
            this.customerName = customerField?.displayValue || customerField?.value?.fields?.Name?.value || '';
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Failed to load project record', error);
        }
    }

    @wire(getOrgInfo)
    wiredOrg({ data, error }) {
        if (data) {
            this.orgName = data.Name || '';
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Failed to load organization', error);
        }
    }

    @wire(getLogoUrl)
    wiredLogoUrl({ data, error }) {
        if (data) {
            this.logoURL = data;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Failed to load logo URL', error);
        }
    }

    @wire(getApplicationStatus, { recordId: '$recordId' })
    wiredAppStatus(result) {
        this.wiredAppStatusResult = result;
        const { data, error } = result;
        if (data) {
            this.isSubmitted = data.isSubmitted === true;
            this.isAlreadySubmitted = data.isSubmitted === true;
            this.primarySignatureUrl = data.primarySignatureUrl || this.primarySignatureUrl;
            this.secondarySignatureUrl = data.secondarySignatureUrl || this.secondarySignatureUrl;
            this.signerName = data.signerName || this.signerName;
            this.coSignerName = data.coSignerName || this.coSignerName;
            this.primarySigned = Boolean(this.primarySignatureUrl);
            this.secondarySigned = Boolean(this.secondarySignatureUrl);
            this.isLoading = false;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Failed to load application status', error);
            this.isLoading = false;
        }
    }

    connectedCallback() {
        if (!this.recordId) {
            this.isLoading = false;
        }
    }

    renderedCallback() {
        this.initializeCanvas('primary');
        this.initializeCanvas('secondary');
    }

    disconnectedCallback() {
        window.clearTimeout(this.toastTimeout);
    }

    get isPreviewMode() {
        return this.isPreview === true || this.isPreview === 'true';
    }

    get isReadOnly() {
        return this.isPreviewMode || this.isSubmitted;
    }

    get showSubmittedMessage() {
        return this.isSubmitted && !this.isPreviewMode;
    }

    get submittedMessage() {
        return this.isAlreadySubmitted
            ? 'Home Improvement Program Photo Release Form has already been submitted for this record.'
            : 'Your Home Improvement Program Photo Release Form has been successfully submitted.';
    }

    get showPrimarySignatureImage() {
        return this.isReadOnly && !!this.primarySignatureUrl;
    }

    get showSecondarySignatureImage() {
        return this.isReadOnly && !!this.secondarySignatureUrl;
    }

    get signatureCanvasClass() {
        return `signature-pad${this.isReadOnly ? ' read-only' : ''}`;
    }

    get customToastClass() {
        return `custom-toast custom-toast_${this.customToastVariant}`;
    }

    get projectAddress() {
        const cityStateZip = [this.city, [this.state, this.zip].filter(Boolean).join(' ')].filter(Boolean).join(', ');
        return [this.address, cityStateZip, this.country].filter(Boolean).join(', ');
    }

    get displayDate() {
        return this.sendDate ? this.formatSendDate(this.sendDate) : this.formatDatePartsFromDate(new Date());
    }

    get isSubmitDisabled() {
        const hasOwnerName = this.signerName.trim() !== '';
        const hasCoOwnerName = this.coSignerName.trim() !== '';
        return this.isReadOnly || !this.primarySigned || !this.secondarySigned || !hasOwnerName || !hasCoOwnerName;
    }

    initializeCanvas(signatureKey) {
        if (this.canvasElements.has(signatureKey)) {
            return;
        }

        const canvas = this.template.querySelector(`canvas[data-signature-id="${signatureKey}"]`);
        if (!canvas) {
            return;
        }

        const ctx = canvas.getContext('2d');
        this.setCanvasSize(canvas, ctx);
        this.canvasElements.set(signatureKey, canvas);
        this.canvasContexts.set(signatureKey, ctx);
    }

    setCanvasSize(canvas, ctx) {
        if (!canvas || !ctx) {
            return;
        }

        canvas.width = canvas.offsetWidth;
        canvas.height = canvas.offsetHeight;
        ctx.lineWidth = 2;
        ctx.lineCap = 'round';
        ctx.strokeStyle = '#000';
    }

    handleNameChange(event) {
        if (this.isReadOnly) {
            return;
        }
        this.signerName = event.target.value;
    }

    handleCoSignerNameChange(event) {
        if (this.isReadOnly) {
            return;
        }
        this.coSignerName = event.target.value;
    }

    handleMouseDown(event) {
        if (this.isReadOnly) {
            return;
        }
        this.beginStroke(event.currentTarget.dataset.signatureId, event.clientX, event.clientY);
    }

    handleMouseMove(event) {
        if (this.isReadOnly || !this.isDrawing) {
            return;
        }
        this.extendStroke(this.activeSignatureKey || event.currentTarget.dataset.signatureId, event.clientX, event.clientY);
    }

    handleMouseUp() {
        this.isDrawing = false;
        this.activeSignatureKey = null;
    }

    handleTouchStart(event) {
        if (this.isReadOnly) {
            return;
        }
        event.preventDefault();
        const touch = event.touches[0];
        this.beginStroke(event.currentTarget.dataset.signatureId, touch.clientX, touch.clientY);
    }

    handleTouchMove(event) {
        if (this.isReadOnly || !this.isDrawing) {
            return;
        }
        event.preventDefault();
        const touch = event.touches[0];
        this.extendStroke(this.activeSignatureKey || event.currentTarget.dataset.signatureId, touch.clientX, touch.clientY);
    }

    handleTouchEnd(event) {
        if (this.isReadOnly) {
            return;
        }
        event.preventDefault();
        this.isDrawing = false;
        this.activeSignatureKey = null;
    }

    beginStroke(signatureKey, clientX, clientY) {
        const canvas = this.canvasElements.get(signatureKey);
        const ctx = this.canvasContexts.get(signatureKey);
        if (!canvas || !ctx) {
            return;
        }

        const { offsetX, offsetY } = this.getCoordinates(canvas, clientX, clientY);
        this.isDrawing = true;
        this.activeSignatureKey = signatureKey;

        if (signatureKey === 'primary') {
            this.primarySigned = true;
        } else if (signatureKey === 'secondary') {
            this.secondarySigned = true;
        }

        ctx.beginPath();
        ctx.moveTo(offsetX, offsetY);
    }

    extendStroke(signatureKey, clientX, clientY) {
        const canvas = this.canvasElements.get(signatureKey);
        const ctx = this.canvasContexts.get(signatureKey);
        if (!canvas || !ctx) {
            return;
        }

        const { offsetX, offsetY } = this.getCoordinates(canvas, clientX, clientY);
        ctx.lineTo(offsetX, offsetY);
        ctx.stroke();
    }

    getCoordinates(canvas, clientX, clientY) {
        const rect = canvas.getBoundingClientRect();
        return {
            offsetX: clientX - rect.left,
            offsetY: clientY - rect.top
        };
    }

    clearSignature(event) {
        if (this.isReadOnly) {
            return;
        }

        const signatureKey = event.currentTarget.dataset.signatureId;
        const canvas = this.canvasElements.get(signatureKey);
        const ctx = this.canvasContexts.get(signatureKey);
        if (!canvas || !ctx) {
            return;
        }

        ctx.clearRect(0, 0, canvas.width, canvas.height);
        if (signatureKey === 'primary') {
            this.primarySigned = false;
        } else if (signatureKey === 'secondary') {
            this.secondarySigned = false;
        }
    }

    handleSubmit() {
        if (this.isReadOnly) {
            return;
        }

        if (this.signerName.trim() === '') {
            this.showError('NAME is required for Home Owner Signature 1.');
            return;
        }
        if (this.coSignerName.trim() === '') {
            this.showError('NAME is required for Home Owner Signature 2.');
            return;
        }
        if (!this.hasSignaturePixels('primary')) {
            this.showError('Home Owner Signature 1 is required.');
            return;
        }
        if (!this.hasSignaturePixels('secondary')) {
            this.showError('Home Owner Signature 2 is required.');
            return;
        }

        const primaryCanvas = this.canvasElements.get('primary');
        const secondaryCanvas = this.canvasElements.get('secondary');
        if (!primaryCanvas || !secondaryCanvas) {
            this.showError('Unable to access the signature pad.');
            return;
        }

        this.isLoading = true;
        this.submitError = '';

        const ownerSignatureBody = primaryCanvas.toDataURL('image/png').replace(/^data:image\/(png|jpg);base64,/, '');
        const coOwnerSignatureBody = secondaryCanvas.toDataURL('image/png').replace(/^data:image\/(png|jpg);base64,/, '');

        Promise.all([
            saveSignature({
                recordId: this.recordId,
                signatureBody: ownerSignatureBody,
                signatureLabel: 'Home Owner 1'
            }),
            saveSignature({
                recordId: this.recordId,
                signatureBody: coOwnerSignatureBody,
                signatureLabel: 'Home Owner 2'
            })
        ])
            .then(([ownerSignatureResult, coOwnerSignatureResult]) => {
                this.primarySignatureUrl = ownerSignatureResult?.imgUrl
                    || (ownerSignatureResult?.cvId
                        ? `/sfc/servlet.shepherd/version/download/${ownerSignatureResult.cvId}`
                        : '');
                this.secondarySignatureUrl = coOwnerSignatureResult?.imgUrl
                    || (coOwnerSignatureResult?.cvId
                        ? `/sfc/servlet.shepherd/version/download/${coOwnerSignatureResult.cvId}`
                        : '');

                return savePdf({
                    recordId: this.recordId,
                    senderId: this.senderId,
                    sendDate: this.sendDate,
                    imgUrl: ownerSignatureResult?.imgUrl || '',
                    signerName: this.signerName,
                    signatureId: ownerSignatureResult?.cvId || '',
                    coSignerImgUrl: coOwnerSignatureResult?.imgUrl || '',
                    coSignerName: this.coSignerName,
                    coSignatureId: coOwnerSignatureResult?.cvId || ''
                });
            })
            .then((pdfResult) => {
                if (pdfResult === 'Success') {
                    this.isSubmitted = true;
                    this.isAlreadySubmitted = false;
                    return refreshApex(this.wiredAppStatusResult).then(() => {
                        this.dispatchEvent(
                            new ShowToastEvent({
                                title: 'Success',
                                message: 'Your Home Improvement Program Photo Release Form has been successfully submitted.',
                                variant: 'success'
                            })
                        );
                        this.showStatusToast('Your Home Improvement Program Photo Release Form has been successfully submitted.', 'success');
                    });
                } else if (pdfResult === 'Already Submitted') {
                    this.isSubmitted = true;
                    this.isAlreadySubmitted = true;
                    return refreshApex(this.wiredAppStatusResult).then(() => {
                        this.dispatchEvent(
                            new ShowToastEvent({
                                title: 'Already Submitted',
                                message: 'Home Improvement Program Photo Release Form has already been submitted for this record.',
                                variant: 'info'
                            })
                        );
                        this.showStatusToast('Home Improvement Program Photo Release Form has already been submitted for this record.', 'info');
                    });
                } else {
                    throw new Error(pdfResult || 'Unable to submit Home Improvement Program Photo Release Form.');
                }
            })
            .catch((error) => {
                const message = error?.body?.message || error?.message || 'An unknown error occurred';
                this.submitError = message;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message,
                        variant: 'error'
                    })
                );
                this.showStatusToast(message, 'error');
                // eslint-disable-next-line no-console
                console.error('Error submitting Home Improvement Program Photo Release Form', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    hasSignaturePixels(signatureKey, minPixels = 25) {
        const canvas = this.canvasElements.get(signatureKey);
        const ctx = this.canvasContexts.get(signatureKey);
        if (!canvas || !ctx) {
            return false;
        }

        const { data } = ctx.getImageData(0, 0, canvas.width, canvas.height);
        let hitCount = 0;
        for (let i = 3; i < data.length; i += 4) {
            if (data[i] !== 0) {
                hitCount += 1;
                if (hitCount >= minPixels) {
                    return true;
                }
            }
        }
        return false;
    }

    showError(message) {
        this.submitError = message;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error'
            })
        );
        this.showStatusToast(message, 'error');
    }

    showStatusToast(message, variant = 'success') {
        window.clearTimeout(this.toastTimeout);
        this.customToastMessage = message;
        this.customToastVariant = variant;
        this.showCustomToast = true;
        this.toastTimeout = window.setTimeout(() => {
            this.showCustomToast = false;
        }, 5000);
    }

    handleCloseToast() {
        window.clearTimeout(this.toastTimeout);
        this.showCustomToast = false;
    }

    formatSendDate(value) {
        const raw = String(value || '').trim();
        if (!raw) {
            return this.formatDatePartsFromDate(new Date());
        }

        const dateOnly = raw.includes(' ') ? raw.split(' ')[0] : raw;
        let month;
        let day;
        let year;

        if (/^\d{4}-\d{2}-\d{2}$/.test(dateOnly)) {
            const parts = dateOnly.split('-');
            year = parseInt(parts[0], 10);
            month = parseInt(parts[1], 10);
            day = parseInt(parts[2], 10);
        } else {
            const parts = dateOnly.split(/[-/]/);
            if (parts.length !== 3) {
                return raw;
            }
            month = parseInt(parts[0], 10);
            day = parseInt(parts[1], 10);
            year = parseInt(parts[2], 10);
        }

        if (Number.isNaN(month) || Number.isNaN(day) || Number.isNaN(year)) {
            return raw;
        }

        return this.formatDateParts(month, day, year);
    }

    formatDatePartsFromDate(dateValue) {
        return this.formatDateParts(dateValue.getMonth() + 1, dateValue.getDate(), dateValue.getFullYear());
    }

    formatDateParts(month, day, year) {
        const monthNames = [
            'January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'
        ];
        const safeMonth = month >= 1 && month <= 12 ? monthNames[month - 1] : '';
        if (!safeMonth) {
            return `${month}-${day}-${year}`;
        }
        return `${safeMonth} ${day}, ${year}`;
    }
}