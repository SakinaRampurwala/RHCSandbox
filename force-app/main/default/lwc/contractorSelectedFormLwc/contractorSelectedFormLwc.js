import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLogoUrl from '@salesforce/apex/ContractorSelectedFormLwcCtrl.getLogoUrl';
import getFormContext from '@salesforce/apex/ContractorSelectedFormLwcCtrl.getFormContext';
import getContractorSelectedFormState from '@salesforce/apex/ContractorSelectedFormLwcCtrl.getContractorSelectedFormState';
import getRfqToVendors from '@salesforce/apex/ContractorSelectedFormLwcCtrl.getRfqToVendors';
import saveSignature from '@salesforce/apex/ContractorSelectedFormLwcCtrl.saveSignature';
import submitHomeownerStage from '@salesforce/apex/ContractorSelectedFormLwcCtrl.submitHomeownerStage';
import finalizeProgramStaffStage from '@salesforce/apex/ContractorSelectedFormLwcCtrl.finalizeProgramStaffStage';

export default class ContractorSelectedFormLwc extends LightningElement {
    @api isPreview;
    @api recordId;
    @api senderId;
    @api sendDate;

    isLoading = true;
    errorMessage = '';
    infoMessage = '';
    logoUrl = '';
    formContext = {};
    vendorRows = [];
    stage = 'HOMEOWNER';
    isSubmitted = false;
    isGuestUser = false;
    canFinalize = false;
    selectedVendorId = '';
    homeownerInitials = '';
    homeownerNotes = '';
    programStaffInitials = '';
    homeownerSignatureId = '';
    homeownerSignatureUrl = '';
    programStaffSignatureId = '';
    programStaffSignatureUrl = '';
    programStaffName = '';
    submittedDate = '';
    fromAddressId = '';
    allowRepresentativeAccess = false;
    programRepresentativeName = '';
    programRepresentativeEmail = '';
    programRepresentativeContactId = '';
    primarySigned = false;
    secondarySigned = false;

    canvasElements = new Map();
    canvasContexts = new Map();
    isDrawing = false;
    activeSignatureKey;

    connectedCallback() {
        document.title = 'Contractor Selected Form';
        const urlParams = new URLSearchParams(window.location.search);
        this.fromAddressId = urlParams.get('fromAddressId') || '';
        this.allowRepresentativeAccess = urlParams.get('isProgramRepresentative') === 'true';
        this.programRepresentativeName = urlParams.get('programRepresentativeName') || '';
        this.programRepresentativeEmail = urlParams.get('programRepresentativeEmail') || '';
        this.programRepresentativeContactId = urlParams.get('programRepresentativeContactId') || '';
        this.loadForm();
    }

    renderedCallback() {
        this.initializeCanvas('homeowner');
        this.initializeCanvas('programStaff');
    }

    get isPreviewMode() {
        return this.isPreview === true || this.isPreview === 'true';
    }

    get isStage1Editable() {
        return !this.isPreviewMode && this.stage === 'HOMEOWNER';
    }

    get isStage2Editable() {
        return !this.isPreviewMode && this.stage === 'PROGRAM_STAFF' && this.canFinalize;
    }

    get showHomeownerCompletePage() {
        return !this.isPreviewMode && this.stage === 'HOMEOWNER_COMPLETE';
    }

    get showFormSurface() {
        return !this.showHomeownerCompletePage;
    }

    get showPreviewBanner() {
        return this.isPreviewMode;
    }

    get showCompletedBanner() {
        return this.stage === 'COMPLETED';
    }

    get showLockedBanner() {
        return this.stage === 'LOCKED';
    }

    get hasVendorRows() {
        return Array.isArray(this.vendorRows) && this.vendorRows.length > 0;
    }

    get hasHomeownerNotes() {
        return Boolean(this.homeownerNotes && this.homeownerNotes.trim());
    }

    get showNotesInput() {
        return this.isStage1Editable;
    }

    get showReadOnlyNotes() {
        return !this.showNotesInput && this.hasHomeownerNotes;
    }

    get showProgramStaffSection() {
        return this.isPreviewMode || this.isStage2Editable || this.stage === 'COMPLETED' || this.stage === 'LOCKED';
    }

    get showHomeownerSignaturePad() {
        return this.isPreviewMode || this.isStage1Editable;
    }

    get showProgramStaffSignaturePad() {
        return this.isPreviewMode || this.isStage2Editable;
    }

    get showHomeownerSignatureActions() {
        return this.isStage1Editable;
    }

    get showProgramStaffSignatureActions() {
        return this.isStage2Editable;
    }

    get showHomeownerSignatureImage() {
        return Boolean(this.homeownerSignatureUrl) && !this.showHomeownerSignaturePad;
    }

    get showProgramStaffSignatureImage() {
        return Boolean(this.programStaffSignatureUrl) && !this.showProgramStaffSignaturePad;
    }

    get primarySignatureCanvasClass() {
        return `signature-pad${this.isStage1Editable ? '' : ' read-only'}`;
    }

    get secondarySignatureCanvasClass() {
        return `signature-pad${this.isStage2Editable ? '' : ' read-only'}`;
    }

    get isSubmitDisabled() {
        if (this.isStage1Editable) {
            return !this.hasVendorRows
                || !this.selectedVendorId
                || !this.primarySigned;
        }

        if (this.isStage2Editable) {
            return !this.secondarySigned;
        }

        return true;
    }

    get displayDate() {
        return this.formatDateString(this.sendDate);
    }

    get selectedVendorLabel() {
        const selectedRow = this.vendorRows.find(row => row.id === this.selectedVendorId);
        return selectedRow ? selectedRow.bidLabel : 'No contractor selected';
    }

    get thankYouMessage() {
        return 'Your Contractor Selected Form has been submitted.';
    }

    get rowsForDisplay() {
        return (this.vendorRows || []).map(row => {
            const isSelected = row.id === this.selectedVendorId;
            return {
                ...row,
                isSelected,
                selectionLabel: isSelected ? 'x' : '',
                selectionClass: `selection-box${isSelected ? ' selected' : ''}${this.isStage1Editable ? '' : ' read-only'}`,
                isSelectionLocked: !this.isStage1Editable,
                homeownerInitialsDisplay: isSelected ? this.homeownerInitials : '',
                programStaffInitialsDisplay: isSelected ? this.programStaffInitials : '',
                showHomeownerInitialInput: isSelected && this.isStage1Editable,
                showHomeownerInitialValue: isSelected && !this.isStage1Editable && Boolean(this.homeownerInitials),
                showProgramStaffInitialInput: isSelected && this.isStage2Editable,
                showProgramStaffInitialValue: isSelected && !this.isStage2Editable && Boolean(this.programStaffInitials)
            };
        });
    }

    async loadForm() {
        if (!this.recordId) {
            this.errorMessage = 'The form could not load because no RFQ record id was provided.';
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        try {
            const [logoUrl, formContext, state, rfqToVendors] = await Promise.all([
                getLogoUrl(),
                getFormContext({ recordId: this.recordId }),
                getContractorSelectedFormState({
                    recordId: this.recordId,
                    allowRepresentativeAccess: this.allowRepresentativeAccess,
                    programRepresentativeName: this.programRepresentativeName
                }),
                getRfqToVendors({ recordId: this.recordId })
            ]);

            this.logoUrl = logoUrl || '';
            this.formContext = formContext || {};
            this.applyState(state || {});
            this.vendorRows = (rfqToVendors || []).map(row => ({
                id: row.Id,
                contractorName: this.buildVendorName(row),
                bidAmountDisplay: this.buildBidAmountDisplay(row),
                bidLabel: this.buildBidLabel(row)
            }));
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'The form data could not be loaded for this RFQ.';
            // eslint-disable-next-line no-console
            console.error('Failed to load Contractor Selected Form', error);
        } finally {
            this.isLoading = false;
        }
    }

    applyState(state) {
        if (this.isPreviewMode) {
            this.stage = 'HOMEOWNER';
            this.isSubmitted = false;
            this.isGuestUser = false;
            this.canFinalize = false;
            this.infoMessage = '';
            this.selectedVendorId = '';
            this.homeownerInitials = '';
            this.homeownerNotes = '';
            this.programStaffInitials = '';
            this.homeownerSignatureId = '';
            this.homeownerSignatureUrl = '';
            this.programStaffSignatureId = '';
            this.programStaffSignatureUrl = '';
            this.programStaffName = '';
            this.submittedDate = '';
            this.primarySigned = false;
            this.secondarySigned = false;
            return;
        }

        this.stage = state.stage || 'HOMEOWNER';
        this.isSubmitted = Boolean(state.isSubmitted);
        this.isGuestUser = Boolean(state.isGuestUser);
        this.canFinalize = Boolean(state.canFinalize);
        this.infoMessage = state.infoMessage || '';
        this.selectedVendorId = state.selectedVendorId || '';
        this.homeownerInitials = state.homeownerInitials || '';
        this.homeownerNotes = state.homeownerNotes || '';
        this.programStaffInitials = state.programStaffInitials || '';
        this.homeownerSignatureId = state.homeownerSignatureId || '';
        this.homeownerSignatureUrl = state.homeownerSignatureUrl || '';
        this.programStaffSignatureId = state.programStaffSignatureId || '';
        this.programStaffSignatureUrl = state.programStaffSignatureUrl || '';
        this.programStaffName = state.programStaffName || '';
        this.submittedDate = state.submittedDate || '';
        this.primarySigned = Boolean(this.homeownerSignatureUrl || this.homeownerSignatureId);
        this.secondarySigned = Boolean(this.programStaffSignatureUrl || this.programStaffSignatureId);
    }

    buildBidLabel(row) {
        const vendorName = this.buildVendorName(row);
        const bidAmountDisplay = this.buildBidAmountDisplay(row);

        if (!bidAmountDisplay) {
            return vendorName;
        }

        return `${vendorName} - ${bidAmountDisplay}`;
    }

    buildVendorName(row) {
        return row?.buildertek__Vendor__r?.Name || row?.Name || 'Unnamed contractor';
    }

    buildBidAmountDisplay(row) {
        const quoteAmount = row?.buildertek__Vendor_Quote_Amount__c;
        if (quoteAmount === null || quoteAmount === undefined) {
            return '';
        }

        return this.formatCurrency(quoteAmount);
    }

    formatCurrency(value) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(value);
    }

    formatDateString(rawValue) {
        if (!rawValue) {
            const today = new Date();
            return `${today.getMonth() + 1}/${today.getDate()}/${today.getFullYear()}`;
        }

        const value = String(rawValue).trim();
        const dateOnly = value.includes(' ') ? value.split(' ')[0] : value;
        const parts = dateOnly.split(/[-/]/);
        if (parts.length === 3) {
            if (dateOnly.includes('-') && parts[0].length === 4) {
                return `${parts[1]}/${parts[2]}/${parts[0]}`;
            }
            return `${parts[0]}/${parts[1]}/${parts[2]}`;
        }

        return value;
    }

    handleSelectVendor(event) {
        if (!this.isStage1Editable) {
            return;
        }

        this.selectedVendorId = event.currentTarget.dataset.rowId;
    }

    handleHomeownerInitialsChange(event) {
        this.homeownerInitials = event.target.value || '';
    }

    handleHomeownerNotesChange(event) {
        this.homeownerNotes = event.target.value || '';
    }

    handleProgramStaffInitialsChange(event) {
        this.programStaffInitials = event.target.value || '';
    }

    initializeCanvas(signatureKey) {
        const canvas = this.template.querySelector(`canvas[data-signature="${signatureKey}"]`);
        if (!canvas || this.canvasElements.get(signatureKey) === canvas) {
            return;
        }

        const context = canvas.getContext('2d');
        canvas.width = canvas.offsetWidth;
        canvas.height = canvas.offsetHeight;
        context.lineWidth = 2;
        context.lineCap = 'round';
        context.strokeStyle = '#000000';
        this.canvasElements.set(signatureKey, canvas);
        this.canvasContexts.set(signatureKey, context);
    }

    handleMouseDown(event) {
        const signatureKey = event.currentTarget.dataset.signature;
        if (!this.canEditSignature(signatureKey)) {
            return;
        }

        this.beginStroke(signatureKey, event.clientX, event.clientY);
    }

    handleMouseMove(event) {
        if (!this.isDrawing) {
            return;
        }

        const signatureKey = this.activeSignatureKey || event.currentTarget.dataset.signature;
        if (!this.canEditSignature(signatureKey)) {
            return;
        }

        this.extendStroke(signatureKey, event.clientX, event.clientY);
    }

    handleMouseUp() {
        this.isDrawing = false;
        this.activeSignatureKey = null;
    }

    handleTouchStart(event) {
        const signatureKey = event.currentTarget.dataset.signature;
        if (!this.canEditSignature(signatureKey)) {
            return;
        }

        event.preventDefault();
        const touch = event.touches[0];
        this.beginStroke(signatureKey, touch.clientX, touch.clientY);
    }

    handleTouchMove(event) {
        if (!this.isDrawing) {
            return;
        }

        const signatureKey = this.activeSignatureKey || event.currentTarget.dataset.signature;
        if (!this.canEditSignature(signatureKey)) {
            return;
        }

        event.preventDefault();
        const touch = event.touches[0];
        this.extendStroke(signatureKey, touch.clientX, touch.clientY);
    }

    handleTouchEnd(event) {
        event.preventDefault();
        this.isDrawing = false;
        this.activeSignatureKey = null;
    }

    canEditSignature(signatureKey) {
        return (signatureKey === 'homeowner' && this.isStage1Editable)
            || (signatureKey === 'programStaff' && this.isStage2Editable);
    }

    beginStroke(signatureKey, clientX, clientY) {
        const canvas = this.canvasElements.get(signatureKey);
        const context = this.canvasContexts.get(signatureKey);
        if (!canvas || !context) {
            return;
        }

        const coordinates = this.getCoordinates(canvas, clientX, clientY);
        this.isDrawing = true;
        this.activeSignatureKey = signatureKey;
        context.beginPath();
        context.moveTo(coordinates.offsetX, coordinates.offsetY);

        if (signatureKey === 'homeowner') {
            this.primarySigned = true;
        } else {
            this.secondarySigned = true;
        }
    }

    extendStroke(signatureKey, clientX, clientY) {
        const canvas = this.canvasElements.get(signatureKey);
        const context = this.canvasContexts.get(signatureKey);
        if (!canvas || !context) {
            return;
        }

        const coordinates = this.getCoordinates(canvas, clientX, clientY);
        context.lineTo(coordinates.offsetX, coordinates.offsetY);
        context.stroke();
    }

    getCoordinates(canvas, clientX, clientY) {
        const rect = canvas.getBoundingClientRect();
        return {
            offsetX: clientX - rect.left,
            offsetY: clientY - rect.top
        };
    }

    clearSignature(event) {
        const signatureKey = event.currentTarget.dataset.signature;
        if (!this.canEditSignature(signatureKey)) {
            return;
        }

        const canvas = this.canvasElements.get(signatureKey);
        const context = this.canvasContexts.get(signatureKey);
        if (!canvas || !context) {
            return;
        }

        context.clearRect(0, 0, canvas.width, canvas.height);
        if (signatureKey === 'homeowner') {
            this.primarySigned = false;
        } else {
            this.secondarySigned = false;
        }
    }

    hasSignaturePixels(signatureKey, minPixels = 25) {
        const canvas = this.canvasElements.get(signatureKey);
        const context = this.canvasContexts.get(signatureKey);
        if (!canvas || !context) {
            return false;
        }

        const { data } = context.getImageData(0, 0, canvas.width, canvas.height);
        let hitCount = 0;
        for (let index = 3; index < data.length; index += 4) {
            if (data[index] !== 0) {
                hitCount += 1;
                if (hitCount >= minPixels) {
                    return true;
                }
            }
        }

        return false;
    }

    handleSubmit() {
        if (this.isStage1Editable) {
            this.submitHomeownerStageFlow();
            return;
        }

        if (this.isStage2Editable) {
            this.finalizeProgramStaffStageFlow();
        }
    }

    submitHomeownerStageFlow() {
        if (!this.selectedVendorId) {
            this.showToast('Validation Error', 'Select exactly one contractor before submitting.', 'error');
            return;
        }

        if (!this.hasSignaturePixels('homeowner')) {
            this.showToast('Validation Error', 'Homeowner signature is required.', 'error');
            return;
        }

        const signatureCanvas = this.canvasElements.get('homeowner');
        const signatureBody = signatureCanvas
            .toDataURL('image/png')
            .replace(/^data:image\/(png|jpg);base64,/, '');

        this.isLoading = true;

        saveSignature({
            recordId: this.recordId,
            signatureBody,
            signatureLabel: 'Homeowner',
            allowRepresentativeAccess: this.allowRepresentativeAccess
        })
            .then(result => {
                this.homeownerSignatureUrl = result?.imgUrl || '';
                this.homeownerSignatureId = result?.cvId || '';
                this.primarySigned = true;
                return submitHomeownerStage({
                    recordId: this.recordId,
                    selectedVendorId: this.selectedVendorId,
                    homeownerInitials: this.homeownerInitials,
                    homeownerNotes: '',
                    senderId: this.senderId,
                    sendDate: this.sendDate,
                    fromAddressId: this.fromAddressId,
                    programRepresentativeName: this.programRepresentativeName
                });
            })
            .then(() => {
                this.stage = 'HOMEOWNER_COMPLETE';
                this.infoMessage = 'Your Contractor Selected Form has been submitted.';
                this.showToast('Success', 'The Contractor Selected Form has been submitted.', 'success');
            })
            .catch(error => {
                this.showToast('Error', error?.body?.message || error?.message || 'An unexpected error occurred.', 'error');
                // eslint-disable-next-line no-console
                console.error('Error submitting homeowner stage', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    finalizeProgramStaffStageFlow() {
        if (!this.hasSignaturePixels('programStaff')) {
            this.showToast('Validation Error', 'Program Representative signature is required.', 'error');
            return;
        }

        const signatureCanvas = this.canvasElements.get('programStaff');
        const signatureBody = signatureCanvas
            .toDataURL('image/png')
            .replace(/^data:image\/(png|jpg);base64,/, '');

        this.isLoading = true;

        saveSignature({
            recordId: this.recordId,
            signatureBody,
            signatureLabel: 'Program Staff',
            allowRepresentativeAccess: this.allowRepresentativeAccess
        })
            .then(result => {
                this.programStaffSignatureUrl = result?.imgUrl || '';
                this.programStaffSignatureId = result?.cvId || '';
                this.secondarySigned = true;
                return finalizeProgramStaffStage({
                    recordId: this.recordId,
                    programStaffInitials: this.programStaffInitials,
                    senderId: this.senderId,
                    sendDate: this.sendDate,
                    allowRepresentativeAccess: this.allowRepresentativeAccess
                });
            })
            .then(result => {
                if (result === 'Already Submitted') {
                    this.showToast('Already Submitted', 'This Contractor Selected Form has already been finalized.', 'info');
                } else {
                    this.showToast('Success', 'The Contractor Selected Form has been finalized.', 'success');
                }
                return this.loadForm();
            })
            .catch(error => {
                this.showToast('Error', error?.body?.message || error?.message || 'An unexpected error occurred.', 'error');
                // eslint-disable-next-line no-console
                console.error('Error finalizing program staff stage', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}